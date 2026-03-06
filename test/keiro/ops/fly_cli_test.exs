defmodule Keiro.Ops.FlyCliTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.FlyCli

  @mock_fly Path.expand("../../support/mock_fly.sh", __DIR__)

  describe "run/3" do
    test "runs fly command and returns stdout" do
      assert {:ok, output} = FlyCli.run(@mock_fly, ["status", "--app", "test", "--json"])
      assert output =~ "lowendinsight"
    end

    test "returns error for unknown commands" do
      assert {:error, output} = FlyCli.run(@mock_fly, ["bogus"])
      assert output =~ "Unknown fly command"
    end

    test "returns error when binary not found" do
      assert {:error, "fly CLI not found:" <> _} = FlyCli.run("/no/such/fly", ["status"])
    end
  end

  describe "fly_path/0" do
    test "returns a string path" do
      assert is_binary(FlyCli.fly_path())
    end
  end
end
