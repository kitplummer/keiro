defmodule Keiro.Task do
  @moduledoc """
  Generic work item protocol.

  Abstracts the concept of a "task" so the orchestrator can work with
  any task source (beads, GitHub issues, JIRA tickets, etc.) through
  a uniform interface.

  ## Implementation

  Implement this protocol for your task struct:

      defimpl Keiro.Task, for: MyApp.JiraTicket do
        def id(ticket), do: ticket.key
        def title(ticket), do: ticket.summary
        def description(ticket), do: ticket.description
        def status(ticket), do: ticket.status
        def priority(ticket), do: ticket.priority
        def labels(ticket), do: ticket.labels
      end
  """

  @doc "Unique identifier for the task."
  @callback id(task :: struct()) :: String.t() | nil

  @doc "Human-readable title."
  @callback title(task :: struct()) :: String.t() | nil

  @doc "Detailed description."
  @callback description(task :: struct()) :: String.t() | nil

  @doc "Current status (e.g. open, in_progress, closed)."
  @callback status(task :: struct()) :: String.t() | nil

  @doc "Priority level (0-4 where 0 is critical)."
  @callback priority(task :: struct()) :: non_neg_integer() | nil

  @doc "Labels/tags for routing."
  @callback labels(task :: struct()) :: [String.t()]

  @optional_callbacks []

  defmacro __using__(_opts) do
    quote do
      @behaviour Keiro.Task
    end
  end
end
