defmodule Keiro.Pipeline.Outcome do
  @moduledoc """
  6-outcome taxonomy for pipeline execution results.

  Replaces binary `:ok`/`:error` with richer classifications that enable
  negative context injection on retry and smarter orchestrator decisions.

  ## Outcomes

  - `:completed` — all stages succeeded, task is done
  - `:deferred` — task punted (e.g., missing prerequisites, not urgent)
  - `:decomposed` — task was too large; sub-tasks were created
  - `:blocked` — hard blocker (missing access, broken dependency)
  - `:retryable` — transient failure (timeout, rate limit, flaky test)
  - `:escalated` — agent determined human intervention is needed
  """

  @type t :: :completed | :deferred | :decomposed | :blocked | :retryable | :escalated

  @outcomes [:completed, :deferred, :decomposed, :blocked, :retryable, :escalated]

  @doc "List all valid outcome values."
  @spec values() :: [t()]
  def values, do: @outcomes

  @doc "Check if a value is a valid outcome."
  @spec valid?(term()) :: boolean()
  def valid?(outcome), do: outcome in @outcomes

  @doc """
  Classify a pipeline result into an outcome.

  Uses heuristics on the error message to distinguish retryable from blocked.
  """
  @spec classify(Keiro.Pipeline.Result.t()) :: t()
  def classify(%{status: :ok}), do: :completed

  def classify(%{status: :error} = result) do
    error_text = extract_error_text(result)

    cond do
      retryable?(error_text) -> :retryable
      escalation?(error_text) -> :escalated
      true -> :blocked
    end
  end

  defp extract_error_text(%{stages: stages}) do
    stages
    |> Enum.filter(&(&1.status == :error))
    |> Enum.map_join(" ", & &1.result)
    |> to_string()
    |> String.downcase()
  end

  @retryable_patterns [
    "timed out",
    "timeout",
    "rate limit",
    "429",
    "503",
    "connection refused",
    "econnrefused",
    "nxdomain"
  ]

  defp retryable?(text) do
    Enum.any?(@retryable_patterns, &String.contains?(text, &1))
  end

  @escalation_patterns [
    "permission denied",
    "unauthorized",
    "403",
    "requires human",
    "manual intervention"
  ]

  defp escalation?(text) do
    Enum.any?(@escalation_patterns, &String.contains?(text, &1))
  end
end
