defmodule Keiro.TQM.DetectorTest do
  use ExUnit.Case, async: true

  alias Keiro.TQM.Detectors.{AgentFailures, ErrorCluster, StageBottleneck, LowSuccessRate}
  alias Keiro.TQM.Pattern

  @config %{
    agent_failure_threshold: 3,
    error_cluster_threshold: 3,
    stage_failure_threshold: 2,
    success_rate_warning: 0.5
  }

  describe "AgentFailures.detect/2" do
    test "detects when threshold exceeded" do
      results = for i <- 1..3, do: %{bead_id: "k-#{i}", status: :error, agent: :uplink}
      patterns = AgentFailures.detect(results, @config)
      assert [%Pattern{name: "repeated_agent_failures"}] = patterns
    end

    test "returns empty below threshold" do
      results = [%{bead_id: "k-1", status: :error, agent: :uplink}]
      assert [] = AgentFailures.detect(results, @config)
    end

    test "groups by agent" do
      results = [
        %{bead_id: "k-1", status: :error, agent: :uplink},
        %{bead_id: "k-2", status: :error, agent: :uplink},
        %{bead_id: "k-3", status: :error, agent: :uplink},
        %{bead_id: "k-4", status: :error, agent: :engineer},
        %{bead_id: "k-5", status: :error, agent: :engineer}
      ]

      patterns = AgentFailures.detect(results, @config)
      assert length(patterns) == 1
      assert hd(patterns).description =~ "uplink"
    end
  end

  describe "ErrorCluster.detect/2" do
    test "detects same error repeated" do
      results =
        for i <- 1..3, do: %{bead_id: "k-#{i}", status: :error, error: "same", agent: :a}

      patterns = ErrorCluster.detect(results, @config)
      assert [%Pattern{name: "error_cluster"}] = patterns
    end

    test "normalizes hashes in errors" do
      assert "failed ref ***" = ErrorCluster.normalize_error("failed ref abc12345")
    end

    test "handles non-string errors" do
      assert is_binary(ErrorCluster.normalize_error({:timeout, 5000}))
    end
  end

  describe "StageBottleneck.detect/2" do
    test "detects stage failing repeatedly" do
      results = [
        %{bead_id: "k-1", status: :error, error_stage: "deploy", agent: :a},
        %{bead_id: "k-2", status: :error, error_stage: "deploy", agent: :b}
      ]

      patterns = StageBottleneck.detect(results, @config)
      assert [%Pattern{name: "stage_bottleneck"}] = patterns
    end

    test "ignores results without error_stage" do
      results = [
        %{bead_id: "k-1", status: :error, agent: :a},
        %{bead_id: "k-2", status: :error, agent: :b}
      ]

      assert [] = StageBottleneck.detect(results, @config)
    end
  end

  describe "LowSuccessRate.detect/2" do
    test "detects low success rate" do
      results = [
        %{bead_id: "k-1", status: :error},
        %{bead_id: "k-2", status: :error},
        %{bead_id: "k-3", status: :ok}
      ]

      patterns = LowSuccessRate.detect(results, @config)
      assert [%Pattern{name: "low_success_rate"}] = patterns
    end

    test "returns empty for high success rate" do
      results = [
        %{bead_id: "k-1", status: :ok},
        %{bead_id: "k-2", status: :ok},
        %{bead_id: "k-3", status: :error}
      ]

      assert [] = LowSuccessRate.detect(results, @config)
    end

    test "returns empty for zero results" do
      assert [] = LowSuccessRate.detect([], @config)
    end
  end
end
