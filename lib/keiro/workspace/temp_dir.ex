defmodule Keiro.Workspace.TempDir do
  @moduledoc """
  Workspace provider using temporary directories.

  Creates an isolated temp directory per task. Suitable for non-git
  repos or tasks that don't need version control isolation.
  """

  @behaviour Keiro.Workspace.Provider

  require Logger

  @impl true
  def available?, do: true

  @impl true
  def create(task_id, _opts) do
    dir_name = "keiro-#{sanitize_id(task_id)}-#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), dir_name)

    case File.mkdir_p(path) do
      :ok ->
        Logger.info("Workspace: created temp dir at #{path}")
        {:ok, %{path: path, metadata: %{task_id: task_id, type: :temp_dir}}}

      {:error, reason} ->
        {:error, "Failed to create temp dir: #{inspect(reason)}"}
    end
  end

  @impl true
  def release(%{path: path}) do
    case File.rm_rf(path) do
      {:ok, _} ->
        Logger.info("Workspace: removed temp dir at #{path}")
        :ok

      {:error, reason, _} ->
        {:error, "Failed to remove temp dir: #{inspect(reason)}"}
    end
  end

  def release(_), do: {:error, "Invalid workspace: missing path"}

  defp sanitize_id(id) do
    id
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "-")
    |> String.slice(0, 100)
  end
end
