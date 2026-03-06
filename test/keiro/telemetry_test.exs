defmodule Keiro.TelemetryTest do
  use ExUnit.Case, async: true

  alias Keiro.Telemetry

  describe "events/0" do
    test "returns all event names as lists of atoms" do
      events = Telemetry.events()
      assert is_list(events)
      assert length(events) > 0

      Enum.each(events, fn event ->
        assert is_list(event)
        assert Enum.all?(event, &is_atom/1)
      end)
    end

    test "includes orchestrator dispatch events" do
      events = Telemetry.events()
      assert [:keiro, :orchestrator, :dispatch, :start] in events
      assert [:keiro, :orchestrator, :dispatch, :stop] in events
      assert [:keiro, :orchestrator, :dispatch, :exception] in events
    end

    test "includes pipeline events" do
      events = Telemetry.events()
      assert [:keiro, :pipeline, :run, :start] in events
      assert [:keiro, :pipeline, :run, :stop] in events
      assert [:keiro, :pipeline, :stage, :start] in events
      assert [:keiro, :pipeline, :stage, :stop] in events
    end

    test "includes beads events" do
      events = Telemetry.events()
      assert [:keiro, :beads, :create, :start] in events
      assert [:keiro, :beads, :create, :stop] in events
      assert [:keiro, :beads, :update_status, :start] in events
      assert [:keiro, :beads, :update_status, :stop] in events
      assert [:keiro, :beads, :close, :start] in events
      assert [:keiro, :beads, :close, :stop] in events
    end
  end

  describe "span/3" do
    test "emits start and stop events" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach_many(
        "test-span-#{inspect(ref)}",
        [
          [:test, :op, :start],
          [:test, :op, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      result = Telemetry.span([:test, :op], %{key: "val"}, fn -> {:ok, 42} end)

      assert result == {:ok, 42}

      assert_receive {:telemetry, [:test, :op, :start], start_measurements, %{key: "val"}}
      assert is_integer(start_measurements.system_time)

      assert_receive {:telemetry, [:test, :op, :stop], stop_measurements, %{key: "val"}}
      assert is_integer(stop_measurements.duration)

      :telemetry.detach("test-span-#{inspect(ref)}")
    end

    test "emits exception event on raise" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach_many(
        "test-exc-#{inspect(ref)}",
        [
          [:test, :exc, :start],
          [:test, :exc, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert_raise RuntimeError, fn ->
        Telemetry.span([:test, :exc], %{key: "val"}, fn -> raise "boom" end)
      end

      assert_receive {:telemetry, [:test, :exc, :start], _, %{key: "val"}}

      assert_receive {:telemetry, [:test, :exc, :exception], _, metadata}
      assert metadata.kind == :error
      assert %RuntimeError{message: "boom"} = metadata.reason

      :telemetry.detach("test-exc-#{inspect(ref)}")
    end

    test "passes through return value" do
      result = Telemetry.span([:test, :passthrough], %{}, fn -> "hello" end)
      assert result == "hello"
    end
  end
end
