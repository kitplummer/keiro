defmodule Keiro.Pipeline.OutcomeTest do
  use ExUnit.Case, async: true

  alias Keiro.Pipeline.Outcome
  alias Keiro.Pipeline.Result
  alias Keiro.Pipeline.Result.StageResult

  describe "values/0" do
    test "returns all 6 outcomes" do
      assert length(Outcome.values()) == 6
      assert :completed in Outcome.values()
      assert :deferred in Outcome.values()
      assert :decomposed in Outcome.values()
      assert :blocked in Outcome.values()
      assert :retryable in Outcome.values()
      assert :escalated in Outcome.values()
    end
  end

  describe "valid?/1" do
    test "returns true for valid outcomes" do
      for outcome <- Outcome.values() do
        assert Outcome.valid?(outcome)
      end
    end

    test "returns false for invalid values" do
      refute Outcome.valid?(:unknown)
      refute Outcome.valid?("completed")
      refute Outcome.valid?(nil)
    end
  end

  describe "classify/1" do
    test "ok result classifies as completed" do
      result = %Result{status: :ok, stages: []}
      assert Outcome.classify(result) == :completed
    end

    test "timeout error classifies as retryable" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{
            name: "eng",
            status: :error,
            result: "timed out waiting for response",
            elapsed_ms: 0
          }
        ]
      }

      assert Outcome.classify(result) == :retryable
    end

    test "rate limit error classifies as retryable" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{
            name: "eng",
            status: :error,
            result: "429 rate limit exceeded",
            elapsed_ms: 0
          }
        ]
      }

      assert Outcome.classify(result) == :retryable
    end

    test "connection refused classifies as retryable" do
      result = %Result{
        status: :error,
        stages: [%StageResult{name: "eng", status: :error, result: "econnrefused", elapsed_ms: 0}]
      }

      assert Outcome.classify(result) == :retryable
    end

    test "503 error classifies as retryable" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{
            name: "eng",
            status: :error,
            result: "HTTP 503 service unavailable",
            elapsed_ms: 0
          }
        ]
      }

      assert Outcome.classify(result) == :retryable
    end

    test "nxdomain classifies as retryable" do
      result = %Result{
        status: :error,
        stages: [%StageResult{name: "eng", status: :error, result: "nxdomain", elapsed_ms: 0}]
      }

      assert Outcome.classify(result) == :retryable
    end

    test "permission denied classifies as escalated" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{
            name: "eng",
            status: :error,
            result: "permission denied: /etc/secrets",
            elapsed_ms: 0
          }
        ]
      }

      assert Outcome.classify(result) == :escalated
    end

    test "unauthorized classifies as escalated" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{
            name: "eng",
            status: :error,
            result: "unauthorized access to API",
            elapsed_ms: 0
          }
        ]
      }

      assert Outcome.classify(result) == :escalated
    end

    test "403 classifies as escalated" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{name: "eng", status: :error, result: "HTTP 403 forbidden", elapsed_ms: 0}
        ]
      }

      assert Outcome.classify(result) == :escalated
    end

    test "requires human classifies as escalated" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{
            name: "eng",
            status: :error,
            result: "requires human review",
            elapsed_ms: 0
          }
        ]
      }

      assert Outcome.classify(result) == :escalated
    end

    test "generic error classifies as blocked" do
      result = %Result{
        status: :error,
        stages: [
          %StageResult{name: "eng", status: :error, result: "compilation failed", elapsed_ms: 0}
        ]
      }

      assert Outcome.classify(result) == :blocked
    end

    test "empty error stages classifies as blocked" do
      result = %Result{status: :error, stages: []}
      assert Outcome.classify(result) == :blocked
    end
  end
end
