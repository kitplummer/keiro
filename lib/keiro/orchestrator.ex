defmodule Keiro.Orchestrator do
  @moduledoc """
  Task router and polling loop for Keiro.

  Pulls ready beads from the task graph and routes them to the appropriate
  pipeline shape based on labels. Can run as a one-shot or as a GenServer
  that polls on an interval.

  ## One-shot usage

      {:ok, result} = Keiro.Orchestrator.run_next(repo_path: "/path/to/lei")
      results = Keiro.Orchestrator.run_all(repo_path: "/path/to/lei")

  ## Polling loop

      {:ok, pid} = Keiro.Orchestrator.start_link(
        repo_path: "/path/to/lei",
        poll_interval: 30_000
      )
  """

  use GenServer

  alias Keiro.Beads.Client, as: BeadsClient
  alias Keiro.Pipeline

  require Logger

  @default_shapes [
    Keiro.Eng.Shape,
    Keiro.Ops.Shape
  ]

  # -- GenServer API --

  @doc """
  Start the orchestrator polling loop.

  Options:
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:poll_interval` — ms between polls (default: 30_000)
  - `:timeout` — per-agent timeout in ms (default: 120_000)
  - `:on_result` — callback fn receiving `%{bead_id, title, result}` (optional)
  - `:shapes` — list of shape modules (default: eng + ops)
  - `:runner_fn` — injectable stage runner for testing (optional)
  - `:approve_fn` — governance approval function (optional)
  """
  def start_link(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)

    GenServer.start_link(__MODULE__, opts,
      name: Keyword.get(opts, :name, {:global, {__MODULE__, repo_path}})
    )
  end

  @doc "Trigger an immediate poll outside the normal interval."
  def poll(pid), do: GenServer.cast(pid, :poll)

  @doc "Stop the orchestrator loop."
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl GenServer
  def init(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    poll_interval = Keyword.get(opts, :poll_interval, 30_000)
    timeout = Keyword.get(opts, :timeout, 120_000)
    on_result = Keyword.get(opts, :on_result)
    shapes = Keyword.get(opts, :shapes, @default_shapes)
    runner_fn = Keyword.get(opts, :runner_fn)
    approve_fn = Keyword.get(opts, :approve_fn)

    state = %{
      repo_path: repo_path,
      poll_interval: poll_interval,
      timeout: timeout,
      on_result: on_result,
      shapes: shapes,
      runner_fn: runner_fn,
      approve_fn: approve_fn,
      running: false
    }

    schedule_poll(poll_interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:poll, %{running: true} = state) do
    Logger.debug("Orchestrator: skipping poll, already processing")
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    state = do_poll(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:poll, %{running: true} = state), do: {:noreply, state}
  def handle_cast(:poll, state), do: {:noreply, do_poll(state)}

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp do_poll(state) do
    state = %{state | running: true}

    result =
      run_next(
        repo_path: state.repo_path,
        timeout: state.timeout,
        shapes: state.shapes,
        runner_fn: state.runner_fn,
        approve_fn: state.approve_fn
      )

    case result do
      {:ok, _result} = ok ->
        if state.on_result, do: state.on_result.(ok)
        %{state | running: false}

      :no_work ->
        Logger.debug("Orchestrator: no ready beads")
        %{state | running: false}

      {:error, reason} ->
        Logger.warning("Orchestrator poll error: #{inspect(reason)}")
        %{state | running: false}
    end
  end

  @doc """
  Pull the next ready bead and route it to the appropriate pipeline shape.

  Options:
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:timeout` — agent timeout in ms (default: 60_000)
  - `:shapes` — list of shape modules (default: eng + ops)
  - `:runner_fn` — injectable stage runner for testing (optional)
  - `:approve_fn` — governance approval function (optional)
  """
  @spec run_next(keyword()) :: {:ok, map()} | {:error, String.t()} | :no_work
  def run_next(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    timeout = Keyword.get(opts, :timeout, 60_000)
    shapes = Keyword.get(opts, :shapes, @default_shapes)
    runner_fn = Keyword.get(opts, :runner_fn)
    approve_fn = Keyword.get(opts, :approve_fn)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, []} ->
        :no_work

      {:ok, [bead | _]} ->
        Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
        BeadsClient.update_status(client, bead.id, "in_progress")

        dispatch(bead, timeout,
          repo_path: repo_path,
          shapes: shapes,
          runner_fn: runner_fn,
          approve_fn: approve_fn
        )

      {:error, reason} ->
        {:error, "Failed to fetch ready beads: #{reason}"}
    end
  end

  @doc """
  Process all ready beads sequentially.
  """
  @spec run_all(keyword()) :: [map()]
  def run_all(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    timeout = Keyword.get(opts, :timeout, 60_000)
    shapes = Keyword.get(opts, :shapes, @default_shapes)
    runner_fn = Keyword.get(opts, :runner_fn)
    approve_fn = Keyword.get(opts, :approve_fn)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, beads} ->
        Enum.map(beads, fn bead ->
          Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
          BeadsClient.update_status(client, bead.id, "in_progress")

          result =
            dispatch(bead, timeout,
              repo_path: repo_path,
              shapes: shapes,
              runner_fn: runner_fn,
              approve_fn: approve_fn
            )

          %{bead_id: bead.id, title: bead.title, result: result}
        end)

      {:error, reason} ->
        Logger.error("Orchestrator: failed to fetch beads: #{reason}")
        []
    end
  end

  @doc """
  Route a bead to the appropriate agent or pipeline based on labels.

  - "eng" beads route to the engineer pipeline (engineer → verify)
  - "ops" beads route directly to UplinkAgent
  """
  @spec route(Keiro.Beads.Bead.t()) ::
          {:ok, :engineer_pipeline} | {:ok, module()} | {:error, :no_matching_agent}
  def route(bead) do
    labels = bead.labels || []

    cond do
      "eng" in labels -> {:ok, :engineer_pipeline}
      "ops" in labels -> {:ok, Keiro.Ops.UplinkAgent}
      true -> {:error, :no_matching_agent}
    end
  end

  @doc """
  Resolve the pipeline shape for a bead.

  Iterates through the shape list in priority order and returns the first
  matching shape module. Returns `{:error, :no_matching_shape}` if none match.
  """
  @spec resolve_shape(Keiro.Beads.Bead.t(), [module()]) ::
          {:ok, module()} | {:error, :no_matching_shape}
  def resolve_shape(bead, shapes \\ @default_shapes) do
    case Enum.find(shapes, fn shape -> shape.match?(bead) end) do
      nil -> {:error, :no_matching_shape}
      shape -> {:ok, shape}
    end
  end

  # -- private --

  defp dispatch(bead, timeout, opts) do
    repo_path = Keyword.get(opts, :repo_path)
    shapes = Keyword.get(opts, :shapes, @default_shapes)
    runner_fn = Keyword.get(opts, :runner_fn)
    tool_context = build_tool_context(opts)

    case resolve_shape(bead, shapes) do
      {:ok, shape} ->
        stages = shape.stages(bead, timeout: timeout)
        client = if repo_path, do: BeadsClient.new(repo_path), else: nil

        pipeline_opts =
          [tool_context: tool_context]
          |> then(fn o -> if runner_fn, do: Keyword.put(o, :runner_fn, runner_fn), else: o end)

        case Pipeline.run(bead, stages, pipeline_opts) do
          {:ok, result} ->
            Logger.info("Pipeline completed for bead #{bead.id}")
            if client, do: BeadsClient.close(client, bead.id)
            {:ok, result}

          {:error, result} ->
            Logger.warning("Pipeline failed at stage #{result.error_stage} for bead #{bead.id}")

            if client, do: BeadsClient.update_status(client, bead.id, "blocked")
            {:error, result}
        end

      {:error, :no_matching_shape} ->
        Logger.warning(
          "Orchestrator: no shape for bead #{bead.id} (labels: #{inspect(bead.labels)})"
        )

        {:error, "no matching shape for labels: #{inspect(bead.labels)}"}
    end
  end

  defp build_tool_context(opts) do
    context = %{}

    context =
      if opts[:repo_path], do: Map.put(context, :repo_path, opts[:repo_path]), else: context

    if opts[:approve_fn],
      do: Map.put(context, :approve_fn, opts[:approve_fn]),
      else: context
  end
end
