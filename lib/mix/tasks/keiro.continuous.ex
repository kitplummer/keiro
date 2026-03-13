defmodule Mix.Tasks.Keiro.Continuous do
  @moduledoc """
  Run the Keiro orchestrator in continuous mode with budget pacing.

  Wraps the orchestrator + health monitor with budget enforcement and a
  watchdog that creates investigation beads on stall.

  ## Usage

      # Run for 8 hours with $50 budget
      mix keiro.continuous --budget 50 --repo /path/to/lei

      # Custom hours and poll interval
      mix keiro.continuous --budget 25 --hours 4 --repo /path/to/lei --poll-interval 60000

      # With health monitoring config
      mix keiro.continuous --budget 50 --repo /path/to/lei \\
        --health-url https://lowendinsight.fly.dev \\
        --fly-app lowendinsight

  ## Options

  - `--budget` — total dollars for the run (required)
  - `--hours` — total hours for the run (default: 8.0)
  - `--repo-path` — path to beads-enabled repo (required)
  - `--poll-interval` — orchestrator poll interval in ms (default: 30_000)
  - `--health-url` — URL for health checks (default: from :keiro :lei config)
  - `--fly-app` — Fly app name (default: from :keiro :lei config)
  - `--cost-per-task` — estimated cost per task in dollars (default: 0.10)
  """
  use Mix.Task

  @shortdoc "Run the Keiro orchestrator in continuous mode with budget pacing"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          budget: :float,
          hours: :float,
          repo_path: :string,
          poll_interval: :integer,
          health_url: :string,
          fly_app: :string,
          cost_per_task: :float
        ]
      )

    budget = Keyword.get(opts, :budget) || Mix.raise("--budget is required")
    repo_path = Keyword.get(opts, :repo_path) || Mix.raise("--repo-path is required")
    hours = Keyword.get(opts, :hours, 8.0)
    poll_interval = Keyword.get(opts, :poll_interval, 30_000)
    cost_per_task = Keyword.get(opts, :cost_per_task, 0.10)

    # Ensure application is started
    Mix.Task.run("app.start")

    lei_config = Application.get_env(:keiro, :lei, [])

    health_url =
      Keyword.get(opts, :health_url) ||
        Keyword.get(lei_config, :smoke_test_url, "https://lowendinsight.fly.dev")

    fly_app =
      Keyword.get(opts, :fly_app) ||
        Keyword.get(lei_config, :fly_app, "lowendinsight")

    Mix.shell().info(
      "Starting continuous mode: budget=$#{budget}, hours=#{hours}, " <>
        "repo=#{repo_path}, poll=#{poll_interval}ms"
    )

    continuous_opts = [
      budget_total: budget,
      hours: hours,
      repo_path: repo_path,
      poll_interval: poll_interval,
      health_url: health_url,
      fly_app: fly_app,
      cost_per_task: cost_per_task
    ]

    case Keiro.Continuous.start_link(continuous_opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            Mix.shell().info("Continuous mode stopped: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("Failed to start continuous mode: #{inspect(reason)}")
    end
  end
end
