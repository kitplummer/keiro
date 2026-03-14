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

    test "finds ADR files in docs/adr/ subdirectory" do
      tmp = Path.join(System.tmp_dir!(), "lei_adr_test_#{:erlang.unique_integer([:positive])}")
      adr_dir = Path.join(tmp, "docs/adr")
      File.mkdir_p!(adr_dir)
      File.write!(Path.join(adr_dir, "ADR-001-test.md"), "# ADR")
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:ok, result} = ListAdrFiles.run(%{repo_path: tmp}, %{})
      assert result.count == 1
      assert hd(result.files) =~ "ADR-001-test.md"
    end

    test "finds both lowercase and uppercase ADR files across locations" do
      tmp = Path.join(System.tmp_dir!(), "lei_adr_multi_#{:erlang.unique_integer([:positive])}")
      docs_dir = Path.join(tmp, "docs")
      adr_dir = Path.join(tmp, "docs/adr")
      File.mkdir_p!(adr_dir)
      File.write!(Path.join(docs_dir, "adr-legacy.md"), "# old")
      File.write!(Path.join(adr_dir, "ADR-001-new.md"), "# new")
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:ok, result} = ListAdrFiles.run(%{repo_path: tmp}, %{})
      assert result.count == 2
      assert Enum.any?(result.files, &String.contains?(&1, "adr-legacy.md"))
      assert Enum.any?(result.files, &String.contains?(&1, "ADR-001-new.md"))
    end

    test "deduplicates files that match both patterns" do
      tmp = Path.join(System.tmp_dir!(), "lei_adr_dedup_#{:erlang.unique_integer([:positive])}")
      docs_dir = Path.join(tmp, "docs")
      File.mkdir_p!(docs_dir)
      File.write!(Path.join(docs_dir, "adr-001.md"), "# ADR")
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:ok, result} = ListAdrFiles.run(%{repo_path: tmp}, %{})
      assert result.count == 1
    end
  end
end
