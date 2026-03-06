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
end
