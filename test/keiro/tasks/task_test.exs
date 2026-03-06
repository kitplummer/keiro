defmodule Keiro.Tasks.TaskTest do
  use ExUnit.Case, async: true

  alias Keiro.Tasks.Task
  alias Keiro.Beads.Bead

  describe "struct defaults" do
    test "has sensible defaults" do
      task = %Task{id: "t-001", title: "Test task"}
      assert task.status == :open
      assert task.priority == 2
      assert task.labels == []
      assert task.dependencies == []
      assert task.payload == %{}
      assert task.source == :unknown
    end
  end

  describe "from_bead/1" do
    test "converts a bead to a task" do
      bead = %Bead{
        id: "gl-100",
        title: "Implement widget",
        description: "Build a widget",
        status: "open",
        priority: 1,
        labels: ["eng", "lei"],
        dependencies: []
      }

      task = Task.from_bead(bead)
      assert task.id == "gl-100"
      assert task.title == "Implement widget"
      assert task.description == "Build a widget"
      assert task.status == :open
      assert task.priority == 1
      assert task.labels == ["eng", "lei"]
      assert task.source == :beads
      assert task.payload.bead == bead
    end

    test "maps status strings to atoms" do
      for {str, atom} <- [
            {"open", :open},
            {"in_progress", :in_progress},
            {"blocked", :blocked},
            {"closed", :closed},
            {"deferred", :deferred}
          ] do
        bead = %Bead{id: "gl-s", title: "Status test", status: str}
        assert Task.from_bead(bead).status == atom
      end
    end

    test "defaults unknown status to :open" do
      bead = %Bead{id: "gl-u", title: "Unknown", status: "weird"}
      assert Task.from_bead(bead).status == :open
    end

    test "handles nil fields" do
      bead = %Bead{id: "gl-nil", title: nil, status: nil, priority: nil, labels: nil}
      task = Task.from_bead(bead)
      assert task.title == ""
      assert task.status == :open
      assert task.priority == 2
      assert task.labels == []
    end

    test "extracts dependency IDs from maps" do
      bead = %Bead{
        id: "gl-d",
        title: "Deps",
        dependencies: [%{"id" => "gl-001"}, %{"id" => "gl-002"}]
      }

      task = Task.from_bead(bead)
      assert task.dependencies == ["gl-001", "gl-002"]
    end

    test "extracts dependency IDs from strings" do
      bead = %Bead{id: "gl-d2", title: "Deps", dependencies: ["gl-001", "gl-002"]}
      task = Task.from_bead(bead)
      assert task.dependencies == ["gl-001", "gl-002"]
    end

    test "handles nil dependencies" do
      bead = %Bead{id: "gl-nd", title: "No deps", dependencies: nil}
      assert Task.from_bead(bead).dependencies == []
    end
  end
end
