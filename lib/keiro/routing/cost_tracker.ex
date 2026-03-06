defmodule Keiro.Routing.CostTracker do
  @moduledoc """
  Tracks per-agent and per-task token spend against budget.

  Lightweight in-memory tracker backed by an Agent process.
  Spend entries are keyed by `{task_id, agent_role}`.
  """

  use Agent

  @type spend_entry :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cost: float(),
          model: String.t()
        }

  @type state :: %{
          entries: %{{String.t(), String.t()} => [spend_entry()]},
          total_cost: float()
        }

  @doc "Start a new cost tracker."
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{entries: %{}, total_cost: 0.0} end, name: name)
  end

  @doc "Record a spend entry for a task/role pair."
  @spec record(GenServer.server(), String.t(), String.t(), spend_entry()) :: :ok
  def record(tracker, task_id, role, entry) do
    Agent.update(tracker, fn state ->
      key = {task_id, role}
      existing = Map.get(state.entries, key, [])

      %{
        state
        | entries: Map.put(state.entries, key, existing ++ [entry]),
          total_cost: state.total_cost + (entry[:cost] || 0.0)
      }
    end)
  end

  @doc "Get total cost across all tasks."
  @spec total_cost(GenServer.server()) :: float()
  def total_cost(tracker) do
    Agent.get(tracker, & &1.total_cost)
  end

  @doc "Get spend entries for a specific task."
  @spec task_cost(GenServer.server(), String.t()) :: float()
  def task_cost(tracker, task_id) do
    Agent.get(tracker, fn state ->
      state.entries
      |> Enum.filter(fn {{tid, _role}, _entries} -> tid == task_id end)
      |> Enum.flat_map(fn {_key, entries} -> entries end)
      |> Enum.reduce(0.0, fn entry, acc -> acc + (entry[:cost] || 0.0) end)
    end)
  end

  @doc "Get spend entries for a specific task/role pair."
  @spec entries(GenServer.server(), String.t(), String.t()) :: [spend_entry()]
  def entries(tracker, task_id, role) do
    Agent.get(tracker, fn state ->
      Map.get(state.entries, {task_id, role}, [])
    end)
  end

  @doc "Get a summary of all spend."
  @spec summary(GenServer.server()) :: state()
  def summary(tracker) do
    Agent.get(tracker, & &1)
  end
end
