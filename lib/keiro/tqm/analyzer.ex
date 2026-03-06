defmodule Keiro.TQM.Analyzer do
  @moduledoc """
  Post-run pattern detection for total quality management.

  Scans a list of batch run results for recurring failure patterns.
  When a pattern exceeds its threshold, the analyzer returns a
  `%Pattern{}` describing the issue and recommended remediation.

  ## Usage

      results = [
        %{bead_id: "k-001", status: :error, error: "deploy failed", agent: :uplink},
        %{bead_id: "k-002", status: :error, error: "deploy failed", agent: :uplink},
        %{bead_id: "k-003", status: :error, error: "deploy failed", agent: :uplink},
        %{bead_id: "k-004", status: :ok, agent: :engineer}
      ]

      patterns = Keiro.TQM.Analyzer.analyze(results)
      # => [%Pattern{name: "repeated_agent_failures", ...}]

  ## Configuration

  Pass a config map as the second argument to override thresholds:

      config = %{agent_failure_threshold: 5, error_cluster_threshold: 4}
      patterns = Keiro.TQM.Analyzer.analyze(results, config)
  """

  alias Keiro.TQM.Pattern

  @default_config %{
    agent_failure_threshold: 3,
    error_cluster_threshold: 3,
    stage_failure_threshold: 2,
    success_rate_warning: 0.5
  }

  @doc """
  Analyze batch run results and return detected patterns.

  Each result map should contain:
  - `:bead_id` — the bead that was processed
  - `:status` — `:ok` or `:error`
  - `:error` — error message (when status is :error)
  - `:agent` — agent module or atom that processed it
  - `:error_stage` — pipeline stage that failed (optional)
  """
  @spec analyze([map()], map()) :: [Pattern.t()]
  def analyze(results, config \\ %{}) when is_list(results) do
    config = Map.merge(@default_config, config)

    [
      &detect_agent_failures/2,
      &detect_error_clusters/2,
      &detect_stage_failures/2,
      &detect_low_success_rate/2
    ]
    |> Enum.flat_map(fn detector -> detector.(results, config) end)
  end

  @doc "Return the default configuration thresholds."
  @spec default_config() :: map()
  def default_config, do: @default_config

  # -- Pattern detectors --

  defp detect_agent_failures(results, config) do
    threshold = config.agent_failure_threshold

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

  defp detect_error_clusters(results, config) do
    threshold = config.error_cluster_threshold

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

  defp detect_stage_failures(results, config) do
    threshold = config.stage_failure_threshold

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

  defp detect_low_success_rate(results, config) do
    total = length(results)

    if total == 0 do
      []
    else
      successes = Enum.count(results, &(&1[:status] == :ok))
      rate = successes / total

      if rate < config.success_rate_warning do
        [
          %Pattern{
            name: "low_success_rate",
            severity: :critical,
            count: total - successes,
            threshold: trunc(total * config.success_rate_warning),
            description:
              "Batch success rate #{Float.round(rate * 100, 1)}% " <>
                "(#{successes}/#{total}) below #{config.success_rate_warning * 100}% threshold",
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

  defp normalize_error(error) when is_binary(error) do
    error
    |> String.slice(0, 100)
    |> String.replace(~r/[0-9a-f]{8,}/, "***")
    |> String.trim()
  end

  defp normalize_error(error), do: inspect(error) |> String.slice(0, 100)
end
