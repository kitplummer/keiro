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

    test "runner_fn defaults to nil" do
      stage = %Stage{
        name: "test",
        prompt_fn: fn _bead, _prev -> "prompt" end
      }

      assert stage.runner_fn == nil
      assert stage.agent_module == nil
    end

    test "stage works without agent_module when runner_fn is set" do
      stage = %Stage{
        name: "custom",
        prompt_fn: fn _bead, _prev -> "prompt" end,
        runner_fn: fn _prompt, _ctx -> {:ok, "done"} end
      }

      assert is_function(stage.runner_fn, 2)
      assert stage.agent_module == nil
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

  describe "run/3 with runner_fn" do
    test "stage with runner_fn bypasses Jido" do
      bead = %Bead{id: "gl-010", title: "Runner fn test"}

      stages = [
        %Stage{
          name: "custom",
          prompt_fn: fn _bead, _prev -> "do the thing" end,
          runner_fn: fn prompt, _ctx ->
            {:ok, "ran: #{prompt}"}
          end
        }
      ]

      assert {:ok, result} = Pipeline.run(bead, stages)
      assert result.status == :ok
      assert [stage_result] = result.stages
      assert stage_result.name == "custom"
      assert stage_result.status == :ok
      assert stage_result.result == "ran: do the thing"
    end

    test "runner_fn error propagates" do
      bead = %Bead{id: "gl-011", title: "Runner fn error"}

      stages = [
        %Stage{
          name: "failing",
          prompt_fn: fn _bead, _prev -> "fail please" end,
          runner_fn: fn _prompt, _ctx ->
            {:error, "runner exploded"}
          end
        }
      ]

      assert {:error, result} = Pipeline.run(bead, stages)
      assert result.status == :error
      assert result.error_stage == "failing"
      assert [stage_result] = result.stages
      assert stage_result.result == "runner exploded"
    end

    test "runner_fn receives tool_context" do
      test_pid = self()
      bead = %Bead{id: "gl-012", title: "Context forwarding"}

      stages = [
        %Stage{
          name: "ctx_check",
          prompt_fn: fn _bead, _prev -> "prompt" end,
          runner_fn: fn _prompt, ctx ->
            send(test_pid, {:got_context, ctx})
            {:ok, "ok"}
          end
        }
      ]

      Pipeline.run(bead, stages, tool_context: %{repo_path: "/my/repo"})
      assert_received {:got_context, %{repo_path: "/my/repo"}}
    end

    test "runner_fn stage followed by Jido stage" do
      bead = %Bead{id: "gl-013", title: "Mixed pipeline"}

      stages = [
        %Stage{
          name: "custom_first",
          prompt_fn: fn _bead, _prev -> "step 1" end,
          runner_fn: fn _prompt, _ctx -> {:ok, "step 1 done"} end
        },
        %Stage{
          name: "jido_second",
          agent_module: NonExistentAgentModule,
          prompt_fn: fn _bead, _prev -> "step 2" end,
          timeout: 5_000
        }
      ]

      # First stage succeeds (runner_fn), second fails (no Jido agent)
      assert {:error, result} = Pipeline.run(bead, stages)
      assert result.error_stage == "jido_second"
      assert length(result.stages) == 2
      assert hd(result.stages).status == :ok
    end
  end
end
