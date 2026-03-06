defmodule Keiro.TaskTest do
  use ExUnit.Case, async: true

  alias Keiro.Beads.Bead

  describe "Bead implements Keiro.Task" do
    test "id/1 returns bead id" do
      bead = %Bead{id: "gl-001"}
      assert Bead.id(bead) == "gl-001"
    end

    test "title/1 returns bead title" do
      bead = %Bead{title: "Fix crash"}
      assert Bead.title(bead) == "Fix crash"
    end

    test "description/1 returns bead description" do
      bead = %Bead{description: "Some details"}
      assert Bead.description(bead) == "Some details"
    end

    test "status/1 returns bead status" do
      bead = %Bead{status: "open"}
      assert Bead.status(bead) == "open"
    end

    test "priority/1 returns bead priority" do
      bead = %Bead{priority: 1}
      assert Bead.priority(bead) == 1
    end

    test "labels/1 returns bead labels" do
      bead = %Bead{labels: ["eng", "ops"]}
      assert Bead.labels(bead) == ["eng", "ops"]
    end

    test "labels/1 returns empty list for nil labels" do
      bead = %Bead{labels: nil}
      assert Bead.labels(bead) == []
    end
  end
end
