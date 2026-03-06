defprotocol Keiro.Budget.Policy do
  @moduledoc """
  Protocol for budget policies.

  A budget policy tracks spend and decides whether there is budget
  remaining for more work. Policies are immutable — `record_spend/2`
  returns an updated copy with the new balance.

  ## Implementations

  - `Keiro.Budget.BatchBudget` — fixed total for an entire run
  - `Keiro.Budget.PerTaskBudget` — per-task cap with optional batch total
  - `Keiro.Budget.UnlimitedBudget` — no limits (testing/development)
  """

  @doc "Check if there is enough budget for the given amount."
  @spec can_spend?(t(), float()) :: boolean()
  def can_spend?(policy, amount)

  @doc "Record spend and return updated policy. Returns error if budget exceeded."
  @spec record_spend(t(), float()) :: {:ok, t()} | {:error, :budget_exceeded}
  def record_spend(policy, amount)

  @doc "Return the remaining budget."
  @spec remaining(t()) :: float()
  def remaining(policy)

  @doc "Return the total budget."
  @spec total(t()) :: float()
  def total(policy)
end
