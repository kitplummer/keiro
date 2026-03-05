defmodule KeiroTest do
  use ExUnit.Case
  doctest Keiro

  test "greets the world" do
    assert Keiro.hello() == :world
  end
end
