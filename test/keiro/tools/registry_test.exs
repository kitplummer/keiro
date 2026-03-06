defmodule Keiro.Tools.RegistryTest do
  use ExUnit.Case, async: true

  alias Keiro.Tools.Registry

  describe "new/0" do
    test "creates empty registry" do
      registry = Registry.new()
      assert Registry.count(registry) == 0
      assert Registry.all(registry) == []
    end
  end

  describe "register/4" do
    test "adds a tool entry" do
      registry =
        Registry.new()
        |> Registry.register("eng", FakeToolA, tags: ["fs", "read"], description: "Read files")

      assert Registry.count(registry) == 1
      [entry] = Registry.all(registry)
      assert entry.domain == "eng"
      assert entry.module == FakeToolA
      assert entry.tags == ["fs", "read"]
      assert entry.description == "Read files"
    end

    test "register multiple tools" do
      registry =
        Registry.new()
        |> Registry.register("eng", FakeToolA)
        |> Registry.register("eng", FakeToolB)
        |> Registry.register("ops", FakeToolC)

      assert Registry.count(registry) == 3
    end
  end

  describe "for_domain/2" do
    test "returns modules for matching domain" do
      registry =
        Registry.new()
        |> Registry.register("eng", FakeToolA)
        |> Registry.register("eng", FakeToolB)
        |> Registry.register("ops", FakeToolC)

      assert Registry.for_domain(registry, "eng") == [FakeToolA, FakeToolB]
      assert Registry.for_domain(registry, "ops") == [FakeToolC]
    end

    test "returns empty for unknown domain" do
      registry = Registry.new() |> Registry.register("eng", FakeToolA)
      assert Registry.for_domain(registry, "unknown") == []
    end
  end

  describe "for_tags/2" do
    test "returns modules matching any tag" do
      registry =
        Registry.new()
        |> Registry.register("eng", FakeToolA, tags: ["fs", "read"])
        |> Registry.register("eng", FakeToolB, tags: ["fs", "write"])
        |> Registry.register("ops", FakeToolC, tags: ["fly", "status"])

      assert Registry.for_tags(registry, ["read"]) == [FakeToolA]
      assert Registry.for_tags(registry, ["fs"]) == [FakeToolA, FakeToolB]
      assert Registry.for_tags(registry, ["fly", "read"]) == [FakeToolA, FakeToolC]
    end

    test "returns empty for no matching tags" do
      registry = Registry.new() |> Registry.register("eng", FakeToolA, tags: ["fs"])
      assert Registry.for_tags(registry, ["git"]) == []
    end
  end

  describe "domains/1" do
    test "returns unique domains" do
      registry =
        Registry.new()
        |> Registry.register("eng", FakeToolA)
        |> Registry.register("eng", FakeToolB)
        |> Registry.register("ops", FakeToolC)

      assert Enum.sort(Registry.domains(registry)) == ["eng", "ops"]
    end
  end

  describe "defaults/0" do
    test "pre-loads eng, ops, and beads tools" do
      registry = Registry.defaults()
      assert Registry.count(registry) > 0
      domains = Registry.domains(registry)
      assert "eng" in domains
      assert "ops" in domains
      assert "beads" in domains
    end

    test "eng domain has filesystem and git tools" do
      registry = Registry.defaults()
      eng_tools = Registry.for_domain(registry, "eng")
      assert Keiro.Eng.Actions.FileRead in eng_tools
      assert Keiro.Eng.Actions.GitCommit in eng_tools
    end

    test "ops domain has fly tools" do
      registry = Registry.defaults()
      ops_tools = Registry.for_domain(registry, "ops")
      assert Keiro.Ops.Actions.FlyStatus in ops_tools
      assert Keiro.Ops.Actions.FlySmokeTest in ops_tools
    end

    test "tag-based queries work on defaults" do
      registry = Registry.defaults()
      git_tools = Registry.for_tags(registry, ["git"])
      assert length(git_tools) >= 3
    end
  end
end
