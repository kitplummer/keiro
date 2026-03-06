# ADR: Discovered Seams — Engineering vs. General Agentic Patterns

**Date:** 2026-03-01
**Authors:** Keiro (Patch), Kit, Rob
**Status:** Active
**Follows:** [The Agentic Corporation Framework](../adr-agentic-corporation-framework.md) (Phase 3 follow-up)
**Related:** [Eng-Org / Kernel Seams](../eng-org-kernel-seams.md), [Seams: Engineering vs. General](../seams-eng-general.md)

---

## Context

The [Agentic Corporation Framework ADR](../adr-agentic-corporation-framework.md) called for standing up an Ops org as a second Keiro instance (Option A) before extracting a general kernel. The explicit goal was to discover, through implementation, where engineering-specific assumptions are baked into the codebase versus what is genuinely general.

> *"The seam discovery in step 2 is the critical learning moment. Do not skip it by designing the kernel in the abstract."*

This ADR documents what was found. It is the Phase 3 output and the required input for Phase 6 (kernel extraction).

---

## Discovered Seams

### Seam 1: `EngineeringPipeline` encodes a software development lifecycle as the only pipeline shape

**Location:** `crates/eng-org/src/pipeline.rs` (~6 500 lines)

**Engineering-specific assumption:**
The `Pipeline` trait is general (`kernel::Pipeline`), but `EngineeringPipeline` hard-codes a linear, deterministic stage sequence: `index → plan → triage → implement → test → security → release → archive`. Every stage name, every transition, and every inter-stage data contract is software-development-specific.

**What leaked:**
An Ops pipeline wants an event-driven, reactive shape. Incoming alerts trigger triage; triage may trigger rollback or investigation; investigation may loop. There is no `plan` stage, no `implement` stage, no `archive`. The stage sequence is not known upfront — it depends on the alert.

**General pattern to extract:**
A `Pipeline` should define only: (a) how stages are discovered/registered, (b) how stage results are threaded forward via `PipelineResult`, and (c) the terminal conditions (`Complete`, `Failed`, `Blocked`). The stage *names* and *order* must be provided by the org, not baked into the trait or a single implementation.

**Kernel candidate:** A `DynamicPipeline` or `StagedPipeline<S: StageGraph>` where `S` encodes the org's own directed stage graph.

---

### Seam 2: `build_user_message()` assembles engineering context for every agent

**Location:** `crates/eng-org/src/agents/mod.rs`

**Engineering-specific assumption:**
The single `build_user_message()` function injects engineering-specific context into every agent call: codebase knowledge (`RepoIndex`), current worktree diff, test output, prior stage results. It assumes agents always need code context.

**What leaked:**
An Ops agent needs infrastructure topology, recent alert history, deployment state, and runbook excerpts — none of which exist in a `RepoIndex`. Passing a code index to an incident-response agent is noise that wastes tokens and confuses the model.

**General pattern to extract:**
`ContextAssembler` (already in `kernel`) is the right abstraction. It is priority-based and composable. The seam is that `build_user_message()` is not using `ContextAssembler` generically — it is a monolithic function that hard-codes what context means for an engineering agent. Each org should supply its own `ContextStrategy` that the kernel's `ContextAssembler` executes.

**Kernel candidate:** `ContextAssembler` promoted to the primary assembly API; `build_user_message()` becomes an eng-org-specific `ContextStrategy` implementation.

---

### Seam 3: `Orchestrator` couples worktree-per-task isolation to the execution model

**Location:** `crates/eng-org/src/orchestrator.rs`, `crates/eng-org/src/workspace.rs`

**Engineering-specific assumption:**
The `Orchestrator` creates a Git worktree for every task. Worktree creation, checkout, and cleanup are core to the execution loop, not optional or configurable. The assumption is that every task involves modifying files in a repository.

**What leaked:**
An Ops pipeline task (e.g., "respond to a CPU spike on node-42") does not involve a Git worktree. There is no repository to check out. The worktree lifecycle management in `Orchestrator` is dead weight for any non-engineering org, and its initialization errors would abort Ops tasks.

**General pattern to extract:**
The general `Orchestrator` should know about task lifecycle (queue, in-flight, retry, budget) but not about worktrees. Workspace management should be an optional `WorkspaceProvider` that engineering injects, defaulting to a no-op for orgs that do not need file isolation.

**Kernel candidate:** `Orchestrator<W: WorkspaceProvider>` where `WorkspaceProvider` is a trait with a no-op default; `GitWorktreeProvider` is the eng-org implementation.

---

### Seam 4: Tool allowlist is hard-coded for software development operations

**Location:** `crates/eng-org/src/tools/`, `crates/eng-org/src/pipeline.rs` (tool registration)

**Engineering-specific assumption:**
The tool set — `read_file`, `write_file`, `edit_file`, `list_files`, `run_command` — is the vocabulary of a developer in a terminal. `run_command` is trusted to execute `cargo test`, `git diff`, `cargo clippy`.

