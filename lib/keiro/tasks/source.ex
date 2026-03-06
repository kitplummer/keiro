defmodule Keiro.Tasks.Source do
  @moduledoc """
  Behaviour for task sources.

  A task source provides tasks to the orchestrator from a backend
  (beads, GitHub issues, JIRA, etc.).

  ## Implementations

  - `Keiro.Tasks.BeadsSource` — backed by beads CLI (`bd`)
  """

  alias Keiro.Tasks.Task

  @doc "Fetch tasks ready for execution (unblocked, open)."
  @callback ready(opts :: keyword()) :: {:ok, [Task.t()]} | {:error, term()}

  @doc "Fetch all tasks matching the given filters."
  @callback list(opts :: keyword()) :: {:ok, [Task.t()]} | {:error, term()}

  @doc "Update task status."
  @callback update_status(task_id :: String.t(), status :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc "Close/complete a task."
  @callback close(task_id :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
end
