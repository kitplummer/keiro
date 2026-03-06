defmodule Keiro.Governance.BudgetPolicy.PerTask do
  @moduledoc """
  Per-task budget cap.

  Enforces a maximum spend per individual task. Does not track
  cumulative spend — use alongside a Batch or Rolling policy for
  total budget enforcement.

  ## Usage

      policy = PerTask.new(1.50)
      {:ok, policy} = BudgetPolicy.check(policy, 1.00)
      {:budget_exceeded, policy} = BudgetPolicy.check(policy, 2.00)
  """

  @behaviour Keiro.Governance.BudgetPolicy

  @type t :: %__MODULE__{
          max_per_task: float(),
          last_cost: float(),
          total_spent: float()
        }

  @enforce_keys [:max_per_task]
  defstruct [:max_per_task, last_cost: 0.0, total_spent: 0.0]

  @doc "Create a per-task budget policy with the given maximum per task."
  @spec new(float()) :: t()
  def new(max_per_task) when is_number(max_per_task) and max_per_task > 0 do
    %__MODULE__{max_per_task: max_per_task / 1}
  end

  @impl Keiro.Governance.BudgetPolicy
  def check(%__MODULE__{max_per_task: max} = policy, estimated_cost) do
    if estimated_cost <= max do
      {:ok,
       %{policy | last_cost: estimated_cost, total_spent: policy.total_spent + estimated_cost}}
    else
      {:budget_exceeded, policy}
    end
  end

  @impl Keiro.Governance.BudgetPolicy
  def remaining(%__MODULE__{max_per_task: max}), do: max

  @impl Keiro.Governance.BudgetPolicy
  def spent(%__MODULE__{total_spent: total}), do: total
end
