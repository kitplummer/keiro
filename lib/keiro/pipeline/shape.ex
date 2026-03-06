defmodule Keiro.Pipeline.Shape do
  @moduledoc """
  Behaviour for pipeline shapes.

  A shape defines a pipeline stage sequence for a class of beads.
  The orchestrator resolves a shape for each bead, then runs the
  stages returned by `stages/2` through `Pipeline.run/3`.

  ## Example

      defmodule MyApp.CustomShape do
        @behaviour Keiro.Pipeline.Shape

        @impl true
        def match?(bead), do: "custom" in (bead.labels || [])

        @impl true
        def stages(bead, opts) do
          timeout = Keyword.get(opts, :timeout, 120_000)

          [
            %Keiro.Pipeline.Stage{
              name: "analyze",
              agent_module: MyApp.AnalyzerAgent,
              prompt_fn: fn b, _prev -> "Analyze \#{b.id}" end,
              timeout: timeout
            }
          ]
        end
      end
  """

  @doc "Returns true if this shape handles the given bead."
  @callback match?(Keiro.Beads.Bead.t()) :: boolean()

  @doc "Returns the ordered list of pipeline stages for the bead."
  @callback stages(Keiro.Beads.Bead.t(), keyword()) :: [Keiro.Pipeline.Stage.t()]
end
