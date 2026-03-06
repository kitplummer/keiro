defmodule Keiro.Pipeline.ShapeTest do
  use ExUnit.Case, async: true

  alias Keiro.Beads.Bead
  alias Keiro.Eng.Shape, as: EngShape
  alias Keiro.Ops.Shape, as: OpsShape

  describe "Eng.Shape.match?/1" do
    test "matches beads with eng label" do
      bead = %Bead{id: "gl-001", title: "Add feature", labels: ["eng"]}
      assert EngShape.match?(bead)
    end

    test "matches beads with eng + other labels" do
      bead = %Bead{id: "gl-002", title: "Add feature", labels: ["eng", "lei"]}
      assert EngShape.match?(bead)
    end

    test "does not match beads without eng label" do
      bead = %Bead{id: "gl-003", title: "Fix crash", labels: ["ops"]}
      refute EngShape.match?(bead)
    end

    test "does not match beads with no labels" do
      bead = %Bead{id: "gl-004", title: "Unknown", labels: []}
      refute EngShape.match?(bead)
    end

    test "handles nil labels" do
      bead = %Bead{id: "gl-005", title: "Nil labels", labels: nil}
      refute EngShape.match?(bead)
    end
  end

  describe "Eng.Shape.stages/2" do
    setup do
      bead = %Bead{id: "gl-010", title: "Build widget", description: "Build it well."}
      %{bead: bead}
    end

    test "returns two stages: engineer and verify", %{bead: bead} do
      stages = EngShape.stages(bead, [])
      assert length(stages) == 2
      assert [eng, verify] = stages
      assert eng.name == "engineer"
      assert verify.name == "verify"
    end

    test "engineer stage uses EngineerAgent", %{bead: bead} do
      [eng | _] = EngShape.stages(bead, [])
      assert eng.agent_module == Keiro.Eng.EngineerAgent
    end

    test "verify stage uses VerifyAgent", %{bead: bead} do
      [_, verify] = EngShape.stages(bead, [])
      assert verify.agent_module == Keiro.Eng.VerifyAgent
    end

    test "threads timeout option", %{bead: bead} do
      stages = EngShape.stages(bead, timeout: 5_000)
      assert Enum.all?(stages, fn s -> s.timeout == 5_000 end)
    end

    test "uses default timeout when not specified", %{bead: bead} do
      stages = EngShape.stages(bead, [])
      assert Enum.all?(stages, fn s -> s.timeout == 120_000 end)
    end

    test "engineer prompt includes bead id and title", %{bead: bead} do
      [eng | _] = EngShape.stages(bead, [])
      prompt = eng.prompt_fn.(bead, [])
      assert prompt =~ "gl-010"
      assert prompt =~ "Build widget"
      assert prompt =~ "Build it well."
      assert prompt =~ "Implement this task"
    end

    test "verify prompt includes bead id and verification instructions", %{bead: bead} do
      [_, verify] = EngShape.stages(bead, [])
      prev = [%{result: "PR #42 opened"}]
      prompt = verify.prompt_fn.(bead, prev)
      assert prompt =~ "gl-010"
      assert prompt =~ "verification checks"
      assert prompt =~ "mix test"
      assert prompt =~ "PR #42 opened"
    end

    test "verify prompt handles empty prev_stages", %{bead: bead} do
      [_, verify] = EngShape.stages(bead, [])
      prompt = verify.prompt_fn.(bead, [])
      assert prompt =~ "verification checks"
      refute prompt =~ "Engineer stage result"
    end
  end

  describe "Ops.Shape.match?/1" do
    test "matches beads with ops label" do
      bead = %Bead{id: "gl-100", title: "Fix crash", labels: ["ops"]}
      assert OpsShape.match?(bead)
    end

    test "matches beads with ops + other labels" do
      bead = %Bead{id: "gl-101", title: "Fix crash", labels: ["ops", "lei"]}
      assert OpsShape.match?(bead)
    end

    test "does not match beads without ops label" do
      bead = %Bead{id: "gl-102", title: "Add feature", labels: ["eng"]}
      refute OpsShape.match?(bead)
    end

    test "does not match beads with no labels" do
      bead = %Bead{id: "gl-103", title: "Unknown", labels: []}
      refute OpsShape.match?(bead)
    end

    test "handles nil labels" do
      bead = %Bead{id: "gl-104", title: "Nil labels", labels: nil}
      refute OpsShape.match?(bead)
    end
  end

  describe "Ops.Shape.stages/2" do
    setup do
      bead = %Bead{id: "gl-200", title: "Fix crash-loop", description: "Pods restarting."}
      %{bead: bead}
    end

    test "returns single ops stage", %{bead: bead} do
      stages = OpsShape.stages(bead, [])
      assert length(stages) == 1
      assert [ops] = stages
      assert ops.name == "ops"
    end

    test "ops stage uses UplinkAgent", %{bead: bead} do
      [ops] = OpsShape.stages(bead, [])
      assert ops.agent_module == Keiro.Ops.UplinkAgent
    end

    test "threads timeout option", %{bead: bead} do
      [ops] = OpsShape.stages(bead, timeout: 10_000)
      assert ops.timeout == 10_000
    end

    test "uses default timeout when not specified", %{bead: bead} do
      [ops] = OpsShape.stages(bead, [])
      assert ops.timeout == 120_000
    end

    test "ops prompt includes bead id and title", %{bead: bead} do
      [ops] = OpsShape.stages(bead, [])
      prompt = ops.prompt_fn.(bead, [])
      assert prompt =~ "gl-200"
      assert prompt =~ "Fix crash-loop"
      assert prompt =~ "Pods restarting."
    end

    test "ops prompt includes smoke test instructions", %{bead: bead} do
      [ops] = OpsShape.stages(bead, [])
      prompt = ops.prompt_fn.(bead, [])
      assert prompt =~ "smoke test"
      assert prompt =~ "https://lowendinsight.dev"
      assert prompt =~ "fly_smoke_test"
    end

    test "ops prompt uses fallback for nil description" do
      bead = %Bead{id: "gl-201", title: "No desc", labels: ["ops"], description: nil}
      [ops] = OpsShape.stages(bead, [])
      prompt = ops.prompt_fn.(bead, [])
      assert prompt =~ "No description."
    end
  end
end
