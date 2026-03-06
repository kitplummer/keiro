defmodule Keiro.TQM.Detector do
  @moduledoc """
  Behaviour for TQM failure pattern detectors.

  Implement this behaviour to create domain-specific failure pattern
  detectors. The TQM Analyzer calls `detect/2` on each registered
  detector module and collects the results.

  ## Example

      defmodule MyApp.TQM.Detectors.ProviderTimeout do
        @behaviour Keiro.TQM.Detector

        @impl true
        def detect(results, config) do
          threshold = Map.get(config, :provider_timeout_threshold, 3)
          timeouts = Enum.filter(results, &(&1[:error] =~ "timeout"))

          if length(timeouts) >= threshold do
            [%Keiro.TQM.Pattern{
              name: "provider_timeout",
              severity: :warning,
              count: length(timeouts),
              threshold: threshold,
              description: "Provider timed out \#{length(timeouts)} times",
              remediation: "Check provider health or increase timeout"
            }]
          else
            []
          end
        end
      end
  """

  alias Keiro.TQM.Pattern

  @doc """
  Scan batch run results for a specific failure pattern.

  Returns a list of detected patterns (empty if no pattern found).
  The `config` map contains threshold overrides.
  """
  @callback detect(results :: [map()], config :: map()) :: [Pattern.t()]
end
