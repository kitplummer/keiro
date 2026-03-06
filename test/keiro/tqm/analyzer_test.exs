defmodule Keiro.TQM.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Keiro.TQM.Analyzer
  alias Keiro.TQM.Pattern

  describe "analyze/2" do
    test "returns empty list for no results" do
      assert Analyzer.analyze([]) == []
    end

    test "returns empty list when all tasks succeed" do
      results = [
        %{bead_id: "k-001", status: :ok, agent: :engineer},
        %{bead_id: "k-002", status: :ok, agent: :uplink}
      ]

      assert Analyzer.analyze(results) == []
    end

    test "detects repeated agent failures" do
      results =
        for i <- 1..4 do
          %{bead_id: "k-#{i}", status: :error, error: "fail #{i}", agent: :uplink}
        end

      patterns = Analyzer.analyze(results)
      assert length(patterns) > 0

      agent_pattern = Enum.find(patterns, &(&1.name == "repeated_agent_failures"))
      assert agent_pattern != nil
      assert agent_pattern.count == 4
      assert agent_pattern.severity == :warning
      assert length(agent_pattern.evidence) == 4
    end

    test "does not flag agent failures below threshold" do
      results = [
        %{bead_id: "k-001", status: :error, error: "fail", agent: :uplink},
        %{bead_id: "k-002", status: :error, error: "fail", agent: :uplink},
        %{bead_id: "k-003", status: :ok, agent: :engineer}
      ]

      patterns = Analyzer.analyze(results)
      agent_patterns = Enum.filter(patterns, &(&1.name == "repeated_agent_failures"))
      assert agent_patterns == []
    end

    test "detects error clusters with same error message" do
      results = [
        %{bead_id: "k-001", status: :error, error: "deploy failed", agent: :a},
        %{bead_id: "k-002", status: :error, error: "deploy failed", agent: :b},
        %{bead_id: "k-003", status: :error, error: "deploy failed", agent: :c}
      ]

      patterns = Analyzer.analyze(results)
      cluster = Enum.find(patterns, &(&1.name == "error_cluster"))
      assert cluster != nil
      assert cluster.count == 3
      assert cluster.severity == :critical
    end

    test "normalizes error messages for clustering" do
      results = [
        %{bead_id: "k-001", status: :error, error: "failed ref abc12345", agent: :a},
        %{bead_id: "k-002", status: :error, error: "failed ref def67890", agent: :b},
        %{bead_id: "k-003", status: :error, error: "failed ref 11223344", agent: :c}
      ]

      patterns = Analyzer.analyze(results)
      cluster = Enum.find(patterns, &(&1.name == "error_cluster"))
      assert cluster != nil
      assert cluster.count == 3
    end

    test "detects pipeline stage bottleneck" do
      results = [
        %{bead_id: "k-001", status: :error, error: "timeout", error_stage: "deploy", agent: :a},
        %{bead_id: "k-002", status: :error, error: "crash", error_stage: "deploy", agent: :b}
      ]

      patterns = Analyzer.analyze(results)
      stage_pattern = Enum.find(patterns, &(&1.name == "stage_bottleneck"))
      assert stage_pattern != nil
      assert stage_pattern.count == 2
      assert stage_pattern.description =~ "deploy"
    end

    test "detects low success rate" do
      results = [
        %{bead_id: "k-001", status: :error, error: "a", agent: :a},
        %{bead_id: "k-002", status: :error, error: "b", agent: :b},
        %{bead_id: "k-003", status: :error, error: "c", agent: :c},
        %{bead_id: "k-004", status: :ok, agent: :d}
      ]

      patterns = Analyzer.analyze(results)
      low_rate = Enum.find(patterns, &(&1.name == "low_success_rate"))
      assert low_rate != nil
      assert low_rate.severity == :critical
      assert low_rate.description =~ "25.0%"
    end

    test "does not flag high success rate" do
      results = [
        %{bead_id: "k-001", status: :ok, agent: :a},
        %{bead_id: "k-002", status: :ok, agent: :b},
        %{bead_id: "k-003", status: :ok, agent: :c},
        %{bead_id: "k-004", status: :error, error: "x", agent: :d}
      ]

      patterns = Analyzer.analyze(results)
      low_rate = Enum.find(patterns, &(&1.name == "low_success_rate"))
      assert low_rate == nil
    end

    test "supports custom thresholds via config option" do
      results = [
        %{bead_id: "k-001", status: :error, error: "fail", agent: :uplink},
        %{bead_id: "k-002", status: :ok, agent: :eng}
      ]

      patterns = Analyzer.analyze(results, config: %{agent_failure_threshold: 1})
      agent_pattern = Enum.find(patterns, &(&1.name == "repeated_agent_failures"))
      assert agent_pattern != nil
    end

    test "all returned items are Pattern structs" do
      results =
        for i <- 1..5 do
          %{bead_id: "k-#{i}", status: :error, error: "same error", agent: :uplink}
        end

      patterns = Analyzer.analyze(results)
      assert length(patterns) > 0

      Enum.each(patterns, fn p ->
        assert %Pattern{} = p
        assert is_binary(p.name)
        assert p.severity in [:critical, :warning, :info]
        assert is_integer(p.count)
        assert is_binary(p.description)
        assert is_binary(p.remediation)
      end)
    end

    test "handles non-string error values" do
      results = [
        %{bead_id: "k-001", status: :error, error: {:timeout, 5000}, agent: :a},
        %{bead_id: "k-002", status: :error, error: {:timeout, 5000}, agent: :b},
        %{bead_id: "k-003", status: :error, error: {:timeout, 5000}, agent: :c}
      ]

      patterns = Analyzer.analyze(results)
      cluster = Enum.find(patterns, &(&1.name == "error_cluster"))
      assert cluster != nil
    end
  end

  describe "custom detectors" do
    defmodule TestDetector do
      @behaviour Keiro.TQM.Detector

      @impl true
      def detect(results, _config) do
        count = Enum.count(results, &(&1[:custom_field] == true))

        if count > 0 do
          [
            %Pattern{
              name: "custom_test",
              severity: :info,
              count: count,
              threshold: 1,
              description: "Custom detector found #{count} items",
              remediation: "Custom fix"
            }
          ]
        else
          []
        end
      end
    end

    test "extra detectors are appended to defaults" do
      results = [
        %{bead_id: "k-001", status: :ok, agent: :a, custom_field: true}
      ]

      patterns = Analyzer.analyze(results, detectors: [TestDetector])
      custom = Enum.find(patterns, &(&1.name == "custom_test"))
      assert custom != nil
      assert custom.count == 1
    end

    test "only option replaces default detectors" do
      results =
        for i <- 1..5 do
          %{bead_id: "k-#{i}", status: :error, error: "fail", agent: :uplink, custom_field: true}
        end

      patterns = Analyzer.analyze(results, only: [TestDetector])
      # Only custom detector should run, not built-ins
      assert length(patterns) == 1
      assert hd(patterns).name == "custom_test"
    end
  end

  describe "default_config/0" do
    test "returns map with all threshold keys" do
      config = Analyzer.default_config()
      assert is_map(config)
      assert Map.has_key?(config, :agent_failure_threshold)
      assert Map.has_key?(config, :error_cluster_threshold)
      assert Map.has_key?(config, :stage_failure_threshold)
      assert Map.has_key?(config, :success_rate_warning)
    end
  end

  describe "default_detectors/0" do
    test "returns four built-in detector modules" do
      detectors = Analyzer.default_detectors()
      assert length(detectors) == 4
      assert Keiro.TQM.Detectors.AgentFailures in detectors
      assert Keiro.TQM.Detectors.ErrorCluster in detectors
      assert Keiro.TQM.Detectors.StageBottleneck in detectors
      assert Keiro.TQM.Detectors.LowSuccessRate in detectors
    end
  end
end
