defmodule Keiro.Governance.ModelChooser.ModelProfile do
  @moduledoc """
  Model metadata for cost-aware routing.

  Stores the cost, capabilities, and tier of an LLM model.
  Used by the `ModelChooser` to select the optimal model for a role.
  """

  @type tier :: :economy | :standard | :premium

  @type t :: %__MODULE__{
          model_string: String.t(),
          tier: tier(),
          input_cost_per_m: float(),
          output_cost_per_m: float(),
          capabilities: [String.t()]
        }

  @enforce_keys [:model_string, :tier, :input_cost_per_m, :output_cost_per_m]
  defstruct [:model_string, :tier, :input_cost_per_m, :output_cost_per_m, capabilities: []]

  @doc "Create a model profile."
  @spec new(String.t(), tier(), float(), float(), [String.t()]) :: t()
  def new(model_string, tier, input_cost_per_m, output_cost_per_m, capabilities \\ []) do
    %__MODULE__{
      model_string: model_string,
      tier: tier,
      input_cost_per_m: input_cost_per_m / 1,
      output_cost_per_m: output_cost_per_m / 1,
      capabilities: capabilities
    }
  end

  @doc "Average cost per token (input + output / 2) in dollars per million tokens."
  @spec cost_per_token(t()) :: float()
  def cost_per_token(%__MODULE__{input_cost_per_m: input, output_cost_per_m: output}) do
    (input + output) / 2
  end
end
