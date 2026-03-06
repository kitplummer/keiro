# ADR: Supervision Trees and Failure-as-Learning

**Date:** 2026-02-24
**Authors:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** First Keiro batch run (2026-02-24), Erlang/OTP supervisor model, production agent pipeline experience

---

## Context

Keiro's first autonomous batch run against its own beads backlog processed 34 tasks in 10 minutes, spending $0.35 of a $100 budget. Results:

| Outcome | Count | What happened |
|---------|-------|---------------|
| **Decomposed** | 21 | Planner broke the task into subtasks |
| **PrCreated** | 1 | Full pipeline success, PR shipped |
| **ImplementationFailed** | 2 | Binary failure — no learning captured |

The two "failures" exposed a fundamental design gap. The pipeline treats outcomes as binary — success or `ImplementationFailed` — then moves on. But an agentic system that marks a task as "failed" and discards everything it learned during the attempt is burning money. The agent explored the codebase, identified constraints, hit a wall, and then all of that context was thrown away.

This is the same problem Erlang solved in the 1980s for telecom switches: **failure is not an error condition to be avoided, it is a signal to be processed.**

Meanwhile, the 21 "Decomposed" outcomes reveal a different issue: the planner is aggressively decomposing rather than implementing. This suggests the system needs clearer supervision directives — when to decompose, when to attempt, and when to escalate.

---

## Decision

### 1. Adopt the OTP Supervisor Model for Pipeline Orchestration

The pipeline is a supervision tree where each level has explicit restart strategies, intensity limits, and escalation behavior. The key OTP insight that applies: **the code that does work should not also be the code that recovers from failure.** Agents do work; the pipeline handles failure.

```
                    [Orchestrator]                    one_for_one
                    /      |       \
           [Pipeline]  [Pipeline]  [Pipeline]         rest_for_one
            /  |  \
     [Plan] [Impl] [Test] [Security] [Release]       worker stages
```

#### Restart Strategies (mapped from OTP)

| OTP Strategy | Keiro Equivalent | When to use |
|-------------|---------------------|-------------|
| `one_for_one` | Orchestrator retries a single failed task | Independent tasks in the queue |
| `rest_for_one` | Pipeline aborts remaining stages after a stage fails | Linear stage dependency (Plan -> Impl -> Test -> ...) |
| `one_for_all` | Restart entire pipeline when shared context is corrupted | Worktree corruption, git state inconsistency |
| `simple_one_for_one` | Dynamic sub-task pool from decomposition | Planner emits N subtasks, each runs independently |

#### Restart Intensity

OTP prevents infinite restart loops with `max_restarts / max_seconds`. Keiro already has `max_fix_attempts` and `max_dollars_per_task`. Extend with:

- **Time-based windowing**: If 3 tasks fail within 5 minutes, suspect a systemic issue (API down, model degraded, config broken) and pause for human review rather than burning through the queue.
- **Escalation on intensity breach**: When a pipeline exhausts its retry budget, it doesn't just mark "Failed" — it terminates and reports structured context to the orchestrator, which decides whether to retry, defer, or halt.

### 2. Replace Binary Pass/Fail with Outcome Classification

`ImplementationFailed` is not a useful signal. Replace it with a taxonomy that drives supervisor behavior:

| Outcome | Supervisor Action | Example |
|---------|-------------------|---------|
| **Completed** | Mark done, advance dependents | PR created and merged |
| **Deferred** | Return to queue with learned context | "Need T12 (Zephyr schema) before this can proceed" |
| **Decomposed** | Inject subtasks, mark parent as waiting | Task too large, planner split it |
| **Blocked** | Park until blocker resolves | External dependency, human decision needed |
| **Retryable** | Retry with backoff + failure context | LLM parse error, API timeout, flaky test |
| **Escalated** | Halt and surface to human/CEO layer | Governance denial, boundary violation, budget exceeded |

The critical distinction: **Deferred and Blocked are not failures.** They are the system learning its own boundaries. A deferred task carries structured context about *why* it couldn't proceed, so the next attempt (or a human reviewer) starts with that knowledge rather than rediscovering it.

### 3. Failure Context is First-Class State

When an agent cannot complete a task, the *reason* is valuable. Capture it as structured data:

