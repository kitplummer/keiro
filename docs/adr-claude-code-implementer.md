# ADR: Claude Code as Implementer Backend

**Date:** 2026-02-28
**Author:** Kit, with Claude analysis
**Status:** Experimental
**Supersedes:** Partial revision of `adr-implementation-strategy-tool-use-vs-api.md`
**Informed by:** Batch runs 1-6 (542 task attempts, 11.5% success rate), canary analysis of failure modes

---

## Context

In February 2026 we decided to build a custom provider-agnostic tool-use loop
for Keiro's implementer agent (see `adr-implementation-strategy-tool-use-vs-api.md`).
The rationale was sound: avoid vendor lock-in, support local models, maintain
governance control over individual tool calls.

Six batch runs of empirical data now show that the custom tool loop has
fundamental quality problems that are not model-dependent:

| Failure mode | Frequency | Root cause |
|---|---|---|
| **Budget exceeded** | 9/15 failures (batch 6) | Naive file reads consume context; each TDD turn amplifies cost quadratically |
| **Consecutive edit errors** | 2/15 failures | `edit_file` requires exact string matching; LLM-generated `old_string` frequently mismatches whitespace, line breaks, or context |
| **Repeated results (stuck loops)** | 1/15 failures | Model enters read→read→read cycles with no progress |
| **Parse errors** | 2/15 failures | LLM produces empty or malformed final JSON |
| **Sub-task too large** | 1/15 failures | Decomposition produces sub-tasks that still exceed budget |

**Key observation:** Claude Code solves all five failure modes natively:

1. **Budget/context management** — Claude Code manages its own 200K token
   context window with automatic compression. No external budget tracking needed.
2. **File editing** — Claude Code's `Edit` tool uses fuzzy matching with
   contextual understanding, not brittle exact-string replacement.
3. **Loop detection** — Claude Code has built-in stuck detection and recovery.
4. **Output formatting** — Claude Code reliably produces structured text output.
5. **Context scoping** — Claude Code reads only what it needs, when it needs it,
   using `Glob` and `Grep` for targeted discovery.

The original ADR's concerns about Claude Code remain valid (vendor lock-in,
local model support, opacity). However, the custom loop's 11.5% success rate
means we are paying for provider-agnosticism with an unusable system.

---

## Decision

**Keiro will support Claude Code CLI (`claude --print`) as an optional
implementer backend alongside the existing native tool-use loop.**

### Architecture

```
Pipeline
  ├── PlannerAgent (unchanged — native tool-use loop)
  ├── ImplementerAgent (native, default)
  │     └── tool_use_loop → Router → Provider (Gemini/Anthropic/OpenAI)
  └── ClaudeCodeImplementer (optional, via config)
        └── claude --print → Claude Code CLI → file edits in worktree
```

The `ClaudeCodeImplementer` implements the same `Agent` trait as the native
`ImplementerAgent`. The pipeline selects between them based on the
`pipeline.use_claude_code_implementer` config flag.

### How it works

1. Pipeline assembles `AgentContext` as usual (plan, file context, constraints).
2. `ClaudeCodeImplementer::execute()` builds a prompt from the context.
3. Invokes: `claude --print -p <prompt> --output-format json --model <model>
   --permission-mode bypassPermissions --allowedTools "Read Edit Write
   Bash(cargo:*) Bash(git diff:*) Glob Grep" --max-budget-usd <budget>`
4. Claude Code runs in the worktree directory, editing files directly.
5. Parses the JSON result (cost, duration, final text).
6. Extracts the implementer's summary JSON from the result text.
7. Returns `AgentOutput` compatible with the rest of the pipeline.

### What stays the same

- **Planner** — Still uses the native tool-use loop (single-turn, cheap).
- **Triage, security, release, archivist** — All unchanged.
- **Pipeline orchestration** — Test/debug loop, PR creation, decomposition,
  budget tracking — all unchanged.
- **Git worktree isolation** — Claude Code runs in the same worktree the
  pipeline creates. No additional isolation needed.
- **Native implementer** — Still available, still the default. Claude Code
  is opt-in.

### What changes

- **Implementer tool execution** — Delegated to Claude Code instead of
  Keiro's `ToolDispatcher`.
- **Token tracking** — Claude Code reports cost in USD but not raw token
  counts. The pipeline tracks cost-based budget instead.
- **Tool governance** — Claude Code's `--allowedTools` flag replaces
  Keiro's `ToolPolicy`. The same constraints apply (no curl, no sudo,
  no rm -rf) but enforcement is by Claude Code, not by us.
- **Stuck detection** — Claude Code handles this internally. Keiro's
  `StuckReason` tracking is bypassed.

---

## Consequences

### Positive

- **Dramatically higher success rate** expected — Claude Code's native file
  editing, context management, and tool orchestration eliminate the top 5
  failure modes.
- **Simpler implementer code** — `ClaudeCodeImplementer` is ~200 lines vs
  ~450 for the native agent + tool loop + dispatcher.
- **Better model quality** — Claude Sonnet/Opus are strong code models with
  native tool use training.
- **No changes to pipeline** — Drop-in replacement at the agent level.

### Negative

- **Vendor dependency** — Claude Code requires the `claude` CLI binary and
  an Anthropic API key. Cannot use Gemini, GPT, or local models through
  this path.
- **Cost** — Claude Sonnet ($3/$15 per M tokens) is ~10x more expensive than
  Gemini Flash ($0.15/$0.60 per M tokens). However, if success rate jumps from
  11% to 60%+, cost per successful task drops significantly.
- **Opacity** — We cannot inspect individual tool calls within a Claude Code
  session. Debugging failures requires reading Claude Code's session logs.
