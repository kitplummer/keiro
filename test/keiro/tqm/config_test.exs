defmodule Keiro.TQM.ConfigTest do
  use ExUnit.Case, async: true

  alias Keiro.TQM.Config

  describe "new/1" do
    test "returns defaults" do
      config = Config.new()
      assert config.stage_failure_threshold == 3
      assert config.model_error_threshold == 3
      assert config.restart_intensity_max == 5
      assert config.restart_intensity_window_ms == 300_000
      assert config.auto_create_beads == false
      assert config.labels == ["tqm", "auto-generated"]
    end

    test "accepts overrides" do
      config = Config.new(stage_failure_threshold: 5, auto_create_beads: true)
      assert config.stage_failure_threshold == 5
      assert config.auto_create_beads == true
    end
  end
end
