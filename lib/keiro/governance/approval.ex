defmodule Keiro.Governance.Approval do
  @moduledoc """
  Human-in-the-loop approval gate for mutating actions.

  For Phase 0: all mutating actions (deploy, config change) require
  interactive terminal approval. Later phases will support webhook,
  Slack, or signal-based approval.

  ## Usage

      case Keiro.Governance.Approval.gate("Deploy lowendinsight to fly.io") do
        :approved -> # proceed
        :rejected -> # abort
      end
  """

  @type decision :: :approved | :rejected

  @doc """
  Present an approval prompt and block until the human responds.

  Returns `:approved` if the user confirms, `:rejected` otherwise.
  The `approve_fn` option allows injecting a custom approval function
  for testing (default: interactive IO.gets prompt).
  """
  @spec gate(String.t(), keyword()) :: decision()
  def gate(action_description, opts \\ []) do
    approve_fn = Keyword.get(opts, :approve_fn, &default_prompt/1)
    approve_fn.(action_description)
  end

  defp default_prompt(description) do
    IO.puts("\n--- APPROVAL REQUIRED ---")
    IO.puts("Action: #{description}")
    response = IO.gets("Approve? [y/N] ") |> String.trim() |> String.downcase()

    if response in ["y", "yes"] do
      :approved
    else
      :rejected
    end
  end
end
