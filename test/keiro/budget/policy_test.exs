defmodule Keiro.Budget.PolicyTest do
  use ExUnit.Case, async: true

  alias Keiro.Budget.Policy
  alias Keiro.Budget.{BatchBudget, PerTaskBudget, UnlimitedBudget}

  describe "BatchBudget" do
    test "new/1 creates with total" do
      budget = BatchBudget.new(total: 5.00)
      assert Policy.total(budget) == 5.00
      assert Policy.remaining(budget) == 5.00
    end

    test "can_spend?/2 checks against remaining" do
      budget = BatchBudget.new(total: 1.00)
      assert Policy.can_spend?(budget, 0.50)
      assert Policy.can_spend?(budget, 1.00)
      refute Policy.can_spend?(budget, 1.01)
    end

    test "record_spend/2 deducts from balance" do
      budget = BatchBudget.new(total: 2.00)
      {:ok, budget} = Policy.record_spend(budget, 0.75)
      assert Policy.remaining(budget) == 1.25
    end

    test "record_spend/2 returns error when exceeded" do
      budget = BatchBudget.new(total: 1.00)
      assert {:error, :budget_exceeded} = Policy.record_spend(budget, 1.50)
    end

    test "record_spend/2 allows exact remaining" do
      budget = BatchBudget.new(total: 1.00)
      {:ok, budget} = Policy.record_spend(budget, 0.50)
      {:ok, budget} = Policy.record_spend(budget, 0.50)
      assert Policy.remaining(budget) == 0.0
      assert {:error, :budget_exceeded} = Policy.record_spend(budget, 0.01)
    end

    test "remaining/1 never goes negative" do
      budget = BatchBudget.new(total: 0.0)
      assert Policy.remaining(budget) == 0.0
    end
  end

  describe "PerTaskBudget" do
    test "new/1 creates with per-task cap" do
      budget = PerTaskBudget.new(max_per_task: 1.00)
      assert budget.max_per_task == 1.00
      assert Policy.total(budget) == :infinity
    end

    test "new/1 accepts optional total" do
      budget = PerTaskBudget.new(max_per_task: 1.00, total: 10.00)
      assert Policy.total(budget) == 10.00
    end

    test "can_spend?/2 rejects amounts exceeding per-task cap" do
      budget = PerTaskBudget.new(max_per_task: 1.00)
      assert Policy.can_spend?(budget, 0.50)
      refute Policy.can_spend?(budget, 1.50)
    end

    test "can_spend?/2 checks batch total when set" do
      budget = PerTaskBudget.new(max_per_task: 2.00, total: 3.00)
      {:ok, budget} = Policy.record_spend(budget, 2.00)
      # 1.00 remaining in batch, per-task allows 2.00, but batch says no
      refute Policy.can_spend?(budget, 1.50)
      assert Policy.can_spend?(budget, 1.00)
    end

    test "record_spend/2 rejects over per-task cap" do
      budget = PerTaskBudget.new(max_per_task: 1.00)
      assert {:error, :budget_exceeded} = Policy.record_spend(budget, 1.50)
    end

    test "record_spend/2 rejects over batch total" do
      budget = PerTaskBudget.new(max_per_task: 5.00, total: 2.00)
      {:ok, budget} = Policy.record_spend(budget, 1.50)
      assert {:error, :budget_exceeded} = Policy.record_spend(budget, 1.00)
    end

    test "remaining/1 returns :infinity without batch total" do
      budget = PerTaskBudget.new(max_per_task: 1.00)
      assert Policy.remaining(budget) == :infinity
    end

    test "remaining/1 returns float with batch total" do
      budget = PerTaskBudget.new(max_per_task: 1.00, total: 5.00)
      {:ok, budget} = Policy.record_spend(budget, 0.50)
      assert Policy.remaining(budget) == 4.50
    end
  end

  describe "UnlimitedBudget" do
    test "always allows spending" do
      budget = UnlimitedBudget.new()
      assert Policy.can_spend?(budget, 1_000_000.00)
    end

    test "record_spend/2 always succeeds" do
      budget = UnlimitedBudget.new()
      {:ok, budget} = Policy.record_spend(budget, 100.00)
      {:ok, _budget} = Policy.record_spend(budget, 100.00)
    end

    test "tracks cumulative spend" do
      budget = UnlimitedBudget.new()
      {:ok, budget} = Policy.record_spend(budget, 1.50)
      {:ok, budget} = Policy.record_spend(budget, 2.50)
      assert budget.spent == 4.00
    end

    test "remaining/1 returns :infinity" do
      assert Policy.remaining(UnlimitedBudget.new()) == :infinity
    end

    test "total/1 returns :infinity" do
      assert Policy.total(UnlimitedBudget.new()) == :infinity
    end
  end
end
