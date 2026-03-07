defmodule Keiro.Pipeline.OutcomeContext do
  @moduledoc """
  Structured context from a pipeline execution.

  Captures what the agent tried, what went wrong, what it discovered,
  and what it recommends. This context is written as a bead comment
  so that retry attempts have negative context injection — they know
  what was already tried and what failed.

  ## Fields

  - `outcome` — the classified outcome (from `Outcome.classify/1`)
  - `approach` — what the agent attempted
  - `obstacle` — what prevented success (if any)
  - `discoveries` — useful findings from the attempt
  - `recommendation` — suggested next action
  - `explored_state` — files/paths/branches touched
  """

  alias Keiro.Pipeline.Outcome

  @type t :: %__MODULE__{
          outcome: Outcome.t(),
          approach: String.t() | nil,
          obstacle: String.t() | nil,
          discoveries: [String.t()],
          recommendation: String.t() | nil,
          explored_state: [String.t()]
        }

  @enforce_keys [:outcome]
  defstruct [:outcome, :approach, :obstacle, :recommendation, discoveries: [], explored_state: []]

  @doc """
  Build an OutcomeContext from a pipeline result.

  Extracts approach/obstacle/discoveries from stage results when available.
  """
  @spec from_result(Keiro.Pipeline.Result.t()) :: t()
  def from_result(result) do
    outcome = Outcome.classify(result)

    %__MODULE__{
      outcome: outcome,
      approach: extract_approach(result),
      obstacle: extract_obstacle(result),
      discoveries: extract_discoveries(result)
    }
  end

  @doc """
  Format the context as a markdown string for bead comments.
  """
  @spec to_markdown(t()) :: String.t()
  def to_markdown(%__MODULE__{} = ctx) do
    sections = [
      "## Outcome: #{ctx.outcome}",
      if(ctx.approach, do: "### Approach\n#{ctx.approach}"),
      if(ctx.obstacle, do: "### Obstacle\n#{ctx.obstacle}"),
      if(ctx.discoveries != [],
        do: "### Discoveries\n#{Enum.map_join(ctx.discoveries, "\n", &"- #{&1}")}"
      ),
      if(ctx.recommendation, do: "### Recommendation\n#{ctx.recommendation}"),
      if(ctx.explored_state != [],
        do: "### Explored State\n#{Enum.map_join(ctx.explored_state, "\n", &"- #{&1}")}"
      )
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  # -- private extraction --

  defp extract_approach(%{stages: stages}) do
    stages
    |> Enum.map(& &1.name)
    |> case do
      [] -> nil
      names -> "Ran stages: #{Enum.join(names, " → ")}"
    end
  end

  defp extract_obstacle(%{status: :ok}), do: nil

  defp extract_obstacle(%{status: :error, stages: stages}) do
    stages
    |> Enum.filter(&(&1.status == :error))
    |> Enum.map_join("; ", fn s -> "#{s.name}: #{truncate(to_string(s.result), 200)}" end)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_discoveries(%{stages: stages}) do
    stages
    |> Enum.filter(&(&1.status == :ok))
    |> Enum.map(fn s -> "#{s.name} completed in #{s.elapsed_ms}ms" end)
  end

  defp truncate(text, max) when byte_size(text) > max, do: String.slice(text, 0, max) <> "..."
  defp truncate(text, _max), do: text
end
