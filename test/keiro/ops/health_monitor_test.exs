defmodule Keiro.Ops.HealthMonitorTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.HealthMonitor

  defp base_opts do
    [
      repo_path: "/tmp/test-repo",
      health_url: "https://example.com/health",
      fly_app: "test-app",
      # Long interval so scheduled checks don't fire during tests
      check_interval: 600_000,
      enabled: true,
      http_check_fn: fn _url -> :ok end,
      fly_check_fn: fn _app -> :ok end,
      bead_create_fn: fn _repo, _title, _opts -> {:ok, "gl-test-001"} end
    ]
  end

  defp start_monitor(overrides \\ []) do
    opts =
      base_opts()
      |> Keyword.merge(overrides)
      |> Keyword.put_new(:name, :"hm_#{:erlang.unique_integer([:positive])}")

    start_supervised!({HealthMonitor, opts})
  end

  describe "start_link and lifecycle" do
    test "starts and is alive" do
      pid = start_monitor()
      assert Process.alive?(pid)
    end

    test "starts with enabled: true and schedules check" do
      pid = start_monitor(enabled: true, check_interval: 600_000)
      assert Process.alive?(pid)
      assert HealthMonitor.enabled?(pid)
    end

    test "accepts custom name" do
      name = :"health_monitor_custom_#{:erlang.unique_integer([:positive])}"
      pid = start_monitor(name: name)
      assert Process.alive?(pid)
      assert GenServer.whereis(name) == pid
    end
  end

  describe "status/1" do
    test "reports initial state" do
      pid = start_monitor()
      status = HealthMonitor.status(pid)

      assert status.status == :unknown
      assert status.consecutive_failures == 0
      assert status.last_check_at == nil
      assert status.investigation_created == false
    end

    test "reports healthy after successful check" do
      pid = start_monitor()
      send(pid, :check)
      # GenServer.call acts as a synchronization barrier — the :check message
      # is processed before the call returns because it was enqueued first
      _ = HealthMonitor.status(pid)

      status = HealthMonitor.status(pid)
      assert status.status == :healthy
      assert status.consecutive_failures == 0
      assert status.last_check_at != nil
    end
  end

  describe "enabled?/1" do
    test "returns true when enabled" do
      pid = start_monitor(enabled: true)
      assert HealthMonitor.enabled?(pid) == true
    end

    test "returns false when disabled" do
      pid = start_monitor(enabled: false)
      assert HealthMonitor.enabled?(pid) == false
    end
  end

  describe "disabled monitor" do
    test "skips checks when disabled" do
      pid = start_monitor(enabled: false)
      initial = HealthMonitor.status(pid)

      send(pid, :check)
      # Synchronize — the :check handle_info runs before this call returns
      _ = HealthMonitor.status(pid)

      after_check = HealthMonitor.status(pid)
      assert after_check == initial
    end
  end

  describe "consecutive failure tracking" do
    test "increments on failure" do
      pid =
        start_monitor(
          http_check_fn: fn _url -> {:error, "timeout"} end,
          fly_check_fn: fn _app -> :ok end
        )

      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 1

      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 2
    end

    test "increments when fly check fails" do
      pid =
        start_monitor(
          http_check_fn: fn _url -> :ok end,
          fly_check_fn: fn _app -> {:error, "not running"} end
        )

      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 1
      assert HealthMonitor.status(pid).status == :unhealthy
    end

    test "increments when both checks fail" do
      pid =
        start_monitor(
          http_check_fn: fn _url -> {:error, "connection refused"} end,
          fly_check_fn: fn _app -> {:error, "not running"} end
        )

      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 1
    end
  end

  describe "recovery" do
    test "resets consecutive failures on recovery" do
      call_count = :counters.new(1, [:atomics])

      pid =
        start_monitor(
          http_check_fn: fn _url ->
            if :counters.get(call_count, 1) < 2 do
              :counters.add(call_count, 1, 1)
              {:error, "timeout"}
            else
              :ok
            end
          end,
          fly_check_fn: fn _app -> :ok end
        )

      # Two failures
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 1

      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 2

      # Recovery
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).consecutive_failures == 0
      assert HealthMonitor.status(pid).status == :healthy
    end

    test "resets investigation_created flag on recovery" do
      call_count = :counters.new(1, [:atomics])

      pid =
        start_monitor(
          max_consecutive_failures: 1,
          http_check_fn: fn _url ->
            if :counters.get(call_count, 1) < 1 do
              :counters.add(call_count, 1, 1)
              {:error, "timeout"}
            else
              :ok
            end
          end,
          fly_check_fn: fn _app -> :ok end
        )

      # Trigger investigation
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).investigation_created == true

      # Recover
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert HealthMonitor.status(pid).investigation_created == false
    end
  end

  describe "investigation bead creation" do
    test "creates bead after max consecutive failures" do
      test_pid = self()

      pid =
        start_monitor(
          max_consecutive_failures: 2,
          http_check_fn: fn _url -> {:error, "connection refused"} end,
          fly_check_fn: fn _app -> {:error, "not running"} end,
          bead_create_fn: fn repo, title, opts ->
            send(test_pid, {:bead_created, repo, title, opts})
            {:ok, "gl-investigation-001"}
          end
        )

      # First failure - no bead yet
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      refute_received {:bead_created, _, _, _}

      # Second failure - threshold reached, bead created
      send(pid, :check)
      _ = HealthMonitor.status(pid)

      assert_received {:bead_created, "/tmp/test-repo", title, opts}
      assert title =~ "Health alert: test-app unhealthy"
      assert title =~ "2 consecutive failures"
      assert Keyword.get(opts, :type) == "task"
      assert Keyword.get(opts, :priority) == 0
      assert Keyword.get(opts, :labels) == ["ops"]
      assert Keyword.get(opts, :description) =~ "connection refused"
      assert Keyword.get(opts, :description) =~ "not running"
    end

    test "does not create duplicate investigation bead" do
      test_pid = self()

      pid =
        start_monitor(
          max_consecutive_failures: 1,
          http_check_fn: fn _url -> {:error, "timeout"} end,
          fly_check_fn: fn _app -> {:error, "not running"} end,
          bead_create_fn: fn _repo, _title, _opts ->
            send(test_pid, :bead_created)
            {:ok, "gl-investigation-001"}
          end
        )

      # First check triggers bead
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert_received :bead_created

      # Subsequent failures don't create more beads
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      refute_received :bead_created

      send(pid, :check)
      _ = HealthMonitor.status(pid)
      refute_received :bead_created
    end

    test "handles bead creation failure gracefully" do
      pid =
        start_monitor(
          max_consecutive_failures: 1,
          http_check_fn: fn _url -> {:error, "timeout"} end,
          fly_check_fn: fn _app -> :ok end,
          bead_create_fn: fn _repo, _title, _opts ->
            {:error, "bd not found"}
          end
        )

      # Should not crash even when bead creation fails
      send(pid, :check)
      _ = HealthMonitor.status(pid)
      assert Process.alive?(pid)
      assert HealthMonitor.status(pid).investigation_created == true
    end
  end

  describe "check scheduling" do
    test "schedules next check after processing" do
      pid =
        start_monitor(
          check_interval: 50,
          http_check_fn: fn _url -> :ok end,
          fly_check_fn: fn _app -> :ok end
        )

      # Trigger a check
      send(pid, :check)
      _ = HealthMonitor.status(pid)

      # Wait for the auto-scheduled next check to fire
      Process.sleep(100)

      status = HealthMonitor.status(pid)
      assert status.last_check_at != nil
      assert status.status == :healthy
    end
  end
end
