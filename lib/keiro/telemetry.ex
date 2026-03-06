defmodule Keiro.Telemetry do
  @moduledoc """
  Telemetry event definitions and helpers for Keiro.

  Emits `:telemetry` events for orchestrator dispatch, pipeline stages,
  and bead state transitions. Consumers attach handlers via
  `:telemetry.attach/4` or `:telemetry.attach_many/4`.

  ## Event Reference

  ### Orchestrator

  - `[:keiro, :orchestrator, :dispatch, :start]` — agent/pipeline dispatch begins
  - `[:keiro, :orchestrator, :dispatch, :stop]` — dispatch completed
  - `[:keiro, :orchestrator, :dispatch, :exception]` — dispatch raised/exited

  Metadata: `%{bead_id, agent, kind}` where kind is `:agent` or `:pipeline`.

  ### Pipeline

  - `[:keiro, :pipeline, :run, :start]` — pipeline begins
  - `[:keiro, :pipeline, :run, :stop]` — pipeline completed
  - `[:keiro, :pipeline, :run, :exception]` — pipeline raised

  Metadata: `%{bead_id, stage_count}` (start), adds `%{status}` (stop).

  - `[:keiro, :pipeline, :stage, :start]` — individual stage begins
  - `[:keiro, :pipeline, :stage, :stop]` — stage completed
  - `[:keiro, :pipeline, :stage, :exception]` — stage raised

  Metadata: `%{bead_id, stage, agent}`.

  ### Beads

  - `[:keiro, :beads, :create, :start]` / `[:keiro, :beads, :create, :stop]`
  - `[:keiro, :beads, :update_status, :start]` / `[:keiro, :beads, :update_status, :stop]`
  - `[:keiro, :beads, :close, :start]` / `[:keiro, :beads, :close, :stop]`

  Metadata: `%{bead_id, status}` (for update_status), `%{title}` (for create).
  """

  @doc "All telemetry events emitted by Keiro."
  @spec events() :: [list(atom())]
  def events do
    [
      # Orchestrator
      [:keiro, :orchestrator, :dispatch, :start],
      [:keiro, :orchestrator, :dispatch, :stop],
      [:keiro, :orchestrator, :dispatch, :exception],
      # Pipeline
      [:keiro, :pipeline, :run, :start],
      [:keiro, :pipeline, :run, :stop],
      [:keiro, :pipeline, :run, :exception],
      [:keiro, :pipeline, :stage, :start],
      [:keiro, :pipeline, :stage, :stop],
      [:keiro, :pipeline, :stage, :exception],
      # Beads
      [:keiro, :beads, :create, :start],
      [:keiro, :beads, :create, :stop],
      [:keiro, :beads, :update_status, :start],
      [:keiro, :beads, :update_status, :stop],
      [:keiro, :beads, :close, :start],
      [:keiro, :beads, :close, :stop]
    ]
  end

  @doc """
  Execute a function within a telemetry span.

  Emits `event_prefix ++ [:start]` before and `event_prefix ++ [:stop]`
  or `event_prefix ++ [:exception]` after the function executes.

  Returns the function's return value.
  """
  @spec span(list(atom()), map(), (-> term())) :: term()
  def span(event_prefix, metadata, fun) when is_list(event_prefix) and is_function(fun, 0) do
    :telemetry.span(event_prefix, metadata, fn ->
      result = fun.()
      {result, metadata}
    end)
  end
end
