defmodule Mix.Tasks.Keiro.Run do
  @moduledoc """
  Run the Keiro orchestrator against the current repository.

  ## Usage

      # Process one bead and exit
      mix keiro.run

      # Process all ready beads with auto-approval
      mix keiro.run --all --auto-approve

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
  - `--auto-approve` — auto-approve all governance gates (no interactive prompts)
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
          timeout: :integer,
          auto_approve: :boolean
        ]
      )

    # Ensure application is started
    Mix.Task.run("app.start")

    repo_path = Keyword.get(opts, :repo, File.cwd!())
    timeout = Keyword.get(opts, :timeout, 120_000)
    approve_fn = if Keyword.get(opts, :auto_approve, false), do: fn _desc -> :approved end

    cond do
      Keyword.get(opts, :loop, false) ->
        run_loop(repo_path, timeout, approve_fn, opts)

      Keyword.get(opts, :all, false) ->
        run_all(repo_path, timeout, approve_fn)

      true ->
        run_next(repo_path, timeout, approve_fn)
    end
  end

  defp run_next(repo_path, timeout, approve_fn) do
    run_opts =
      [repo_path: repo_path, timeout: timeout]
      |> maybe_add(:approve_fn, approve_fn)

    case Orchestrator.run_next(run_opts) do
      {:ok, result} ->
        Mix.shell().info("Completed: #{inspect(result)}")

      :no_work ->
        Mix.shell().info("No ready beads.")

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
    end
  end

  defp run_all(repo_path, timeout, approve_fn) do
    run_opts =
      [repo_path: repo_path, timeout: timeout]
      |> maybe_add(:approve_fn, approve_fn)

    results = Orchestrator.run_all(run_opts)

    Enum.each(results, fn %{bead_id: id, title: title, result: result} ->
      status = if match?({:ok, _}, result), do: "ok", else: "error"
      Mix.shell().info("[#{status}] #{id}: #{title}")
    end)

    Mix.shell().info("Processed #{length(results)} bead(s).")
  end

  defp run_loop(repo_path, timeout, approve_fn, opts) do
    interval = Keyword.get(opts, :interval, 30_000)

    Mix.shell().info("Starting orchestrator loop (interval: #{interval}ms)...")

    loop_opts =
      [
        repo_path: repo_path,
        poll_interval: interval,
        timeout: timeout,
        on_result: fn {:ok, result} ->
          Mix.shell().info("Completed: #{inspect(result)}")
        end
      ]
      |> maybe_add(:approve_fn, approve_fn)

    {:ok, pid} = Orchestrator.start_link(loop_opts)

    # Block until interrupted
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        Mix.shell().info("Orchestrator stopped: #{inspect(reason)}")
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
