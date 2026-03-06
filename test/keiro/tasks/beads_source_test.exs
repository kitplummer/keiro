defmodule Keiro.Tasks.BeadsSourceTest do
  use ExUnit.Case, async: false

  alias Keiro.Tasks.BeadsSource

  @mock_bd Path.expand("../../support/mock_bd_eng.sh", __DIR__)

  setup do
    log_file = Path.join(System.tmp_dir!(), "mock_bd_log_#{System.unique_integer([:positive])}")
    File.rm(log_file)
    System.put_env("MOCK_BD_LOG", log_file)
    Application.put_env(:keiro, :beads_bd_path, @mock_bd)

    on_exit(fn ->
      System.delete_env("MOCK_BD_LOG")
      Application.delete_env(:keiro, :beads_bd_path)
      File.rm(log_file)
    end)

    %{log_file: log_file}
  end

  describe "ready/1" do
    test "returns tasks converted from beads" do
      {:ok, tasks} = BeadsSource.ready(repo_path: System.tmp_dir!())
      assert length(tasks) == 1
      [task] = tasks
      assert task.id == "gl-100"
      assert task.title == "Implement widget"
      assert task.source == :beads
      assert "eng" in task.labels
    end
  end

  describe "list/1" do
    test "returns tasks from list" do
      {:ok, tasks} = BeadsSource.list(repo_path: System.tmp_dir!())
      assert length(tasks) >= 1
    end
  end

  describe "update_status/3" do
    test "delegates to beads client", %{log_file: log_file} do
      assert :ok =
               BeadsSource.update_status("gl-100", "in_progress", repo_path: System.tmp_dir!())

      log = File.read!(log_file)
      assert log =~ "update gl-100 --status in_progress"
    end
  end

  describe "close/2" do
    test "delegates to beads client", %{log_file: log_file} do
      assert :ok = BeadsSource.close("gl-100", repo_path: System.tmp_dir!())
      log = File.read!(log_file)
      assert log =~ "close gl-100"
    end
  end
end
