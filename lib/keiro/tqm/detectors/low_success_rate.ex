defmodule Keiro.TQM.Detectors.LowSuccessRate do
  @moduledoc "Detects batch-wide success rate below threshold."

  @behaviour Keiro.TQM.Detector

  alias Keiro.TQM.Pattern

  @default_threshold 0.5

  @impl Keiro.TQM.Detector
  def detect(results, config) do
    total = length(results)

    if total == 0 do
      []
    else
      threshold = Map.get(config, :success_rate_warning, @default_threshold)
      successes = Enum.count(results, &(&1[:status] == :ok))
      rate = successes / total

      if rate < threshold do
        [
          %Pattern{
            name: "low_success_rate",
            severity: :critical,
            count: total - successes,
            threshold: trunc(total * threshold),
            description:
              "Batch success rate #{Float.round(rate * 100, 1)}% " <>
                "(#{successes}/#{total}) below #{threshold * 100}% threshold",
            remediation:
              "Halt further batch runs until systemic issues are resolved. " <>
                "Check provider health, API keys, and base branch state.",
            evidence: []
          }
        ]
      else
        []
      end
    end
  end
end
