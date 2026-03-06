defmodule Mix.Tasks.Keiro.RunTest do
  use ExUnit.Case, async: true

  describe "mix keiro.run" do
    test "module exists and has run/1" do
      Code.ensure_loaded!(Mix.Tasks.Keiro.Run)
      assert function_exported?(Mix.Tasks.Keiro.Run, :run, 1)
    end

    test "has shortdoc" do
      Code.ensure_loaded!(Mix.Tasks.Keiro.Run)

      assert Mix.Tasks.Keiro.Run.__info__(:attributes)[:shortdoc] == [
               "Run the Keiro orchestrator"
             ]
    end

    test "has moduledoc" do
      Code.ensure_loaded!(Mix.Tasks.Keiro.Run)
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Mix.Tasks.Keiro.Run)
      assert moduledoc =~ "Run the Keiro orchestrator"
    end
  end
end
