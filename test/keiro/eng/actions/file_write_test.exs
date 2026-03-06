defmodule Keiro.Eng.Actions.FileWriteTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.Actions.FileWrite

  @tmp_dir System.tmp_dir!()

  setup do
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "run/2" do
    test "writes file content", %{approve: ctx} do
      path = Path.join(@tmp_dir, "eng_test_write.txt")

      assert {:ok, result} =
               FileWrite.run(%{path: path, content: "new content", repo_path: @tmp_dir}, ctx)

      assert result.written == true
      assert result.bytes == 11
      assert File.read!(path) == "new content"

      File.rm(path)
    end

    test "creates parent directories", %{approve: ctx} do
      dir = Path.join(@tmp_dir, "eng_test_nested_write")
      path = Path.join(dir, "sub/deep/file.txt")

      assert {:ok, _} = FileWrite.run(%{path: path, content: "deep", repo_path: @tmp_dir}, ctx)
      assert File.read!(path) == "deep"

      File.rm_rf(dir)
    end

    test "resolves relative paths against repo_path", %{approve: ctx} do
      path = Path.join(@tmp_dir, "eng_rel_write.txt")

      assert {:ok, result} =
               FileWrite.run(
                 %{path: "eng_rel_write.txt", content: "rel", repo_path: @tmp_dir},
                 ctx
               )

      assert result.path == path
      assert File.read!(path) == "rel"

      File.rm(path)
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}
      path = Path.join(@tmp_dir, "eng_test_reject_write.txt")

      assert {:error, msg} =
               FileWrite.run(%{path: path, content: "nope", repo_path: @tmp_dir}, reject)

      assert msg =~ "Rejected by governance gate"
      refute File.exists?(path)
    end
  end
end
