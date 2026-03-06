defmodule Keiro.Routing.ModelProfile do
  @moduledoc """
  Metadata for an available LLM model.

  Captures cost, tier, and capabilities so the `ModelChooser` can select
  the best model for a given role and budget.
  """

  @type tier :: :economy | :standard | :premium

  @type t :: %__MODULE__{
          name: String.t(),
          tier: tier(),
          input_cost_per_m: float(),
          output_cost_per_m: float(),
          capabilities: MapSet.t(String.t())
        }

  @enforce_keys [:name, :tier]
  defstruct [
    :name,
    :tier,
    input_cost_per_m: 0.0,
    output_cost_per_m: 0.0,
    capabilities: MapSet.new()
  ]

  @tier_rank %{economy: 0, standard: 1, premium: 2}

  @doc "Compare tiers: returns true if `a` >= `b`."
  @spec tier_gte?(tier(), tier()) :: boolean()
  def tier_gte?(a, b) do
    Map.fetch!(@tier_rank, a) >= Map.fetch!(@tier_rank, b)
  end

  @doc "Blended cost per million tokens (simple average of input + output)."
  @spec blended_cost(t()) :: float()
  def blended_cost(%__MODULE__{} = p) do
    (p.input_cost_per_m + p.output_cost_per_m) / 2.0
  end
end
