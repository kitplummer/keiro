defmodule Keiro.ToolRegistryTest do
  use ExUnit.Case, async: true

  alias Keiro.ToolRegistry

  setup do
    {:ok, pid} = ToolRegistry.start_link(name: :"registry_#{inspect(self())}")
    {:ok, registry: pid}
  end

  describe "register/3" do
    test "registers a tool under a category", %{registry: reg} do
      assert :ok = ToolRegistry.register(:eng, SomeTool, reg)
      assert [SomeTool] = ToolRegistry.tools(:eng, reg)
    end

    test "does not duplicate tools", %{registry: reg} do
      ToolRegistry.register(:eng, SomeTool, reg)
      ToolRegistry.register(:eng, SomeTool, reg)
      assert [SomeTool] = ToolRegistry.tools(:eng, reg)
    end

    test "maintains insertion order", %{registry: reg} do
      ToolRegistry.register(:eng, ToolA, reg)
      ToolRegistry.register(:eng, ToolB, reg)
      ToolRegistry.register(:eng, ToolC, reg)
      assert [ToolA, ToolB, ToolC] = ToolRegistry.tools(:eng, reg)
    end
  end

  describe "register_all/3" do
    test "registers multiple tools at once", %{registry: reg} do
      ToolRegistry.register_all(:ops, [ToolX, ToolY, ToolZ], reg)
      assert [ToolX, ToolY, ToolZ] = ToolRegistry.tools(:ops, reg)
    end

    test "skips already registered tools", %{registry: reg} do
      ToolRegistry.register(:ops, ToolX, reg)
      ToolRegistry.register_all(:ops, [ToolX, ToolY], reg)
      assert [ToolX, ToolY] = ToolRegistry.tools(:ops, reg)
    end
  end

  describe "tools/2" do
    test "returns empty list for unknown category", %{registry: reg} do
      assert [] = ToolRegistry.tools(:unknown, reg)
    end
  end

  describe "all/1" do
    test "returns all tools across categories", %{registry: reg} do
      ToolRegistry.register(:eng, ToolA, reg)
      ToolRegistry.register(:ops, ToolB, reg)
      all = ToolRegistry.all(reg)
      assert ToolA in all
      assert ToolB in all
    end

    test "deduplicates tools registered in multiple categories", %{registry: reg} do
      ToolRegistry.register(:eng, SharedTool, reg)
      ToolRegistry.register(:ops, SharedTool, reg)
      all = ToolRegistry.all(reg)
      assert Enum.count(all, &(&1 == SharedTool)) == 1
    end

    test "returns empty list when nothing registered", %{registry: reg} do
      assert [] = ToolRegistry.all(reg)
    end
  end

  describe "categories/1" do
    test "returns all registered categories", %{registry: reg} do
      ToolRegistry.register(:eng, ToolA, reg)
      ToolRegistry.register(:ops, ToolB, reg)
      ToolRegistry.register(:arch, ToolC, reg)
      cats = ToolRegistry.categories(reg)
      assert :eng in cats
      assert :ops in cats
      assert :arch in cats
    end
  end

  describe "unregister/3" do
    test "removes a tool from a category", %{registry: reg} do
      ToolRegistry.register(:eng, ToolA, reg)
      ToolRegistry.register(:eng, ToolB, reg)
      ToolRegistry.unregister(:eng, ToolA, reg)
      assert [ToolB] = ToolRegistry.tools(:eng, reg)
    end

    test "no-op for unregistered tool", %{registry: reg} do
      assert :ok = ToolRegistry.unregister(:eng, NonExistent, reg)
    end
  end

  describe "start_link/1" do
    test "accepts initial tools via :tools option" do
      {:ok, pid} =
        ToolRegistry.start_link(
          name: :"init_registry_#{inspect(self())}",
          tools: %{eng: [ToolA], ops: [ToolB]}
        )

      assert [ToolA] = ToolRegistry.tools(:eng, pid)
      assert [ToolB] = ToolRegistry.tools(:ops, pid)
    end
  end
end
