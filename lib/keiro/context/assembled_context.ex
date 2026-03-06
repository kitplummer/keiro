defmodule Keiro.Context.AssembledContext do
  @moduledoc """
  Result of context assembly.

  Contains the assembled context content along with metadata about
  how it was assembled.
  """

  @type source :: %{
          type: atom(),
          identifier: String.t(),
          token_count: non_neg_integer(),
          priority: non_neg_integer()
        }

  @type t :: %__MODULE__{
          content: String.t(),
          sources: [source()],
          token_count: non_neg_integer(),
          priority_order: [atom()],
          truncated: boolean(),
          assembly_time_ms: non_neg_integer(),
          metadata: map()
        }

  @enforce_keys [:content, :sources, :token_count]
  defstruct [
    :content,
    :sources,
    :token_count,
    priority_order: [],
    truncated: false,
    assembly_time_ms: 0,
    metadata: %{}
  ]

  @doc """
  Create a new assembled context.

  ## Examples

      iex> AssembledContext.new("System prompt\\nTask: Fix bug", [%{type: :system_prompt, identifier: "engineer", token_count: 100, priority: 0}], 150)
      %AssembledContext{
        content: "System prompt\\nTask: Fix bug",
        sources: [%{type: :system_prompt, identifier: "engineer", token_count: 100, priority: 0}],
        token_count: 150,
        priority_order: [],
        truncated: false,
        assembly_time_ms: 0,
        metadata: %{}
      }
  """
  @spec new(String.t(), [source()], non_neg_integer(), keyword()) :: t()
  def new(content, sources, token_count, opts \\ []) do
    %__MODULE__{
      content: content,
      sources: sources,
      token_count: token_count,
      priority_order: Keyword.get(opts, :priority_order, []),
      truncated: Keyword.get(opts, :truncated, false),
      assembly_time_ms: Keyword.get(opts, :assembly_time_ms, 0),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Calculate total token count from sources.
  """
  @spec total_tokens([source()]) :: non_neg_integer()
  def total_tokens(sources) do
    Enum.reduce(sources, 0, fn source, acc -> acc + source.token_count end)
  end

  @doc """
  Check if context was truncated due to token limits.
  """
  @spec truncated?(t()) :: boolean()
  def truncated?(%__MODULE__{truncated: truncated}), do: truncated

  @doc """
  Get sources by type.
  """
  @spec sources_by_type(t(), atom()) :: [source()]
  def sources_by_type(%__MODULE__{sources: sources}, type) do
    Enum.filter(sources, fn source -> source.type == type end)
  end
end
