defmodule Keiro.Beads.ClientTest do
  use ExUnit.Case, async: true

  alias Keiro.Beads.{Client, Bead}

  @mock_bd Path.expand("../../support/mock_bd.sh", __DIR__)
  @mock_bd_error Path.expand("../../support/mock_bd_error.sh", __DIR__)
  @repo_path System.tmp_dir!()

  defp client(opts \\ []) do
    bd_path = Keyword.get(opts, :bd_path, @mock_bd)
    Client.new(@repo_path, bd_path: bd_path)
  end

  describe "new/2" do
    test "uses provided bd_path" do
      c = Client.new("/tmp", bd_path: "/custom/bd")
      assert c.bd_path == "/custom/bd"
      assert c.repo_path == "/tmp"
    end

    test "defaults bd_path from application config" do
      c = Client.new("/tmp")
      assert is_binary(c.bd_path)
    end
  end

  describe "check_installed/1" do
    test "returns version string on success" do
      assert {:ok, "bd 0.49.3"} = Client.check_installed(client())
    end

    test "returns error when bd not found" do
      c = client(bd_path: "/nonexistent/bd")
      assert {:error, "bd not found:" <> _} = Client.check_installed(c)
    end
  end

  describe "create/3" do
    test "creates a bead with title" do
      assert {:ok, "gl-001"} = Client.create(client(), "Fix crash-loop")
    end

    test "passes options through" do
      assert {:ok, _} =
               Client.create(client(), "Test bead",
                 id: "gl-test",
                 type: "bug",
                 priority: 0,
                 labels: ["ops", "lei"],
                 description: "A test bead"
               )
    end
  end

  describe "update_status/3" do
    test "updates bead status" do
      assert {:ok, "Updated gl-001"} = Client.update_status(client(), "gl-001", "in_progress")
    end
  end

  describe "close/2" do
    test "closes a bead" do
      assert {:ok, "Closed gl-001"} = Client.close(client(), "gl-001")
    end
  end

  describe "list/2" do
    test "returns parsed beads" do
      assert {:ok, beads} = Client.list(client())
      assert length(beads) == 2
      assert [%Bead{id: "gl-001", title: "Fix crash-loop"} | _] = beads
    end

    test "parses all fields correctly" do
      {:ok, [bead | _]} = Client.list(client())
      assert bead.id == "gl-001"
      assert bead.title == "Fix crash-loop"
      assert bead.status == "open"
      assert bead.priority == 0
      assert bead.labels == ["ops"]
      assert bead.dependencies == []
    end

    test "parses dependencies" do
      {:ok, [_, bead]} = Client.list(client())
      assert [%{"target_id" => "gl-001", "dep_type" => "blocks"}] = bead.dependencies
    end

    test "returns error on failure" do
      assert {:error, _} = Client.list(client(bd_path: @mock_bd_error))
    end
  end

  describe "ready/1" do
    test "returns unblocked beads" do
      assert {:ok, beads} = Client.ready(client())
      assert length(beads) == 1
      assert [%Bead{id: "gl-001", priority: 0}] = beads
    end
  end

  describe "comment/3" do
    test "adds a comment to a bead" do
      assert {:ok, "Comment added"} = Client.comment(client(), "gl-001", "## Outcome: completed")
    end
  end

  describe "link/3" do
    test "returns ok (no-op, bd does not support link)" do
      assert {:ok, _} = Client.link(client(), "gl-002", "gl-001")
    end
  end

  describe "error handling" do
    test "bd returning non-zero exit code" do
      c = client(bd_path: @mock_bd_error)
      assert {:error, _reason} = Client.create(c, "will fail")
    end

    test "bd binary not found" do
      c = client(bd_path: "/no/such/binary")
      assert {:error, "bd not found:" <> _} = Client.check_installed(c)
    end
  end
end
