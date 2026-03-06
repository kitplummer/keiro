defmodule Keiro.TQM.Pattern do
  @moduledoc """
  A detected failure pattern from TQM analysis.

  Each pattern has a kind, the affected bead IDs, a human-readable description,
  and suggested priority for the remediation bead.
  """

  @type kind ::
          :repeated_stage_failure
          | :model_degradation
          | :restart_intensity_exceeded

  @type t :: %__MODULE__{
          kind: kind(),
          description: String.t(),
          affected_beads: [String.t()],
          detail: map(),
          suggested_priority: non_neg_integer()
        }

  @enforce_keys [:kind, :description]
  defstruct [:kind, :description, affected_beads: [], detail: %{}, suggested_priority: 1]
end
