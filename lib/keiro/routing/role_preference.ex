defmodule Keiro.Routing.RolePreference do
  @moduledoc """
  Per-role model preference — minimum tier and required capabilities.
  """

  @type t :: %__MODULE__{
          role: String.t(),
          min_tier: Keiro.Routing.ModelProfile.tier(),
          requires: MapSet.t(String.t())
        }

  @enforce_keys [:role]
  defstruct [
    :role,
    min_tier: :economy,
    requires: MapSet.new()
  ]
end
