defmodule Keiro.Eng.VerifyAgentTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.VerifyAgent

  describe "module definition" do
    test "defines agent name" do
      agent = VerifyAgent.new()
      assert agent.name == "verify"
    end

    test "agent has correct description" do
      agent = VerifyAgent.new()
      assert agent.description =~ "verification"
    end

    test "defines ask and ask_sync functions" do
      Code.ensure_loaded!(VerifyAgent)
      assert {:ask, 2} in VerifyAgent.__info__(:functions)
      assert {:ask_sync, 2} in VerifyAgent.__info__(:functions)
    end

    test "agent uses fast model" do
      agent = VerifyAgent.new()
      assert agent.state.model == :fast
    end
  end
end
