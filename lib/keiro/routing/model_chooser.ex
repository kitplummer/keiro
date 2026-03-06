defmodule Keiro.Routing.ModelChooser do
  @moduledoc """
  Selects the best model for a given role and budget.

  Tier 1 (rule-based) cost routing per the cost-aware model routing ADR:

  1. Filter models by required capabilities for the role.
  2. Apply role preference for minimum tier.
  3. If budget is tight, bias toward cheaper models.
  4. Among eligible models, pick the cheapest.

  The `cost_quality_threshold` (0.0–1.0) controls the tradeoff:
  - `0.0` → always pick the role's preferred tier (quality-first)
  - `1.0` → always pick the cheapest capable model (cost-first)
  """

  alias Keiro.Routing.{ModelProfile, RolePreference}

  @type t :: %__MODULE__{
          models: [ModelProfile.t()],
          role_preferences: %{String.t() => RolePreference.t()},
          cost_quality_threshold: float()
        }

  @enforce_keys [:models]
  defstruct [
    :models,
    role_preferences: %{},
    cost_quality_threshold: 0.5
  ]

  @doc """
  Select the best model for a role given the current budget state.

  Returns `{:ok, model_profile}` or `{:error, :no_eligible_model}`.

  ## Options

    * `:budget_remaining` — remaining budget in dollars (default: `:unlimited`)
    * `:budget_total` — total budget in dollars (used with remaining to compute pressure)

  """
  @spec choose(t(), String.t(), keyword()) ::
          {:ok, ModelProfile.t()} | {:error, :no_eligible_model}
  def choose(%__MODULE__{} = chooser, role, opts \\ []) do
    pref = Map.get(chooser.role_preferences, role, %RolePreference{role: role})
    budget_remaining = Keyword.get(opts, :budget_remaining, :unlimited)
    budget_total = Keyword.get(opts, :budget_total, :unlimited)

    effective_min_tier =
      effective_min_tier(pref, chooser.cost_quality_threshold, budget_remaining, budget_total)

    eligible =
      chooser.models
      |> Enum.filter(&has_capabilities?(&1, pref.requires))
      |> Enum.filter(&ModelProfile.tier_gte?(&1.tier, effective_min_tier))

    case Enum.sort_by(eligible, &ModelProfile.blended_cost/1) do
      [best | _] -> {:ok, best}
      [] -> cheapest_fallback(chooser.models, pref.requires)
    end
  end

  @doc """
  Map a model profile tier to a Jido model atom (`:fast`, `:capable`, `:premium`).
  """
  @spec tier_to_jido_model(ModelProfile.tier()) :: atom()
  def tier_to_jido_model(:economy), do: :fast
  def tier_to_jido_model(:standard), do: :capable
  def tier_to_jido_model(:premium), do: :capable

  # -- private --

  defp has_capabilities?(%ModelProfile{} = profile, requires) do
    MapSet.subset?(requires, profile.capabilities)
  end

  defp effective_min_tier(pref, threshold, budget_remaining, budget_total) do
    budget_pressure = budget_pressure(budget_remaining, budget_total)

    # If threshold is high OR budget pressure is high, drop to economy
    if threshold >= 0.8 or budget_pressure >= 0.8 do
      :economy
    else
      pref.min_tier
    end
  end

  # Returns 0.0 (no pressure) to 1.0 (out of budget)
  defp budget_pressure(:unlimited, _total), do: 0.0
  defp budget_pressure(_remaining, :unlimited), do: 0.0

  defp budget_pressure(remaining, total) when total > 0 do
    used_fraction = 1.0 - remaining / total
    # Pressure ramps up in the last 20% of budget
    max(0.0, (used_fraction - 0.8) / 0.2)
  end

  defp budget_pressure(_, _), do: 0.0

  # If no model meets tier requirements, fall back to cheapest with required capabilities
  defp cheapest_fallback(models, requires) do
    case models
         |> Enum.filter(&has_capabilities?(&1, requires))
         |> Enum.sort_by(&ModelProfile.blended_cost/1) do
      [best | _] -> {:ok, best}
      [] -> {:error, :no_eligible_model}
    end
  end
end
