defmodule Keiro.TQM.Pattern do
  @moduledoc """
  A detected failure pattern from batch run analysis.

  Patterns represent recurring issues that the TQM analyzer detects
  from orchestrator run results. Each pattern includes a recommended
  remediation and enough context to create a bead.
  """

  @type severity :: :critical | :warning | :info

  @type t :: %__MODULE__{
          name: String.t(),
          severity: severity(),
          count: non_neg_integer(),
          threshold: non_neg_integer(),
          description: String.t(),
          remediation: String.t(),
          evidence: [String.t()]
        }

  @enforce_keys [:name, :severity, :count, :threshold, :description, :remediation]
  defstruct [:name, :severity, :count, :threshold, :description, :remediation, evidence: []]
end
