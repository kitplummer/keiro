defmodule Keiro.Governance.BudgetPolicy do
  @moduledoc """
  Behaviour for budget enforcement policies.

  A budget policy decides whether the system can afford to run the next
  task based on accumulated spend. Three built-in policies:

  - `Batch` — fixed total budget for a batch run
  - `Rolling` — budget replenishes over a time window
  - `PerTask` — maximum spend per individual task

  ## Usage

      policy = Keiro.Governance.BudgetPolicy.Batch.new(5.00)
      {:ok, policy} = BudgetPolicy.check(policy, 0.50)
      {:ok, policy} = BudgetPolicy.check(policy, 0.75)
      {:budget_exceeded, policy} = BudgetPolicy.check(policy, 10.00)
  """

  @type check_result :: {:ok, t()} | {:budget_exceeded, t()}

  @type t :: struct()

  @doc "Check whether the estimated cost can be afforded. Returns updated policy state."
  @callback check(policy :: t(), estimated_cost :: float()) :: check_result()

  @doc "Return the remaining budget."
  @callback remaining(policy :: t()) :: float()

  @doc "Return the total spent so far."
  @callback spent(policy :: t()) :: float()

  @doc "Check whether the estimated cost can be afforded (delegated to implementation)."
  @spec check(t(), float()) :: check_result()
  def check(%module{} = policy, estimated_cost) do
    module.check(policy, estimated_cost)
  end

  @doc "Return remaining budget (delegated to implementation)."
  @spec remaining(t()) :: float()
  def remaining(%module{} = policy) do
    module.remaining(policy)
  end

  @doc "Return total spent (delegated to implementation)."
  @spec spent(t()) :: float()
  def spent(%module{} = policy) do
    module.spent(policy)
  end
end
