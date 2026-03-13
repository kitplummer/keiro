defmodule Mix.Tasks.Keiro.ContinuousTest do
  use ExUnit.Case, async: true

  describe "mix keiro.continuous" do
    test "module exists and has run/1" do
      Code.ensure_loaded!(Mix.Tasks.Keiro.Continuous)
      assert function_exported?(Mix.Tasks.Keiro.Continuous, :run, 1)
    end

    test "has shortdoc" do
      Code.ensure_loaded!(Mix.Tasks.Keiro.Continuous)

      assert Mix.Tasks.Keiro.Continuous.__info__(:attributes)[:shortdoc] == [
               "Run the Keiro orchestrator in continuous mode with budget pacing"
             ]
    end

    test "has moduledoc" do
      Code.ensure_loaded!(Mix.Tasks.Keiro.Continuous)

      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} =
        Code.fetch_docs(Mix.Tasks.Keiro.Continuous)

      assert moduledoc =~ "continuous mode"
    end
  end
end
