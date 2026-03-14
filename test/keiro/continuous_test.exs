defmodule Keiro.ContinuousTest do
  use ExUnit.Case, async: true

  alias Keiro.Continuous

  # A minimal GenServer that responds to :tripped? like the real orchestrator
  defmodule MockOrchestrator do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl GenServer
    def init(opts), do: {:ok, %{opts: opts, tripped: false}}

    @impl GenServer
    def handle_call(:tripped?, _from, state), do: {:reply, state.tripped, state}
    def handle_call(:resume, _from, state), do: {:reply, :ok, %{state | tripped: false}}
    def handle_call(:busy?, _from, state), do: {:reply, Map.get(state, :busy, false), state}

    def handle_call({:set_busy, busy}, _from, state),
      do: {:reply, :ok, Map.put(state, :busy, busy)}
  end

  defp mock_orchestrator_start(opts) do
    MockOrchestrator.start_link(opts)
  end

  defp mock_health_monitor_start(_opts) do
    Agent.start_link(fn -> %{} end)
  end

  defp base_opts do
    [
      budget_total: 10.0,
      hours: 8.0,
      repo_path: "/tmp/test-repo",
      poll_interval: 600_000,
      health_url: "https://example.com/health",
      fly_app: "test-app",
      cost_per_task: 0.10,
      # Long watchdog interval so it doesn't fire during tests
      watchdog_interval: 600_000,
      stall_threshold_ms: 30 * 60_000,
      bead_create_fn: fn _repo, _title, _opts -> {:ok, "gl-test-001"} end,
      orchestrator_start_fn: &mock_orchestrator_start/1,
      health_monitor_start_fn: &mock_health_monitor_start/1
    ]
  end

  defp start_continuous(overrides \\ []) do
    opts =
      base_opts()
      |> Keyword.merge(overrides)
      |> Keyword.put_new(:name, :"continuous_#{:erlang.unique_integer([:positive])}")

    start_supervised!({Continuous, opts})
  end

  describe "start_link and lifecycle" do
    test "starts orchestrator and health monitor" do
      pid = start_continuous()
      assert Process.alive?(pid)

      status = Continuous.status(pid)
      assert status.orchestrator_alive == true
      assert status.health_monitor_alive == true
    end

    test "stops gracefully" do
      pid = start_continuous()
      assert Process.alive?(pid)
      Continuous.stop(pid)
      refute Process.alive?(pid)
    end

    test "fails if orchestrator fails to start" do
      Process.flag(:trap_exit, true)

      opts =
        base_opts()
        |> Keyword.merge(orchestrator_start_fn: fn _opts -> {:error, :test_failure} end)

      assert {:error, {:orchestrator_start_failed, :test_failure}} =
               Continuous.start_link(opts)
    end

    test "fails if health monitor fails to start" do
      Process.flag(:trap_exit, true)

      opts =
        base_opts()
        |> Keyword.merge(health_monitor_start_fn: fn _opts -> {:error, :test_failure} end)

      assert {:error, {:health_monitor_start_failed, :test_failure}} =
               Continuous.start_link(opts)
    end
  end

  describe "status/1" do
    test "returns meaningful data" do
      pid = start_continuous(budget_total: 50.0, hours: 4.0)
      status = Continuous.status(pid)

      assert status.budget_total == 50.0
      assert status.budget_spent == 0.0
      assert status.budget_remaining == 50.0
      assert status.hours == 4.0
      assert is_float(status.elapsed_hours)
      assert is_float(status.elapsed_fraction)
      assert status.budget_fraction == 0.0
      assert status.paused == false
      assert status.stall_reported == false
      assert status.tasks_completed == 0
      assert status.orchestrator_alive == true
      assert status.health_monitor_alive == true
      assert status.orchestrator_tripped == false
    end
  end

  describe "tracks budget spent" do
    test "updates budget on task complete" do
      pid = start_continuous(cost_per_task: 0.50)

      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      # Synchronize with a call
      status = Continuous.status(pid)

      assert status.budget_spent == 0.50
      assert status.budget_remaining == 9.50
      assert status.tasks_completed == 1
    end

    test "accumulates budget across multiple tasks" do
      pid = start_continuous(cost_per_task: 0.25)

      for _ <- 1..4 do
        Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      end

      status = Continuous.status(pid)
      assert_in_delta status.budget_spent, 1.0, 0.001
      assert status.tasks_completed == 4
    end
  end

  describe "pauses when overspending" do
    test "pauses when budget fraction exceeds elapsed fraction by 10%" do
      # budget_total: 1.0, hours: 8.0, cost_per_task: 0.50
      # At start (elapsed_fraction ~0.0), spending $0.50 of $1.0 = 50% budget
      # 50% >> 0% + 10%, so should pause
      pid = start_continuous(budget_total: 1.0, cost_per_task: 0.50)

      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      status = Continuous.status(pid)

      assert status.paused == true
      assert status.budget_spent == 0.50
    end

    test "does not pause when spending is within budget" do
      # budget_total: 100.0, hours: 8.0, cost_per_task: 0.10
      # Spending $0.10 of $100 = 0.1% — well within budget
      pid = start_continuous(budget_total: 100.0, cost_per_task: 0.10)

      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      status = Continuous.status(pid)

      assert status.paused == false
    end
  end

  describe "watchdog detects stall" do
    test "creates investigation bead on stall" do
      test_pid = self()

      pid =
        start_continuous(
          # Very short stall threshold for testing
          stall_threshold_ms: 1,
          # Short watchdog interval so it fires quickly
          watchdog_interval: 50,
          bead_create_fn: fn repo, title, opts ->
            send(test_pid, {:bead_created, repo, title, opts})
            {:ok, "gl-stall-001"}
          end
        )

      # Wait for watchdog to fire
      assert_receive {:bead_created, "/tmp/test-repo", title, opts}, 1_000

      assert title =~ "orchestrator stall"
      assert Keyword.get(opts, :type) == "task"
      assert Keyword.get(opts, :priority) == 1
      assert Keyword.get(opts, :labels) == ["ops"]
      assert Keyword.get(opts, :description) =~ "has not completed a task"

      status = Continuous.status(pid)
      assert status.stall_reported == true
    end

    test "does not duplicate stall investigation" do
      test_pid = self()
      call_count = :counters.new(1, [:atomics])

      _pid =
        start_continuous(
          stall_threshold_ms: 1,
          watchdog_interval: 50,
          bead_create_fn: fn _repo, _title, _opts ->
            :counters.add(call_count, 1, 1)
            send(test_pid, :bead_created)
            {:ok, "gl-stall-001"}
          end
        )

      # Wait for first bead creation
      assert_receive :bead_created, 1_000

      # Give time for multiple watchdog ticks
      Process.sleep(200)

      # Should only have created one bead
      assert :counters.get(call_count, 1) == 1
    end

    test "resets stall flag on task progress" do
      pid =
        start_continuous(
          stall_threshold_ms: 1,
          watchdog_interval: 600_000
        )

      # Wait long enough for the stall threshold (1ms) to elapse
      Process.sleep(10)

      # Manually trigger watchdog to mark stall
      send(pid, :watchdog)
      # Synchronize
      status = Continuous.status(pid)
      assert status.stall_reported == true

      # Task completion resets stall
      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      status = Continuous.status(pid)
      assert status.stall_reported == false
    end
  end

  describe "budget exhaustion shutdown" do
    test "shuts down when budget is fully spent" do
      Process.flag(:trap_exit, true)

      pid =
        start_continuous(
          budget_total: 0.20,
          cost_per_task: 0.10,
          watchdog_interval: 50
        )

      # Spend the full budget
      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-002"}})

      # Wait for watchdog to detect exhaustion
      Process.sleep(200)

      # The process should have stopped (or be stopping)
      refute Process.alive?(pid)
    end

    test "waits for in-flight task before shutting down on budget exhaustion" do
      Process.flag(:trap_exit, true)

      orch_pid_holder = :ets.new(:orch_drain, [:set, :public])

      pid =
        start_continuous(
          budget_total: 0.10,
          cost_per_task: 0.10,
          watchdog_interval: 50,
          orchestrator_start_fn: fn opts ->
            {:ok, orch_pid} = mock_orchestrator_start(opts)
            :ets.insert(orch_pid_holder, {:pid, orch_pid})
            {:ok, orch_pid}
          end
        )

      # Spend the full budget
      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      # Wait for watchdog to see budget exhaustion
      Process.sleep(200)

      # Should have shut down since orchestrator is not busy
      refute Process.alive?(pid)
      :ets.delete(orch_pid_holder)
    end

    test "drains when orchestrator is busy at budget exhaustion" do
      Process.flag(:trap_exit, true)

      orch_pid_holder = :ets.new(:orch_drain2, [:set, :public])

      pid =
        start_continuous(
          budget_total: 0.10,
          cost_per_task: 0.10,
          watchdog_interval: 50,
          orchestrator_start_fn: fn opts ->
            {:ok, orch_pid} = mock_orchestrator_start(opts)
            :ets.insert(orch_pid_holder, {:pid, orch_pid})
            # Mark orchestrator as busy (simulating an in-flight task)
            GenServer.call(orch_pid, {:set_busy, true})
            {:ok, orch_pid}
          end
        )

      # Spend the full budget — but orchestrator is "busy"
      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-001"}})
      # Wait for watchdog to see budget exhaustion
      Process.sleep(200)

      # Should still be alive — draining, waiting for orchestrator
      assert Process.alive?(pid)

      # Now simulate the orchestrator finishing its task
      [{:pid, orch_pid}] = :ets.lookup(orch_pid_holder, :pid)
      GenServer.call(orch_pid, {:set_busy, false})
      Continuous.on_task_complete(pid, {:ok, %{bead_id: "gl-002"}})

      # Should shut down after the task completes
      Process.sleep(100)
      refute Process.alive?(pid)

      :ets.delete(orch_pid_holder)
    end
  end

  describe "orchestrator DOWN handling" do
    test "stops when orchestrator crashes" do
      Process.flag(:trap_exit, true)

      orch_pid_holder = :ets.new(:orch_holder, [:set, :public])

      pid =
        start_continuous(
          orchestrator_start_fn: fn opts ->
            {:ok, orch_pid} = mock_orchestrator_start(opts)
            :ets.insert(orch_pid_holder, {:pid, orch_pid})
            {:ok, orch_pid}
          end
        )

      status = Continuous.status(pid)
      assert status.orchestrator_alive == true

      [{:pid, orch_pid}] = :ets.lookup(orch_pid_holder, :pid)
      Process.exit(orch_pid, :kill)

      # Give time for the DOWN message to propagate
      Process.sleep(100)

      refute Process.alive?(pid)
      :ets.delete(orch_pid_holder)
    end
  end

  describe "bead creation failure handling" do
    test "survives bead creation failure in stall watchdog" do
      pid =
        start_continuous(
          stall_threshold_ms: 1,
          watchdog_interval: 50,
          bead_create_fn: fn _repo, _title, _opts ->
            {:error, "bd not found"}
          end
        )

      # Wait for watchdog to fire
      Process.sleep(200)

      # Should still be alive despite bead creation failure
      assert Process.alive?(pid)
    end
  end
end
