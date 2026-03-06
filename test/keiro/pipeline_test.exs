defmodule Keiro.PipelineTest do
  use ExUnit.Case, async: true

  alias Keiro.Pipeline
  alias Keiro.Pipeline.{Stage, Result}
  alias Keiro.Pipeline.Result.StageResult
  alias Keiro.Beads.Bead

  describe "Stage struct" do
    test "has default timeout" do
      stage = %Stage{
        name: "test",
        agent_module: FakeAgent,
        prompt_fn: fn _bead, _prev -> "prompt" end
      }

      assert stage.timeout == 120_000
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Stage, [])
      end
    end
  end

  describe "Result struct" do
    test "defaults to ok status with empty stages" do
      result = %Result{}
      assert result.status == :ok
      assert result.stages == []
      assert result.error_stage == nil
    end
  end

  describe "StageResult struct" do
    test "holds stage execution data" do
      sr = %StageResult{name: "engineer", status: :ok, result: "done", elapsed_ms: 500}
      assert sr.name == "engineer"
      assert sr.status == :ok
      assert sr.result == "done"
      assert sr.elapsed_ms == 500
    end
  end

  describe "run/3" do
    test "returns error when agent module fails to start" do
      bead = %Bead{id: "gl-001", title: "Test bead"}

      stages = [
        %Stage{
          name: "bad_stage",
          agent_module: NonExistentAgentModule,
          prompt_fn: fn _bead, _prev -> "do something" end,
          timeout: 5_000
        }
      ]

      assert {:error, result} = Pipeline.run(bead, stages)
      assert result.status == :error
      assert result.error_stage == "bad_stage"
      assert length(result.stages) == 1

      [stage_result] = result.stages
      assert stage_result.name == "bad_stage"
      assert stage_result.status == :error
      assert is_binary(stage_result.result)
      assert stage_result.result =~ "Failed to start agent"
    end

    test "returns ok with empty stages" do
      bead = %Bead{id: "gl-002", title: "Empty pipeline"}

      assert {:ok, result} = Pipeline.run(bead, [])
      assert result.status == :ok
      assert result.stages == []
    end

    test "prompt_fn receives bead and previous stage results" do
      test_pid = self()
      bead = %Bead{id: "gl-003", title: "Prompt test"}

      stages = [
        %Stage{
          name: "check_prompt",
          agent_module: NonExistentAgentModule,
          prompt_fn: fn received_bead, prev ->
            send(test_pid, {:prompt_called, received_bead, prev})
            "test prompt"
          end,
          timeout: 5_000
        }
      ]

      Pipeline.run(bead, stages)

      assert_received {:prompt_called, ^bead, []}
    end

    test "passes tool_context option" do
      bead = %Bead{id: "gl-004", title: "Context test"}

      stages = [
        %Stage{
          name: "ctx_stage",
          agent_module: NonExistentAgentModule,
          prompt_fn: fn _bead, _prev -> "prompt" end,
          timeout: 5_000
        }
      ]

      # This will fail at agent start, but verifies the function accepts opts
      assert {:error, _} = Pipeline.run(bead, stages, tool_context: %{repo_path: "/tmp"})
    end
  end
end
