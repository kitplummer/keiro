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

  @doc """
  Check governance approval from within an action's run/2.

  Extracts `approve_fn` from the action context map (for testing) or
  falls back to the interactive terminal prompt.

  Returns `{:ok, :approved}` or `{:error, "Rejected: ..."}`.
  """
  @spec require(String.t(), map()) :: {:ok, :approved} | {:error, String.t()}
  def require(description, context \\ %{}) do
    approve_fn = Map.get(context, :approve_fn, &default_prompt/1)

    case approve_fn.(description) do
      :approved -> {:ok, :approved}
      :rejected -> {:error, "Rejected by governance gate: #{description}"}
    end
  end

  defp default_prompt(description) do
    IO.puts("\n--- APPROVAL REQUIRED ---")
    IO.puts("Action: #{description}")

    case IO.gets("Approve? [y/N] ") do
      result when result in [nil, :eof] ->
        IO.puts("No interactive terminal — rejecting")
        :rejected

      response when is_binary(response) ->
        normalized = response |> String.trim() |> String.downcase()

        if normalized in ["y", "yes"] do
          :approved
        else
          :rejected
        end
    end
  end
end
