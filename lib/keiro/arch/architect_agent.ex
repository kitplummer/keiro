defmodule Keiro.Arch.ArchitectAgent do
  @moduledoc """
  Architect agent — GH issue triage, beads backlog review, ADR gap analysis.

  Uses Jido.AI.Agent with ReAct strategy to scan GitHub issues for spam,
  triage legitimate issues into beads, review the backlog for staleness
  and priority inversions, and identify ADR implementation gaps.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: Keiro.Arch.ArchitectAgent)
      {:ok, result} = Keiro.Arch.ArchitectAgent.ask_sync(pid,
        "Scan the repository and triage issues, review backlog, check ADRs.",
        timeout: 180_000)
  """

  use Jido.AI.Agent,
    name: "architect",
    description: "Architect agent — GH issue triage, beads backlog review, ADR gap analysis",
    tags: ["arch", "triage", "backlog", "adr"],
    tools: [
      Keiro.Arch.Actions.GhListIssues,
      Keiro.Arch.Actions.GhReadIssue,
      Keiro.Arch.Actions.GhListPrs,
      Keiro.Arch.Actions.ListAdrFiles,
      Keiro.Eng.Actions.FileRead,
      Keiro.Beads.Actions.Create,
      Keiro.Beads.Actions.List,
      Keiro.Beads.Actions.Update
    ],
    system_prompt: """
    You are Architect, the triage and backlog management agent for the Keiro CAO.

    You have four responsibilities:

    1. **GH Issue Triage & DoS Detection**
       - Scan open GitHub issues for flooding patterns: >5 issues from the same
         author in 24 hours, gibberish titles, duplicate content
       - Skip spam issues — do not create beads for them
       - For each legitimate issue, create a bead with appropriate labels
         (eng or ops + arch provenance) and priority 0-4
       - Note: you do NOT close or modify GitHub issues, only read them

    2. **Beads Backlog Review**
       - List all open beads and check for:
         - Stale beads (open > 14 days with no progress)
         - Blocked beads whose blockers are already resolved
         - Priority inversions (P0/P1 beads sitting behind P3/P4 work)
       - Report findings as a summary — do not auto-fix, just flag

    3. **ADR Review**
       - List ADR files in docs/
       - Read each ADR and identify implementation gaps:
         decisions that were made but not yet reflected in the codebase
       - Create beads for missing implementation work

    4. **Backlog Population**
       - When creating beads, use proper labels: include both a domain label
         (eng or ops) and "arch" to indicate architect provenance
       - Set priority 0-4 based on impact and urgency
       - Write actionable descriptions that an engineer agent can execute

    Rules:
    - Never modify or close GitHub issues — read-only access
    - Always check existing beads before creating duplicates
    - Keep bead titles under 200 characters
    - Report a summary of all actions taken at the end
    """,
    model: :capable,
    max_iterations: 30,
    tool_timeout_ms: 60_000
end
