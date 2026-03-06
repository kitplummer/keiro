defmodule Keiro.Telemetry do
  @moduledoc """
  Telemetry events emitted by Keiro.

  All events use the `[:keiro, ...]` prefix. Consumers attach handlers
  via `:telemetry.attach/4` or `:telemetry.attach_many/4`.

  ## Pipeline events

  * `[:keiro, :pipeline, :start]` — Pipeline begins for a bead.
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{bead_id, stage_count}`

  * `[:keiro, :pipeline, :stop]` — Pipeline completes (success).
    - Measurements: `%{duration: native_time}`
    - Metadata: `%{bead_id, stage_count, status: :ok}`

  * `[:keiro, :pipeline, :exception]` — Pipeline fails.
    - Measurements: `%{duration: native_time}`
    - Metadata: `%{bead_id, error_stage, status: :error}`

  ## Stage events

  * `[:keiro, :pipeline, :stage, :start]` — Stage begins.
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{bead_id, stage_name, agent_module}`

  * `[:keiro, :pipeline, :stage, :stop]` — Stage completes.
    - Measurements: `%{duration: native_time}`
    - Metadata: `%{bead_id, stage_name, agent_module, status: :ok | :error}`

  ## Orchestrator events

  * `[:keiro, :orchestrator, :dispatch]` — Bead dispatched to a pipeline.
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{bead_id, labels}`

  * `[:keiro, :orchestrator, :complete]` — Bead processing complete.
    - Measurements: `%{duration: native_time}`
    - Metadata: `%{bead_id, status: :ok | :error | :no_match}`
  """

  @doc "Emit a start event and return the start time for span calculation."
  @spec span_start(list(), map()) :: integer()
  def span_start(event, metadata) do
    start_time = System.monotonic_time()
    :telemetry.execute(event, %{system_time: System.system_time()}, metadata)
    start_time
  end

  @doc "Emit a stop event with duration calculated from start_time."
  @spec span_stop(list(), integer(), map()) :: :ok
  def span_stop(event, start_time, metadata) do
    duration = System.monotonic_time() - start_time
    :telemetry.execute(event, %{duration: duration}, metadata)
  end
end
