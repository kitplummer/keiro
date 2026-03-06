defmodule Keiro.Ops.UplinkAgentTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.UplinkAgent

  describe "module definition" do
    test "defines agent name" do
      agent = UplinkAgent.new()
      assert agent.name == "uplink"
    end

    test "agent has correct description" do
      agent = UplinkAgent.new()
      assert agent.description =~ "SRE agent"
    end

    test "defines ask and ask_sync functions" do
      Code.ensure_loaded!(UplinkAgent)
      assert {:ask, 2} in UplinkAgent.__info__(:functions)
      assert {:ask_sync, 2} in UplinkAgent.__info__(:functions)
    end

    test "agent state includes model" do
      agent = UplinkAgent.new()
      assert agent.state.model == :capable
    end
  end
end
