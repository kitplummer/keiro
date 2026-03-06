defmodule Keiro.Governance.BudgetPolicy.Batch do
  @moduledoc """
  Fixed-total budget for a batch run.

  Tracks cumulative spend against a hard ceiling. Once the ceiling is
  reached, all further checks return `:budget_exceeded`.

  ## Usage

      policy = Batch.new(5.00)
      {:ok, policy} = BudgetPolicy.check(policy, 1.50)
      assert BudgetPolicy.remaining(policy) == 3.50
  """

  @behaviour Keiro.Governance.BudgetPolicy

  @type t :: %__MODULE__{
          total: float(),
          spent: float()
        }

  @enforce_keys [:total]
  defstruct [:total, spent: 0.0]

  @doc "Create a batch budget policy with the given total."
  @spec new(float()) :: t()
  def new(total) when is_number(total) and total > 0 do
    %__MODULE__{total: total / 1, spent: 0.0}
  end

  @impl Keiro.Governance.BudgetPolicy
  def check(%__MODULE__{total: total, spent: spent} = policy, estimated_cost) do
    if spent + estimated_cost <= total do
      {:ok, %{policy | spent: spent + estimated_cost}}
    else
      {:budget_exceeded, policy}
    end
  end

  @impl Keiro.Governance.BudgetPolicy
  def remaining(%__MODULE__{total: total, spent: spent}) do
    max(total - spent, 0.0)
  end

  @impl Keiro.Governance.BudgetPolicy
  def spent(%__MODULE__{spent: spent}), do: spent
end
