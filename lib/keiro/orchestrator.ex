defmodule Keiro.Orchestrator do
  @moduledoc """
  Task router and polling loop for Keiro.

  Pulls ready beads from the task graph and routes them to the appropriate
  agent based on labels/type. Can run as a one-shot or as a GenServer that
  polls on an interval.

  ## One-shot usage

      {:ok, result} = Keiro.Orchestrator.run_next(repo_path: "/path/to/lei")
      results = Keiro.Orchestrator.run_all(repo_path: "/path/to/lei")

  ## Polling loop

      {:ok, pid} = Keiro.Orchestrator.start_link(
        repo_path: "/path/to/lei",
        poll_interval: 30_000
      )
  """

  use GenServer

  alias Keiro.Beads.Client, as: BeadsClient
  alias Keiro.Pipeline
  alias Keiro.Pipeline.Stage
  alias Keiro.Telemetry

  require Logger

  # -- GenServer API --

  @doc """
  Start the orchestrator polling loop.

  Options:
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:poll_interval` — ms between polls (default: 30_000)
  - `:timeout` — per-agent timeout in ms (default: 120_000)
  - `:on_result` — callback fn receiving `%{bead_id, title, result}` (optional)
  """
  def start_link(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)

    GenServer.start_link(__MODULE__, opts,
      name: Keyword.get(opts, :name, {:global, {__MODULE__, repo_path}})
    )
  end

  @doc "Trigger an immediate poll outside the normal interval."
  def poll(pid), do: GenServer.cast(pid, :poll)

  @doc "Stop the orchestrator loop."
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl GenServer
  def init(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    poll_interval = Keyword.get(opts, :poll_interval, 30_000)
    timeout = Keyword.get(opts, :timeout, 120_000)
    on_result = Keyword.get(opts, :on_result)

    state = %{
      repo_path: repo_path,
      poll_interval: poll_interval,
      timeout: timeout,
      on_result: on_result,
      running: false
    }

    schedule_poll(poll_interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:poll, %{running: true} = state) do
    Logger.debug("Orchestrator: skipping poll, already processing")
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    state = do_poll(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:poll, %{running: true} = state), do: {:noreply, state}
  def handle_cast(:poll, state), do: {:noreply, do_poll(state)}

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp do_poll(state) do
    state = %{state | running: true}

    case run_next(repo_path: state.repo_path, timeout: state.timeout) do
      {:ok, _result} = result ->
        if state.on_result, do: state.on_result.(result)
        %{state | running: false}

      :no_work ->
        Logger.debug("Orchestrator: no ready beads")
        %{state | running: false}

      {:error, reason} ->
        Logger.warning("Orchestrator poll error: #{inspect(reason)}")
        %{state | running: false}
    end
  end

  @doc """
  Pull the next ready bead and route it to the appropriate agent.

  Options:
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:timeout` — agent timeout in ms (default: 60_000)
  """
  @spec run_next(keyword()) :: {:ok, map()} | {:error, String.t()} | :no_work
  def run_next(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    timeout = Keyword.get(opts, :timeout, 60_000)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, []} ->
        :no_work

      {:ok, [bead | _]} ->
        Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
        BeadsClient.update_status(client, bead.id, "in_progress")
        dispatch(bead, timeout, repo_path: repo_path)

      {:error, reason} ->
        {:error, "Failed to fetch ready beads: #{reason}"}
    end
  end

  @doc """
  Process all ready beads sequentially.
  """
  @spec run_all(keyword()) :: [map()]
  def run_all(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, beads} ->
        Enum.map(beads, fn bead ->
          Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
          BeadsClient.update_status(client, bead.id, "in_progress")
          result = dispatch(bead, Keyword.get(opts, :timeout, 60_000), repo_path: repo_path)
          %{bead_id: bead.id, title: bead.title, result: result}
        end)

      {:error, reason} ->
        Logger.error("Orchestrator: failed to fetch beads: #{reason}")
        []
    end
  end

  @doc """
  Route a bead to the appropriate agent or pipeline based on labels.

  - "eng" beads route to the engineer pipeline (engineer → deploy)
  - "ops" beads route directly to UplinkAgent
  """
  @spec route(Keiro.Beads.Bead.t()) ::
          {:ok, :engineer_pipeline} | {:ok, module()} | {:error, :no_matching_agent}
  def route(bead) do
    labels = bead.labels || []

    cond do
      "eng" in labels -> {:ok, :engineer_pipeline}
      "ops" in labels -> {:ok, Keiro.Ops.UplinkAgent}
      true -> {:error, :no_matching_agent}
    end
  end

  # -- private --

  defp dispatch(bead, timeout, opts) do
    repo_path = Keyword.get(opts, :repo_path)
    tool_context = build_tool_context(opts)
    dispatch_meta = %{bead_id: bead.id, labels: bead.labels || []}
    dispatch_start = Telemetry.span_start([:keiro, :orchestrator, :dispatch], dispatch_meta)

    result =
      case route(bead) do
        {:ok, :engineer_pipeline} ->
          dispatch_pipeline(bead, timeout, repo_path, tool_context)

        {:ok, agent_module} ->
          dispatch_agent(bead, agent_module, timeout, tool_context)

        {:error, :no_matching_agent} ->
          Logger.warning(
            "Orchestrator: no agent for bead #{bead.id} (labels: #{inspect(bead.labels)})"
          )

          {:error, "no matching agent for labels: #{inspect(bead.labels)}"}
      end

    complete_status =
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end

    Telemetry.span_stop(
      [:keiro, :orchestrator, :complete],
      dispatch_start,
      Map.put(dispatch_meta, :status, complete_status)
    )

    result
  end

  defp dispatch_agent(bead, agent_module, timeout, tool_context) do
    prompt = "Bead #{bead.id}: #{bead.title}\n\n#{bead.description || "No description."}"

    try do
      case Jido.AgentServer.start(agent: agent_module) do
        {:ok, pid} ->
          result =
            agent_module.ask_sync(pid, prompt,
              timeout: timeout,
              tool_context: tool_context
            )

          GenServer.stop(pid, :normal)
          result

        {:error, reason} ->
          {:error, "Failed to start agent: #{inspect(reason)}"}
      end
    catch
      :exit, reason ->
        {:error, "Failed to start agent: #{inspect(reason)}"}
    end
  end

  defp dispatch_pipeline(bead, timeout, repo_path, tool_context) do
    client = if repo_path, do: BeadsClient.new(repo_path), else: nil

    stages = [
      %Stage{
        name: "engineer",
        agent_module: Keiro.Eng.EngineerAgent,
        prompt_fn: &eng_prompt/2,
        timeout: timeout
      },
      %Stage{
        name: "deploy",
        agent_module: Keiro.Ops.UplinkAgent,
        prompt_fn: &deploy_prompt/2,
        timeout: timeout
      }
    ]

    case Pipeline.run(bead, stages, tool_context: tool_context) do
      {:ok, result} ->
        Logger.info("Pipeline completed for bead #{bead.id}")
        if client, do: BeadsClient.close(client, bead.id)
        {:ok, result}

      {:error, result} ->
        Logger.warning("Pipeline failed at stage #{result.error_stage} for bead #{bead.id}")
        if client, do: BeadsClient.update_status(client, bead.id, "blocked")
        {:error, result}
    end
  end

  defp eng_prompt(bead, _prev_stages) do
    """
    Bead #{bead.id}: #{bead.title}

    #{bead.description || "No description."}

    Implement this task: create a branch, write the code, run tests, and open a PR.
    """
  end

  defp deploy_prompt(bead, prev_stages) do
    eng_result =
      case prev_stages do
        [%{result: result} | _] -> "\n\nEngineer stage result: #{inspect(result)}"
        _ -> ""
      end

    """
    Bead #{bead.id}: #{bead.title}

    The engineer has completed implementation. Deploy and verify.#{eng_result}
    """
  end

  defp build_tool_context(opts) do
    context = %{}

    context =
      if opts[:repo_path], do: Map.put(context, :repo_path, opts[:repo_path]), else: context

    if opts[:approve_fn],
      do: Map.put(context, :approve_fn, opts[:approve_fn]),
      else: context
  end
end
