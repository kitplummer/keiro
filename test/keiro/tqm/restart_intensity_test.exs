defmodule Keiro.TQM.RestartIntensityTest do
  use ExUnit.Case, async: true

  alias Keiro.TQM.RestartIntensity

  describe "new/1" do
    test "creates with defaults" do
      tracker = RestartIntensity.new()
      assert tracker.max_failures == 5
      assert tracker.window_ms == 300_000
      assert tracker.failures == []
    end

    test "accepts overrides" do
      tracker = RestartIntensity.new(max_failures: 3, window_ms: 10_000)
      assert tracker.max_failures == 3
      assert tracker.window_ms == 10_000
    end
  end

  describe "record_failure/1" do
    test "returns :ok when within limits" do
      tracker = RestartIntensity.new(max_failures: 3)
      {action, tracker} = RestartIntensity.record_failure(tracker)
      assert action == :ok
      assert RestartIntensity.failure_count(tracker) == 1
    end

    test "returns :halt when exceeding max_failures" do
      tracker = RestartIntensity.new(max_failures: 2)

      {action, tracker} = RestartIntensity.record_failure(tracker)
      assert action == :ok

      {action, tracker} = RestartIntensity.record_failure(tracker)
      assert action == :ok

      {action, _tracker} = RestartIntensity.record_failure(tracker)
      assert action == :halt
    end

    test "failures outside window are pruned" do
      # Use a tiny window so failures expire immediately
      tracker = RestartIntensity.new(max_failures: 2, window_ms: 0)

      {_action, tracker} = RestartIntensity.record_failure(tracker)
      {_action, tracker} = RestartIntensity.record_failure(tracker)

      # All past failures are outside the 0ms window
      # New failure should be the only one counted
      Process.sleep(1)
      {action, _tracker} = RestartIntensity.record_failure(tracker)
      assert action == :ok
    end
  end

  describe "record_success/1" do
    test "prunes old failures" do
      tracker = RestartIntensity.new(window_ms: 0)
      {_, tracker} = RestartIntensity.record_failure(tracker)
      Process.sleep(1)
      tracker = RestartIntensity.record_success(tracker)
      assert RestartIntensity.failure_count(tracker) == 0
    end
  end

  describe "failure_count/1" do
    test "returns 0 for fresh tracker" do
      assert RestartIntensity.failure_count(RestartIntensity.new()) == 0
    end

    test "counts failures within window" do
      tracker = RestartIntensity.new()
      {_, tracker} = RestartIntensity.record_failure(tracker)
      {_, tracker} = RestartIntensity.record_failure(tracker)
      assert RestartIntensity.failure_count(tracker) == 2
    end
  end
end
