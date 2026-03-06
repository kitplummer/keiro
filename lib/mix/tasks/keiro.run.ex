defmodule Mix.Tasks.Keiro.Run do
  @moduledoc """
  Run the Keiro orchestrator against the current repository.

  ## Usage

      # Process one bead and exit
      mix keiro.run

      # Process all ready beads
      mix keiro.run --all

      # Run as polling loop
      mix keiro.run --loop --interval 30000

      # Target a different repo
      mix keiro.run --repo /path/to/repo

  ## Options

  - `--all` — process all ready beads instead of just the next one
  - `--loop` — run as a polling loop instead of one-shot
  - `--interval` — poll interval in ms (default: 30000, requires --loop)
  - `--repo` — path to beads-enabled repo (default: current directory)
  - `--timeout` — per-agent timeout in ms (default: 120000)
  """
  use Mix.Task

  alias Keiro.Orchestrator

  @shortdoc "Run the Keiro orchestrator"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          all: :boolean,
          loop: :boolean,
          interval: :integer,
          repo: :string,
          timeout: :integer
        ]
      )

    # Ensure application is started
    Mix.Task.run("app.start")

    repo_path = Keyword.get(opts, :repo, File.cwd!())
    timeout = Keyword.get(opts, :timeout, 120_000)

    cond do
      Keyword.get(opts, :loop, false) ->
        run_loop(repo_path, timeout, opts)

      Keyword.get(opts, :all, false) ->
        run_all(repo_path, timeout)

      true ->
        run_next(repo_path, timeout)
    end
  end

  defp run_next(repo_path, timeout) do
    case Orchestrator.run_next(repo_path: repo_path, timeout: timeout) do
      {:ok, result} ->
        Mix.shell().info("Completed: #{inspect(result)}")

      :no_work ->
        Mix.shell().info("No ready beads.")

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
    end
  end

  defp run_all(repo_path, timeout) do
    results = Orchestrator.run_all(repo_path: repo_path, timeout: timeout)

    Enum.each(results, fn %{bead_id: id, title: title, result: result} ->
      status = if match?({:ok, _}, result), do: "ok", else: "error"
      Mix.shell().info("[#{status}] #{id}: #{title}")
    end)

    Mix.shell().info("Processed #{length(results)} bead(s).")
  end

  defp run_loop(repo_path, timeout, opts) do
    interval = Keyword.get(opts, :interval, 30_000)

    Mix.shell().info("Starting orchestrator loop (interval: #{interval}ms)...")

    {:ok, pid} =
      Orchestrator.start_link(
        repo_path: repo_path,
        poll_interval: interval,
        timeout: timeout,
        on_result: fn {:ok, result} ->
          Mix.shell().info("Completed: #{inspect(result)}")
        end
      )

    # Block until interrupted
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        Mix.shell().info("Orchestrator stopped: #{inspect(reason)}")
    end
  end
end
