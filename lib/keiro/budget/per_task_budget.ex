defmodule Keiro.Budget.PerTaskBudget do
  @moduledoc """
  Per-task budget cap with optional batch total.

  Each task is capped at `max_per_task`. The batch total (if set)
  provides an additional ceiling on cumulative spend.

  ## Usage

      budget = Keiro.Budget.PerTaskBudget.new(max_per_task: 1.00, total: 10.00)
      Keiro.Budget.Policy.can_spend?(budget, 0.50)  # => true
      Keiro.Budget.Policy.can_spend?(budget, 1.50)  # => false (exceeds per-task)
  """

  @type t :: %__MODULE__{
          max_per_task: float(),
          total_budget: float() | :infinity,
          spent: float()
        }

  @enforce_keys [:max_per_task]
  defstruct [:max_per_task, total_budget: :infinity, spent: 0.0]

  @doc "Create a new per-task budget."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      max_per_task: Keyword.fetch!(opts, :max_per_task),
      total_budget: Keyword.get(opts, :total, :infinity)
    }
  end

  defimpl Keiro.Budget.Policy do
    def can_spend?(budget, amount) do
      amount <= budget.max_per_task && batch_ok?(budget, amount)
    end

    def record_spend(budget, amount) do
      cond do
        amount > budget.max_per_task ->
          {:error, :budget_exceeded}

        !batch_ok?(budget, amount) ->
          {:error, :budget_exceeded}

        true ->
          {:ok, %{budget | spent: budget.spent + amount}}
      end
    end

    def remaining(budget) do
      case budget.total_budget do
        :infinity -> :infinity
        total -> max(total - budget.spent, 0.0)
      end
    end

    def total(budget) do
      budget.total_budget
    end

    defp batch_ok?(budget, amount) do
      case budget.total_budget do
        :infinity -> true
        total -> total - budget.spent >= amount
      end
    end
  end
end
