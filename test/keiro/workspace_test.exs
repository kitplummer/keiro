defmodule Keiro.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Keiro.Workspace

  describe "Directory provider" do
    test "acquires existing directory" do
      provider = Workspace.Directory.new(System.tmp_dir!())
      assert {:ok, ws} = Workspace.acquire(provider)
      assert ws.path == System.tmp_dir!()
      assert ws.metadata.provider == :directory
    end

    test "errors on non-existent directory" do
      provider = Workspace.Directory.new("/nonexistent/path/abc123")
      assert {:error, msg} = Workspace.acquire(provider)
      assert msg =~ "does not exist"
    end

    test "release is a no-op" do
      provider = Workspace.Directory.new(System.tmp_dir!())
      {:ok, ws} = Workspace.acquire(provider)
      assert :ok = Workspace.release(provider, ws)
    end
  end

  describe "TempDir provider" do
    test "creates and removes temp directory" do
      provider = Workspace.TempDir.new(prefix: "keiro-test-")
      assert {:ok, ws} = Workspace.acquire(provider)
      assert File.dir?(ws.path)
      assert ws.metadata.provider == :temp_dir
      assert ws.metadata.created == true

      assert :ok = Workspace.release(provider, ws)
      refute File.dir?(ws.path)
    end

    test "creates unique directories on each acquire" do
      provider = Workspace.TempDir.new()
      {:ok, ws1} = Workspace.acquire(provider)
      {:ok, ws2} = Workspace.acquire(provider)
      assert ws1.path != ws2.path

      # Cleanup
      Workspace.release(provider, ws1)
      Workspace.release(provider, ws2)
    end

    test "uses default prefix" do
      provider = Workspace.TempDir.new()
      assert provider.prefix == "keiro-workspace-"
    end
  end

  describe "GitWorktree provider" do
    test "new/1 creates provider with repo path" do
      provider = Workspace.GitWorktree.new("/some/repo")
      assert provider.repo_path == "/some/repo"
      assert provider.worktree_dir == ".worktrees"
    end

    test "new/2 accepts custom worktree dir" do
      provider = Workspace.GitWorktree.new("/some/repo", worktree_dir: ".wt")
      assert provider.worktree_dir == ".wt"
    end

    test "acquire errors when git is not available or repo doesn't exist" do
      provider = Workspace.GitWorktree.new("/nonexistent/repo")
      assert {:error, _} = Workspace.acquire(provider)
    end
  end

  describe "dispatch" do
    test "acquire dispatches to correct provider" do
      dir = Workspace.Directory.new(System.tmp_dir!())
      assert {:ok, %{metadata: %{provider: :directory}}} = Workspace.acquire(dir)
    end

    test "release dispatches to correct provider" do
      provider = Workspace.TempDir.new()
      {:ok, ws} = Workspace.acquire(provider)
      assert :ok = Workspace.release(provider, ws)
    end
  end
end
