defmodule Keiro.Pipeline.Stage do
  @moduledoc """
  A single stage in a multi-agent pipeline.

  Each stage has a name, a function to build the prompt from the bead and
  previous results, and a timeout. Execution is dispatched via either:

  - `runner_fn` — a custom runner `(prompt, tool_context) -> {:ok, term()} | {:error, term()}`
  - `agent_module` — a Jido agent started via `AgentServer`

  At least one of `runner_fn` or `agent_module` must be set.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          agent_module: module() | nil,
          prompt_fn: (Keiro.Beads.Bead.t(), [Keiro.Pipeline.Result.StageResult.t()] -> String.t()),
          runner_fn: (String.t(), map() -> {:ok, term()} | {:error, term()}) | nil,
          timeout: pos_integer()
        }

  @enforce_keys [:name, :prompt_fn]
  defstruct [:name, :agent_module, :prompt_fn, :runner_fn, timeout: 120_000]
end
