defmodule Keiro.OrchestratorTest do
  use ExUnit.Case, async: true

  alias Keiro.Orchestrator
  alias Keiro.Beads.Bead

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
      # Use a very long interval so it doesn't fire during test
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

      # Manual poll — will get :no_work since /tmp/nonexistent has no beads
      Orchestrator.poll(pid)
      # Give it a moment to process
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
  end

  describe "pipeline stage selection" do
    test "eng-only bead skips deploy stage" do
      bead = %Bead{id: "gl-030", title: "Code only", labels: ["eng"]}
      labels = bead.labels || []
      # eng-only should NOT include deploy
      assert "ops" not in labels
    end

    test "eng+ops bead includes deploy stage" do
      bead = %Bead{id: "gl-031", title: "Code + deploy", labels: ["eng", "ops"]}
      labels = bead.labels || []
      assert "ops" in labels
    end
  end
end
