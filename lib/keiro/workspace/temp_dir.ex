defmodule Keiro.Workspace.TempDir do
  @moduledoc """
  Workspace provider that creates a temporary directory.

  Creates a unique temp directory on acquire and removes it on release.
  Useful for tasks that need a clean, isolated workspace without
  git worktree overhead.
  """

  @behaviour Keiro.Workspace

  @type t :: %__MODULE__{prefix: String.t()}

  defstruct prefix: "keiro-workspace-"

  @doc "Create a temp dir workspace provider."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{prefix: Keyword.get(opts, :prefix, "keiro-workspace-")}
  end

  @impl Keiro.Workspace
  def acquire(%__MODULE__{prefix: prefix}) do
    dir = Path.join(System.tmp_dir!(), prefix <> random_suffix())

    case File.mkdir_p(dir) do
      :ok -> {:ok, %{path: dir, metadata: %{provider: :temp_dir, created: true}}}
      {:error, reason} -> {:error, "Failed to create temp dir: #{inspect(reason)}"}
    end
  end

  @impl Keiro.Workspace
  def release(%__MODULE__{}, %{path: path}) do
    File.rm_rf!(path)
    :ok
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end
end
