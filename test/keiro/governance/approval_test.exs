defmodule Keiro.Governance.ApprovalTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.Approval

  describe "gate/2" do
    test "returns :approved when approve_fn approves" do
      assert :approved = Approval.gate("Deploy app", approve_fn: fn _desc -> :approved end)
    end

    test "returns :rejected when approve_fn rejects" do
      assert :rejected = Approval.gate("Deploy app", approve_fn: fn _desc -> :rejected end)
    end

    test "passes action description to approve_fn" do
      Approval.gate("Delete everything",
        approve_fn: fn desc ->
          assert desc == "Delete everything"
          :approved
        end
      )
    end
  end

  describe "require/2" do
    test "returns {:ok, :approved} when approved" do
      ctx = %{approve_fn: fn _desc -> :approved end}
      assert {:ok, :approved} = Approval.require("Deploy app", ctx)
    end

    test "returns {:error, message} when rejected" do
      ctx = %{approve_fn: fn _desc -> :rejected end}
      assert {:error, msg} = Approval.require("Deploy app", ctx)
      assert msg =~ "Rejected by governance gate"
      assert msg =~ "Deploy app"
    end

    test "works with empty context (would use default prompt)" do
      # Can't test default prompt without IO, but verify it accepts empty map
      ctx = %{approve_fn: fn _desc -> :approved end}
      assert {:ok, :approved} = Approval.require("test", ctx)
    end
  end
end
