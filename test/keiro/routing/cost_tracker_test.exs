defmodule Keiro.Routing.CostTrackerTest do
  use ExUnit.Case, async: true

  alias Keiro.Routing.CostTracker

  setup do
    name = :"tracker_#{System.unique_integer([:positive])}"
    {:ok, pid} = CostTracker.start_link(name: name)
    %{tracker: pid}
  end

  describe "record/4 and total_cost/1" do
    test "starts at zero", %{tracker: tracker} do
      assert CostTracker.total_cost(tracker) == 0.0
    end

    test "accumulates cost from entries", %{tracker: tracker} do
      CostTracker.record(tracker, "gl-001", "planner", %{
        input_tokens: 1000,
        output_tokens: 500,
        cost: 0.05,
        model: "sonnet"
      })

      CostTracker.record(tracker, "gl-001", "implementer", %{
        input_tokens: 5000,
        output_tokens: 2000,
        cost: 0.35,
        model: "sonnet"
      })

      assert_in_delta CostTracker.total_cost(tracker), 0.40, 0.001
    end
  end

  describe "task_cost/2" do
    test "returns cost for a specific task", %{tracker: tracker} do
      CostTracker.record(tracker, "gl-001", "planner", %{cost: 0.10, model: "sonnet"})
      CostTracker.record(tracker, "gl-002", "planner", %{cost: 0.20, model: "sonnet"})
      CostTracker.record(tracker, "gl-001", "debugger", %{cost: 0.02, model: "flash"})

      assert_in_delta CostTracker.task_cost(tracker, "gl-001"), 0.12, 0.001
      assert_in_delta CostTracker.task_cost(tracker, "gl-002"), 0.20, 0.001
    end

    test "returns 0 for unknown task", %{tracker: tracker} do
      assert CostTracker.task_cost(tracker, "nonexistent") == 0.0
    end
  end

  describe "entries/3" do
    test "returns entries for a task/role pair", %{tracker: tracker} do
      entry = %{input_tokens: 1000, output_tokens: 500, cost: 0.05, model: "sonnet"}
      CostTracker.record(tracker, "gl-001", "planner", entry)

      entries = CostTracker.entries(tracker, "gl-001", "planner")
      assert length(entries) == 1
      assert hd(entries).cost == 0.05
    end

    test "returns empty list for unknown pair", %{tracker: tracker} do
      assert CostTracker.entries(tracker, "gl-001", "planner") == []
    end
  end

  describe "summary/1" do
    test "returns full state", %{tracker: tracker} do
      CostTracker.record(tracker, "gl-001", "planner", %{cost: 0.10, model: "sonnet"})

      summary = CostTracker.summary(tracker)
      assert is_map(summary.entries)
      assert_in_delta summary.total_cost, 0.10, 0.001
    end
  end
end
