defmodule Keiro.PipelineTelemetryTest do
  @moduledoc "Tests that Pipeline emits correct telemetry events."
  use ExUnit.Case, async: true

  alias Keiro.Pipeline
  alias Keiro.Pipeline.Stage
  alias Keiro.Beads.Bead

  setup do
    test_pid = self()
    ref = make_ref()

    events = [
      [:keiro, :pipeline, :start],
      [:keiro, :pipeline, :stop],
      [:keiro, :pipeline, :exception],
      [:keiro, :pipeline, :stage, :start],
      [:keiro, :pipeline, :stage, :stop]
    ]

    handler_id = "pipeline-telemetry-test-#{inspect(ref)}"

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    %{bead: %Bead{id: "gl-t01", title: "Telemetry test bead"}}
  end

  describe "successful pipeline" do
    test "emits pipeline start/stop and stage start/stop", %{bead: bead} do
      assert {:ok, _} = Pipeline.run(bead, [])

      assert_received {:telemetry, [:keiro, :pipeline, :start], %{system_time: _},
                       %{bead_id: "gl-t01", stage_count: 0}}

      assert_received {:telemetry, [:keiro, :pipeline, :stop], %{duration: d},
                       %{bead_id: "gl-t01", status: :ok}}

      assert is_integer(d)
    end
  end

  describe "failed pipeline" do
    test "emits pipeline start/exception and stage events", %{bead: bead} do
      stages = [
        %Stage{
          name: "bad_stage",
          agent_module: NonExistentAgentModule,
          prompt_fn: fn _b, _p -> "prompt" end,
          timeout: 1_000
        }
      ]

      assert {:error, _} = Pipeline.run(bead, stages)

      assert_received {:telemetry, [:keiro, :pipeline, :start], %{system_time: _},
                       %{bead_id: "gl-t01", stage_count: 1}}

      assert_received {:telemetry, [:keiro, :pipeline, :stage, :start], %{system_time: _},
                       %{
                         bead_id: "gl-t01",
                         stage_name: "bad_stage",
                         agent_module: NonExistentAgentModule
                       }}

      assert_received {:telemetry, [:keiro, :pipeline, :stage, :stop], %{duration: _},
                       %{bead_id: "gl-t01", stage_name: "bad_stage", status: :error}}

      assert_received {:telemetry, [:keiro, :pipeline, :exception], %{duration: _},
                       %{bead_id: "gl-t01", status: :error, error_stage: "bad_stage"}}
    end
  end
end
