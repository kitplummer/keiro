defmodule Keiro.Continuous do
  @moduledoc """
  Budget-paced continuous orchestration with watchdog.

  Wraps the orchestrator and health monitor, enforcing:
  - Budget pacing: spreads $N across H hours
  - Watchdog: creates investigation bead if no progress for 30 minutes
  - Graceful shutdown: finishes current task on SIGTERM
  """
  use GenServer
  require Logger

  alias Keiro.Beads.Client, as: BeadsClient

  @watchdog_interval 60_000
  @stall_threshold_ms 30 * 60_000
  @default_cost_per_task 0.10

  # -- Public API --

  @doc """
  Start the continuous mode GenServer.

  Options:
  - `:budget_total` — total dollars for the run (required)
  - `:hours` — total hours for the run (default: 8.0)
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:poll_interval` — orchestrator poll interval in ms (default: 30_000)
  - `:health_url` — URL for health checks (required)
  - `:fly_app` — Fly app name (required)
  - `:cost_per_task` — estimated cost per task in dollars (default: 0.10)
  - `:watchdog_interval` — ms between watchdog ticks (default: 60_000)
  - `:stall_threshold_ms` — ms of no progress before watchdog fires (default: 1_800_000)
  - `:bead_create_fn` — override bead creation for testing
  - `:orchestrator_start_fn` — override orchestrator start for testing
  - `:health_monitor_start_fn` — override health monitor start for testing
  - `:name` — GenServer name (optional)
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Stop the continuous mode GenServer gracefully."
  def stop(pid), do: GenServer.stop(pid, :normal)

  @doc "Get current status: budget info, uptime, last progress, etc."
  def status(pid), do: GenServer.call(pid, :status)

  @doc """
  Notify the continuous runner that a task completed.

  Called by the orchestrator's `on_result` callback. Updates budget spent
  and last progress time.
  """
  def on_task_complete(pid, result) do
    GenServer.cast(pid, {:task_complete, result})
  end

  # -- GenServer callbacks --

  @impl GenServer
  def init(opts) do
    budget_total = Keyword.fetch!(opts, :budget_total)
    hours = Keyword.get(opts, :hours, 8.0)
    repo_path = Keyword.fetch!(opts, :repo_path)
    poll_interval = Keyword.get(opts, :poll_interval, 30_000)
    cost_per_task = Keyword.get(opts, :cost_per_task, @default_cost_per_task)
    watchdog_interval = Keyword.get(opts, :watchdog_interval, @watchdog_interval)
    stall_threshold_ms = Keyword.get(opts, :stall_threshold_ms, @stall_threshold_ms)

    health_url = Keyword.fetch!(opts, :health_url)
    fly_app = Keyword.fetch!(opts, :fly_app)

    bead_create_fn = Keyword.get(opts, :bead_create_fn, &default_bead_create/3)

    orchestrator_start_fn =
      Keyword.get(opts, :orchestrator_start_fn, &default_orchestrator_start/1)

    health_monitor_start_fn =
      Keyword.get(opts, :health_monitor_start_fn, &default_health_monitor_start/1)

    now = System.monotonic_time(:millisecond)

    continuous_pid = self()

    on_result = fn result ->
      on_task_complete(continuous_pid, result)
    end

    orchestrator_result =
      orchestrator_start_fn.(
        repo_path: repo_path,
        poll_interval: poll_interval,
        on_result: on_result,
        name: {:global, {Keiro.Orchestrator, "continuous-#{:erlang.unique_integer([:positive])}"}}
      )

    health_monitor_result =
      health_monitor_start_fn.(
        repo_path: repo_path,
        health_url: health_url,
        fly_app: fly_app,
        name: :"health_monitor_continuous_#{:erlang.unique_integer([:positive])}"
      )

    case {orchestrator_result, health_monitor_result} do
      {{:ok, orch_pid}, {:ok, hm_pid}} ->
        Process.monitor(orch_pid)
        Process.monitor(hm_pid)

        state = %{
          budget_total: budget_total,
          budget_spent: 0.0,
          hours: hours,
          started_at: now,
          last_progress_at: now,
          orchestrator_pid: orch_pid,
          health_monitor_pid: hm_pid,
          repo_path: repo_path,
          cost_per_task: cost_per_task,
          paused: false,
          stall_reported: false,
          watchdog_interval: watchdog_interval,
          stall_threshold_ms: stall_threshold_ms,
          bead_create_fn: bead_create_fn,
          tasks_completed: 0
        }

        schedule_watchdog(watchdog_interval)

        Logger.info(
          "Continuous mode started: budget=$#{budget_total}, hours=#{hours}, " <>
            "repo=#{repo_path}"
        )

        {:ok, state}

      {{:error, reason}, _} ->
        {:stop, {:orchestrator_start_failed, reason}}

      {_, {:error, reason}} ->
        {:stop, {:health_monitor_start_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - state.started_at
    elapsed_hours = elapsed_ms / 3_600_000
    budget_remaining = state.budget_total - state.budget_spent

    elapsed_fraction = elapsed_ms / (state.hours * 3_600_000)

    budget_fraction =
      if state.budget_total > 0, do: state.budget_spent / state.budget_total, else: 0.0

    orchestrator_tripped =
      if Process.alive?(state.orchestrator_pid) do
        try do
          Keiro.Orchestrator.tripped?(state.orchestrator_pid)
        catch
          :exit, _ -> :unknown
        end
      else
        :unknown
      end

    status = %{
      budget_total: state.budget_total,
      budget_spent: state.budget_spent,
      budget_remaining: budget_remaining,
      hours: state.hours,
      elapsed_hours: Float.round(elapsed_hours, 2),
      elapsed_fraction: Float.round(elapsed_fraction, 4),
      budget_fraction: Float.round(budget_fraction, 4),
      paused: state.paused,
      stall_reported: state.stall_reported,
      tasks_completed: state.tasks_completed,
      orchestrator_alive: Process.alive?(state.orchestrator_pid),
      health_monitor_alive: Process.alive?(state.health_monitor_pid),
      orchestrator_tripped: orchestrator_tripped
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast({:task_complete, _result}, state) do
    now = System.monotonic_time(:millisecond)

    state = %{
      state
      | budget_spent: state.budget_spent + state.cost_per_task,
        last_progress_at: now,
        tasks_completed: state.tasks_completed + 1,
        stall_reported: false
    }

    Logger.info(
      "Continuous: task completed (##{state.tasks_completed}), " <>
        "budget spent: $#{Float.round(state.budget_spent, 2)}/$#{state.budget_total}"
    )

    # Check budget pacing after spend update
    state = check_budget_pacing(state, now)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:watchdog, state) do
    now = System.monotonic_time(:millisecond)

    # Check budget exhaustion
    if state.budget_spent >= state.budget_total do
      Logger.info(
        "Continuous: budget exhausted ($#{state.budget_spent}/$#{state.budget_total}), shutting down"
      )

      {:stop, :normal, state}
    else
      # Check time exhaustion
      elapsed_ms = now - state.started_at

      if elapsed_ms >= state.hours * 3_600_000 do
        Logger.info("Continuous: time limit reached (#{state.hours}h), shutting down")
        {:stop, :normal, state}
      else
        state = check_budget_pacing(state, now)
        state = check_stall(state, now)
        schedule_watchdog(state.watchdog_interval)
        {:noreply, state}
      end
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      pid == state.orchestrator_pid ->
        Logger.warning("Continuous: orchestrator exited: #{inspect(reason)}")
        {:stop, {:orchestrator_down, reason}, state}

      pid == state.health_monitor_pid ->
        Logger.warning("Continuous: health monitor exited: #{inspect(reason)}")
        # Health monitor crashing is not fatal — continue without it
        {:noreply, %{state | health_monitor_pid: pid}}

      true ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info(
      "Continuous: shutting down (reason: #{inspect(reason)}), " <>
        "completed #{state.tasks_completed} tasks, spent $#{Float.round(state.budget_spent, 2)}"
    )

    # Best-effort graceful shutdown of children
    safe_stop(state.orchestrator_pid)
    safe_stop(state.health_monitor_pid)

    :ok
  end

  # -- Private --

  defp check_budget_pacing(state, now) do
    elapsed_ms = now - state.started_at
    elapsed_fraction = elapsed_ms / (state.hours * 3_600_000)

    budget_fraction =
      if state.budget_total > 0, do: state.budget_spent / state.budget_total, else: 0.0

    overspending = budget_fraction > elapsed_fraction + 0.1

    cond do
      overspending and not state.paused ->
        Logger.warning(
          "Continuous: pausing — overspending " <>
            "(#{Float.round(budget_fraction * 100, 1)}% budget used, " <>
            "#{Float.round(elapsed_fraction * 100, 1)}% time elapsed)"
        )

        %{state | paused: true}

      not overspending and state.paused ->
        Logger.info("Continuous: resuming — budget pacing back on track")
        %{state | paused: false}

      true ->
        state
    end
  end

  defp check_stall(state, now) do
    stalled = now - state.last_progress_at > state.stall_threshold_ms

    if stalled and not state.stall_reported do
      Logger.warning(
        "Continuous: stall detected — no progress for #{div(state.stall_threshold_ms, 60_000)} minutes"
      )

      create_stall_investigation(state)
      %{state | stall_reported: true}
    else
      state
    end
  end

  defp create_stall_investigation(state) do
    title =
      String.slice(
        "Investigate: orchestrator stall — no progress for " <>
          "#{div(state.stall_threshold_ms, 60_000)} minutes",
        0,
        200
      )

    description = """
    The continuous orchestrator has not completed a task in \
    #{div(state.stall_threshold_ms, 60_000)} minutes.

    Budget: $#{Float.round(state.budget_spent, 2)} / $#{state.budget_total}
    Tasks completed: #{state.tasks_completed}
    Paused: #{state.paused}

    Investigate:
    1. Check if the orchestrator is stuck on a long-running task
    2. Check circuit breaker state
    3. Check if there are ready beads available
    4. Review agent logs for errors
    """

    case state.bead_create_fn.(state.repo_path, title,
           type: "task",
           priority: 1,
           labels: ["ops"],
           description: description
         ) do
      {:ok, id} ->
        Logger.info("Continuous: created stall investigation bead #{id}")

      {:error, reason} ->
        Logger.warning("Continuous: failed to create stall investigation bead: #{reason}")
    end
  end

  defp schedule_watchdog(interval) do
    Process.send_after(self(), :watchdog, interval)
  end

  defp safe_stop(pid) do
    if Process.alive?(pid) do
      try do
        GenServer.stop(pid, :normal, 5_000)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp default_bead_create(repo_path, title, opts) do
    client = BeadsClient.new(repo_path)
    BeadsClient.create(client, title, opts)
  end

  defp default_orchestrator_start(opts) do
    Keiro.Orchestrator.start_link(opts)
  end

  defp default_health_monitor_start(opts) do
    Keiro.Ops.HealthMonitor.start_link(opts)
  end
end
