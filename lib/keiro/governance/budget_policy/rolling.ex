defmodule Keiro.Governance.BudgetPolicy.Rolling do
  @moduledoc """
  Time-window rolling budget.

  Tracks spend entries with timestamps. Only entries within the
  configured window count toward the budget. Expired entries are
  pruned on each check.

  ## Usage

      policy = Rolling.new(5.00, window_ms: 3_600_000)  # $5/hour
      {:ok, policy} = BudgetPolicy.check(policy, 1.00)
      assert BudgetPolicy.remaining(policy) == 4.00
  """

  @behaviour Keiro.Governance.BudgetPolicy

  @type entry :: {integer(), float()}

  @type t :: %__MODULE__{
          budget: float(),
          window_ms: non_neg_integer(),
          entries: [entry()]
        }

  @enforce_keys [:budget, :window_ms]
  defstruct [:budget, :window_ms, entries: []]

  @doc """
  Create a rolling budget policy.

  Options:
  - `:window_ms` — time window in milliseconds (default: 3_600_000 = 1 hour)
  - `:now_fn` — function returning current monotonic time (for testing)
  """
  @spec new(float(), keyword()) :: t()
  def new(budget, opts \\ []) when is_number(budget) and budget > 0 do
    window_ms = Keyword.get(opts, :window_ms, 3_600_000)
    %__MODULE__{budget: budget / 1, window_ms: window_ms}
  end

  @impl Keiro.Governance.BudgetPolicy
  def check(%__MODULE__{} = policy, estimated_cost) do
    now = System.monotonic_time(:millisecond)
    policy = prune(policy, now)
    current_spend = window_spend(policy)

    if current_spend + estimated_cost <= policy.budget do
      {:ok, %{policy | entries: policy.entries ++ [{now, estimated_cost}]}}
    else
      {:budget_exceeded, policy}
    end
  end

  @impl Keiro.Governance.BudgetPolicy
  def remaining(%__MODULE__{} = policy) do
    now = System.monotonic_time(:millisecond)
    policy = prune(policy, now)
    max(policy.budget - window_spend(policy), 0.0)
  end

  @impl Keiro.Governance.BudgetPolicy
  def spent(%__MODULE__{} = policy) do
    now = System.monotonic_time(:millisecond)
    policy = prune(policy, now)
    window_spend(policy)
  end

  defp prune(%__MODULE__{entries: entries, window_ms: window_ms} = policy, now) do
    cutoff = now - window_ms
    %{policy | entries: Enum.filter(entries, fn {ts, _cost} -> ts >= cutoff end)}
  end

  defp window_spend(%__MODULE__{entries: entries}) do
    Enum.reduce(entries, 0.0, fn {_ts, cost}, acc -> acc + cost end)
  end
end
