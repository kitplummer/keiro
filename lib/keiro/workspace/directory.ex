defmodule Keiro.Workspace.Directory do
  @moduledoc """
  Workspace provider that uses a directory directly (no isolation).

  The simplest provider — just returns the given path as the workspace.
  No cleanup needed. Suitable for single-agent runs or when the caller
  manages isolation externally.
  """

  @behaviour Keiro.Workspace

  @type t :: %__MODULE__{path: String.t()}

  @enforce_keys [:path]
  defstruct [:path]

  @doc "Create a directory workspace provider."
  @spec new(String.t()) :: t()
  def new(path), do: %__MODULE__{path: path}

  @impl Keiro.Workspace
  def acquire(%__MODULE__{path: path}) do
    if File.dir?(path) do
      {:ok, %{path: path, metadata: %{provider: :directory}}}
    else
      {:error, "Directory does not exist: #{path}"}
    end
  end

  @impl Keiro.Workspace
  def release(%__MODULE__{}, _workspace), do: :ok
end
