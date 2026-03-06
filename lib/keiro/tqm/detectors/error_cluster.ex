defmodule Keiro.TQM.Detectors.ErrorCluster do
  @moduledoc "Detects clusters of the same error message across agents."

  @behaviour Keiro.TQM.Detector

  alias Keiro.TQM.Pattern

  @default_threshold 3

  @impl Keiro.TQM.Detector
  def detect(results, config) do
    threshold = Map.get(config, :error_cluster_threshold, @default_threshold)

    results
    |> Enum.filter(&(&1[:status] == :error and &1[:error] != nil))
    |> Enum.group_by(&normalize_error(&1[:error]))
    |> Enum.flat_map(fn {error_key, failures} ->
      if length(failures) >= threshold do
        bead_ids = Enum.map(failures, & &1[:bead_id])

        [
          %Pattern{
            name: "error_cluster",
            severity: :critical,
            count: length(failures),
            threshold: threshold,
            description: "Same error repeated #{length(failures)} times: #{error_key}",
            remediation:
              "This error is systemic — fix the root cause before retrying. " <>
                "Common causes: provider outage, missing credentials, broken base branch.",
            evidence: Enum.map(bead_ids, &"bead #{&1}")
          }
        ]
      else
        []
      end
    end)
  end

  @doc false
  def normalize_error(error) when is_binary(error) do
    error
    |> String.slice(0, 100)
    |> String.replace(~r/[0-9a-f]{8,}/, "***")
    |> String.trim()
  end

  def normalize_error(error), do: inspect(error) |> String.slice(0, 100)
end
