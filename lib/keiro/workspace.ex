defmodule Keiro.Workspace do
  @moduledoc """
  Behaviour for workspace isolation providers.

  A workspace provider creates an isolated working directory for agent
  execution and cleans it up afterward. This allows different isolation
  strategies depending on the deployment environment.

  Built-in providers:
  - `Keiro.Workspace.Directory` — uses the repo directory directly (no isolation)
  - `Keiro.Workspace.TempDir` — creates a temporary directory copy
  - `Keiro.Workspace.GitWorktree` — creates a git worktree for branch isolation

  ## Usage

      {:ok, workspace} = Keiro.Workspace.acquire(provider)
      # ... do work in workspace.path ...
      :ok = Keiro.Workspace.release(provider, workspace)
  """

  @type workspace :: %{path: String.t(), metadata: map()}

  @doc "Acquire an isolated workspace. Returns the workspace path and metadata."
  @callback acquire(provider :: struct()) :: {:ok, workspace()} | {:error, term()}

  @doc "Release/clean up a workspace after use."
  @callback release(provider :: struct(), workspace :: workspace()) :: :ok | {:error, term()}

  @doc "Dispatch acquire to provider module."
  @spec acquire(struct()) :: {:ok, workspace()} | {:error, term()}
  def acquire(%module{} = provider), do: module.acquire(provider)

  @doc "Dispatch release to provider module."
  @spec release(struct(), workspace()) :: :ok | {:error, term()}
  def release(%module{} = provider, workspace), do: module.release(provider, workspace)
end
