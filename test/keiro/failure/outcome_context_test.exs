defmodule Keiro.Failure.OutcomeContextTest do
  use ExUnit.Case, async: true

  alias Keiro.Failure.{OutcomeContext, ObstacleKind}

  describe "new/1" do
    test "creates with required fields" do
      ctx =
        OutcomeContext.new(
          approach: "Tried adding function",
          obstacle: ObstacleKind.unknown("failed")
        )

      assert ctx.approach == "Tried adding function"
      assert ctx.discoveries == []
      assert ctx.recommendation == nil
      assert ctx.explored_files == []
    end

    test "creates with all fields" do
      ctx =
        OutcomeContext.new(
          approach: "Tried adding function",
          obstacle: ObstacleKind.missing_prerequisite("gl-042", "no module"),
          discoveries: ["Uses Phoenix", "Has custom router"],
          recommendation: "Create module first",
          explored_files: ["lib/app.ex", "lib/router.ex"]
        )

      assert length(ctx.discoveries) == 2
      assert ctx.recommendation == "Create module first"
      assert length(ctx.explored_files) == 2
    end
  end

  describe "to_prompt/1" do
    test "renders basic context" do
      ctx =
        OutcomeContext.new(
          approach: "Added greeting function",
          obstacle: ObstacleKind.unknown("compile error")
        )

      prompt = OutcomeContext.to_prompt(ctx)
      assert prompt =~ "Previous attempt: Added greeting function"
      assert prompt =~ "Obstacle: Unknown: compile error"
    end

    test "includes discoveries when present" do
      ctx =
        OutcomeContext.new(
          approach: "Tried fix",
          obstacle: ObstacleKind.architectural_gap("No plugin system"),
          discoveries: ["Uses GenServer", "Has supervisor tree"]
        )

      prompt = OutcomeContext.to_prompt(ctx)
      assert prompt =~ "Discoveries: Uses GenServer; Has supervisor tree"
    end

    test "includes recommendation when present" do
      ctx =
        OutcomeContext.new(
          approach: "Tried fix",
          obstacle: ObstacleKind.scope_too_large(10, 3),
          recommendation: "Split into smaller tasks"
        )

      prompt = OutcomeContext.to_prompt(ctx)
      assert prompt =~ "Recommendation: Split into smaller tasks"
    end

    test "omits discoveries and recommendation when absent" do
      ctx =
        OutcomeContext.new(
          approach: "Tried fix",
          obstacle: ObstacleKind.external_dependency("redis")
        )

      prompt = OutcomeContext.to_prompt(ctx)
      refute prompt =~ "Discoveries"
      refute prompt =~ "Recommendation"
    end

    test "formats all obstacle kinds" do
      obstacles = [
        {ObstacleKind.missing_prerequisite("gl-1", "need it"), "Missing prerequisite gl-1"},
        {ObstacleKind.architectural_gap("no hooks"), "Architectural gap: no hooks"},
        {ObstacleKind.model_limitation("flash", "parse"), "Model limitation (flash): parse"},
        {ObstacleKind.external_dependency("fly.io"), "External dependency unavailable: fly.io"},
        {ObstacleKind.scope_too_large(10, 3), "Scope too large: 10 files (max 3)"},
        {ObstacleKind.unknown("weird"), "Unknown: weird"}
      ]

      for {obstacle, expected_text} <- obstacles do
        ctx = OutcomeContext.new(approach: "test", obstacle: obstacle)
        prompt = OutcomeContext.to_prompt(ctx)

        assert prompt =~ expected_text,
               "Expected '#{expected_text}' in prompt for #{inspect(obstacle)}"
      end
    end
  end
end