- **Binary dependency** — Requires `claude` CLI installed and authenticated
  in the runtime environment.
- **Governance gap** — Keiro's `ApprovedAction<T>` type-level governance
  is bypassed for the implementation phase. Claude Code has its own permission
  model but it's not ours.

### Mitigations

- **Dual-mode** — Native implementer remains for non-Claude environments and
  local model usage. Config toggles between them.
- **Cost control** — `--max-budget-usd` flag caps per-task spend. Pipeline
  still tracks cumulative batch budget.
- **Tool restrictions** — `--allowedTools` limits Claude Code to safe
  operations (read, edit, write, cargo, git status/diff).
- **Session isolation** — `--no-session-persistence` prevents Claude Code
  from persisting session state. Each invocation is stateless.

---

## Alternatives Considered

### A. Switch Router to Anthropic models (config change only)

Just change `routing.implementer` to `anthropic/claude-sonnet-4-6` and keep
the native tool-use loop.

**Rejected because:** The failure modes are in the tool loop, not the model.
Better model + same brittle `edit_file` = same failures. The consecutive
edit errors are a string-matching problem, not a model-quality problem.

### B. Claude Agent SDK (full rewrite)

Rebuild Keiro's agent layer on the Claude Agent SDK.

**Rejected because:** The SDK is Python-only. Keiro is Rust. A full
rewrite is disproportionate to the problem. The CLI subprocess approach
gets 80% of the benefit with 5% of the effort.

### C. Improve the native tool loop

Fix `edit_file` to use fuzzy matching, add smarter context management,
improve budget estimation.

**Not rejected, but insufficient alone.** We should improve the native
loop over time, but these are deep problems. The Claude Code backend
gives us a working system now while we iterate on the native path.

---

## Open Question: Call vs. Bootstrap

There are two fundamentally different ways to integrate Claude Code:

### "Call it" — Keiro as brain, Claude Code as hands

```
glitchlab (orchestrator)
  ├── triage, plan, decompose        (glitchlab's native agents)
  └── implement                      (claude --print subprocess)
       └── edits files in worktree
```

Keiro controls the workflow: what to build, when to decompose, budget
gates, retry logic, PR creation. Claude Code is invoked per-task as a
skilled executor. This is what the current prototype implements.

**Strengths:** Deterministic scheduling, batch parallelism, cost control,
decomposition logic, history tracking, TQM feedback loops — all stay in
Keiro's Rust codebase where they're testable and governable.

**Weakness:** Two layers of orchestration. Keiro's planner produces a
plan, then Claude Code re-interprets that plan using its own judgment. The
plan is a lossy interface between two systems that both want to be in charge.

### "Bootstrap from it" — Claude Code as brain, Keiro as scheduler

```
claude code (interactive session or --print invocation)
  ├── understands task, reads code, plans approach
  ├── implements directly (edit, write, bash)
  └── optionally invokes glitchlab for:
       ├── batch scheduling (glitchlab batch)
       ├── bead tracking (bd)
       └── CI/test infrastructure
```

A Claude Code session (like the one writing this ADR right now) IS the
architect and implementer. It reads code, understands architecture, writes
implementations, runs tests — all natively. Keiro becomes a scheduling
and persistence layer that Claude Code invokes when it needs batch execution,
history tracking, or multi-task coordination.

**Strengths:** No lossy plan interface. The same context that understands the
code also writes the code. 200K context window. Native fuzzy editing. This is
demonstrably more effective — the session writing this code has a ~100%
success rate on the tasks it attempts, vs. 11.5% for the automated pipeline.

**Weakness:** Requires an interactive session or expensive long-running
`--print` invocation. No built-in batch parallelism. Harder to run
unattended (requires API key management, no built-in retry/resume).
Cost scales linearly with session length.

### Resolution: Call it

**Decision: "Call it."** Keiro calls Claude Code as a subprocess, not the
other way around. This preserves the model-agnostic architecture that is a
core project objective. Claude Code is one implementer backend alongside the
native tool-use loop (which supports Gemini, OpenAI, local models via Ollama,
and any future provider).

If we bootstrapped from Claude Code, Keiro would become
Anthropic-specific infrastructure. By calling it, Claude Code is a pluggable
capability — powerful when available, not required when it isn't.

---

## Validation Results

### Canary (single task): SUCCESS
- PR #99 created. Claude Code Sonnet: 8 turns, 70s, $0.26, tests passing.

### Batch 7 (subprocess integration): FAILED
- 6 Claude Code invocations, $3.20 total, **zero successes**.
- Root cause: integration layer problems, not Claude Code quality:
  1. Output JSON parsing — `result` field from CLI not correctly extracted
  2. Cost tracking — Claude Code's $0.50+/task not flowing to pipeline budget
  3. Budget gate — 80K native limit rejects tasks Claude Code handles easily
- Claude Code was doing useful work (7-15 turns each) but the pipeline
  couldn't read the results.

### Phase decision

**Phase 1 (now):** Use Claude Code in "bootstrap" mode — interactive sessions
or direct `--print` invocations for implementation work. This is demonstrably
effective (this session has ~100% success rate).

**Phase 2 (future):** Fix the subprocess integration layer:
- Parse `result` field from `claude --print --output-format json` correctly
- Flow `total_cost_usd` back to the pipeline's `BudgetTracker`
- Adjust budget gates to account for Claude Code's 200K context window
- Ensure final JSON output format matches expected schema

**Phase 3 (future):** Re-enable `use_claude_code_implementer: true` once
Phase 2 fixes are validated by canary runs.
