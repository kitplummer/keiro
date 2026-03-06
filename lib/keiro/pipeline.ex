defmodule Keiro.Pipeline do
  @moduledoc """
  Multi-stage pipeline runner.

  Sequences agents, passing results between stages. Each stage builds
  its prompt from the bead and accumulated results of previous stages.
  Halts on the first stage failure.

  ## Usage

      stages = [
        %Stage{name: "engineer", agent_module: EngineerAgent, prompt_fn: &eng_prompt/2},
        %Stage{name: "deploy", agent_module: UplinkAgent, prompt_fn: &deploy_prompt/2}
      ]

      {:ok, result} = Pipeline.run(bead, stages, tool_context: %{repo_path: "."})
  """

  alias Keiro.Pipeline.{Stage, Result}
  alias Keiro.Pipeline.Result.StageResult

  require Logger

  @doc """
  Run a pipeline of stages for a given bead.

  Options:
  - `:tool_context` — map passed to agent's `ask_sync` as `tool_context:` (optional)

  Returns `{:ok, %Result{}}` when all stages succeed, or
  `{:error, %Result{}}` when a stage fails.
  """
  @spec run(Keiro.Beads.Bead.t(), [Stage.t()], keyword()) ::
          {:ok, Result.t()} | {:error, Result.t()}
  def run(bead, stages, opts \\ []) do
    tool_context = Keyword.get(opts, :tool_context, %{})

    result =
      Enum.reduce_while(stages, %Result{}, fn stage, acc ->
        Logger.info("Pipeline: starting stage #{stage.name}")
        start_time = System.monotonic_time(:millisecond)

        case run_stage(bead, stage, acc.stages, tool_context) do
          {:ok, stage_result} ->
            elapsed = System.monotonic_time(:millisecond) - start_time

            stage_entry = %StageResult{
              name: stage.name,
              status: :ok,
              result: stage_result,
              elapsed_ms: elapsed
            }

            {:cont, %{acc | stages: acc.stages ++ [stage_entry]}}

          {:error, reason} ->
            elapsed = System.monotonic_time(:millisecond) - start_time

            stage_entry = %StageResult{
              name: stage.name,
              status: :error,
              result: reason,
              elapsed_ms: elapsed
            }

            {:halt,
             %{acc | status: :error, error_stage: stage.name, stages: acc.stages ++ [stage_entry]}}
        end
      end)

    case result.status do
      :ok -> {:ok, result}
      :error -> {:error, result}
    end
  end

  defp run_stage(bead, stage, prev_stages, tool_context) do
    prompt = stage.prompt_fn.(bead, prev_stages)

    try do
      case Jido.AgentServer.start(agent: stage.agent_module) do
        {:ok, pid} ->
          try do
            result =
              stage.agent_module.ask_sync(pid, prompt,
                timeout: stage.timeout,
                tool_context: tool_context
              )

            GenServer.stop(pid, :normal)
            result
          catch
            :exit, reason ->
              {:error, "Stage #{stage.name} timed out or crashed: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to start agent for stage #{stage.name}: #{inspect(reason)}"}
      end
    catch
      :exit, reason ->
        {:error, "Failed to start agent for stage #{stage.name}: #{inspect(reason)}"}
    end
  end
end
