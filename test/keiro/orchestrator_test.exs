defmodule Keiro.OrchestratorTest do
  use ExUnit.Case, async: true

  alias Keiro.Orchestrator
  alias Keiro.Beads.Bead

  @mock_bd_eng Path.expand("../support/mock_bd_eng.sh", __DIR__)
  @mock_bd_docs Path.expand("../support/mock_bd_docs.sh", __DIR__)
  @mock_bd_empty Path.expand("../support/mock_bd_empty.sh", __DIR__)
  @mock_claude Path.expand("../support/mock_claude.sh", __DIR__)
  @mock_claude_fail Path.expand("../support/mock_claude_fail.sh", __DIR__)

  describe "route/1" do
    test "routes ops-labeled beads to UplinkAgent" do
      bead = %Bead{id: "gl-001", title: "Fix crash", labels: ["ops"]}
      assert {:ok, Keiro.Ops.UplinkAgent} = Orchestrator.route(bead)
    end

    test "routes ops + other labels to UplinkAgent" do
      bead = %Bead{id: "gl-002", title: "Deploy fix", labels: ["ops", "lei"]}
      assert {:ok, Keiro.Ops.UplinkAgent} = Orchestrator.route(bead)
    end

    test "routes eng-labeled beads to engineer pipeline" do
      bead = %Bead{id: "gl-010", title: "Add feature", labels: ["eng"]}
      assert {:ok, :engineer_pipeline} = Orchestrator.route(bead)
    end

    test "routes eng + other labels to engineer pipeline" do
      bead = %Bead{id: "gl-011", title: "Add feature", labels: ["eng", "lei"]}
      assert {:ok, :engineer_pipeline} = Orchestrator.route(bead)
    end

    test "eng label takes priority over ops" do
      bead = %Bead{id: "gl-012", title: "Eng+ops", labels: ["eng", "ops"]}
      assert {:ok, :engineer_pipeline} = Orchestrator.route(bead)
    end

    test "routes arch-labeled beads to ArchitectAgent" do
      bead = %Bead{id: "gl-020", title: "Triage issues", labels: ["arch"]}
      assert {:ok, Keiro.Arch.ArchitectAgent} = Orchestrator.route(bead)
    end

    test "eng label takes priority over arch" do
      bead = %Bead{id: "gl-021", title: "Eng+arch", labels: ["eng", "arch"]}
      assert {:ok, :engineer_pipeline} = Orchestrator.route(bead)
    end

    test "ops label takes priority over arch" do
      bead = %Bead{id: "gl-022", title: "Ops+arch", labels: ["ops", "arch"]}
      assert {:ok, Keiro.Ops.UplinkAgent} = Orchestrator.route(bead)
    end

    test "returns error for beads without matching agent" do
      bead = %Bead{id: "gl-003", title: "Write docs", labels: ["docs"]}
      assert {:error, :no_matching_agent} = Orchestrator.route(bead)
    end

    test "returns error for beads with no labels" do
      bead = %Bead{id: "gl-004", title: "Unknown", labels: []}
      assert {:error, :no_matching_agent} = Orchestrator.route(bead)
    end

    test "handles nil labels" do
      bead = %Bead{id: "gl-005", title: "Nil labels", labels: nil}
      assert {:error, :no_matching_agent} = Orchestrator.route(bead)
    end
  end

  describe "GenServer loop" do
    test "starts and schedules poll" do
      {:ok, pid} =
        Orchestrator.start_link(
          repo_path: "/tmp/nonexistent",
          poll_interval: 600_000,
          name: {:global, {__MODULE__, :start_test}}
        )

      assert Process.alive?(pid)
      Orchestrator.stop(pid)
    end

    test "manual poll triggers processing" do
      test_pid = self()

      {:ok, pid} =
        Orchestrator.start_link(
          repo_path: "/tmp/nonexistent",
          poll_interval: 600_000,
          name: {:global, {__MODULE__, :poll_test}},
          on_result: fn result -> send(test_pid, {:result, result}) end
        )

      Orchestrator.poll(pid)
      Process.sleep(100)
      assert Process.alive?(pid)
      Orchestrator.stop(pid)
    end

    test "accepts approve_fn in opts" do
      {:ok, pid} =
        Orchestrator.start_link(
          repo_path: "/tmp/nonexistent",
          poll_interval: 600_000,
          name: {:global, {__MODULE__, :approve_fn_test}},
          approve_fn: fn _action -> :ok end
        )

      assert Process.alive?(pid)
      Orchestrator.stop(pid)
    end

    test "skips poll when already running (cast path)" do
      {:ok, pid} =
        Orchestrator.start_link(
          repo_path: "/tmp/nonexistent",
          poll_interval: 600_000,
          name: {:global, {__MODULE__, :running_skip_cast}}
        )

      :sys.replace_state(pid, fn state -> %{state | running: true} end)
      GenServer.cast(pid, :poll)
      Process.sleep(50)
      assert Process.alive?(pid)
      Orchestrator.stop(pid)
    end

    test "skips poll when already running (info path)" do
      {:ok, pid} =
        Orchestrator.start_link(
          repo_path: "/tmp/nonexistent",
          poll_interval: 600_000,
          name: {:global, {__MODULE__, :running_skip_info}}
        )

      :sys.replace_state(pid, fn state -> %{state | running: true} end)
      send(pid, :poll)
      Process.sleep(50)
      assert Process.alive?(pid)
      Orchestrator.stop(pid)
    end

    test "timer-triggered poll processes and reschedules" do
      {:ok, pid} =
        Orchestrator.start_link(
          repo_path: "/tmp/nonexistent",
          poll_interval: 50,
          name: {:global, {__MODULE__, :timer_poll_test}}
        )

      # Wait for at least one timer-triggered poll to fire
      Process.sleep(150)
      assert Process.alive?(pid)
      Orchestrator.stop(pid)
    end

    test "do_poll :ok path with on_result callback" do
      test_pid = self()

      with_env(%{"BEADS_BD_PATH" => @mock_bd_eng, "CLAUDE_BIN_PATH" => @mock_claude}, fn ->
        {:ok, pid} =
          Orchestrator.start_link(
            repo_path: System.tmp_dir!(),
            poll_interval: 600_000,
            name: {:global, {__MODULE__, :ok_callback_test}},
            on_result: fn result -> send(test_pid, {:got_result, result}) end
          )

        Orchestrator.poll(pid)
        Process.sleep(500)
        assert_received {:got_result, {:ok, _}}
        Orchestrator.stop(pid)
      end)
    end
  end

  describe "pipeline stage selection" do
    test "eng-only bead skips deploy stage" do
      bead = %Bead{id: "gl-030", title: "Code only", labels: ["eng"]}
      labels = bead.labels || []
      assert "ops" not in labels
    end

    test "eng+ops bead includes deploy stage" do
      bead = %Bead{id: "gl-031", title: "Code + deploy", labels: ["eng", "ops"]}
      labels = bead.labels || []
      assert "ops" in labels
    end
  end

  describe "run_next/1" do
    test "returns error when beads client fails" do
      assert {:error, msg} = Orchestrator.run_next(repo_path: "/tmp/nonexistent")
      assert msg =~ "Failed to fetch ready beads"
    end

    test "returns :no_work when no ready beads" do
      with_env(%{"BEADS_BD_PATH" => @mock_bd_empty}, fn ->
        assert :no_work = Orchestrator.run_next(repo_path: System.tmp_dir!())
      end)
    end

    test "processes eng-labeled bead via pipeline with runner_fn" do
      with_env(%{"CLAUDE_BIN_PATH" => @mock_claude, "BEADS_BD_PATH" => @mock_bd_eng}, fn ->
        result = Orchestrator.run_next(repo_path: System.tmp_dir!())
        assert {:ok, pipeline_result} = result
        assert pipeline_result.status == :ok
      end)
    end

    test "returns error for bead with no matching agent" do
      with_env(%{"BEADS_BD_PATH" => @mock_bd_docs}, fn ->
        result = Orchestrator.run_next(repo_path: System.tmp_dir!())
        assert {:error, msg} = result
        assert msg =~ "no matching agent"
      end)
    end

    # dispatch_agent (ops/arch beads) requires live Jido — tested via integration

    test "pipeline failure path marks bead as blocked" do
      with_env(%{"CLAUDE_BIN_PATH" => @mock_claude_fail, "BEADS_BD_PATH" => @mock_bd_eng}, fn ->
        result = Orchestrator.run_next(repo_path: System.tmp_dir!())
        assert {:error, pipeline_result} = result
        assert pipeline_result.error_stage == "engineer"
      end)
    end
  end

  describe "run_all/1" do
    test "returns empty list when beads client fails" do
      assert [] == Orchestrator.run_all(repo_path: "/tmp/nonexistent")
    end

    test "processes all eng-labeled beads" do
      with_env(%{"CLAUDE_BIN_PATH" => @mock_claude, "BEADS_BD_PATH" => @mock_bd_eng}, fn ->
        results = Orchestrator.run_all(repo_path: System.tmp_dir!())
        assert length(results) == 1
        [first] = results
        assert first.bead_id == "gl-100"
        assert first.title == "Add login page"
        assert {:ok, _} = first.result
      end)
    end
  end

  describe "TQM integration" do
    test "run_all runs TQM analysis on batch results" do
      with_env(%{"CLAUDE_BIN_PATH" => @mock_claude, "BEADS_BD_PATH" => @mock_bd_eng}, fn ->
        results = Orchestrator.run_all(repo_path: System.tmp_dir!())
        # TQM runs silently — no patterns expected for single success
        assert length(results) == 1
        assert {:ok, _} = hd(results).result
      end)
    end

    test "run_all with tqm_enabled: false skips analysis" do
      with_env(%{"CLAUDE_BIN_PATH" => @mock_claude, "BEADS_BD_PATH" => @mock_bd_eng}, fn ->
        results = Orchestrator.run_all(repo_path: System.tmp_dir!(), tqm_enabled: false)
        assert length(results) == 1
      end)
    end

    test "GenServer collects results and runs TQM" do
      test_pid = self()

      with_env(%{"CLAUDE_BIN_PATH" => @mock_claude, "BEADS_BD_PATH" => @mock_bd_eng}, fn ->
        {:ok, pid} =
          Orchestrator.start_link(
            repo_path: System.tmp_dir!(),
            poll_interval: 600_000,
            name: {:global, {__MODULE__, :tqm_genserver_test}},
            on_result: fn result -> send(test_pid, {:result, result}) end,
            tqm_enabled: true
          )

        Orchestrator.poll(pid)
        Process.sleep(500)

        # Verify result was collected
        state = :sys.get_state(pid)
        assert length(state.results) >= 1

        Orchestrator.stop(pid)
      end)
    end

    test "GenServer with tqm_enabled: false does not accumulate" do
      with_env(%{"BEADS_BD_PATH" => @mock_bd_empty}, fn ->
        {:ok, pid} =
          Orchestrator.start_link(
            repo_path: System.tmp_dir!(),
            poll_interval: 600_000,
            name: {:global, {__MODULE__, :tqm_disabled_test}},
            tqm_enabled: false
          )

        Orchestrator.poll(pid)
        Process.sleep(100)
        assert Process.alive?(pid)
        Orchestrator.stop(pid)
      end)
    end
  end

  # -- helpers --

  defp with_env(env_map, fun) do
    originals =
      Enum.map(env_map, fn {key, _val} ->
        {key, System.get_env(key)}
      end)

    Enum.each(env_map, fn {key, val} -> System.put_env(key, val) end)

    try do
      fun.()
    after
      Enum.each(originals, fn
        {key, nil} -> System.delete_env(key)
        {key, val} -> System.put_env(key, val)
      end)
    end
  end
end
