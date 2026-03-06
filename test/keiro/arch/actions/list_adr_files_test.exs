defmodule Keiro.Arch.Actions.ListAdrFilesTest do
  use ExUnit.Case, async: true

  alias Keiro.Arch.Actions.ListAdrFiles

  describe "run/2" do
    test "lists ADR files from repository docs/" do
      # Use the actual keiro repo which has docs/adr-*.md files
      repo_path = Path.expand("../../../../", __DIR__)

      assert {:ok, result} = ListAdrFiles.run(%{repo_path: repo_path}, %{})
      assert is_list(result.files)
      assert result.count == length(result.files)

      # All returned files should match the adr-*.md pattern
      Enum.each(result.files, fn file ->
        assert String.contains?(file, "adr-")
        assert String.ends_with?(file, ".md")
      end)
    end

    test "returns empty list for missing docs directory" do
      assert {:ok, result} = ListAdrFiles.run(%{repo_path: "/tmp/nonexistent"}, %{})
      assert result.files == []
      assert result.count == 0
    end

    test "supports custom glob pattern" do
      assert {:ok, result} =
               ListAdrFiles.run(%{repo_path: "/tmp/nonexistent", pattern: "*.txt"}, %{})

      assert result.files == []
      assert result.count == 0
    end
  end
end