**What leaked:**
An Ops agent needs tools like `get_metrics(node, window)`, `trigger_rollback(deployment)`, `page_oncall(message)`, `query_logs(service, query)`. The file system tools are mostly irrelevant. More critically, `run_command` is too powerful (arbitrary shell) and too weak (no structured API client) for cloud operations work.

**General pattern to extract:**
`ToolDefinition`, `ToolCall`, and `ToolResult` in `kernel` are already general. The seam is that tool *registration* and tool *execution* are tied to the eng-org pipeline, not the kernel. Each org should register its own tool set. Governance (`ApprovedAction<T>`) already enforces boundaries — this just needs to be plumbed per-org rather than per-pipeline.

**Kernel candidate:** A `ToolRegistry` in kernel that orgs populate at startup; `ApprovedAction<T>` wrapping every execution call regardless of org.

---

### Seam 5: `EngConfig` + `TaskQueue` assume YAML task files and a development workflow

**Location:** `crates/eng-org/src/config.rs`, `crates/eng-org/src/taskqueue.rs`

**Engineering-specific assumption:**
`EngConfig` structures routing, limits, and agent personas for a software engineering team. `TaskQueue` loads from `.glitchlab/tasks.yaml` or Beads, where tasks describe code changes: `title`, `description`, `files_likely_affected`, `estimated_complexity`.

**What leaked:**
Ops tasks arrive from alerting systems (PagerDuty, Prometheus webhooks, Dolt triggers), not from YAML files. Their schema is `alert_name`, `severity`, `affected_service`, `runbook_url`. Finance tasks arrive on a cron schedule. The `TaskQueue` and `Task` struct encode the *delivery mechanism and schema of engineering work orders*, not a general task concept.

**General pattern to extract:**
A `Task` in the kernel should be a minimal envelope: `id`, `org`, `priority`, `payload: serde_json::Value`. The `TaskQueue` trait should abstract over delivery: YAML file, Beads graph, webhook, cron. Each org defines its own task schema and deserializes from `payload`.

**Kernel candidate:** `Task<P>` with generic payload; `TaskSource` trait with `YamlFileSource`, `BeadsSource`, `WebhookSource` implementations.

---

### Seam 6: `TQMAnalyzer` pattern recognition is scoped to code-generation failure modes

**Location:** `crates/eng-org/src/tqm.rs`

**Engineering-specific assumption:**
The nine `PatternKind` variants — `TestFailureLoop`, `CompilationError`, `SecurityBlockade`, `ContextWindowExhaustion`, etc. — all describe ways a software implementation task can fail. The TQM feedback loop updates the engineering pipeline to avoid these patterns.

**What leaked:**
Ops failure patterns are qualitatively different: `AlertStormNoise`, `RunbookStaleness`, `EscalationCascade`, `FalsePositiveRollback`. A general TQM system needs to be pattern-agnostic, with org-specific pattern libraries that feed into a shared learning loop.

**General pattern to extract:**
The TQM *mechanism* (observe failures, classify patterns, feed back into pipeline config) is general. The `PatternKind` enum is engineering-specific. The kernel should expose `FailurePattern` as a trait; each org provides its own implementation. The shared learning loop operates on `Box<dyn FailurePattern>`.

**Kernel candidate:** `TqmAnalyzer<P: FailurePattern>` with the pattern library injected by the org.

---

### Seam 7: `CumulativeBudget` tracks tokens as a proxy for cost across a batch of code tasks

**Location:** `crates/eng-org/src/orchestrator.rs` (`CumulativeBudget`, `AttemptTracker`)

**Engineering-specific assumption:**
Budget is measured in tokens and USD per task, across a batch of sequential tasks (a sprint). Retries are tracked per-task with hard limits. The mental model is a developer running a queue of coding tickets overnight.

**What leaked:**
An Ops org has a perpetual budget (it must respond to incidents whenever they arrive, not during a fixed batch window). A Finance org's budget unit might be API calls to Stripe or rows written to Dolt. The batch-and-retry model does not map to always-on reactive systems.

**General pattern to extract:**
`BudgetTracker` in `kernel` is already partially general (token + dollar limits). The seam is the batch-window framing in `CumulativeBudget` and the sequential-task assumption in `AttemptTracker`. The kernel should support both **batch budgets** (fixed window, sequential) and **perpetual budgets** (rolling window, event-triggered). Org declares which model it uses.

**Kernel candidate:** `BudgetPolicy` enum: `BatchWindow { max_tasks, max_cost }` vs. `RollingWindow { period, max_cost_per_period }`.

---

## Summary Table

