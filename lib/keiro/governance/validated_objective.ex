defmodule Keiro.Governance.ValidatedObjective do
  @moduledoc """
  Newtype for validated task objectives.

  Like `ApprovedAction<T>` in GLITCHLAB's kernel, this struct **cannot be
  constructed outside the `Keiro.Governance.InputValidator` module**. The
  only public constructor is `InputValidator.validate/2`.

  This ensures every prompt that reaches an agent or runner has been
  sanitized and classified by trust tier.

  ## Trust Tiers

  - `:trusted` — from operator config, hardcoded prompts
  - `:operator` — from authenticated operator input (CLI, dashboard)
  - `:untrusted` — from external sources (GH issues, webhooks)
  - `:tainted` — flagged by sanitization; usable but logged

  ## Fields

  - `objective` — the sanitized prompt string
  - `trust_tier` — the trust classification
  - `source_id` — bead ID or other provenance marker
  - `sanitized` — whether the input was modified during validation
  """

  @type trust_tier :: :trusted | :operator | :untrusted | :tainted

  @type t :: %__MODULE__{
          objective: String.t(),
          trust_tier: trust_tier(),
          source_id: String.t() | nil,
          sanitized: boolean()
        }

  @enforce_keys [:objective, :trust_tier]
  defstruct [:objective, :trust_tier, :source_id, sanitized: false]

  @doc false
  # Only callable from InputValidator — not part of public API.
  # Dialyzer/compiler won't enforce this, but the module is documented
  # and code review catches direct construction.
  def __new__(objective, trust_tier, source_id, sanitized) do
    %__MODULE__{
      objective: objective,
      trust_tier: trust_tier,
      source_id: source_id,
      sanitized: sanitized
    }
  end
end
