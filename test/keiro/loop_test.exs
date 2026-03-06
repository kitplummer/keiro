defmodule Keiro.LoopTest do
  @moduledoc """
  Integration tests for the closed-loop orchestration:
  bead ready → in_progress → pipeline stages → closed/blocked.

  Uses injectable runner_fn to avoid needing a live LLM backend.
  """
  use ExUnit.Case, async: true

  alias Keiro.Orchestrator

  @mock_bd_eng Path.expand("../support/mock_bd_eng.sh", __DIR__)
  @mock_bd_ops Path.expand("../support/mock_bd_ops.sh", __DIR__)

  setup do
    log_file = Path.join(System.tmp_dir!(), "mock_bd_log_#{System.unique_integer([:positive])}")
    File.rm(log_file)
    System.put_env("MOCK_BD_LOG", log_file)

    on_exit(fn ->
      System.delete_env("MOCK_BD_LOG")
      File.rm(log_file)
    end)

    %{log_file: log_file}
  end

  describe "eng bead happy path" do
    test "pipeline stages run and bead is closed", %{log_file: log_file} do
      runner_fn = fn _bead, stage, _prev_stages, _tool_context ->
        {:ok, "#{stage.name} completed"}
      end

      Application.put_env(:keiro, :beads_bd_path, @mock_bd_eng)

      result =
        Orchestrator.run_next(
          repo_path: System.tmp_dir!(),
          runner_fn: runner_fn,
          approve_fn: fn _action -> :ok end
        )

      Application.delete_env(:keiro, :beads_bd_path)

      assert {:ok, pipeline_result} = result
      assert pipeline_result.status == :ok
      assert length(pipeline_result.stages) == 2

      [eng_stage, verify_stage] = pipeline_result.stages
      assert eng_stage.name == "engineer"
      assert eng_stage.status == :ok
      assert eng_stage.result == "engineer completed"
      assert verify_stage.name == "verify"
      assert verify_stage.status == :ok

      # Verify bd received the lifecycle calls
      log = File.read!(log_file)
      assert log =~ "update gl-100 --status in_progress"
      assert log =~ "close gl-100"
    end
  end

  describe "eng bead failure path" do
    test "pipeline failure sets bead to blocked", %{log_file: log_file} do
      runner_fn = fn _bead, stage, _prev_stages, _tool_context ->
        case stage.name do
          "engineer" -> {:ok, "eng done"}
          "verify" -> {:error, "verify failed: tests failing"}
        end
      end

      Application.put_env(:keiro, :beads_bd_path, @mock_bd_eng)

      result =
        Orchestrator.run_next(
          repo_path: System.tmp_dir!(),
          runner_fn: runner_fn,
          approve_fn: fn _action -> :ok end
        )

      Application.delete_env(:keiro, :beads_bd_path)

      assert {:error, pipeline_result} = result
      assert pipeline_result.status == :error
      assert pipeline_result.error_stage == "verify"

      # Verify bd received in_progress then blocked (not close)
      log = File.read!(log_file)
      assert log =~ "update gl-100 --status in_progress"
      assert log =~ "update gl-100 --status blocked"
      refute log =~ "close gl-100"
    end
  end

  describe "ops bead path" do
    test "ops bead runs through pipeline and is closed", %{log_file: log_file} do
      test_pid = self()

      runner_fn = fn bead, stage, _prev_stages, _tool_context ->
        send(test_pid, {:runner_called, bead.id, stage.name, stage.agent_module})
        {:ok, "ops handled"}
      end

      Application.put_env(:keiro, :beads_bd_path, @mock_bd_ops)

      result =
        Orchestrator.run_next(
          repo_path: System.tmp_dir!(),
          runner_fn: runner_fn,
          approve_fn: fn _action -> :ok end
        )

      Application.delete_env(:keiro, :beads_bd_path)

      assert {:ok, %{status: :ok} = pipeline_result} = result
      assert length(pipeline_result.stages) == 1
      [ops_stage] = pipeline_result.stages
      assert ops_stage.name == "ops"
      assert ops_stage.status == :ok
      assert ops_stage.result == "ops handled"

      # Verify the runner was called with the ops agent module
      assert_received {:runner_called, "gl-200", "ops", Keiro.Ops.UplinkAgent}

      # Verify bd received the lifecycle calls (including close — new behavior)
      log = File.read!(log_file)
      assert log =~ "update gl-200 --status in_progress"
      assert log =~ "close gl-200"
    end
  end
end
