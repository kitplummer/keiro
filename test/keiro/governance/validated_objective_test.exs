defmodule Keiro.Governance.ValidatedObjectiveTest do
  use ExUnit.Case, async: true

  alias Keiro.Governance.ValidatedObjective

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(ValidatedObjective, [])
      end
    end

    test "requires objective and trust_tier" do
      vo = %ValidatedObjective{objective: "test", trust_tier: :trusted}
      assert vo.objective == "test"
      assert vo.trust_tier == :trusted
      assert vo.source_id == nil
      assert vo.sanitized == false
    end
  end

  describe "__new__/4" do
    test "constructs a validated objective" do
      vo = ValidatedObjective.__new__("fix bug", :operator, "gl-001", false)
      assert vo.objective == "fix bug"
      assert vo.trust_tier == :operator
      assert vo.source_id == "gl-001"
      assert vo.sanitized == false
    end

    test "marks sanitized when true" do
      vo = ValidatedObjective.__new__("cleaned", :tainted, "gl-002", true)
      assert vo.sanitized == true
      assert vo.trust_tier == :tainted
    end
  end
end
