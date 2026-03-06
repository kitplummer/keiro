defmodule Keiro.Budget.UnlimitedBudget do
  @moduledoc """
  No-op budget policy for testing and development.

  Always allows spending. Tracks cumulative spend for observability
  but never rejects.
  """

  @type t :: %__MODULE__{spent: float()}

  defstruct spent: 0.0

  @doc "Create a new unlimited budget."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  defimpl Keiro.Budget.Policy do
    def can_spend?(_budget, _amount), do: true

    def record_spend(budget, amount) do
      {:ok, %{budget | spent: budget.spent + amount}}
    end

    def remaining(_budget), do: :infinity
    def total(_budget), do: :infinity
  end
end
