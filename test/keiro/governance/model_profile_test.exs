defmodule Keiro.Governance.ModelChooser.ModelProfileTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.ModelChooser.ModelProfile

  describe "new/5" do
    test "creates profile with all fields" do
      profile = ModelProfile.new("gemini/flash", :standard, 0.15, 0.60, ["tool_use", "code"])
      assert profile.model_string == "gemini/flash"
      assert profile.tier == :standard
      assert profile.input_cost_per_m == 0.15
      assert profile.output_cost_per_m == 0.60
      assert profile.capabilities == ["tool_use", "code"]
    end

    test "defaults capabilities to empty list" do
      profile = ModelProfile.new("gemini/flash", :standard, 0.15, 0.60)
      assert profile.capabilities == []
    end
  end

  describe "cost_per_token/1" do
    test "returns average of input and output cost" do
      profile = ModelProfile.new("test", :economy, 1.0, 3.0)
      assert ModelProfile.cost_per_token(profile) == 2.0
    end

    test "handles zero cost" do
      profile = ModelProfile.new("local", :economy, 0.0, 0.0)
      assert ModelProfile.cost_per_token(profile) == 0.0
    end
  end
end
