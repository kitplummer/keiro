defmodule Keiro.Context.Strategy do
  @moduledoc """
  Behavior for context assembly strategies.

  Context assembly currently assumes code repos. This behavior allows
  organizations to assemble context from arbitrary sources: logs, metrics,
  infrastructure state, documentation, etc.

  ## Usage

      defmodule MyOrg.LogsContextStrategy do
        @behaviour Keiro.Context.Strategy

        @impl true
        def assemble(context_request, opts) do
          # Fetch relevant logs, format for agent consumption
          {:ok, %Keiro.Context.AssembledContext{...}}
        end

        @impl true
        def priority_order do
          [:recent_errors, :performance_metrics, :deployment_logs]
        end
      end

  ## Context Request

  A `ContextRequest` specifies what context an agent needs:
  - `agent_role` - the role requesting context (e.g., "engineer", "ops")
  - `task_description` - what the agent is trying to accomplish
  - `constraints` - any limitations or requirements
  - `max_tokens` - token budget for context assembly
  - `priority_hints` - optional hints about what context is most important

  ## Assembled Context

  The strategy returns an `AssembledContext` with:
  - `content` - the assembled context as a string
  - `sources` - list of sources used (for audit/debugging)
  - `token_count` - estimated token count
  - `priority_order` - the order in which context was prioritized
  - `truncated` - whether content was truncated due to token limits
  """

  alias Keiro.Context.{ContextRequest, AssembledContext}

  @doc """
  Assemble context for an agent based on the request.

  Returns `{:ok, assembled_context}` on success, or `{:error, reason}` on failure.
  """
  @callback assemble(ContextRequest.t(), keyword()) ::
              {:ok, AssembledContext.t()} | {:error, term()}

  @doc """
  Return the default priority order for context elements.

  This defines how the strategy prioritizes different types of context
  when token limits require truncation.
  """
  @callback priority_order() :: [atom()]

  @doc """
  Optional callback to validate context request before assembly.

  Default implementation accepts all requests.
  """
  @callback validate_request(ContextRequest.t()) :: :ok | {:error, term()}

  @optional_callbacks [validate_request: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Keiro.Context.Strategy

      @impl true
      def validate_request(_request), do: :ok

      defoverridable validate_request: 1
    end
  end
end
