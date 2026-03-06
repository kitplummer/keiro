defmodule Keiro.Arch.ArchitectAgentTest do
  use ExUnit.Case, async: true

  alias Keiro.Arch.ArchitectAgent

  describe "module definition" do
    test "defines agent name" do
      agent = ArchitectAgent.new()
      assert agent.name == "architect"
    end

    test "agent has correct description" do
      agent = ArchitectAgent.new()
      assert agent.description =~ "Architect agent"
    end

    test "agent has arch tags" do
      agent = ArchitectAgent.new()
      assert "arch" in agent.tags
      assert "triage" in agent.tags
    end

    test "defines ask and ask_sync functions" do
      Code.ensure_loaded!(ArchitectAgent)
      assert {:ask, 2} in ArchitectAgent.__info__(:functions)
      assert {:ask_sync, 2} in ArchitectAgent.__info__(:functions)
    end

    test "agent state includes model" do
      agent = ArchitectAgent.new()
      assert agent.state.model == :capable
    end
  end
end
