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
  alias Keiro.Governance.{InputValidator, PromptAssembler}
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

  - "eng" beads route to the engineer pipeline (on success, creates an ops deploy bead)
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
      {:ok, validated} ->
        dispatch_validated(bead, validated, timeout, repo_path, tool_context)

      {:error, reason} ->
        Logger.warning(
          "Orchestrator: input validation failed for bead #{bead.id}: #{inspect(reason)}"
        )

        {:error, "input validation failed: #{inspect(reason)}"}
    end
  end

  defp dispatch_validated(bead, validated, timeout, repo_path, tool_context) do
    case route(bead) do
      {:ok, :engineer_pipeline} ->
        dispatch_pipeline(bead, validated, timeout, repo_path, tool_context)

      {:ok, agent_module} ->
        dispatch_agent(bead, validated, agent_module, timeout, tool_context)

      {:error, :no_matching_agent} ->
        Logger.warning(
          "Orchestrator: no agent for bead #{bead.id} (labels: #{inspect(bead.labels)})"
        )

        {:error, "no matching agent for labels: #{inspect(bead.labels)}"}
    end
  end

  defp dispatch_agent(bead, validated, agent_module, timeout, tool_context) do
    metadata = %{bead_id: bead.id, agent: agent_module, kind: :agent}
    repo_path = Map.get(tool_context, :repo_path)

    Keiro.Telemetry.span([:keiro, :orchestrator, :dispatch], metadata, fn ->
      prompt = PromptAssembler.assemble_task_prompt(validated)

      result =
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

      # Post-dispatch: persist results and handle failures
      if repo_path do
        client = BeadsClient.new(repo_path)
        record_agent_outcome(client, bead, agent_module, result)
      end

      result
    end)
  end

  @doc false
  def record_agent_outcome(client, bead, agent_module, result) do
    agent_name = agent_module |> Module.split() |> List.last()

    case result do
      {:ok, output} ->
        comment = format_agent_result_comment(agent_name, :ok, output)
        BeadsClient.comment(client, bead.id, comment)
        BeadsClient.close(client, bead.id)

      {:error, reason} ->
        comment = format_agent_result_comment(agent_name, :error, reason)
        BeadsClient.comment(client, bead.id, comment)
        BeadsClient.update_status(client, bead.id, "blocked")
        create_investigation_bead(client, bead, agent_name, reason)
    end
  end

  defp format_agent_result_comment(agent_name, :ok, output) do
    output_str = inspect(output, limit: 500, printable_limit: 1000)

    """
    ## #{agent_name} — Completed

    **Status:** success
    **Output:** #{String.slice(output_str, 0, 1500)}
    """
  end

  defp format_agent_result_comment(agent_name, :error, reason) do
    """
    ## #{agent_name} — Failed

    **Status:** error
    **Reason:** #{inspect(reason, limit: 500, printable_limit: 1000)}
    """
  end

  @doc false
  def create_investigation_bead(client, failed_bead, agent_name, reason) do
    title = "Investigate: #{agent_name} failure on #{failed_bead.id}" |> String.slice(0, 200)

    description = """
    #{agent_name} failed while processing bead #{failed_bead.id}: #{failed_bead.title}

    Error: #{inspect(reason, limit: 500, printable_limit: 1000)}

    Original bead description:
    #{failed_bead.description || "No description."}

    Investigate the root cause and either fix the issue or escalate.
    """

    case BeadsClient.create(client, title,
           type: "task",
           priority: min((failed_bead.priority || 2) + 0, 4),
           labels: ["ops"],
           description: description
         ) do
      {:ok, inv_id} ->
        BeadsClient.link(client, inv_id, failed_bead.id)
        Logger.info("Created investigation bead #{inv_id} for failed #{failed_bead.id}")

      {:error, reason} ->
        Logger.warning("Failed to create investigation bead: #{reason}")
    end
  end

  defp dispatch_pipeline(bead, validated, timeout, repo_path, tool_context) do
    metadata = %{bead_id: bead.id, kind: :pipeline}

    Keiro.Telemetry.span([:keiro, :orchestrator, :dispatch], metadata, fn ->
      client = if repo_path, do: BeadsClient.new(repo_path), else: nil

      eng_stage = %Stage{
        name: "engineer",
        agent_module: Keiro.Eng.EngineerAgent,
        prompt_fn: fn bead, prev_stages -> eng_prompt(bead, validated, prev_stages) end,
        runner_fn: &claude_engineer_runner/2,
        timeout: timeout
      }

      case Pipeline.run(bead, [eng_stage], tool_context: tool_context) do
        {:ok, result} ->
          Logger.info("Pipeline completed for bead #{bead.id}")
          result = attach_outcome_context(result, client, bead.id)
          if client, do: BeadsClient.close(client, bead.id)
          if client, do: create_deploy_bead(client, bead, result)
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

  defp eng_prompt(_bead, validated, _prev_stages) do
    objective = PromptAssembler.assemble_task_prompt(validated)

    """
    #{objective}

    Implement this task: create a branch, write the code, run tests, and open a PR.
    """
  end

  defp create_deploy_bead(client, eng_bead, eng_result) do
    title = "Deploy: #{eng_bead.title}" |> String.slice(0, 200)
    lei_config = Application.get_env(:keiro, :lei, [])
    smoke_url = Keyword.get(lei_config, :smoke_test_url, "https://lowendinsight.fly.dev")
    fly_app = Keyword.get(lei_config, :fly_app, "lowendinsight")
    dockerfile = Keyword.get(lei_config, :dockerfile, "apps/lowendinsight_get/Dockerfile")
    smoke_script = Keyword.get(lei_config, :smoke_test_script, "scripts/smoke-test.sh")

    description = """
    Engineer pipeline completed for #{eng_bead.id}.
    Deploy the changes to fly.io and verify with smoke tests.

    Fly app: #{fly_app}
    Dockerfile: #{dockerfile}
    Smoke test URL: #{smoke_url}
    Smoke test script: #{smoke_script}

    Steps:
    1. Deploy with fly_deploy using app: "#{fly_app}", dockerfile: "#{dockerfile}"
    2. Run fly_smoke_test with script: "#{smoke_script}" and url: "#{smoke_url}"
    3. If smoke tests fail, create an investigation bead with failure details

    Engineer result: #{summarize_eng_result(eng_result)}
    """

    case BeadsClient.create(client, title,
           type: "task",
           priority: eng_bead.priority || 2,
           labels: ["ops"],
           description: description
         ) do
      {:ok, deploy_id} ->
        BeadsClient.link(client, deploy_id, eng_bead.id)
        Logger.info("Created deploy bead #{deploy_id} linked to #{eng_bead.id}")
        {:ok, deploy_id}

      {:error, reason} ->
        Logger.warning("Failed to create deploy bead: #{reason}")
        {:error, reason}
    end
  end

  defp summarize_eng_result(%{outcome: outcome}) when is_binary(outcome), do: outcome
  defp summarize_eng_result(%{status: status}), do: to_string(status)
  defp summarize_eng_result(result), do: inspect(result, limit: 200)

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

    approve_fn = opts[:approve_fn] || (&batch_auto_approve/1)
    Map.put(context, :approve_fn, approve_fn)
  end

  defp batch_auto_approve(description) do
    Logger.info("Orchestrator: auto-approving in batch mode: #{description}")
    :approved
  end
end
