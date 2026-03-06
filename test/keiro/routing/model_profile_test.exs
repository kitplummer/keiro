defmodule Keiro.Routing.ModelProfileTest do
  use ExUnit.Case, async: true

  alias Keiro.Routing.ModelProfile

  describe "struct" do
    test "enforces name and tier" do
      profile = %ModelProfile{name: "test-model", tier: :economy}
      assert profile.name == "test-model"
      assert profile.tier == :economy
      assert profile.input_cost_per_m == 0.0
      assert profile.output_cost_per_m == 0.0
      assert profile.capabilities == MapSet.new()
    end
  end

  describe "tier_gte?/2" do
    test "economy >= economy" do
      assert ModelProfile.tier_gte?(:economy, :economy)
    end

    test "standard >= economy" do
      assert ModelProfile.tier_gte?(:standard, :economy)
    end

    test "premium >= standard" do
      assert ModelProfile.tier_gte?(:premium, :standard)
    end

    test "economy < standard" do
      refute ModelProfile.tier_gte?(:economy, :standard)
    end

    test "standard < premium" do
      refute ModelProfile.tier_gte?(:standard, :premium)
    end
  end

  describe "blended_cost/1" do
    test "averages input and output costs" do
      profile = %ModelProfile{
        name: "test",
        tier: :standard,
        input_cost_per_m: 3.0,
        output_cost_per_m: 15.0
      }

      assert ModelProfile.blended_cost(profile) == 9.0
    end

    test "returns 0 for free models" do
      profile = %ModelProfile{name: "local", tier: :economy}
      assert ModelProfile.blended_cost(profile) == 0.0
    end
  end
end
