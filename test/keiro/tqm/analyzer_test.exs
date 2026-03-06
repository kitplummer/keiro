defmodule Keiro.TQM.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Keiro.TQM.{Analyzer, Config}
  alias Keiro.Pipeline.Result
  alias Keiro.Pipeline.Result.StageResult

  defp make_failure(bead_id, stage_name, error_msg \\ "something failed") do
    %{
      bead_id: bead_id,
      title: "Task #{bead_id}",
      result:
        {:error,
         %Result{
           status: :error,
           error_stage: stage_name,
           stages: [
             %StageResult{name: stage_name, status: :error, result: error_msg, elapsed_ms: 100}
           ]
         }}
    }
  end

  defp make_success(bead_id) do
    %{
      bead_id: bead_id,
      title: "Task #{bead_id}",
      result:
        {:ok,
         %Result{
           status: :ok,
           stages: [
             %StageResult{name: "engineer", status: :ok, result: "done", elapsed_ms: 100}
           ]
         }}
    }
  end

  describe "analyze/2 — repeated stage failures" do
    test "detects when same stage fails >= threshold times" do
      config = Config.new(stage_failure_threshold: 2)

      results = [
        make_failure("gl-001", "engineer"),
        make_failure("gl-002", "engineer"),
        make_success("gl-003")
      ]

      patterns = Analyzer.analyze(results, config)
      assert length(patterns) == 1
      [pattern] = patterns
      assert pattern.kind == :repeated_stage_failure
      assert pattern.detail.stage_name == "engineer"
      assert pattern.detail.count == 2
      assert "gl-001" in pattern.affected_beads
      assert "gl-002" in pattern.affected_beads
    end

    test "does not flag when below threshold" do
      config = Config.new(stage_failure_threshold: 3)

      results = [
        make_failure("gl-001", "engineer"),
        make_failure("gl-002", "engineer")
      ]

      patterns = Analyzer.analyze(results, config)
      assert patterns == []
    end

    test "groups by stage name" do
      config = Config.new(stage_failure_threshold: 2)

      results = [
        make_failure("gl-001", "engineer"),
        make_failure("gl-002", "deploy"),
        make_failure("gl-003", "engineer"),
        make_failure("gl-004", "deploy")
      ]

      patterns = Analyzer.analyze(results, config)
      stage_names = Enum.map(patterns, fn p -> p.detail.stage_name end) |> Enum.sort()
      assert stage_names == ["deploy", "engineer"]
    end

    test "returns empty for all-success batch" do
      config = Config.new()
      results = [make_success("gl-001"), make_success("gl-002")]
      assert Analyzer.analyze(results, config) == []
    end

    test "returns empty for empty results" do
      assert Analyzer.analyze([], Config.new()) == []
    end
  end

  describe "analyze/2 — model degradation" do
    test "detects repeated agent_start_failure" do
      config = Config.new(model_error_threshold: 2)

      results = [
        make_failure("gl-001", "engineer", "Failed to start agent: noproc"),
        make_failure("gl-002", "engineer", "Failed to start agent: timeout"),
        make_success("gl-003")
      ]

      patterns = Analyzer.analyze(results, config)
      model_patterns = Enum.filter(patterns, fn p -> p.kind == :model_degradation end)
      assert length(model_patterns) == 1
      [p] = model_patterns
      assert p.detail.error_class == "agent_start_failure"
    end

    test "detects repeated timeout errors" do
      config = Config.new(model_error_threshold: 2)

      results = [
        make_failure("gl-001", "ops", "Stage ops timed out or crashed: timeout"),
        make_failure("gl-002", "ops", "Stage ops timed out or crashed: timeout")
      ]

      patterns = Analyzer.analyze(results, config)
      model_patterns = Enum.filter(patterns, fn p -> p.kind == :model_degradation end)
      assert length(model_patterns) >= 1
      assert Enum.any?(model_patterns, fn p -> p.detail.error_class == "timeout" end)
    end
  end

  describe "analyze_and_remediate/3" do
    test "returns patterns without creating beads when auto_create_beads is false" do
      config = Config.new(stage_failure_threshold: 1, auto_create_beads: false)
      results = [make_failure("gl-001", "engineer")]

      {patterns, created} = Analyzer.analyze_and_remediate(results, config, nil)
      assert length(patterns) == 1
      assert created == []
    end

    test "returns patterns without creating beads when client is nil" do
      config = Config.new(stage_failure_threshold: 1, auto_create_beads: true)
      results = [make_failure("gl-001", "engineer")]

      {patterns, created} = Analyzer.analyze_and_remediate(results, config, nil)
      assert length(patterns) == 1
      assert created == []
    end
  end
end
