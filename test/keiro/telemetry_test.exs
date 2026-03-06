defmodule Keiro.TelemetryTest do
  use ExUnit.Case, async: true

  alias Keiro.Telemetry

  describe "span_start/2" do
    test "emits event with system_time and returns monotonic start" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-start-#{inspect(ref)}",
        [:test, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      start = Telemetry.span_start([:test, :start], %{foo: "bar"})

      assert is_integer(start)
      assert_received {:telemetry, [:test, :start], %{system_time: sys_time}, %{foo: "bar"}}
      assert is_integer(sys_time)

      :telemetry.detach("test-start-#{inspect(ref)}")
    end
  end

  describe "span_stop/3" do
    test "emits event with duration" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-stop-#{inspect(ref)}",
        [:test, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      start = System.monotonic_time()
      Telemetry.span_stop([:test, :stop], start, %{status: :ok})

      assert_received {:telemetry, [:test, :stop], %{duration: duration}, %{status: :ok}}
      assert is_integer(duration)
      assert duration >= 0

      :telemetry.detach("test-stop-#{inspect(ref)}")
    end
  end
end