| Seam | Engineering Assumption | General Candidate |
|------|----------------------|-------------------|
| 1. Pipeline shape | Linear SDLC stages hard-coded | `StageGraph` trait; org-supplied stage DAG |
| 2. Context assembly | Code context injected for every agent | `ContextStrategy` trait; org-supplied strategy |
| 3. Workspace isolation | Git worktree per task | `WorkspaceProvider` trait; no-op default |
| 4. Tool vocabulary | File system + shell | `ToolRegistry`; org-registered tool set |
| 5. Task schema & source | YAML files with dev task fields | `Task<P>` with generic payload; `TaskSource` trait |
| 6. Failure pattern library | Code-gen failure modes (TQM) | `FailurePattern` trait; org-supplied library |
| 7. Budget model | Batch window, token + USD | `BudgetPolicy` enum; batch or rolling |

---

## Implications for Kernel Extraction (Phase 6)

### What the kernel already owns (no change needed)

- `Agent` trait + `AgentContext` + `AgentOutput` + `Message` — fully general
- `ContextAssembler` with priority-based segment selection — general; just needs a strategy injection point
- `BudgetTracker` — general at the task level; extend with `BudgetPolicy` for batch vs. perpetual
- `ApprovedAction<T>` governance — fully general
- `ToolDefinition`, `ToolCall`, `ToolResult` — fully general
- `Provider` trait + `Router` — fully general (provider-agnostic LLM access)
- `HistoryBackend` trait + JSONL — fully general
- `PipelineStatus` + `ObstacleKind` + `OutcomeContext` — fully general

### What must move from `eng-org` to the kernel

| Concept | Current Location | Kernel Form |
|---------|-----------------|-------------|
| Stage graph execution | `EngineeringPipeline` | `Pipeline<S: StageGraph>` |
| Context strategy | `build_user_message()` | `ContextStrategy` trait |
| Workspace provider | `workspace.rs` + `orchestrator.rs` | `WorkspaceProvider` trait |
| Tool registry | scattered in `tools/` + pipeline | `ToolRegistry` in kernel |
| Task envelope | `Task` in `taskqueue.rs` | `Task<P>` in kernel |
| Task source | `TaskQueue` in `taskqueue.rs` | `TaskSource` trait in kernel |
| Failure pattern | `PatternKind` in `tqm.rs` | `FailurePattern` trait in kernel |
| Budget policy | `CumulativeBudget` in `orchestrator.rs` | `BudgetPolicy` in `kernel::budget` |

### What stays in `eng-org`

Everything else: `EngineeringPipeline` stage implementations, all agent implementations, `EngConfig`, the concrete tools, `RepoIndex`, `TQMAnalyzer` with its `PatternKind` variants, `GitWorktreeProvider`, `YamlFileTaskSource`.

`eng-org` becomes a first-class example of a kernel consumer — the canonical reference implementation.

---

## Recommended Extraction Order (Phase 6)

1. **`WorkspaceProvider`** — Smallest change; unblocks Ops org immediately. Extract the worktree logic from `Orchestrator` behind a trait. No behavioral change for `eng-org`.

2. **`Task<P>` + `TaskSource`** — Unblocks Ops and Finance task ingestion. The YAML source remains; new sources can be added without touching orchestration logic.

3. **`ToolRegistry`** — Decouples tool registration from the pipeline. Each org registers tools at startup. Governance wraps every execution via `ApprovedAction<T>`.

4. **`ContextStrategy`** — Refactor `build_user_message()` into a `ContextStrategy` implementation. `ContextAssembler` becomes the kernel API.

5. **`BudgetPolicy`** — Generalize `CumulativeBudget` into `BudgetPolicy`. Adds rolling-window support; existing eng-org behavior maps to `BatchWindow`.

6. **`StageGraph` + `Pipeline<S>`** — Most invasive. Refactor `EngineeringPipeline` to separate the stage graph (eng-specific) from the execution engine (general). Do this last — it depends on all the others being stable.

7. **`FailurePattern` + `TqmAnalyzer<P>`** — Generalize `PatternKind` last; TQM is not on the critical path for standing up new orgs.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Over-abstracting prematurely | High | Extract only the seven seams above. Do not generalize anything not on this list without a concrete second org needing it. |
| Breaking `eng-org` test coverage | High | Every extraction step requires `eng-org` tests to remain green. Use the existing 90% coverage bar as a regression gate. |
| Leaking engineering defaults into kernel | Medium | All kernel traits must have no-op or panic-on-use defaults. No engineering behavior may be the default. |
| Seam list is incomplete | Medium | This list is based on one additional org (Ops). Finance and GTM may surface new seams. Revisit this ADR after each new org. |

---

## Decision

Proceed with Phase 6 kernel extraction using the seven seams and the extraction order defined above. `eng-org` serves as the reference implementation and must remain fully functional throughout. No new orgs should be built on the current `eng-org` codebase; they should wait for the kernel traits to be available.

---

*This ADR should be updated as each extraction step completes, and revisited when a third org (Finance or GTM) is stood up.*
