defmodule Keiro.Governance.BudgetPolicy.RollingTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.BudgetPolicy.Rolling

  describe "new/2" do
    test "creates policy with budget and default window" do
      policy = Rolling.new(5.00)
      assert policy.budget == 5.00
      assert policy.window_ms == 3_600_000
      assert policy.entries == []
    end

    test "accepts custom window" do
      policy = Rolling.new(10.00, window_ms: 60_000)
      assert policy.window_ms == 60_000
    end
  end

  describe "check/2" do
    test "approves cost within budget" do
      policy = Rolling.new(5.00)
      assert {:ok, updated} = Rolling.check(policy, 2.00)
      assert length(updated.entries) == 1
    end

    test "approves multiple costs within budget" do
      policy = Rolling.new(5.00)
      {:ok, policy} = Rolling.check(policy, 1.00)
      {:ok, policy} = Rolling.check(policy, 1.00)
      assert {:ok, policy} = Rolling.check(policy, 1.00)
      assert length(policy.entries) == 3
    end

    test "rejects cost that exceeds remaining budget" do
      policy = Rolling.new(5.00)
      {:ok, policy} = Rolling.check(policy, 4.00)
      assert {:budget_exceeded, _} = Rolling.check(policy, 2.00)
    end
  end

  describe "remaining/1" do
    test "returns full budget when nothing spent" do
      policy = Rolling.new(10.00)
      assert Rolling.remaining(policy) == 10.00
    end

    test "returns reduced amount after spend" do
      policy = Rolling.new(10.00)
      {:ok, policy} = Rolling.check(policy, 3.00)
      remaining = Rolling.remaining(policy)
      assert remaining >= 6.99 and remaining <= 7.01
    end
  end

  describe "spent/1" do
    test "returns zero initially" do
      policy = Rolling.new(5.00)
      assert Rolling.spent(policy) == 0.0
    end

    test "tracks spend within window" do
      policy = Rolling.new(10.00)
      {:ok, policy} = Rolling.check(policy, 1.50)
      {:ok, policy} = Rolling.check(policy, 2.00)
      spent = Rolling.spent(policy)
      assert spent >= 3.49 and spent <= 3.51
    end
  end

  describe "window expiry" do
    test "expired entries are pruned" do
      # Create a policy with a tiny window
      policy = Rolling.new(5.00, window_ms: 1)

      # Add an entry
      {:ok, policy} = Rolling.check(policy, 3.00)

      # Wait for the entry to expire
      Process.sleep(5)

      # Now the budget should be fully available again
      assert Rolling.remaining(policy) == 5.00
      assert Rolling.spent(policy) == 0.0
    end
  end
end
