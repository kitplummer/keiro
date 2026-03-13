defmodule Keiro.Ops.HealthMonitor do
  @moduledoc """
  Periodic health monitor for deployed services.

  Runs independently of the orchestrator's bead dispatch loop. Checks service
  health at a configurable interval and creates investigation beads when
  consecutive failures exceed the threshold.

  ## Usage

      {:ok, pid} = Keiro.Ops.HealthMonitor.start_link(
        repo_path: "/path/to/lei",
        health_url: "https://lowendinsight.fly.dev",
        fly_app: "lowendinsight"
      )

  ## Options

  - `:repo_path` — path to beads-enabled repo (required)
  - `:health_url` — URL to GET for health check (required)
  - `:fly_app` — Fly app name for `fly status` check (required)
  - `:check_interval` — ms between checks (default: 300_000 / 5 min)
  - `:max_consecutive_failures` — failures before creating investigation bead (default: 3)
  - `:enabled` — whether monitoring is active (default: true)
  - `:http_check_fn` — override HTTP check function for testing (default: internal :httpc call)
  - `:fly_check_fn` — override fly status check function for testing (default: internal fly CLI call)
  - `:bead_create_fn` — override bead creation function for testing (default: BeadsClient.create)
  """
  use GenServer
  require Logger

  alias Keiro.Beads.Client, as: BeadsClient

  @default_interval 300_000
  @default_max_failures 3
  @http_timeout 20_000

  @doc "Start the health monitor as a linked GenServer."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Check whether monitoring is currently enabled."
  @spec enabled?(GenServer.server()) :: boolean()
  def enabled?(pid \\ __MODULE__), do: GenServer.call(pid, :enabled?)

  @doc "Get the current health status."
  @spec status(GenServer.server()) :: map()
  def status(pid \\ __MODULE__), do: GenServer.call(pid, :status)

  # -- GenServer callbacks --

  @impl GenServer
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)

    state = %{
      repo_path: Keyword.fetch!(opts, :repo_path),
      health_url: Keyword.fetch!(opts, :health_url),
      fly_app: Keyword.fetch!(opts, :fly_app),
      check_interval: Keyword.get(opts, :check_interval, @default_interval),
      max_consecutive_failures:
        Keyword.get(opts, :max_consecutive_failures, @default_max_failures),
      enabled: enabled,
      consecutive_failures: 0,
      last_check_at: nil,
      last_status: :unknown,
      investigation_created: false,
      http_check_fn: Keyword.get(opts, :http_check_fn, &default_http_check/1),
      fly_check_fn: Keyword.get(opts, :fly_check_fn, &default_fly_check/1),
      bead_create_fn: Keyword.get(opts, :bead_create_fn, &default_bead_create/3)
    }

    if enabled, do: schedule_check(state.check_interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:check, %{enabled: false} = state), do: {:noreply, state}

  def handle_info(:check, state) do
    state = run_check(state)
    schedule_check(state.check_interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:enabled?, _from, state), do: {:reply, state.enabled, state}

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       status: state.last_status,
       consecutive_failures: state.consecutive_failures,
       last_check_at: state.last_check_at,
       investigation_created: state.investigation_created
     }, state}
  end

  # -- Private --

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp run_check(state) do
    now = System.system_time(:millisecond)
    http_result = state.http_check_fn.(state.health_url)
    fly_result = state.fly_check_fn.(state.fly_app)

    case {http_result, fly_result} do
      {:ok, :ok} ->
        if state.consecutive_failures > 0 do
          Logger.info(
            "HealthMonitor: #{state.fly_app} recovered after #{state.consecutive_failures} failures"
          )
        else
          Logger.debug("HealthMonitor: #{state.fly_app} healthy")
        end

        %{
          state
          | consecutive_failures: 0,
            last_check_at: now,
            last_status: :healthy,
            investigation_created: false
        }

      _ ->
        failures = state.consecutive_failures + 1

        Logger.warning(
          "HealthMonitor: #{state.fly_app} check failed " <>
            "(#{failures}/#{state.max_consecutive_failures}), " <>
            "http=#{inspect(http_result)}, fly=#{inspect(fly_result)}"
        )

        state = %{
          state
          | consecutive_failures: failures,
            last_check_at: now,
            last_status: :unhealthy
        }

        if failures >= state.max_consecutive_failures and not state.investigation_created do
          create_investigation(state, http_result, fly_result)
          %{state | investigation_created: true}
        else
          state
        end
    end
  end

  defp create_investigation(state, http_result, fly_result) do
    title =
      String.slice(
        "Health alert: #{state.fly_app} unhealthy " <>
          "(#{state.consecutive_failures} consecutive failures)",
        0,
        200
      )

    description = """
    HealthMonitor detected #{state.consecutive_failures} consecutive health check failures \
    for #{state.fly_app}.

    HTTP check (#{state.health_url}): #{format_check_result(http_result)}
    Fly status: #{format_check_result(fly_result)}

    Investigate:
    1. Check fly logs: `fly logs --app #{state.fly_app}`
    2. Check fly status: `fly status --app #{state.fly_app}`
    3. Check if recent deploy caused regression
    4. Restart if needed: `fly apps restart #{state.fly_app}`
    """

    case state.bead_create_fn.(state.repo_path, title,
           type: "task",
           priority: 0,
           labels: ["ops"],
           description: description
         ) do
      {:ok, id} ->
        Logger.warning("HealthMonitor: created investigation bead #{id} for #{state.fly_app}")

      {:error, reason} ->
        Logger.error("HealthMonitor: failed to create investigation bead: #{reason}")
    end
  end

  defp format_check_result(:ok), do: "OK"
  defp format_check_result({:error, reason}), do: "FAILED - #{reason}"

  # -- Default check implementations --

  defp default_http_check(url) do
    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [timeout: @http_timeout, connect_timeout: @http_timeout],
           []
         ) do
      {:ok, {{_, status, _}, _headers, _body}} when status in 200..299 -> :ok
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp default_fly_check(app_name) do
    fly_bin = Application.get_env(:keiro, :fly_bin_path, "fly")

    case System.cmd(fly_bin, ["status", "--app", app_name], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "running") or String.contains?(output, "deployed") do
          :ok
        else
          {:error, "fly status: not running"}
        end

      {output, _code} ->
        {:error, "fly status failed: #{String.slice(output, 0, 200)}"}
    end
  rescue
    e -> {:error, "fly status error: #{Exception.message(e)}"}
  end

  defp default_bead_create(repo_path, title, opts) do
    client = BeadsClient.new(repo_path)
    BeadsClient.create(client, title, opts)
  end
end
