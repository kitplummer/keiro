defmodule Keiro.Pipeline.OutcomeContextTest do
  use ExUnit.Case, async: true

  alias Keiro.Pipeline.OutcomeContext
  alias Keiro.Pipeline.Result
  alias Keiro.Pipeline.Result.StageResult

  describe "from_result/1" do
    test "builds context from successful result" do
      result = %Result{
        status: :ok,
        stages: [
          %StageResult{name: "engineer", status: :ok, result: "done", elapsed_ms: 5000},
          %StageResult{name: "deploy", status: :ok, result: "deployed", elapsed_ms: 3000}
        ]
      }

      ctx = OutcomeContext.from_result(result)
      assert ctx.outcome == :completed
      assert ctx.approach =~ "engineer"
      assert ctx.approach =~ "deploy"
      assert ctx.obstacle == nil
      assert length(ctx.discoveries) == 2
      assert Enum.any?(ctx.discoveries, &(&1 =~ "engineer completed"))
      assert Enum.any?(ctx.discoveries, &(&1 =~ "deploy completed"))
    end

    test "builds context from failed result" do
      result = %Result{
        status: :error,
        error_stage: "deploy",
        stages: [
          %StageResult{name: "engineer", status: :ok, result: "done", elapsed_ms: 5000},
          %StageResult{
            name: "deploy",
            status: :error,
            result: "compilation failed",
            elapsed_ms: 1000
          }
        ]
      }

      ctx = OutcomeContext.from_result(result)
      assert ctx.outcome == :blocked
      assert ctx.approach =~ "engineer → deploy"
      assert ctx.obstacle =~ "deploy: compilation failed"
      assert length(ctx.discoveries) == 1
    end

    test "builds context from empty stages" do
      result = %Result{status: :ok, stages: []}
      ctx = OutcomeContext.from_result(result)
      assert ctx.outcome == :completed
      assert ctx.approach == nil
      assert ctx.obstacle == nil
      assert ctx.discoveries == []
    end

    test "truncates long error messages in obstacle" do
      long_error = String.duplicate("x", 300)

      result = %Result{
        status: :error,
        stages: [
          %StageResult{name: "eng", status: :error, result: long_error, elapsed_ms: 0}
        ]
      }

      ctx = OutcomeContext.from_result(result)
      assert ctx.obstacle =~ "..."
      assert byte_size(ctx.obstacle) < byte_size(long_error) + 50
    end
  end

  describe "to_markdown/1" do
    test "formats completed context" do
      ctx = %OutcomeContext{
        outcome: :completed,
        approach: "Ran stages: engineer → deploy",
        discoveries: ["engineer completed in 5000ms", "deploy completed in 3000ms"]
      }

      md = OutcomeContext.to_markdown(ctx)
      assert md =~ "## Outcome: completed"
      assert md =~ "### Approach"
      assert md =~ "engineer → deploy"
      assert md =~ "### Discoveries"
      assert md =~ "- engineer completed"
      refute md =~ "### Obstacle"
      refute md =~ "### Recommendation"
    end

    test "formats blocked context with obstacle" do
      ctx = %OutcomeContext{
        outcome: :blocked,
        approach: "Ran stages: engineer",
        obstacle: "compilation failed",
        recommendation: "Fix syntax errors in auth.ex"
      }

      md = OutcomeContext.to_markdown(ctx)
      assert md =~ "## Outcome: blocked"
      assert md =~ "### Obstacle"
      assert md =~ "compilation failed"
      assert md =~ "### Recommendation"
      assert md =~ "Fix syntax errors"
    end

    test "formats context with explored_state" do
      ctx = %OutcomeContext{
        outcome: :retryable,
        explored_state: ["lib/auth.ex", "test/auth_test.exs"]
      }

      md = OutcomeContext.to_markdown(ctx)
      assert md =~ "### Explored State"
      assert md =~ "- lib/auth.ex"
      assert md =~ "- test/auth_test.exs"
    end

    test "omits empty sections" do
      ctx = %OutcomeContext{outcome: :completed}

      md = OutcomeContext.to_markdown(ctx)
      assert md == "## Outcome: completed"
    end
  end

  describe "struct" do
    test "enforces outcome key" do
      assert_raise ArgumentError, fn ->
        struct!(OutcomeContext, [])
      end
    end

    test "defaults for optional fields" do
      ctx = %OutcomeContext{outcome: :completed}
      assert ctx.approach == nil
      assert ctx.obstacle == nil
      assert ctx.recommendation == nil
      assert ctx.discoveries == []
      assert ctx.explored_state == []
    end
  end
end
