defmodule Keiro.Governance.ModelChooserTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.ModelChooser
  alias Keiro.Governance.ModelChooser.ModelProfile

  @flash_lite ModelProfile.new("gemini/flash-lite", :economy, 0.075, 0.30, ["tool_use", "code"])
  @flash ModelProfile.new("gemini/flash", :standard, 0.15, 0.60, [
           "tool_use",
           "code",
           "long_context"
         ])
  @sonnet ModelProfile.new("anthropic/sonnet", :premium, 3.0, 15.0, [
            "tool_use",
            "code",
            "long_context",
            "vision"
          ])

  @chooser ModelChooser.new(
             models: [@flash_lite, @flash, @sonnet],
             roles: %{
               "planner" => %{min_tier: :standard, requires: ["code"]},
               "debugger" => %{min_tier: :economy, requires: ["tool_use"]},
               "archivist" => %{min_tier: :economy},
               "vision_task" => %{min_tier: :economy, requires: ["vision"]}
             }
           )

  describe "select/3" do
    test "selects cheapest model meeting role requirements" do
      assert {:ok, profile} = ModelChooser.select(@chooser, "debugger")
      assert profile.model_string == "gemini/flash-lite"
    end

    test "respects minimum tier preference" do
      assert {:ok, profile} = ModelChooser.select(@chooser, "planner")
      assert profile.model_string == "gemini/flash"
    end

    test "filters by required capabilities" do
      assert {:ok, profile} = ModelChooser.select(@chooser, "vision_task")
      assert profile.model_string == "anthropic/sonnet"
    end

    test "returns error when no model matches" do
      chooser =
        ModelChooser.new(
          models: [@flash_lite],
          roles: %{"special" => %{requires: ["vision"]}}
        )

      assert {:error, msg} = ModelChooser.select(chooser, "special")
      assert msg =~ "No eligible model"
    end

    test "unknown role uses defaults (economy, no requirements)" do
      assert {:ok, profile} = ModelChooser.select(@chooser, "unknown_role")
      assert profile.model_string == "gemini/flash-lite"
    end

    test "downgrades tier under budget pressure" do
      # With budget_remaining < 20% of total, should downgrade
      assert {:ok, profile} =
               ModelChooser.select(@chooser, "planner",
                 budget_remaining: 0.50,
                 budget_total: 5.00
               )

      # Planner normally requires :standard, but under pressure
      # it should downgrade to :economy and pick the cheapest
      assert profile.model_string == "gemini/flash-lite"
    end

    test "does not downgrade without budget pressure" do
      assert {:ok, profile} =
               ModelChooser.select(@chooser, "planner",
                 budget_remaining: 4.00,
                 budget_total: 5.00
               )

      assert profile.model_string == "gemini/flash"
    end
  end

  describe "select_with_fallbacks/3" do
    test "returns models sorted by cost" do
      fallbacks = ModelChooser.select_with_fallbacks(@chooser, "debugger")
      assert length(fallbacks) == 3
      assert hd(fallbacks).model_string == "gemini/flash-lite"
      assert List.last(fallbacks).model_string == "anthropic/sonnet"
    end

    test "filters by required capabilities" do
      fallbacks = ModelChooser.select_with_fallbacks(@chooser, "vision_task")
      assert length(fallbacks) == 1
      assert hd(fallbacks).model_string == "anthropic/sonnet"
    end
  end

  describe "new/1" do
    test "creates chooser with defaults" do
      chooser = ModelChooser.new(models: [@flash])
      assert chooser.cost_quality_threshold == 0.7
      assert chooser.roles == %{}
    end

    test "accepts custom cost_quality_threshold" do
      chooser = ModelChooser.new(models: [@flash], cost_quality_threshold: 0.3)
      assert chooser.cost_quality_threshold == 0.3
    end
  end
end