```rust
pub struct OutcomeContext {
    /// What the agent attempted
    pub approach: String,
    /// What went wrong (structured, not just an error string)
    pub obstacle: ObstacleKind,
    /// What the agent learned about the codebase/task
    pub discoveries: Vec<String>,
    /// What the agent recommends for the next attempt
    pub recommendation: Option<String>,
    /// Files explored, dependencies identified, etc.
    pub explored_state: ExploredState,
}

pub enum ObstacleKind {
    /// Missing prerequisite — needs another task first
    MissingPrerequisite { task_id: String, reason: String },
    /// Codebase constraint — architecture doesn't support this yet
    ArchitecturalGap { description: String },
    /// LLM limitation — model couldn't produce valid output
    ModelLimitation { model: String, error_class: String },
    /// External dependency — API down, tool unavailable
    ExternalDependency { service: String },
    /// Scope too large — needs decomposition
    ScopeTooLarge { estimated_files: usize, max_files: usize },
}
```

This context is:
1. Written to the bead as a comment (persisted in the task graph)
2. Injected into the planner prompt on retry ("Negative Context Injection" — see Section 5)
3. Available to the orchestrator for pattern detection

### 4. Process Isolation via Worktrees (Already Implemented)

Keiro's git worktree-per-task model provides the same isolation guarantee as BEAM's per-process heap:

| BEAM | Keiro |
|------|-----------|
| Process has its own heap | Task has its own worktree |
| Process crash cannot corrupt other processes | Bad code in one worktree cannot affect main or other tasks |
| Restart = fresh process with clean heap | Retry = clean worktree from HEAD |
| Per-process GC | Worktree cleanup on task completion |

This is already correct. No changes needed, but the ADR formalizes the analogy so future contributors understand *why* worktrees are non-negotiable.

### 5. Production Pipeline Principles

The following principles are derived from production experience running agent pipelines. They are not theoretical — each addresses a failure mode observed in real systems.

#### The Do's

**Deterministic Orchestration ("Brainstem Pattern").** LLMs never decide who speaks next or when a task is done. The pipeline is a rigid, deterministic sequence: Plan -> Implement -> Test -> Security -> Release -> Archive. LLMs are stateless cogs that perform a single transformation at each step. "Emergent" routing creates infinite loops. Explicit governance creates infrastructure.

**Dual-Mode Architecture (Tiered Autonomy).** Separate tasks by risk. Maintenance Mode: surgical, tightly constrained, no test modifications, fully autonomous. Evolution Mode: broad refactors, high risk, requires human PR review. You cannot get creative growth and infrastructure-grade reliability from the same prompt and the same guardrails.

**Surgical Insertion over Full Regeneration.** If you only need to change a docstring or a single function, do not ask the LLM to output the whole file. Ask for the specific text and use code to inject it. Asking an LLM to rewrite a 2,000-line file to fix a typo guarantees hallucinated deletions and token limit explosions.

**Fuzzy Application (Forgiving Tooling).** Never expect an LLM to do perfect math or exact string matching. `git apply` (requires perfect line numbers) fails constantly. `patch --fuzz=3` (looks for the general shape) succeeds. LLMs are linguistic engines, not calculators. Build your pipeline to tolerate slight offsets in whitespace, line numbers, or casing.

**Defensive Parsing (Regex Fallback).** Even when instructed "Output ONLY JSON," LLMs will eventually output markdown-wrapped JSON. Always use regex extraction as a fallback before crashing the JSON parser.

**Negative Context Injection.** Pass a short history of recent failures into the Planner's prompt: "Attempt 1 failed because X. Attempt 2 failed because Y." Without memory, stateless agents try the exact same hallucinated fix repeatedly. This is where OutcomeContext (Section 3) feeds back into the loop.

**Truncation / Sanity Guards at the Write Layer.** Before applying a destructive change, compare sizes. If the LLM proposes replacing a 1,000-line file with a 50-line file, catch it in code and abort. This is a pipeline-level guard, not an agent-level one.

#### The Don'ts

**No Wide Blast Radius.** The probability of a successful diff drops exponentially when an LLM modifies more than 2 files or 150 lines at once. Force the Planner to chunk work: max 2 files per step. If it needs to touch 5 files, it must generate sequential tasks.

**Never Let Agents Mutate the Validation Layer.** LLMs take the path of least resistance. If a test fails, the agent will delete or alter the test rather than fixing the logic. Strictly block modifications to test/validation files unless explicitly authorized in Evolution Mode. Keiro already enforces this via `protected_paths` in boundaries config.

