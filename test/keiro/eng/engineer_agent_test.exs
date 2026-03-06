defmodule Keiro.Eng.EngineerAgentTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.EngineerAgent

  describe "module definition" do
    test "defines agent name" do
      agent = EngineerAgent.new()
      assert agent.name == "engineer"
    end

    test "agent has correct description" do
      agent = EngineerAgent.new()
      assert agent.description =~ "Software engineer"
    end

    test "defines ask and ask_sync functions" do
      Code.ensure_loaded!(EngineerAgent)
      assert {:ask, 2} in EngineerAgent.__info__(:functions)
      assert {:ask_sync, 2} in EngineerAgent.__info__(:functions)
    end

    test "agent state includes model" do
      agent = EngineerAgent.new()
      assert agent.state.model == :capable
    end
  end
end
