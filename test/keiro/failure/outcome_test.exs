defmodule Keiro.Failure.OutcomeTest do
  use ExUnit.Case, async: true

  alias Keiro.Failure.Outcome
  alias Keiro.Pipeline.Result

  describe "values/0" do
    test "returns all outcomes" do
      values = Outcome.values()
      assert :completed in values
      assert :deferred in values
      assert :decomposed in values
      assert :blocked in values
      assert :retryable in values
      assert :escalated in values
      assert length(values) == 6
    end
  end

  describe "valid?/1" do
    test "accepts valid outcomes" do
      for outcome <- Outcome.values() do
        assert Outcome.valid?(outcome)
      end
    end

    test "rejects invalid values" do
      refute Outcome.valid?(:failed)
      refute Outcome.valid?("completed")
      refute Outcome.valid?(nil)
    end
  end

  describe "classify/1" do
    test "ok result is completed" do
      assert Outcome.classify({:ok, %Result{status: :ok}}) == :completed
    end

    test "error with pipeline result is retryable" do
      result = %Result{status: :error, error_stage: "engineer"}
      assert Outcome.classify({:error, result}) == :retryable
    end

    test "error string with 'no matching' is escalated" do
      assert Outcome.classify({:error, "no matching agent for labels"}) == :escalated
    end

    test "error string with 'budget' is escalated" do
      assert Outcome.classify({:error, "budget exceeded"}) == :escalated
    end

    test "generic error string is retryable" do
      assert Outcome.classify({:error, "something went wrong"}) == :retryable
    end

    test "unexpected input is escalated" do
      assert Outcome.classify(:weird) == :escalated
    end
  end
end
