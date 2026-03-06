defmodule Keiro.Eng.Shape do
  @moduledoc """
  Pipeline shape for engineering beads.

  Matches beads with the "eng" label and returns a two-stage pipeline:
  engineer (implement) → verify (CI checks).
  """

  @behaviour Keiro.Pipeline.Shape

  alias Keiro.Pipeline.Stage

  @impl true
  def match?(bead) do
    "eng" in (bead.labels || [])
  end

  @impl true
  def stages(_bead, opts) do
    timeout = Keyword.get(opts, :timeout, 120_000)

    [
      %Stage{
        name: "engineer",
        agent_module: Keiro.Eng.EngineerAgent,
        prompt_fn: &eng_prompt/2,
        timeout: timeout
      },
      %Stage{
        name: "verify",
        agent_module: Keiro.Eng.VerifyAgent,
        prompt_fn: &verify_prompt/2,
        timeout: timeout
      }
    ]
  end

  defp eng_prompt(bead, _prev_stages) do
    """
    Bead #{bead.id}: #{bead.title}

    #{bead.description || "No description."}

    Implement this task: create a branch, write the code, run tests, and open a PR.
    """
  end

  defp verify_prompt(bead, prev_stages) do
    eng_result =
      case prev_stages do
        [%{result: result} | _] -> "\n\nEngineer stage result: #{inspect(result)}"
        _ -> ""
      end

    """
    Bead #{bead.id}: #{bead.title}

    The engineer has completed implementation. Run verification checks:
    1. `mix test` — all tests must pass
    2. `mix format --check-formatted` — code must be formatted
    3. `mix compile --warnings-as-errors` — no compiler warnings

    Report pass/fail for each check.#{eng_result}
    """
  end
end
