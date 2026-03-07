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
  alias Keiro.Governance.InputValidator
  alias Keiro.Pipeline
  alias Keiro.Pipeline.{OutcomeContext, Stage}
  alias Keiro.TQM

  require Logger

  # -- GenServer API --

  @doc """
  Start the orchestrator polling loop.

  Options:
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:poll_interval` — ms between polls (default: 30_000)
  - `:timeout` — per-agent timeout in ms (default: 120_000)
  - `:on_result` — callback fn receiving `%{bead_id, title, result}` (optional)
  - `:approve_fn` — approval callback for governance (optional)
  - `:tqm_enabled` — run TQM analysis after dispatch (default: true)
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
    approve_fn = Keyword.get(opts, :approve_fn)
    tqm_enabled = Keyword.get(opts, :tqm_enabled, true)

    state = %{
      repo_path: repo_path,
      poll_interval: poll_interval,
      timeout: timeout,
      on_result: on_result,
      approve_fn: approve_fn,
      tqm_enabled: tqm_enabled,
      results: [],
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

    opts =
      [repo_path: state.repo_path, timeout: state.timeout]
      |> maybe_add(:approve_fn, state.approve_fn)

    case run_next(opts) do
      {:ok, _result} = result ->
        if state.on_result, do: state.on_result.(result)
        entry = %{status: :ok, bead_id: nil}

        state
        |> Map.update!(:results, &[entry | &1])
        |> maybe_run_tqm()
        |> Map.put(:running, false)

      :no_work ->
        Logger.debug("Orchestrator: no ready beads")
        %{state | running: false}

      {:error, reason} ->
        Logger.warning("Orchestrator poll error: #{inspect(reason)}")
        entry = %{status: :error, error: inspect(reason), bead_id: nil}

        state
        |> Map.update!(:results, &[entry | &1])
        |> maybe_run_tqm()
        |> Map.put(:running, false)
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
        dispatch(bead, timeout, opts)

      {:error, reason} ->
        {:error, "Failed to fetch ready beads: #{reason}"}
    end
  end

  @doc """
  Process all ready beads sequentially.

  Runs TQM analysis after all beads are processed (unless `:tqm_enabled` is false).
  """
  @spec run_all(keyword()) :: [map()]
  def run_all(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    tqm_enabled = Keyword.get(opts, :tqm_enabled, true)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, beads} ->
        results =
          Enum.map(beads, fn bead ->
            Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
            BeadsClient.update_status(client, bead.id, "in_progress")
            result = dispatch(bead, Keyword.get(opts, :timeout, 60_000), opts)
            %{bead_id: bead.id, title: bead.title, result: result}
          end)

        if tqm_enabled and results != [] do
          tqm_results = Enum.map(results, &to_tqm_entry/1)
          run_tqm_analysis(tqm_results, repo_path)
        end

        results

      {:error, reason} ->
        Logger.error("Orchestrator: failed to fetch beads: #{reason}")
        []
    end
  end

  @doc """
  Route a bead to the appropriate agent or pipeline based on labels.

  - "eng" beads route to the engineer pipeline (engineer → deploy)
  - "ops" beads route directly to UplinkAgent
  - "arch" beads route directly to ArchitectAgent
  """
  @spec route(Keiro.Beads.Bead.t()) ::
          {:ok, :engineer_pipeline} | {:ok, module()} | {:error, :no_matching_agent}
  def route(bead) do
    labels = bead.labels || []

    cond do
      "eng" in labels -> {:ok, :engineer_pipeline}
      "ops" in labels -> {:ok, Keiro.Ops.UplinkAgent}
      "arch" in labels -> {:ok, Keiro.Arch.ArchitectAgent}
      true -> {:error, :no_matching_agent}
    end
  end

  # -- private --

  defp dispatch(bead, timeout, opts) do
    repo_path = Keyword.get(opts, :repo_path)
    tool_context = build_tool_context(opts)

    case InputValidator.validate_bead(bead) do
      {:ok, _validated} ->
        dispatch_validated(bead, timeout, repo_path, tool_context)

      {:error, reason} ->
        Logger.warning(
          "Orchestrator: input validation failed for bead #{bead.id}: #{inspect(reason)}"
        )

        {:error, "input validation failed: #{inspect(reason)}"}
    end
  end

  defp dispatch_validated(bead, timeout, repo_path, tool_context) do
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
  end

  defp dispatch_agent(bead, agent_module, timeout, tool_context) do
    metadata = %{bead_id: bead.id, agent: agent_module, kind: :agent}

    Keiro.Telemetry.span([:keiro, :orchestrator, :dispatch], metadata, fn ->
      # Bead already validated in dispatch/3; build prompt from validated content
      prompt = build_bead_prompt(bead)

      try do
        case Jido.AgentServer.start(agent: agent_module, jido: Keiro.Jido) do
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
    end)
  end

  defp dispatch_pipeline(bead, timeout, repo_path, tool_context) do
    metadata = %{bead_id: bead.id, kind: :pipeline}

    Keiro.Telemetry.span([:keiro, :orchestrator, :dispatch], metadata, fn ->
      client = if repo_path, do: BeadsClient.new(repo_path), else: nil

      eng_stage = %Stage{
        name: "engineer",
        agent_module: Keiro.Eng.EngineerAgent,
        prompt_fn: &eng_prompt/2,
        runner_fn: &claude_engineer_runner/2,
        timeout: timeout
      }

      deploy_stage = %Stage{
        name: "deploy",
        agent_module: Keiro.Ops.UplinkAgent,
        prompt_fn: &deploy_prompt/2,
        timeout: timeout
      }

      labels = bead.labels || []
      stages = if "ops" in labels, do: [eng_stage, deploy_stage], else: [eng_stage]

      case Pipeline.run(bead, stages, tool_context: tool_context) do
        {:ok, result} ->
          Logger.info("Pipeline completed for bead #{bead.id}")
          result = attach_outcome_context(result, client, bead.id)
          if client, do: BeadsClient.close(client, bead.id)
          {:ok, result}

        {:error, result} ->
          Logger.warning("Pipeline failed at stage #{result.error_stage} for bead #{bead.id}")
          result = attach_outcome_context(result, client, bead.id)
          if client, do: BeadsClient.update_status(client, bead.id, "blocked")
          {:error, result}
      end
    end)
  end

  defp attach_outcome_context(result, client, bead_id) do
    ctx = OutcomeContext.from_result(result)
    result = %{result | outcome: ctx.outcome, outcome_context: ctx}

    if client do
      markdown = OutcomeContext.to_markdown(ctx)
      BeadsClient.comment(client, bead_id, markdown)
    end

    result
  end

  defp claude_engineer_runner(prompt, tool_context) do
    repo_path = Map.get(tool_context, :repo_path, ".")
    Keiro.Eng.ClaudeCli.run(prompt, repo_path, timeout: 300_000)
  end

  defp build_bead_prompt(bead) do
    "Bead #{bead.id}: #{bead.title}\n\n#{bead.description || "No description."}"
  end

  defp eng_prompt(bead, _prev_stages) do
    """
    #{build_bead_prompt(bead)}

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
    #{build_bead_prompt(bead)}

    The engineer has completed implementation. Deploy and verify.#{eng_result}
    """
  end

  # -- TQM integration --

  defp maybe_run_tqm(%{tqm_enabled: false} = state), do: state

  defp maybe_run_tqm(%{tqm_enabled: true, results: results, repo_path: repo_path} = state) do
    run_tqm_analysis(results, repo_path)
    state
  end

  defp run_tqm_analysis(results, repo_path) do
    patterns = TQM.Analyzer.analyze(results)

    if patterns != [] do
      Logger.info("TQM: detected #{length(patterns)} pattern(s)")
      client = BeadsClient.new(repo_path)

      Enum.each(patterns, fn pattern ->
        title = "TQM: #{pattern.name} (#{pattern.severity})"
        description = "#{pattern.description}\n\nRemediation: #{pattern.remediation}"

        BeadsClient.create(client, title,
          type: "task",
          priority: tqm_severity_to_priority(pattern.severity),
          labels: ["eng", "tqm"],
          description: description
        )
      end)
    end

    patterns
  end

  defp tqm_severity_to_priority(:critical), do: 0
  defp tqm_severity_to_priority(:warning), do: 2
  defp tqm_severity_to_priority(:info), do: 3
  defp tqm_severity_to_priority(_), do: 2

  defp to_tqm_entry(%{bead_id: bead_id, result: {:ok, _}}),
    do: %{bead_id: bead_id, status: :ok}

  defp to_tqm_entry(%{bead_id: bead_id, result: {:error, reason}}),
    do: %{bead_id: bead_id, status: :error, error: inspect(reason)}

  defp to_tqm_entry(%{bead_id: bead_id}),
    do: %{bead_id: bead_id, status: :error, error: "unknown"}

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp build_tool_context(opts) do
    context = %{}

    context =
      if opts[:repo_path], do: Map.put(context, :repo_path, opts[:repo_path]), else: context

    if opts[:approve_fn],
      do: Map.put(context, :approve_fn, opts[:approve_fn]),
      else: context
  end
end
