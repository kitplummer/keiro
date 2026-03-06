defmodule Keiro.Ops.Actions.FlySmokeTestTest do
  use ExUnit.Case, async: true

  alias Keiro.Ops.Actions.FlySmokeTest

  test "reports unhealthy when connection fails" do
    # Use a definitely-unreachable URL
    assert {:ok, result} =
             FlySmokeTest.run(%{url: "http://127.0.0.1:1", expected_status: 200}, %{})

    assert result.healthy == false
    assert result.status_code == nil
    assert is_binary(result.error)
  end
end
