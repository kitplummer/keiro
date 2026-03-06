defmodule Keiro.Workspace.NoOp do
  @moduledoc """
  No-op workspace provider for testing and development.

  Returns the repo_path (or cwd) as the workspace path without
  creating any isolation.
  """

  @behaviour Keiro.Workspace.Provider

  @impl true
  def available?, do: true

  @impl true
  def create(task_id, opts) do
    path = Keyword.get(opts, :repo_path, File.cwd!())
    {:ok, %{path: path, metadata: %{task_id: task_id, type: :no_op}}}
  end

  @impl true
  def release(_workspace), do: :ok
end
