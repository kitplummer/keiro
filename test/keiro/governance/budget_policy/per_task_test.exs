defmodule Keiro.Governance.BudgetPolicy.PerTaskTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.BudgetPolicy.PerTask

  describe "new/1" do
    test "creates policy with max per task" do
      policy = PerTask.new(1.50)
      assert policy.max_per_task == 1.50
      assert policy.last_cost == 0.0
      assert policy.total_spent == 0.0
    end
  end

  describe "check/2" do
    test "approves cost within per-task limit" do
      policy = PerTask.new(1.50)
      assert {:ok, updated} = PerTask.check(policy, 1.00)
      assert updated.last_cost == 1.00
      assert updated.total_spent == 1.00
    end

    test "rejects cost exceeding per-task limit" do
      policy = PerTask.new(1.50)
      assert {:budget_exceeded, _} = PerTask.check(policy, 2.00)
    end

    test "each check is independent (no cumulative limit)" do
      policy = PerTask.new(1.50)
      {:ok, policy} = PerTask.check(policy, 1.00)
      {:ok, policy} = PerTask.check(policy, 1.00)
      {:ok, policy} = PerTask.check(policy, 1.00)
      # All pass because each is under 1.50
      assert policy.total_spent == 3.00
    end

    test "approves exact max amount" do
      policy = PerTask.new(1.50)
      assert {:ok, _} = PerTask.check(policy, 1.50)
    end
  end

  describe "remaining/1" do
    test "always returns max per task" do
      policy = PerTask.new(1.50)
      {:ok, policy} = PerTask.check(policy, 1.00)
      assert PerTask.remaining(policy) == 1.50
    end
  end

  describe "spent/1" do
    test "tracks total cumulative spend" do
      policy = PerTask.new(2.00)
      {:ok, policy} = PerTask.check(policy, 1.00)
      {:ok, policy} = PerTask.check(policy, 0.75)
      assert PerTask.spent(policy) == 1.75
    end
  end
end
