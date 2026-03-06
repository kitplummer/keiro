defmodule Keiro.Workspace.GitWorktree do
  @moduledoc """
  Workspace provider using git worktrees.

  Creates a git worktree per task, providing full isolation from the
  main branch. Changes in one worktree cannot affect others.

  Requires git to be installed and the repo_path to be a git repository.
  """

  @behaviour Keiro.Workspace.Provider

  require Logger

  @impl true
  def available? do
    case System.cmd("git", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @impl true
  def create(task_id, opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    base_branch = Keyword.get(opts, :base_branch, "HEAD")
    branch_name = "eng/#{sanitize_id(task_id)}"

    worktree_path = Path.join([repo_path, ".worktrees", sanitize_id(task_id)])

    case System.cmd(
           "git",
           ["worktree", "add", "-b", branch_name, worktree_path, base_branch],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Workspace: created worktree at #{worktree_path}")

        {:ok,
         %{
           path: worktree_path,
           metadata: %{
             branch: branch_name,
             repo_path: repo_path,
             task_id: task_id
           }
         }}

      {output, _code} ->
        {:error, "Failed to create worktree: #{String.trim(output)}"}
    end
  end

  @impl true
  def release(%{path: worktree_path, metadata: %{repo_path: repo_path}}) do
    case System.cmd("git", ["worktree", "remove", worktree_path, "--force"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.info("Workspace: removed worktree at #{worktree_path}")
        :ok

      {output, _code} ->
        {:error, "Failed to remove worktree: #{String.trim(output)}"}
    end
  end

  def release(_), do: {:error, "Invalid workspace: missing metadata"}

  defp sanitize_id(id) do
    id
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "-")
    |> String.slice(0, 100)
  end
end
