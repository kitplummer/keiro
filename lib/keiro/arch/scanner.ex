defmodule Keiro.Arch.Scanner do
  @moduledoc """
  One-shot entry point for the Architect agent.

  Starts an ArchitectAgent, sends a scan prompt, and returns the result.
  Designed for manual use from `iex` or mix tasks.

  ## Usage

      {:ok, result} = Keiro.Arch.Scanner.scan("/path/to/repo")
      {:ok, result} = Keiro.Arch.Scanner.scan("/path/to/repo", timeout: 300_000)
  """

  alias Keiro.Arch.ArchitectAgent

  @default_timeout 180_000

  @scan_prompt """
  Scan this repository and perform all four architect responsibilities:

  1. List open GitHub issues and triage them — detect spam/DoS patterns, create beads for legitimate issues
  2. Review the beads backlog for staleness, blocked items, and priority inversions
  3. List and read ADR files, identify implementation gaps
  4. Create beads for any missing work discovered

  Report a summary of all findings and actions taken.
  """

  @doc """
  Run a full architect scan on the given repo.

  Options:
  - `:timeout` — agent timeout in ms (default: #{@default_timeout})
  - `:approve_fn` — governance approval function (default: auto-approve)
  """
  @spec scan(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def scan(repo_path, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    approve_fn = Keyword.get(opts, :approve_fn, fn _desc -> :approved end)

    tool_context = %{
      repo_path: repo_path,
      approve_fn: approve_fn
    }

    try do
      case Jido.AgentServer.start(agent: ArchitectAgent, jido: Keiro.Jido) do
        {:ok, pid} ->
          result =
            ArchitectAgent.ask_sync(pid, @scan_prompt,
              timeout: timeout,
              tool_context: tool_context
            )

          GenServer.stop(pid, :normal)
          result

        {:error, reason} ->
          {:error, "Failed to start architect agent: #{inspect(reason)}"}
      end
    catch
      :exit, reason ->
        {:error, "Architect agent failed: #{inspect(reason)}"}
    end
  end
end
