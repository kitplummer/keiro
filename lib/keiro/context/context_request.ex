defmodule Keiro.Context.ContextRequest do
  @moduledoc """
  Request for context assembly.

  Specifies what context an agent needs and any constraints on the assembly.
  """

  @type t :: %__MODULE__{
          agent_role: String.t(),
          task_description: String.t(),
          constraints: [String.t()],
          max_tokens: pos_integer(),
          priority_hints: [atom()],
          metadata: map()
        }

  @enforce_keys [:agent_role, :task_description]
  defstruct [
    :agent_role,
    :task_description,
    constraints: [],
    max_tokens: 50_000,
    priority_hints: [],
    metadata: %{}
  ]

  @doc """
  Create a new context request.

  ## Examples

      iex> ContextRequest.new("engineer", "Fix authentication bug")
      %ContextRequest{
        agent_role: "engineer",
        task_description: "Fix authentication bug",
        constraints: [],
        max_tokens: 50_000,
        priority_hints: [],
        metadata: %{}
      }

      iex> ContextRequest.new("ops", "Deploy to production", max_tokens: 30_000, constraints: ["no destructive changes"])
      %ContextRequest{
        agent_role: "ops",
        task_description: "Deploy to production",
        constraints: ["no destructive changes"],
        max_tokens: 30_000,
        priority_hints: [],
        metadata: %{}
      }
  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(agent_role, task_description, opts \\ []) do
    %__MODULE__{
      agent_role: agent_role,
      task_description: task_description,
      constraints: Keyword.get(opts, :constraints, []),
      max_tokens: Keyword.get(opts, :max_tokens, 50_000),
      priority_hints: Keyword.get(opts, :priority_hints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
