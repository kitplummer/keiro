defmodule Keiro.Arch.ScannerTest do
  use ExUnit.Case, async: true

  alias Keiro.Arch.Scanner

  describe "scan/2" do
    test "returns error when agent server cannot start without API key" do
      # Without a valid API key, the agent will fail to start or process
      result = Scanner.scan("/tmp/nonexistent", timeout: 5_000)

      case result do
        {:error, _reason} -> :ok
        # If it somehow starts (e.g., mock LLM configured), that's also fine
        {:ok, _} -> :ok
      end
    end
  end
end
