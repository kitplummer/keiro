defmodule Keiro.Ops.Actions.FileEditTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.Actions.FileEdit

  @tmp_dir System.tmp_dir!()

  describe "SRE scope enforcement" do
    test "allows Dockerfile edit" do
      path = Path.join(@tmp_dir, "test_Dockerfile")
      assert {:ok, result} = FileEdit.run(%{path: path, content: "FROM elixir:1.17"}, %{})
      assert result.written == true
      assert File.read!(path) == "FROM elixir:1.17"
      File.rm(path)
    end

    test "allows fly.toml edit" do
      path = Path.join(@tmp_dir, "fly.toml")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "[env]"}, %{})
      File.rm(path)
    end

    test "allows env.sh.eex edit" do
      dir = Path.join(@tmp_dir, "rel")
      path = Path.join(dir, "env.sh.eex")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "#!/bin/sh"}, %{})
      File.rm_rf(dir)
    end

    test "allows application.ex edit" do
      path = Path.join(@tmp_dir, "application.ex")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "defmodule App do end"}, %{})
      File.rm(path)
    end

    test "allows config/runtime.exs edit" do
      dir = Path.join(@tmp_dir, "config")
      path = Path.join(dir, "runtime.exs")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "import Config"}, %{})
      File.rm_rf(dir)
    end

    test "rejects business logic files" do
      assert {:error, msg} = FileEdit.run(%{path: "/app/lib/my_app/router.ex", content: "x"}, %{})
      assert msg =~ "outside SRE scope"
    end

    test "rejects test files" do
      assert {:error, msg} = FileEdit.run(%{path: "/app/test/my_test.exs", content: "x"}, %{})
      assert msg =~ "outside SRE scope"
    end

    test "rejects lib domain files" do
      assert {:error, msg} =
               FileEdit.run(%{path: "/app/lib/web/controllers/page.ex", content: "x"}, %{})

      assert msg =~ "outside SRE scope"
    end
  end
end
