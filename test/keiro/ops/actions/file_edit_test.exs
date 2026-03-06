defmodule Keiro.Ops.Actions.FileEditTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.Actions.FileEdit

  @tmp_dir System.tmp_dir!()

  setup do
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "SRE scope enforcement" do
    test "allows Dockerfile edit", %{approve: ctx} do
      path = Path.join(@tmp_dir, "test_Dockerfile")
      assert {:ok, result} = FileEdit.run(%{path: path, content: "FROM elixir:1.17"}, ctx)
      assert result.written == true
      assert File.read!(path) == "FROM elixir:1.17"
      File.rm(path)
    end

    test "allows fly.toml edit", %{approve: ctx} do
      path = Path.join(@tmp_dir, "fly.toml")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "[env]"}, ctx)
      File.rm(path)
    end

    test "allows env.sh.eex edit", %{approve: ctx} do
      dir = Path.join(@tmp_dir, "rel")
      path = Path.join(dir, "env.sh.eex")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "#!/bin/sh"}, ctx)
      File.rm_rf(dir)
    end

    test "allows application.ex edit", %{approve: ctx} do
      path = Path.join(@tmp_dir, "application.ex")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "defmodule App do end"}, ctx)
      File.rm(path)
    end

    test "allows config/runtime.exs edit", %{approve: ctx} do
      dir = Path.join(@tmp_dir, "config")
      path = Path.join(dir, "runtime.exs")
      assert {:ok, _} = FileEdit.run(%{path: path, content: "import Config"}, ctx)
      File.rm_rf(dir)
    end

    test "rejects business logic files", %{approve: ctx} do
      assert {:error, msg} = FileEdit.run(%{path: "/app/lib/my_app/router.ex", content: "x"}, ctx)
      assert msg =~ "outside SRE scope"
    end

    test "rejects test files", %{approve: ctx} do
      assert {:error, msg} = FileEdit.run(%{path: "/app/test/my_test.exs", content: "x"}, ctx)
      assert msg =~ "outside SRE scope"
    end

    test "rejects lib domain files", %{approve: ctx} do
      assert {:error, msg} =
               FileEdit.run(%{path: "/app/lib/web/controllers/page.ex", content: "x"}, ctx)

      assert msg =~ "outside SRE scope"
    end
  end

  describe "governance gate" do
    test "rejects when governance gate rejects" do
      path = Path.join(@tmp_dir, "test_Dockerfile_reject")
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} = FileEdit.run(%{path: path, content: "FROM elixir"}, reject)
      assert msg =~ "Rejected by governance gate"
      refute File.exists?(path)
    end
  end
end
