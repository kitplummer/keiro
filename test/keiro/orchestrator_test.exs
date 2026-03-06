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
end