**No Multi-Modal Outputs in One Prompt.** "Write the code, run the tests, and deploy" in a single prompt means the LLM will hallucinate CLI output ("I have run the tests and they passed!"). Agents output data or plans. Deterministic code executes the tools.

**Never Trust LLM-Generated Identifiers.** LLMs inject colons, slashes, and spaces into filenames. Always sanitize strings generated by an LLM before using them in file paths, URLs, or database keys.

**No Implicit Feature Creep.** Vague instructions like "Improve the module" trigger people-pleasing: the LLM adds features you didn't ask for, imports libraries you don't need, and over-engineers simple scripts. Prompts must contain aggressive limiters: "Do not refactor. Do not improve. Do not add features. Fix the EXACT failure and nothing else."

### 6. The Fundamental Principle

> Agentic workflows fail when we treat the AI like a human employee ("Here's a big project, figure it out"). They succeed when we treat the AI like a highly capable but erratic micro-processor constrained inside a rigid, boring, traditional software pipeline.

This is the Erlang insight applied to AI: a BEAM process is powerful but unreliable in isolation. Its power comes from the supervision infrastructure that contains, manages, and recovers from its failures. An LLM agent is the same. The agent is the process. The pipeline is the supervisor. The orchestrator is the application supervisor. The governance layer is the VM.

---

## Phased Implementation

### Phase 0: Outcome Taxonomy (immediate)

- Replace `PipelineStatus::ImplementationFailed` with the classified outcome model from Section 2
- Add `OutcomeContext` struct to kernel
- Wire failure context into JSONL history and bead comments
- No behavioral changes yet — just richer data capture

### Phase 1: Negative Context Injection

- Planner receives `OutcomeContext` from previous attempts on the same task
- Orchestrator tracks per-task attempt history
- Deferred tasks return to the queue with context attached

### Phase 2: Restart Intensity and Escalation

- Time-windowed failure detection (N failures in M seconds = systemic issue)
- Escalation path: agent retry -> pipeline restart -> orchestrator pause -> human review
- Backoff with jitter on retryable failures (API rate limits, parse errors)

### Phase 3: Dual-Mode Autonomy

- Maintenance Mode: max 2 files, no test mutations, auto-merge on green CI
- Evolution Mode: broad scope allowed, requires human PR review
- Mode selection based on task labels, priority, or explicit config

### Phase 4: Write-Layer Guards

- File size delta checks before applying edits
- Identifier sanitization for LLM-generated paths
- Blast radius enforcement in the Planner (max files per step)

---

## Prior Art

- **Erlang/OTP Supervisor Behaviour** — The original supervision tree model. Restart strategies, intensity limits, and escalation have been battle-tested in telecom systems since the 1980s.
- **Jido (Elixir)** — AI agents built natively on OTP. Agents are immutable data structures; side effects are directives executed by the OTP runtime. Demonstrates that agent logic should be pure and testable, separate from lifecycle management.
- **"Your Agent Framework Is Just a Bad Clone of Elixir"** (George Guimaraes, 2025) — Analysis showing LangGraph, AutoGen, CrewAI, and Langroid all independently reinvent OTP patterns without the isolation, scheduling, or fault tolerance guarantees.
- **Jason BDI Agent Platform** — Academic work on mapping agent supervision to Erlang-style supervision trees. Identifies higher-level agent failure modes: "event overload" (agent cannot process events fast enough) and "divergence" (agent stuck in a reasoning loop).
- **Keiro Batch Run #1** (2026-02-24) — 34 tasks, $0.35 spent, 21 decomposed, 1 PR created, 2 binary failures with no context captured. Direct motivation for this ADR.

---

## Consequences

### Positive

- Failures become learning opportunities, not dead ends
- Structured failure context reduces redundant work across attempts
- Supervision tree model provides clear escalation paths
- Production principles prevent the most common agent pipeline failure modes
- Dual-mode autonomy enables both safe maintenance and ambitious evolution

### Negative

- More complex orchestrator logic (but complexity is in the right place — supervision, not agents)
- OutcomeContext adds to token cost on retry (but prevents much larger waste from blind retries)
- Dual-mode requires task classification, which may need human input initially

### Neutral

- Worktree isolation model is validated and unchanged
- Existing `max_fix_attempts` and `max_dollars_per_task` become parameters of the supervision model rather than standalone limits
