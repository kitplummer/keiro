defmodule Keiro.Failure.OutcomeContext do
  @moduledoc """
  Structured context captured when a task cannot be completed.

  Preserves what the agent attempted, what went wrong, and what it
  learned — so that retry attempts and TQM analysis start with
  accumulated knowledge instead of rediscovering it.

  ## Usage

      context = OutcomeContext.new(
        approach: "Tried to add greeting function to lib/greeting.ex",
        obstacle: ObstacleKind.missing_prerequisite("gl-042", "Module doesn't exist yet"),
        discoveries: ["Project uses Phoenix, not plain Mix"],
        recommendation: "Create the module first, then add the function"
      )
  """

  alias Keiro.Failure.ObstacleKind

  @type t :: %__MODULE__{
          approach: String.t(),
          obstacle: ObstacleKind.t(),
          discoveries: [String.t()],
          recommendation: String.t() | nil,
          explored_files: [String.t()],
          metadata: map()
        }

  @enforce_keys [:approach, :obstacle]
  defstruct [
    :approach,
    :obstacle,
    :recommendation,
    discoveries: [],
    explored_files: [],
    metadata: %{}
  ]

  @doc "Create a new outcome context."
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @doc "Render the context as a string for prompt injection (negative context)."
  @spec to_prompt(t()) :: String.t()
  def to_prompt(%__MODULE__{} = ctx) do
    parts = [
      "Previous attempt: #{ctx.approach}",
      "Obstacle: #{format_obstacle(ctx.obstacle)}"
    ]

    parts =
      if ctx.discoveries != [] do
        parts ++ ["Discoveries: #{Enum.join(ctx.discoveries, "; ")}"]
      else
        parts
      end

    parts =
      if ctx.recommendation do
        parts ++ ["Recommendation: #{ctx.recommendation}"]
      else
        parts
      end

    Enum.join(parts, "\n")
  end

  defp format_obstacle({kind, opts}) do
    case kind do
      :missing_prerequisite ->
        "Missing prerequisite #{opts[:task_id]}: #{opts[:reason]}"

      :architectural_gap ->
        "Architectural gap: #{opts[:description]}"

      :model_limitation ->
        "Model limitation (#{opts[:model]}): #{opts[:error_class]}"

      :external_dependency ->
        "External dependency unavailable: #{opts[:service]}"

      :scope_too_large ->
        "Scope too large: #{opts[:estimated_files]} files (max #{opts[:max_files]})"

      :unknown ->
        "Unknown: #{opts[:reason]}"
    end
  end
end
