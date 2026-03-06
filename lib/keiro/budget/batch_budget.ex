defmodule Keiro.Budget.BatchBudget do
  @moduledoc """
  Fixed total budget for an entire batch run.

  Tracks cumulative spend against a total cap. Once the remaining
  balance drops below zero, no further spend is allowed.

  ## Usage

      budget = Keiro.Budget.BatchBudget.new(total: 5.00)
      {:ok, budget} = Keiro.Budget.Policy.record_spend(budget, 0.50)
      Keiro.Budget.Policy.remaining(budget) # => 4.50
  """

  @type t :: %__MODULE__{
          total_budget: float(),
          spent: float()
        }

  @enforce_keys [:total_budget]
  defstruct [:total_budget, spent: 0.0]

  @doc "Create a new batch budget."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{total_budget: Keyword.fetch!(opts, :total)}
  end

  defimpl Keiro.Budget.Policy do
    def can_spend?(budget, amount) do
      budget.total_budget - budget.spent >= amount
    end

    def record_spend(budget, amount) do
      if budget.total_budget - budget.spent >= amount do
        {:ok, %{budget | spent: budget.spent + amount}}
      else
        {:error, :budget_exceeded}
      end
    end

    def remaining(budget) do
      max(budget.total_budget - budget.spent, 0.0)
    end

    def total(budget) do
      budget.total_budget
    end
  end
end
