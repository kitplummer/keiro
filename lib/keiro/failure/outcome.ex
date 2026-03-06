defmodule Keiro.Failure.Outcome do
  @moduledoc """
  Outcome taxonomy for task execution.

  Replaces binary pass/fail with classified outcomes that drive
  supervisor behaviour:

  - `:completed` — task done, advance dependents
  - `:deferred` — return to queue with learned context
  - `:decomposed` — subtasks injected, parent waits
  - `:blocked` — parked until external blocker resolves
  - `:retryable` — retry with backoff + failure context
  - `:escalated` — halt and surface to human review
  """

  @type t ::
          :completed
          | :deferred
          | :decomposed
          | :blocked
          | :retryable
          | :escalated

  @outcomes [:completed, :deferred, :decomposed, :blocked, :retryable, :escalated]

  @doc "All valid outcome values."
  @spec values() :: [t()]
  def values, do: @outcomes

  @doc "Check if a value is a valid outcome."
  @spec valid?(term()) :: boolean()
  def valid?(outcome), do: outcome in @outcomes

  @doc "Classify a pipeline result into an outcome."
  @spec classify({:ok | :error, term()}) :: t()
  def classify({:ok, _result}), do: :completed

  def classify({:error, %{error_stage: _stage} = _pipeline_result}), do: :retryable

  def classify({:error, reason}) when is_binary(reason) do
    cond do
      reason =~ "no matching" -> :escalated
      reason =~ "budget" -> :escalated
      true -> :retryable
    end
  end

  def classify(_), do: :escalated
end
