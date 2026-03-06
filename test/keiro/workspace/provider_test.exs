defmodule Keiro.Workspace.ProviderTest do
  use ExUnit.Case, async: true

  alias Keiro.Workspace.{TempDir, NoOp}

  describe "TempDir" do
    test "available? is true" do
      assert TempDir.available?()
    end

    test "create and release" do
      {:ok, workspace} = TempDir.create("gl-test-001", [])
      assert File.dir?(workspace.path)
      assert workspace.metadata.task_id == "gl-test-001"
      assert workspace.metadata.type == :temp_dir

      assert :ok = TempDir.release(workspace)
      refute File.dir?(workspace.path)
    end

    test "create sanitizes task id" do
      {:ok, workspace} = TempDir.create("gl/weird:id with spaces", [])
      assert workspace.path =~ "keiro-gl-weird-id-with-spaces"
      TempDir.release(workspace)
    end
  end

  describe "NoOp" do
    test "available? is true" do
      assert NoOp.available?()
    end

    test "create returns repo_path without creating anything" do
      {:ok, workspace} = NoOp.create("gl-test-002", repo_path: "/tmp")
      assert workspace.path == "/tmp"
      assert workspace.metadata.task_id == "gl-test-002"
      assert workspace.metadata.type == :no_op
    end

    test "create defaults to cwd" do
      {:ok, workspace} = NoOp.create("gl-test-003", [])
      assert workspace.path == File.cwd!()
    end

    test "release is no-op" do
      {:ok, workspace} = NoOp.create("gl-test-004", [])
      assert :ok = NoOp.release(workspace)
    end
  end

  describe "GitWorktree" do
    alias Keiro.Workspace.GitWorktree

    test "available? checks for git" do
      # git should be installed in the test environment
      assert GitWorktree.available?()
    end

    test "create fails gracefully on non-git directory" do
      assert {:error, msg} =
               GitWorktree.create("gl-test-005", repo_path: System.tmp_dir!())

      assert msg =~ "Failed to create worktree"
    end
  end
end
