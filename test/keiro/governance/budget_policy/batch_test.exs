defmodule Keiro.Governance.BudgetPolicy.BatchTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.BudgetPolicy.Batch

  describe "new/1" do
    test "creates policy with given total" do
      policy = Batch.new(5.00)
      assert policy.total == 5.00
      assert policy.spent == 0.0
    end
  end

  describe "check/2" do
    test "approves cost within budget" do
      policy = Batch.new(5.00)
      assert {:ok, updated} = Batch.check(policy, 2.00)
      assert updated.spent == 2.00
    end

    test "approves multiple costs that sum within budget" do
      policy = Batch.new(5.00)
      {:ok, policy} = Batch.check(policy, 2.00)
      {:ok, policy} = Batch.check(policy, 2.00)
      assert {:ok, policy} = Batch.check(policy, 1.00)
      assert policy.spent == 5.00
    end

    test "rejects cost that exceeds remaining budget" do
      policy = Batch.new(5.00)
      {:ok, policy} = Batch.check(policy, 4.00)
      assert {:budget_exceeded, policy} = Batch.check(policy, 2.00)
      # Spend not updated on rejection
      assert policy.spent == 4.00
    end

    test "rejects when budget is exactly exhausted" do
      policy = Batch.new(5.00)
      {:ok, policy} = Batch.check(policy, 5.00)
      assert {:budget_exceeded, _} = Batch.check(policy, 0.01)
    end

    test "approves exact remaining amount" do
      policy = Batch.new(5.00)
      {:ok, policy} = Batch.check(policy, 3.00)
      assert {:ok, _} = Batch.check(policy, 2.00)
    end
  end

  describe "remaining/1" do
    test "returns full budget when nothing spent" do
      policy = Batch.new(10.00)
      assert Batch.remaining(policy) == 10.00
    end

    test "returns reduced amount after spend" do
      policy = Batch.new(10.00)
      {:ok, policy} = Batch.check(policy, 3.50)
      assert Batch.remaining(policy) == 6.50
    end

    test "returns zero when fully spent" do
      policy = Batch.new(5.00)
      {:ok, policy} = Batch.check(policy, 5.00)
      assert Batch.remaining(policy) == 0.0
    end
  end

  describe "spent/1" do
    test "returns zero initially" do
      policy = Batch.new(5.00)
      assert Batch.spent(policy) == 0.0
    end

    test "tracks cumulative spend" do
      policy = Batch.new(10.00)
      {:ok, policy} = Batch.check(policy, 1.50)
      {:ok, policy} = Batch.check(policy, 2.25)
      assert Batch.spent(policy) == 3.75
    end
  end
end
