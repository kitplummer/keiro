defmodule Keiro.Governance.ModelChooser do
  @moduledoc """
  Cost-aware model selection for agent roles.

  Selects the most cost-effective model for a given role based on:
  1. Required capabilities (e.g., tool_use, code)
  2. Minimum tier preference per role (economy, standard, premium)
  3. Remaining budget pressure (shifts to cheaper models as budget depletes)
  4. Among eligible models, picks the cheapest

  ## Usage

      chooser = ModelChooser.new(
        models: [
          ModelProfile.new("gemini/flash-lite", :economy, 0.075, 0.30, ["tool_use", "code"]),
          ModelProfile.new("gemini/flash", :standard, 0.15, 0.60, ["tool_use", "code"]),
          ModelProfile.new("anthropic/sonnet", :premium, 3.0, 15.0, ["tool_use", "code"])
        ],
        roles: %{
          "planner" => %{min_tier: :standard, requires: ["code"]},
          "debugger" => %{min_tier: :economy, requires: ["tool_use"]}
        }
      )

      {:ok, profile} = ModelChooser.select(chooser, "debugger")
      {:ok, profile} = ModelChooser.select(chooser, "planner", budget_remaining: 1.0)
  """

  alias Keiro.Governance.ModelChooser.ModelProfile

  @type role_config :: %{
          optional(:min_tier) => ModelProfile.tier(),
          optional(:requires) => [String.t()]
        }

  @type t :: %__MODULE__{
          models: [ModelProfile.t()],
          roles: %{String.t() => role_config()},
          cost_quality_threshold: float()
        }

  @enforce_keys [:models]
  defstruct models: [], roles: %{}, cost_quality_threshold: 0.7

  @doc """
  Create a new model chooser.

  Options:
  - `:models` — list of `ModelProfile` structs (required)
  - `:roles` — map of role name to config (min_tier, requires)
  - `:cost_quality_threshold` — 0.0 = quality-first, 1.0 = cost-first (default: 0.7)
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      models: Keyword.fetch!(opts, :models),
      roles: Keyword.get(opts, :roles, %{}),
      cost_quality_threshold: Keyword.get(opts, :cost_quality_threshold, 0.7)
    }
  end

  @doc """
  Select the best model for a role.

  Options:
  - `:budget_remaining` — remaining budget in dollars (optional)
  - `:budget_total` — total budget in dollars (optional, for pressure calculation)

  Returns `{:ok, profile}` or `{:error, reason}`.
  """
  @spec select(t(), String.t(), keyword()) :: {:ok, ModelProfile.t()} | {:error, String.t()}
  def select(%__MODULE__{} = chooser, role, opts \\ []) do
    role_config = Map.get(chooser.roles, role, %{})
    required_caps = Map.get(role_config, :requires, [])
    min_tier = Map.get(role_config, :min_tier, :economy)
    budget_remaining = Keyword.get(opts, :budget_remaining)
    budget_total = Keyword.get(opts, :budget_total)

    effective_min_tier =
      if budget_pressure?(budget_remaining, budget_total) do
        downgrade_tier(min_tier)
      else
        min_tier
      end

    eligible =
      chooser.models
      |> Enum.filter(&has_capabilities?(&1, required_caps))
      |> Enum.filter(&meets_tier?(&1, effective_min_tier))

    case Enum.sort_by(eligible, &ModelProfile.cost_per_token/1) do
      [cheapest | _] -> {:ok, cheapest}
      [] -> {:error, "No eligible model for role '#{role}' (requires: #{inspect(required_caps)})"}
    end
  end

  @doc """
  Select a model with ordered fallbacks for cascade routing.

  Returns eligible models sorted cheapest-first.
  """
  @spec select_with_fallbacks(t(), String.t(), keyword()) :: [ModelProfile.t()]
  def select_with_fallbacks(%__MODULE__{} = chooser, role, opts \\ []) do
    role_config = Map.get(chooser.roles, role, %{})
    required_caps = Map.get(role_config, :requires, [])

    chooser.models
    |> Enum.filter(&has_capabilities?(&1, required_caps))
    |> Enum.sort_by(&ModelProfile.cost_per_token/1)
    |> maybe_apply_budget_filter(opts)
  end

  defp has_capabilities?(profile, required) do
    Enum.all?(required, &(&1 in profile.capabilities))
  end

  defp meets_tier?(profile, min_tier) do
    tier_rank(profile.tier) >= tier_rank(min_tier)
  end

  defp tier_rank(:economy), do: 0
  defp tier_rank(:standard), do: 1
  defp tier_rank(:premium), do: 2

  defp budget_pressure?(nil, _), do: false
  defp budget_pressure?(_, nil), do: false

  defp budget_pressure?(remaining, total) when total > 0 do
    remaining / total < 0.2
  end

  defp budget_pressure?(_, _), do: false

  defp downgrade_tier(:premium), do: :standard
  defp downgrade_tier(:standard), do: :economy
  defp downgrade_tier(:economy), do: :economy

  defp maybe_apply_budget_filter(models, _opts), do: models
end
