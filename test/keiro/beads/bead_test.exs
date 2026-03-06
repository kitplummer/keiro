defmodule Keiro.Beads.BeadTest do
  use ExUnit.Case, async: true

  alias Keiro.Beads.Bead

  describe "from_map/1" do
    test "parses a complete bead map" do
      map = %{
        "id" => "gl-001",
        "title" => "Fix crash",
        "description" => "Redis TLS issue",
        "status" => "open",
        "priority" => 0,
        "type" => "bug",
        "labels" => ["ops", "lei"],
        "dependencies" => [%{"target_id" => "gl-000", "dep_type" => "blocks"}],
        "external_ref" => "GH-42",
        "assignee" => "uplink",
        "created_at" => "2026-03-05T10:00:00Z"
      }

      bead = Bead.from_map(map)
      assert %Bead{} = bead
      assert bead.id == "gl-001"
      assert bead.title == "Fix crash"
      assert bead.description == "Redis TLS issue"
      assert bead.status == "open"
      assert bead.priority == 0
      assert bead.issue_type == "bug"
      assert bead.labels == ["ops", "lei"]
      assert bead.dependencies == [%{"target_id" => "gl-000", "dep_type" => "blocks"}]
      assert bead.external_ref == "GH-42"
      assert bead.assignee == "uplink"
      assert bead.created_at == "2026-03-05T10:00:00Z"
    end

    test "handles missing optional fields" do
      bead = Bead.from_map(%{"id" => "gl-002", "title" => "Minimal"})
      assert bead.id == "gl-002"
      assert bead.title == "Minimal"
      assert bead.labels == []
      assert bead.dependencies == []
      assert bead.description == nil
    end

    test "prefers issue_type over type" do
      bead = Bead.from_map(%{"issue_type" => "feature", "type" => "bug"})
      assert bead.issue_type == "feature"
    end

    test "falls back to type when issue_type is nil" do
      bead = Bead.from_map(%{"type" => "bug"})
      assert bead.issue_type == "bug"
    end
  end
end
