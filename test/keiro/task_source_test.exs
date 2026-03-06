defmodule Keiro.TaskSourceTest do
  use ExUnit.Case, async: true

  alias Keiro.TaskSource

  describe "Beads task source" do
    test "new/1 creates a source wrapping beads client" do
      source = TaskSource.Beads.new("/tmp/repo")
      assert %TaskSource.Beads{} = source
      assert source.client.repo_path == "/tmp/repo"
    end

    test "dispatch delegates list to source module" do
      source = TaskSource.Beads.new("/tmp/nonexistent")
      # Will error because bd isn't at /tmp/nonexistent, but proves dispatch works
      result = TaskSource.list(source)
      assert {:error, _} = result
    end

    test "dispatch delegates ready to source module" do
      source = TaskSource.Beads.new("/tmp/nonexistent")
      result = TaskSource.ready(source)
      assert {:error, _} = result
    end

    test "dispatch delegates update_status to source module" do
      source = TaskSource.Beads.new("/tmp/nonexistent")
      result = TaskSource.update_status(source, "gl-001", "closed")
      assert {:error, _} = result
    end

    test "dispatch delegates close to source module" do
      source = TaskSource.Beads.new("/tmp/nonexistent")
      result = TaskSource.close(source, "gl-001")
      assert {:error, _} = result
    end
  end
end
