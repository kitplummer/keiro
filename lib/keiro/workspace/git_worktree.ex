defmodule Keiro.Workspace.GitWorktree do
  @moduledoc """
  Workspace provider using git worktrees for branch isolation.

  Creates a git worktree on acquire, allowing agents to work on
  isolated branches without affecting the main checkout. Removes
  the worktree on release.
  """

  @behaviour Keiro.Workspace

  alias Keiro.Eng.GitCli

  @type t :: %__MODULE__{
          repo_path: String.t(),
          worktree_dir: String.t()
        }

  @enforce_keys [:repo_path]
  defstruct [:repo_path, worktree_dir: ".worktrees"]

  @doc "Create a git worktree workspace provider."
  @spec new(String.t(), keyword()) :: t()
  def new(repo_path, opts \\ []) do
    worktree_dir = Keyword.get(opts, :worktree_dir, ".worktrees")
    %__MODULE__{repo_path: repo_path, worktree_dir: worktree_dir}
  end

  @impl Keiro.Workspace
  def acquire(%__MODULE__{repo_path: repo_path, worktree_dir: worktree_dir}) do
    branch = "workspace-" <> random_suffix()
    worktree_path = Path.join([repo_path, worktree_dir, branch])
    git = GitCli.git_path()

    case GitCli.run(git, ["worktree", "add", "-b", branch, worktree_path], cd: repo_path) do
      {:ok, _output} ->
        {:ok, %{path: worktree_path, metadata: %{provider: :git_worktree, branch: branch}}}

      {:error, reason} ->
        {:error, "Failed to create worktree: #{reason}"}
    end
  end

  @impl Keiro.Workspace
  def release(%__MODULE__{repo_path: repo_path}, %{path: worktree_path, metadata: metadata}) do
    git = GitCli.git_path()
    branch = metadata[:branch]

    with {:ok, _} <-
           GitCli.run(git, ["worktree", "remove", "--force", worktree_path], cd: repo_path),
         {:ok, _} <- GitCli.run(git, ["branch", "-D", branch], cd: repo_path) do
      :ok
    else
      {:error, reason} -> {:error, "Failed to clean up worktree: #{reason}"}
    end
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
  end
end
