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
        Logger.warning("Orchestrator poll error: #{reason}")
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
        dispatch(bead, timeout)

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
          result = dispatch(bead, Keyword.get(opts, :timeout, 60_000))
          %{bead_id: bead.id, title: bead.title, result: result}
        end)

      {:error, reason} ->
        Logger.error("Orchestrator: failed to fetch beads: #{reason}")
        []
    end
  end

  @doc """
  Route a bead to the appropriate agent based on labels.

  Phase 0: all beads with "ops" label go to UplinkAgent.
  """
  @spec route(Keiro.Beads.Bead.t()) :: {:ok, module()} | {:error, :no_matching_agent}
  def route(bead) do
    labels = bead.labels || []

    cond do
      "ops" in labels -> {:ok, Keiro.Ops.UplinkAgent}
      true -> {:error, :no_matching_agent}
    end
  end

  # -- private --

  defp dispatch(bead, timeout) do
    case route(bead) do
      {:ok, agent_module} ->
        prompt = "Bead #{bead.id}: #{bead.title}\n\n#{bead.description || "No description."}"

        case Jido.AgentServer.start(agent: agent_module) do
          {:ok, pid} ->
            result = agent_module.ask_sync(pid, prompt, timeout: timeout)
            GenServer.stop(pid, :normal)
            result

          {:error, reason} ->
            {:error, "Failed to start agent: #{inspect(reason)}"}
        end

      {:error, :no_matching_agent} ->
        Logger.warning(
          "Orchestrator: no agent for bead #{bead.id} (labels: #{inspect(bead.labels)})"
        )

        {:error, "no matching agent for labels: #{inspect(bead.labels)}"}
    end
  end
end
