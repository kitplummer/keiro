defmodule Keiro.Workspace.Provider do
  @moduledoc """
  Behaviour for workspace isolation providers.

  A workspace provider creates isolated environments for task execution.
  The orchestrator acquires a workspace before dispatching to an agent
  and releases it after completion.

  ## Implementations

  - `Keiro.Workspace.GitWorktree` — git worktree per task (default)
  - `Keiro.Workspace.TempDir` — temporary directory (for non-git repos)
  - `Keiro.Workspace.NoOp` — no isolation (testing/development)
  """

  @type workspace :: %{
          path: String.t(),
          metadata: map()
        }

  @doc "Create an isolated workspace for the given task. Returns the workspace path and metadata."
  @callback create(task_id :: String.t(), opts :: keyword()) ::
              {:ok, workspace()} | {:error, term()}

  @doc "Release/cleanup the workspace after task completion."
  @callback release(workspace()) :: :ok | {:error, term()}

  @doc "Check if the provider is available (e.g., git installed for worktree provider)."
  @callback available?() :: boolean()
end
