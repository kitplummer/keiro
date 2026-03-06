defmodule Keiro.Failure.ObstacleKindTest do
  use ExUnit.Case, async: true

  alias Keiro.Failure.ObstacleKind

  describe "constructors" do
    test "missing_prerequisite" do
      obstacle = ObstacleKind.missing_prerequisite("gl-042", "Module doesn't exist")
      assert {:missing_prerequisite, opts} = obstacle
      assert opts[:task_id] == "gl-042"
      assert opts[:reason] == "Module doesn't exist"
    end

    test "architectural_gap" do
      obstacle = ObstacleKind.architectural_gap("No plugin system")
      assert {:architectural_gap, opts} = obstacle
      assert opts[:description] == "No plugin system"
    end

    test "model_limitation" do
      obstacle = ObstacleKind.model_limitation("gemini-flash", "parse_error")
      assert {:model_limitation, opts} = obstacle
      assert opts[:model] == "gemini-flash"
      assert opts[:error_class] == "parse_error"
    end

    test "external_dependency" do
      obstacle = ObstacleKind.external_dependency("fly.io")
      assert {:external_dependency, opts} = obstacle
      assert opts[:service] == "fly.io"
    end

    test "scope_too_large" do
      obstacle = ObstacleKind.scope_too_large(15, 5)
      assert {:scope_too_large, opts} = obstacle
      assert opts[:estimated_files] == 15
      assert opts[:max_files] == 5
    end

    test "unknown" do
      obstacle = ObstacleKind.unknown("something weird")
      assert {:unknown, opts} = obstacle
      assert opts[:reason] == "something weird"
    end
  end

  describe "kind/1" do
    test "extracts kind atom" do
      assert ObstacleKind.kind(ObstacleKind.missing_prerequisite("x", "y")) ==
               :missing_prerequisite

      assert ObstacleKind.kind(ObstacleKind.model_limitation("m", "e")) == :model_limitation
      assert ObstacleKind.kind(ObstacleKind.unknown("r")) == :unknown
    end
  end
end
