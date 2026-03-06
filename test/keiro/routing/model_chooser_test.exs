defmodule Keiro.Routing.ModelChooserTest do
  use ExUnit.Case, async: true

  alias Keiro.Routing.{ModelChooser, ModelProfile, RolePreference}

  @flash %ModelProfile{
    name: "gemini/gemini-2.5-flash-lite",
    tier: :economy,
    input_cost_per_m: 0.075,
    output_cost_per_m: 0.3,
    capabilities: MapSet.new(["tool_use", "code"])
  }

  @sonnet %ModelProfile{
    name: "anthropic/claude-sonnet-4",
    tier: :standard,
    input_cost_per_m: 3.0,
    output_cost_per_m: 15.0,
    capabilities: MapSet.new(["tool_use", "code", "long_context"])
  }

  @opus %ModelProfile{
    name: "anthropic/claude-opus-4",
    tier: :premium,
    input_cost_per_m: 15.0,
    output_cost_per_m: 75.0,
    capabilities: MapSet.new(["tool_use", "code", "long_context", "vision"])
  }

  @chooser %ModelChooser{
    models: [@flash, @sonnet, @opus],
    role_preferences: %{
      "planner" => %RolePreference{role: "planner", min_tier: :standard},
      "implementer" => %RolePreference{
        role: "implementer",
        min_tier: :standard,
        requires: MapSet.new(["tool_use"])
      },
      "debugger" => %RolePreference{
        role: "debugger",
        min_tier: :economy,
        requires: MapSet.new(["tool_use"])
      },
      "archivist" => %RolePreference{role: "archivist", min_tier: :economy}
    }
  }

  describe "choose/3" do
    test "selects cheapest model meeting role min_tier" do
      {:ok, model} = ModelChooser.choose(@chooser, "planner")
      assert model.tier in [:standard, :premium]
      assert model.name == @sonnet.name
    end

    test "selects economy model for roles with no min_tier preference" do
      {:ok, model} = ModelChooser.choose(@chooser, "archivist")
      assert model.name == @flash.name
    end

    test "filters by required capabilities" do
      {:ok, model} = ModelChooser.choose(@chooser, "debugger")
      assert MapSet.member?(model.capabilities, "tool_use")
    end

    test "falls back to cheapest when role has no preference" do
      {:ok, model} = ModelChooser.choose(@chooser, "unknown_role")
      assert model.name == @flash.name
    end

    test "returns error when no model has required capabilities" do
      chooser = %ModelChooser{
        models: [@flash],
        role_preferences: %{
          "vision_agent" => %RolePreference{
            role: "vision_agent",
            min_tier: :economy,
            requires: MapSet.new(["vision"])
          }
        }
      }

      assert {:error, :no_eligible_model} = ModelChooser.choose(chooser, "vision_agent")
    end

    test "drops to economy under budget pressure" do
      {:ok, model} =
        ModelChooser.choose(@chooser, "planner",
          budget_remaining: 0.02,
          budget_total: 1.00
        )

      # Under high budget pressure (98% used), should pick cheapest
      assert model.name == @flash.name
    end

    test "respects min_tier when budget is healthy" do
      {:ok, model} =
        ModelChooser.choose(@chooser, "planner",
          budget_remaining: 0.80,
          budget_total: 1.00
        )

      assert model.tier in [:standard, :premium]
    end

    test "cost_quality_threshold at 1.0 always picks cheapest" do
      chooser = %{@chooser | cost_quality_threshold: 1.0}
      {:ok, model} = ModelChooser.choose(chooser, "planner")
      assert model.name == @flash.name
    end

    test "cost_quality_threshold at 0.0 respects role preferences" do
      chooser = %{@chooser | cost_quality_threshold: 0.0}
      {:ok, model} = ModelChooser.choose(chooser, "planner")
      assert model.tier in [:standard, :premium]
    end
  end

  describe "tier_to_jido_model/1" do
    test "maps tiers to jido model atoms" do
      assert ModelChooser.tier_to_jido_model(:economy) == :fast
      assert ModelChooser.tier_to_jido_model(:standard) == :capable
      assert ModelChooser.tier_to_jido_model(:premium) == :capable
    end
  end
end
