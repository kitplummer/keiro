defmodule Keiro.TQM.Analyzer do
  @moduledoc """
  Post-run pattern detection for Total Quality Management.

  Scans a batch of task run results for recurring failure patterns and
  returns detected patterns as `Keiro.TQM.Pattern` structs. Optionally
  creates remediation beads via `BeadsClient`.

  ## Usage

      config = Keiro.TQM.Config.new()
      results = Keiro.Orchestrator.run_all(repo_path: ".")
      patterns = Keiro.TQM.Analyzer.analyze(results, config)
  """

  alias Keiro.TQM.{Config, Pattern}

  require Logger

  @doc """
  Analyze a list of task run results and return detected patterns.

  Each result is expected to be `%{bead_id: String.t(), title: String.t(), result: term()}`,
  matching the shape returned by `Orchestrator.run_all/1`.
  """
  @spec analyze([map()], Config.t()) :: [Pattern.t()]
  def analyze(results, %Config{} = config \\ %Config{}) do
    []
    |> then(&(detect_repeated_stage_failures(results, config) ++ &1))
    |> then(&(detect_model_degradation(results, config) ++ &1))
  end

  @doc """
  Analyze results and optionally create remediation beads.

  Returns `{patterns, created_bead_ids}`. Only creates beads when
  `config.auto_create_beads` is true and a `client` is provided.
  """
  @spec analyze_and_remediate([map()], Config.t(), Keiro.Beads.Client.t() | nil) ::
          {[Pattern.t()], [String.t()]}
  def analyze_and_remediate(results, config, client) do
    patterns = analyze(results, config)

    created =
      if config.auto_create_beads && client do
        Enum.flat_map(patterns, fn pattern ->
          case create_remediation_bead(client, pattern, config.labels) do
            {:ok, id} ->
              Logger.info("TQM: created remediation bead #{id} for #{pattern.kind}")
              [id]

            {:error, reason} ->
              Logger.warning("TQM: failed to create bead for #{pattern.kind}: #{reason}")
              []
          end
        end)
      else
        []
      end

    {patterns, created}
  end

  # -- Pattern detectors --

  defp detect_repeated_stage_failures(results, config) do
    # Group failures by stage name, flag any stage that failed >= threshold times
    stage_failures =
      results
      |> Enum.flat_map(&extract_failed_stages/1)
      |> Enum.group_by(fn {stage_name, _bead_id} -> stage_name end)

    stage_failures
    |> Enum.filter(fn {_stage, failures} ->
      length(failures) >= config.stage_failure_threshold
    end)
    |> Enum.map(fn {stage_name, failures} ->
      bead_ids = Enum.map(failures, fn {_stage, bead_id} -> bead_id end)

      %Pattern{
        kind: :repeated_stage_failure,
        description:
          "Stage '#{stage_name}' failed #{length(failures)} times (threshold: #{config.stage_failure_threshold})",
        affected_beads: bead_ids,
        detail: %{stage_name: stage_name, count: length(failures)},
        suggested_priority: 1
      }
    end)
  end

  defp detect_model_degradation(results, config) do
    # Count errors that look like model/parse failures
    model_errors =
      results
      |> Enum.flat_map(&extract_model_errors/1)
      |> Enum.group_by(fn {error_class, _bead_id} -> error_class end)

    model_errors
    |> Enum.filter(fn {_class, errors} -> length(errors) >= config.model_error_threshold end)
    |> Enum.map(fn {error_class, errors} ->
      bead_ids = Enum.map(errors, fn {_class, bead_id} -> bead_id end)

      %Pattern{
        kind: :model_degradation,
        description:
          "Model error '#{error_class}' occurred #{length(errors)} times (threshold: #{config.model_error_threshold})",
        affected_beads: bead_ids,
        detail: %{error_class: error_class, count: length(errors)},
        suggested_priority: 1
      }
    end)
  end

  # -- Helpers --

  defp extract_failed_stages(%{bead_id: bead_id, result: {:error, pipeline_result}})
       when is_map(pipeline_result) do
    case pipeline_result do
      %{error_stage: stage_name} when is_binary(stage_name) ->
        [{stage_name, bead_id}]

      _ ->
        []
    end
  end

  defp extract_failed_stages(_), do: []

  defp extract_model_errors(%{bead_id: bead_id, result: {:error, pipeline_result}})
       when is_map(pipeline_result) do
    pipeline_result
    |> Map.get(:stages, [])
    |> Enum.filter(fn stage -> stage.status == :error end)
    |> Enum.flat_map(fn stage ->
      error_str = to_string(stage.result)

      cond do
        error_str =~ "Failed to start agent" -> [{"agent_start_failure", bead_id}]
        error_str =~ "timed out" -> [{"timeout", bead_id}]
        error_str =~ "parse" -> [{"parse_failure", bead_id}]
        true -> []
      end
    end)
  end

  defp extract_model_errors(_), do: []

  defp create_remediation_bead(client, pattern, labels) do
    title =
      case pattern.kind do
        :repeated_stage_failure ->
          "TQM: fix repeated #{pattern.detail.stage_name} stage failures"

        :model_degradation ->
          "TQM: investigate #{pattern.detail.error_class} model errors"

        :restart_intensity_exceeded ->
          "TQM: investigate systemic failure (restart intensity exceeded)"
      end
      |> String.slice(0, 200)

    Keiro.Beads.Client.create(client, title,
      type: "bug",
      priority: pattern.suggested_priority,
      description:
        pattern.description <> "\n\nAffected beads: #{Enum.join(pattern.affected_beads, ", ")}",
      labels: labels
    )
  end
end
