defmodule Keiro.Eng.Actions.FileReadTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.Actions.FileRead

  @tmp_dir System.tmp_dir!()

  describe "run/2" do
    test "reads an existing file" do
      path = Path.join(@tmp_dir, "eng_test_read.txt")
      File.write!(path, "hello world")

      assert {:ok, result} = FileRead.run(%{path: path, repo_path: @tmp_dir}, %{})
      assert result.content == "hello world"
      assert result.bytes == 11
      assert result.path == path

      File.rm(path)
    end

    test "resolves relative paths against repo_path" do
      path = Path.join(@tmp_dir, "eng_relative_read.txt")
      File.write!(path, "relative content")

      assert {:ok, result} =
               FileRead.run(%{path: "eng_relative_read.txt", repo_path: @tmp_dir}, %{})

      assert result.content == "relative content"

      File.rm(path)
    end

    test "returns error for missing file" do
      assert {:error, msg} = FileRead.run(%{path: "/no/such/file.txt", repo_path: @tmp_dir}, %{})
      assert msg =~ "Cannot read"
    end
  end
end
