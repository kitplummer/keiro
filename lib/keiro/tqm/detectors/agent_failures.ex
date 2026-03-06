defmodule Keiro.TQM.Detectors.AgentFailures do
  @moduledoc "Detects repeated failures from the same agent."

  @behaviour Keiro.TQM.Detector

  alias Keiro.TQM.Pattern

  @default_threshold 3

  @impl Keiro.TQM.Detector
  def detect(results, config) do
    threshold = Map.get(config, :agent_failure_threshold, @default_threshold)

    results
    |> Enum.filter(&(&1[:status] == :error))
    |> Enum.group_by(& &1[:agent])
    |> Enum.flat_map(fn {agent, failures} ->
      if length(failures) >= threshold do
        bead_ids = Enum.map(failures, & &1[:bead_id])

        [
          %Pattern{
            name: "repeated_agent_failures",
            severity: :warning,
            count: length(failures),
            threshold: threshold,
            description:
              "Agent #{inspect(agent)} failed #{length(failures)} times " <>
                "(threshold: #{threshold})",
            remediation:
              "Investigate agent #{inspect(agent)} for systemic issues. " <>
                "Check model availability, prompt quality, or tool configuration.",
            evidence: Enum.map(bead_ids, &"bead #{&1}")
          }
        ]
      else
        []
      end
    end)
  end
end
