defmodule Keiro.TQM.PatternTest do
  use ExUnit.Case, async: true

  alias Keiro.TQM.Pattern

  describe "struct" do
    test "creates pattern with required fields" do
      pattern = %Pattern{
        name: "test_pattern",
        severity: :warning,
        count: 3,
        threshold: 2,
        description: "A test pattern",
        remediation: "Fix it"
      }

      assert pattern.name == "test_pattern"
      assert pattern.severity == :warning
      assert pattern.count == 3
      assert pattern.threshold == 2
      assert pattern.evidence == []
    end

    test "accepts evidence list" do
      pattern = %Pattern{
        name: "test",
        severity: :critical,
        count: 1,
        threshold: 1,
        description: "desc",
        remediation: "fix",
        evidence: ["bead k-001", "bead k-002"]
      }

      assert length(pattern.evidence) == 2
    end
  end
end
