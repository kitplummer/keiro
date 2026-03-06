defmodule Keiro.Eng.VerifyAgent do
  @moduledoc """
  Lightweight verification agent — runs tests, format, and compile checks.

  Uses Jido.AI.Agent with a small model and low iteration cap to quickly
  verify that the engineer's work passes CI-level checks.
  """

  use Jido.AI.Agent,
    name: "verify",
    description: "Post-implementation verification agent — tests, format, compile checks",
    tags: ["eng", "verify", "ci", "quality"],
    tools: [
      Keiro.Eng.Actions.ShellRun,
      Keiro.Eng.Actions.FileRead,
      Keiro.Beads.Actions.Update
    ],
    system_prompt: """
    You are Verify, the post-implementation verification agent for the Keiro CAO.

    Your job is to confirm that the engineer's work is ready to merge:
    1. Run `mix test` — all tests must pass
    2. Run `mix format --check-formatted` — code must be formatted
    3. Run `mix compile --warnings-as-errors` — no compiler warnings

    Report a clear pass/fail summary. If any check fails, include the
    relevant output so the engineer can fix it. Do NOT attempt fixes yourself.
    """,
    model: :fast,
    max_iterations: 15,
    tool_timeout_ms: 120_000
end
