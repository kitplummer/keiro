defmodule Keiro.Pipeline.Stage do
  @moduledoc """
  A single stage in a multi-agent pipeline.

  Each stage has a name, agent module, a function to build the prompt
  from the bead and previous results, and a timeout.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          agent_module: module(),
          prompt_fn: (Keiro.Beads.Bead.t(), [Keiro.Pipeline.Result.StageResult.t()] -> String.t()),
          timeout: pos_integer()
        }

  @enforce_keys [:name, :agent_module, :prompt_fn]
  defstruct [:name, :agent_module, :prompt_fn, timeout: 120_000]
end
