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
    pipeline_meta = %{bead_id: bead.id, stage_count: length(stages)}

    Keiro.Telemetry.span([:keiro, :pipeline, :run], pipeline_meta, fn ->
      result =
        Enum.reduce_while(stages, %Result{}, fn stage, acc ->
          Logger.info("Pipeline: starting stage #{stage.name}")

          stage_meta = %{
            bead_id: bead.id,
            stage: stage.name,
            agent: stage.agent_module || :custom_runner
          }

          stage_result =
            Keiro.Telemetry.span([:keiro, :pipeline, :stage], stage_meta, fn ->
              run_stage(bead, stage, acc.stages, tool_context)
            end)

          start_time = System.monotonic_time(:millisecond)

          case stage_result do
            {:ok, sr} ->
              elapsed = System.monotonic_time(:millisecond) - start_time

              stage_entry = %StageResult{
                name: stage.name,
                status: :ok,
                result: sr,
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
               %{
                 acc
                 | status: :error,
                   error_stage: stage.name,
                   stages: acc.stages ++ [stage_entry]
               }}
          end
        end)

      case result.status do
        :ok -> {:ok, result}
        :error -> {:error, result}
      end
    end)
  end

  defp run_stage(bead, stage, prev_stages, tool_context) do
    prompt = stage.prompt_fn.(bead, prev_stages)

    if stage.runner_fn do
      stage.runner_fn.(prompt, tool_context)
    else
      run_via_jido(bead, stage, prompt, tool_context)
    end
  end

  defp run_via_jido(_bead, stage, prompt, tool_context) do
    try do
      case Jido.AgentServer.start(agent: stage.agent_module, jido: Keiro.Jido) do
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
