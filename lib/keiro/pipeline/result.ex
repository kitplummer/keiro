defmodule Keiro.Pipeline.Result do
  @moduledoc """
  Accumulates results from pipeline stage execution.
  """

  @type t :: %__MODULE__{
          status: :ok | :error,
          stages: [StageResult.t()],
          error_stage: String.t() | nil,
          outcome: atom() | nil,
          outcome_context: Keiro.Pipeline.OutcomeContext.t() | nil
        }

  defstruct status: :ok, stages: [], error_stage: nil, outcome: nil, outcome_context: nil

  defmodule StageResult do
    @moduledoc "Result of a single pipeline stage."

    @type t :: %__MODULE__{
            name: String.t(),
            status: :ok | :error,
            result: term(),
            elapsed_ms: non_neg_integer()
          }

    defstruct [:name, :status, :result, :elapsed_ms]
  end
end
