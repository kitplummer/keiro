defmodule Keiro.Governance.BudgetPolicyTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.BudgetPolicy

  describe "dispatch to implementations" do
    test "check/2 delegates to struct module" do
      policy = BudgetPolicy.Batch.new(5.00)
      assert {:ok, updated} = BudgetPolicy.check(policy, 1.00)
      assert BudgetPolicy.remaining(updated) == 4.00
    end

    test "remaining/1 delegates to struct module" do
      policy = BudgetPolicy.Batch.new(10.00)
      assert BudgetPolicy.remaining(policy) == 10.00
    end

    test "spent/1 delegates to struct module" do
      policy = BudgetPolicy.Batch.new(10.00)
      assert BudgetPolicy.spent(policy) == 0.0
    end
  end
end
