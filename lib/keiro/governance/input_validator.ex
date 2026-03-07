defmodule Keiro.Governance.InputValidator do
  @moduledoc """
  Validates and sanitizes raw input before it becomes an agent objective.

  This is the **only** sanctioned constructor for `ValidatedObjective`.
  All bead descriptions and external inputs must pass through `validate/2`
  before reaching an agent or runner.

  ## Trust Tiers

  - `:trusted` — hardcoded/config prompts, no sanitization applied
  - `:operator` — CLI/dashboard input, length-checked
  - `:untrusted` — external sources (GH issues, webhooks), fully sanitized
  - `:tainted` — input that was modified by sanitization; still usable but logged

  ## Sanitization (`:untrusted` tier)

  1. Length capped at `@max_length` (50_000 chars)
  2. Control characters stripped (bytes 0–31 except tab, newline, CR)
  3. Prompt injection patterns neutralized (common jailbreak prefixes)
  4. Excessive whitespace collapsed
  """

  alias Keiro.Governance.ValidatedObjective

  require Logger

  @max_length 50_000
  @max_length_operator 100_000

  @injection_patterns [
    ~r/ignore\s+(the\s+)?(previous|above)\s+instructions/i,
    ~r/override\s+(your\s+)?system/i,
    ~r/you\s+are\s+now\s+(a\s+)?(different|new)/i,
    ~r/pretend\s+(to\s+be|you\s+are)/i,
    ~r/bypass\s+(all\s+)?(safety|filters?|security)/i,
    ~r/(repeat|return|show)\s+your\s+(system\s+)?prompt/i,
    ~r/disregard\s+(all\s+)?(previous|prior|above)/i
  ]

  @doc """
  Validate raw input and produce a `ValidatedObjective`.

  ## Examples

      iex> InputValidator.validate("Fix the login bug", :operator)
      {:ok, %ValidatedObjective{objective: "Fix the login bug", trust_tier: :operator}}

      iex> InputValidator.validate("", :untrusted)
      {:error, :empty_input}
  """
  @spec validate(String.t(), ValidatedObjective.trust_tier(), keyword()) ::
          {:ok, ValidatedObjective.t()} | {:error, atom() | String.t()}
  def validate(raw, trust_tier, opts \\ [])

  def validate(nil, _trust_tier, _opts), do: {:error, :empty_input}
  def validate("", _trust_tier, _opts), do: {:error, :empty_input}

  def validate(raw, :trusted, opts) when is_binary(raw) do
    source_id = Keyword.get(opts, :source_id)
    {:ok, ValidatedObjective.__new__(raw, :trusted, source_id, false)}
  end

  def validate(raw, :operator, opts) when is_binary(raw) do
    source_id = Keyword.get(opts, :source_id)

    if String.length(raw) > @max_length_operator do
      {:error, :input_too_long}
    else
      {:ok, ValidatedObjective.__new__(raw, :operator, source_id, false)}
    end
  end

  def validate(raw, :untrusted, opts) when is_binary(raw) do
    source_id = Keyword.get(opts, :source_id)

    with {:ok, truncated} <- check_length(raw),
         {:ok, cleaned} <- strip_control_chars(truncated),
         {:ok, sanitized, was_modified} <- neutralize_injections(cleaned) do
      collapsed = collapse_whitespace(sanitized)

      any_modified =
        was_modified or collapsed != sanitized or cleaned != truncated or truncated != raw

      tier = if any_modified, do: :tainted, else: :untrusted

      if any_modified do
        Logger.warning("InputValidator: sanitized input from #{source_id || "unknown"}")
      end

      {:ok, ValidatedObjective.__new__(collapsed, tier, source_id, any_modified)}
    end
  end

  def validate(_raw, tier, _opts) when tier not in [:trusted, :operator, :untrusted] do
    {:error, :invalid_trust_tier}
  end

  @doc """
  Validate a bead's title and description as a combined objective.

  Convenience wrapper for the common orchestrator pattern.
  """
  @spec validate_bead(Keiro.Beads.Bead.t(), ValidatedObjective.trust_tier()) ::
          {:ok, ValidatedObjective.t()} | {:error, atom() | String.t()}
  def validate_bead(bead, trust_tier \\ :untrusted) do
    raw = "Bead #{bead.id}: #{bead.title}\n\n#{bead.description || "No description."}"
    validate(raw, trust_tier, source_id: bead.id)
  end

  # -- Private sanitization steps --

  defp check_length(input) do
    if String.length(input) > @max_length do
      {:ok, String.slice(input, 0, @max_length)}
    else
      {:ok, input}
    end
  end

  defp strip_control_chars(input) do
    # Keep tab (9), newline (10), carriage return (13)
    cleaned =
      input
      |> String.to_charlist()
      |> Enum.filter(fn c -> c >= 32 or c in [9, 10, 13] end)
      |> List.to_string()

    {:ok, cleaned}
  end

  defp neutralize_injections(input) do
    {result, modified} =
      Enum.reduce(@injection_patterns, {input, false}, fn pattern, {text, was_modified} ->
        if Regex.match?(pattern, text) do
          neutralized = Regex.replace(pattern, text, "[REDACTED]")
          {neutralized, true}
        else
          {text, was_modified}
        end
      end)

    {:ok, result, modified}
  end

  defp collapse_whitespace(input) do
    input
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end
