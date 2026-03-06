defmodule Keiro.TQM.Analyzer do
  @moduledoc """
  Post-run pattern detection for total quality management.

  Scans a list of batch run results for recurring failure patterns
  using pluggable `Keiro.TQM.Detector` modules. When a pattern exceeds
  its threshold, the analyzer returns a `%Pattern{}` describing the
  issue and recommended remediation.

  ## Usage

      results = [
        %{bead_id: "k-001", status: :error, error: "deploy failed", agent: :uplink},
        %{bead_id: "k-002", status: :error, error: "deploy failed", agent: :uplink},
        %{bead_id: "k-003", status: :error, error: "deploy failed", agent: :uplink},
        %{bead_id: "k-004", status: :ok, agent: :engineer}
      ]

      patterns = Keiro.TQM.Analyzer.analyze(results)
      # => [%Pattern{name: "repeated_agent_failures", ...}]

  ## Custom Detectors

  Register domain-specific detectors via the `:detectors` option:

      patterns = Keiro.TQM.Analyzer.analyze(results,
        detectors: [MyApp.TQM.Detectors.ProviderTimeout]
      )

  Pass a config map to override thresholds:

      patterns = Keiro.TQM.Analyzer.analyze(results,
        config: %{agent_failure_threshold: 5}
      )
  """

  alias Keiro.TQM.Pattern

  @default_detectors [
    Keiro.TQM.Detectors.AgentFailures,
    Keiro.TQM.Detectors.ErrorCluster,
    Keiro.TQM.Detectors.StageBottleneck,
    Keiro.TQM.Detectors.LowSuccessRate
  ]

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

  Options:
  - `:config` — map of threshold overrides (merged with defaults)
  - `:detectors` — list of additional detector modules (appended to built-ins)
  - `:only` — list of detector modules to use instead of defaults
  """
  @spec analyze([map()], keyword()) :: [Pattern.t()]
  def analyze(results, opts \\ []) when is_list(results) do
    config = Map.merge(@default_config, Keyword.get(opts, :config, %{}))
    extra_detectors = Keyword.get(opts, :detectors, [])

    detectors =
      case Keyword.get(opts, :only) do
        nil -> @default_detectors ++ extra_detectors
        only -> only
      end

    Enum.flat_map(detectors, fn detector ->
      detector.detect(results, config)
    end)
  end

  @doc "Return the default configuration thresholds."
  @spec default_config() :: map()
  def default_config, do: @default_config

  @doc "Return the list of built-in detector modules."
  @spec default_detectors() :: [module()]
  def default_detectors, do: @default_detectors
end
