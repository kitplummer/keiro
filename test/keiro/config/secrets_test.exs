defmodule Keiro.Config.SecretsTest do
  use ExUnit.Case, async: true

  alias Keiro.Config.Secrets

  describe "get/2" do
    test "returns nil for unknown key with no env fallback" do
      assert is_nil(Secrets.get(:nonexistent_key_xyz_test))
    end

    test "returns default when key not found" do
      assert Secrets.get(:nonexistent_key_xyz_test, "fallback") == "fallback"
    end

    test "reads from env var as fallback" do
      System.put_env("TEST_SECRET_KEY_XYZ", "from_env")
      assert Secrets.get(:test_secret_key_xyz) == "from_env"
      System.delete_env("TEST_SECRET_KEY_XYZ")
    end
  end

  describe "path/0" do
    test "returns expanded path" do
      path = Secrets.path()
      assert String.ends_with?(path, ".config/keiro/secrets.yaml")
      refute String.contains?(path, "~")
    end
  end
end
