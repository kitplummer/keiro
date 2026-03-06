defmodule Keiro.TQM.Detectors.StageBottleneck do
  @moduledoc "Detects pipeline stages that fail repeatedly."

  @behaviour Keiro.TQM.Detector

  alias Keiro.TQM.Pattern

  @default_threshold 2

  @impl Keiro.TQM.Detector
  def detect(results, config) do
    threshold = Map.get(config, :stage_failure_threshold, @default_threshold)

    results
    |> Enum.filter(&(&1[:status] == :error and &1[:error_stage] != nil))
    |> Enum.group_by(& &1[:error_stage])
    |> Enum.flat_map(fn {stage, failures} ->
      if length(failures) >= threshold do
        bead_ids = Enum.map(failures, & &1[:bead_id])

        [
          %Pattern{
            name: "stage_bottleneck",
            severity: :warning,
            count: length(failures),
            threshold: threshold,
            description:
              "Pipeline stage '#{stage}' failed #{length(failures)} times " <>
                "(threshold: #{threshold})",
            remediation:
              "Stage '#{stage}' is a bottleneck. Check agent configuration, " <>
                "timeouts, and tool availability for this stage.",
            evidence: Enum.map(bead_ids, &"bead #{&1}")
          }
        ]
      else
        []
      end
    end)
  end
end
