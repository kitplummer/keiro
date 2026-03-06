defmodule Keiro.TQM.Config do
  @moduledoc """
  Configuration for TQM pattern detection thresholds.
  """

  @type t :: %__MODULE__{
          stage_failure_threshold: pos_integer(),
          model_error_threshold: pos_integer(),
          restart_intensity_max: pos_integer(),
          restart_intensity_window_ms: pos_integer(),
          auto_create_beads: boolean(),
          labels: [String.t()]
        }

  defstruct stage_failure_threshold: 3,
            model_error_threshold: 3,
            restart_intensity_max: 5,
            restart_intensity_window_ms: 300_000,
            auto_create_beads: false,
            labels: ["tqm", "auto-generated"]

  @doc "Build config from keyword opts, falling back to defaults."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end
end
