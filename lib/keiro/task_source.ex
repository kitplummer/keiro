defmodule Keiro.TaskSource do
  @moduledoc """
  Behaviour for pluggable task sources.

  A task source provides work items to the orchestrator. The default
  implementation is `Keiro.TaskSource.Beads` which wraps the `bd` CLI.
  Custom sources can integrate GitHub Issues, JIRA, or any other
  work tracking system.

  ## Usage

      source = Keiro.TaskSource.Beads.new("/path/to/repo")
      {:ok, tasks} = Keiro.TaskSource.list(source)
      {:ok, ready} = Keiro.TaskSource.ready(source)
  """

  @doc "List all tasks from the source."
  @callback list(source :: struct(), opts :: keyword()) :: {:ok, [struct()]} | {:error, term()}

  @doc "List tasks that are ready to be worked on."
  @callback ready(source :: struct()) :: {:ok, [struct()]} | {:error, term()}

  @doc "Update the status of a task."
  @callback update_status(source :: struct(), id :: String.t(), status :: String.t()) ::
              {:ok, term()} | {:error, term()}

  @doc "Mark a task as closed/completed."
  @callback close(source :: struct(), id :: String.t()) :: {:ok, term()} | {:error, term()}

  @doc "Dispatch to the source module's list/2."
  @spec list(struct(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def list(%module{} = source, opts \\ []), do: module.list(source, opts)

  @doc "Dispatch to the source module's ready/1."
  @spec ready(struct()) :: {:ok, [struct()]} | {:error, term()}
  def ready(%module{} = source), do: module.ready(source)

  @doc "Dispatch to the source module's update_status/3."
  @spec update_status(struct(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def update_status(%module{} = source, id, status), do: module.update_status(source, id, status)

  @doc "Dispatch to the source module's close/2."
  @spec close(struct(), String.t()) :: {:ok, term()} | {:error, term()}
  def close(%module{} = source, id), do: module.close(source, id)
end
