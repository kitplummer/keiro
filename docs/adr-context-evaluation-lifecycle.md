# ADR: Context Evaluation Lifecycle — Testing the Inputs, Not Just the Outputs

**Date:** 2026-02-26
**Authors:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** Tessl CDLC framework (Feb 2026), Agent Swarm (desplega-ai), Keiro batch runs 1–2, ADR: TQM — Self-Improvement as First-Degree Architecture

---

## Context

Keiro's TQM architecture detects failure patterns in *execution outcomes* — decomposition loops, model degradation, stuck agents, budget pressure. This is the right approach for runtime supervision. But it has a blind spot: **it never tests whether the context we feed agents is itself correct, complete, and non-regressed.**

Consider what happens today when we change a planner system prompt, adjust the `ContextAssembler` priority ordering, modify `ToolPolicy` allowlists, or tweak `RoutingConfig` model assignments. The change ships. We run a batch. If tasks succeed, we assume the context was good. If tasks fail, TQM detects the symptom (ParseFailure, StuckAgent) but cannot distinguish "the model had a bad day" from "we broke the planner prompt last Tuesday."

This is the equivalent of testing a web app by checking whether users complain, rather than running a test suite. It works — until it doesn't.

Tessl's Context Development Lifecycle (CDLC) framework, published February 2026, formalizes an insight we've been circling: **organizational context is an engineered artifact that needs its own generate → evaluate → distribute → observe lifecycle.** Their core argument — that models are commoditizing, tools are converging, and accumulated context is the durable moat — is the same thesis Keiro is built on. But they've named a gap we haven't addressed: context evaluation.

Meanwhile, desplega-ai's Agent Swarm project demonstrates the opposite extreme. Agents maintain persistent, self-modifying identity files (SOUL.md, IDENTITY.md). There is no governance over what agents write into their own prompts. This is interesting as a personality experiment but architecturally dangerous — mutable context with no evaluation or versioning is context rot by design.

Keiro sits between these positions. Our context is versioned (it lives in config files and source code). Our context is governed (ApprovedAction, BoundaryEnforcer). But our context is not *tested*. We test what agents *do*. We don't test what agents *receive*.

---

## Decision

### Context is a testable artifact. Treat it like one.

The `ContextAssembler` already owns the assembly of what goes into each agent's context window. Extend this with a closed-loop evaluation mechanism: known tasks with known-good outcomes serve as regression tests for context quality.

### 1. Context Evaluation Scenarios

A **context scenario** is a frozen (task, expected behavior) pair. It captures: given this `AgentContext`, the agent should produce output that satisfies these assertions.

```rust
pub struct ContextScenario {
    /// Human-readable name for the scenario
    pub name: String,
    /// Which agent role this scenario tests
    pub role: String,
    /// Frozen AgentContext (task, constraints, file_context, previous_output)
    pub context: AgentContext,
    /// Assertions on the agent's output
    pub expectations: Vec<Expectation>,
    /// Optional: the context config at time of last known-good run
    pub baseline_config_hash: Option<String>,
}

pub enum Expectation {
    /// Output JSON must contain this field with a value matching the pattern
    FieldMatches { path: String, pattern: String },
    /// Output must NOT contain these patterns (anti-regression)
    Absent { patterns: Vec<String> },
    /// Risk level must be at or below this threshold
    MaxRisk(RiskLevel),
    /// Plan must decompose (or must NOT decompose)
    Decomposes(bool),
    /// Token usage must stay within this budget
    MaxTokens(usize),
    /// Must reference specific files (tests codebase awareness)
    ReferencesFiles(Vec<String>),
}
```

Scenarios are not unit tests for agent logic — they are regression tests for the context-to-behavior pipeline. They answer: "does the planner still produce a sensible plan for task X, given the current system prompt, config, and routing?"

### 2. The Four-Stage Lifecycle (Adapted from CDLC)

Tessl's CDLC maps cleanly onto Keiro's existing architecture with one new component per stage:

| Stage | CDLC Concept | Keiro Today | What We Add |
|-------|-------------|-----------------|-------------|
| **Generate** | Make implicit knowledge explicit | System prompts, OrgConfig, ToolPolicy, constraints, ContextAssembler priorities | **Context manifest**: a single document (generated, not hand-written) that describes what each agent receives and why |
| **Evaluate** | Test-driven context quality | TQM (tests outcomes, not inputs) | **Context scenarios**: frozen task/expectation pairs run against current context config |
| **Distribute** | Version, publish, share context | Config checked into repo, but no cross-org sharing | **Context packages**: OrgConfig + prompts + scenarios as a versioned unit that the ops-org (or any future org) can depend on |
| **Observe** | Learn from production use | HistoryBackend, failure_context(), OutcomeContext | **Context drift detection**: compare scenario results across runs to identify slow degradation |

### 3. Context Manifest (Generate)

Today, understanding what an agent receives requires reading `ContextAssembler`, the agent's system prompt, `OrgConfig`, `ToolPolicy`, `BoundaryEnforcer`, and `RoutingConfig` — then mentally assembling them. A **context manifest** is a machine-generated summary of the assembled context for each role, produced by running `ContextAssembler::assemble()` in dry-run mode.

```
$ glitchlab context manifest --role planner

Role: planner
Model: gemini/gemini-2.5-flash
System prompt: 847 tokens (priority 0, always included)
Task description: variable (priority 1)
Constraints: 12 tokens (priority 2)
Previous output: variable (priority 3)
File contents: variable (priority 4)
Failure history: variable (priority 5)
Tool policy: 8 allowed prefixes, 3 blocked patterns
Protected paths: 5 entries
Budget: 200k tokens / $2.00 per task
```

This is documentation that cannot go stale because it's computed from the source of truth.

### 4. Context Scenarios (Evaluate)

Scenarios are stored alongside ADRs and config — they're project-level artifacts, not test-framework internals.

```yaml
# .glitchlab/scenarios/planner-decomposition.yaml
name: planner-decomposes-large-task
role: planner
context:
  task_id: "scenario-decomp-01"
  objective: "Refactor the authentication module to support OAuth2, JWT, and API key auth"
  constraints: ["max 2 files per step"]
  file_context:
    src/auth.rs: "... frozen file content ..."
expectations:
  - decomposes: true
  - max_tokens: 50000
  - absent: ["delete", "remove test"]
```

Running scenarios is a batch operation analogous to `cargo test` — it's a gate, not a monitor:

```
$ glitchlab context eval

planner-decomposition ........ PASS (decomposed: yes, tokens: 34,201)
planner-simple-fix ........... PASS (decomposed: no, tokens: 12,044)
implementer-tool-use ......... PASS (references: [src/auth.rs], absent violations: 0)
architect-triage-already-done  PASS (status: already_done)

4 scenarios, 4 passed, 0 failed
```

Because LLM outputs are non-deterministic, scenarios should be run N times (configurable, default 3) with a pass threshold (e.g., 2/3). This is statistical quality control, not exact assertion matching. The `Expectation` types are deliberately coarse-grained — we're testing directional correctness, not exact output.

### 5. Context Drift Detection (Observe)

Each scenario run produces a `ScenarioResult` with metrics: token usage, latency, key output features. Over time, these form a time series. Drift detection is threshold-based (matching TQM's pattern detection philosophy — counting, not ML):

| Signal | Detection | Threshold |
|--------|-----------|-----------|
| Token inflation | Mean tokens for scenario X increased >30% over 5 runs | Configurable |
| Decomposition shift | Scenario that should NOT decompose starts decomposing | Binary — immediate flag |
| Latency regression | Mean latency increased >50% (may indicate model routing change) | Configurable |
| Pass rate degradation | Scenario drops below pass threshold across N consecutive batches | 3 consecutive |

Drift alerts feed into TQM as a new pattern kind: `ContextDrift`. This closes the loop — context degradation becomes a TQM-detected anti-pattern that can spawn remediation beads.

### 6. Context Packages (Distribute)

This is forward-looking, targeting the multi-org phase. When the ops-org needs to understand what the eng-org's agents expect and produce, it shouldn't read source code — it should depend on a versioned context package:

```
.glitchlab/
  config.yaml           # eng-org config
  scenarios/            # eng-org context scenarios
  context-manifest.json # generated, describes assembled context per role
```

A context package is: config + scenarios + manifest, versioned together. When the kernel supports multiple orgs, each org publishes its context package. Cross-org dependencies (ops-org needs to understand eng-org's PR output format) are expressed as scenario expectations on the upstream org's output schema.

This is the "context as a dependency" idea from Tessl, grounded in Keiro's existing config-in-repo model rather than requiring a separate package registry.

---

## Consequences

### Positive

- **Context changes become testable.** Modifying a system prompt triggers scenario evaluation. Regressions are caught before they burn batch budget.
- **The flywheel accelerates.** TQM already turns execution failures into learning. Context evaluation turns *context quality* into learning. The system now improves both what agents do and what agents receive.
- **Cross-org becomes tractable.** Context packages give the ops-org (and future orgs) a stable interface to depend on, rather than coupling to eng-org internals.
- **The moat deepens.** Every scenario we write encodes institutional knowledge about what good agent behavior looks like for *our* codebase. This is the flywheel Tessl describes — accumulated context that competitors cannot purchase.

### Negative

- **LLM cost for evaluation.** Running scenarios requires actual LLM calls. Mitigated by: using economy-tier models for evaluation runs, caching results, running scenarios only when context-affecting files change (system prompts, config, ContextAssembler).
- **Scenario maintenance burden.** Scenarios can themselves go stale. Mitigated by: keeping expectations coarse-grained (directional, not exact), auto-flagging scenarios that haven't been updated in N days, and — eventually — having the Archivist agent propose scenario updates based on production drift.
- **Non-determinism makes hard assertions impossible.** A scenario that passes 2/3 times but fails 1/3 is ambiguous. Mitigated by: statistical thresholds rather than exact matching, trend analysis rather than point-in-time assertions, and the deliberate coarseness of `Expectation` types.

### Trade-offs

- **Evaluation granularity vs. cost.** Fine-grained scenarios (one per agent per task type) give better signal but cost more to run. Start coarse: one scenario per agent role testing the most critical behavior (planner decomposes correctly, implementer uses tools, architect triages correctly). Expand as the budget allows.
- **Scenario creation: manual vs. generated.** Initially, scenarios are hand-written from real batch run data (freeze a known-good task/output pair). Eventually, the TQM-to-scenario pipeline should auto-generate scenarios from production successes — "this task succeeded; preserve its context as a regression test." But auto-generation is Phase 2 work.

---

## Relationship to Existing ADRs

| ADR | Relationship |
|-----|-------------|
| **TQM Self-Improvement** | Context drift detection becomes a new TQM pattern kind (`ContextDrift`). Scenario failures can spawn remediation beads. |
| **Supervision and Failure-as-Learning** | Context scenarios are the "test suite" for the negative context injection mechanism — verify that failure history actually changes agent behavior. |
| **Cost-Aware Model Routing** | Scenario evaluation runs use economy-tier models. Context manifest exposes routing decisions for inspection. |
| **Agentic Corporation Framework** | Context packages are the interface contract between orgs. This is the "discover seams before designing interfaces" principle applied to context. |

---

## Implementation Path

| Phase | What | Validates |
|-------|------|-----------|
| **0: Manifest** | `glitchlab context manifest` CLI command. Dry-run `ContextAssembler::assemble()` and print what each role receives. | That we can introspect context assembly without running agents. |
| **1: Scenarios** | `ContextScenario` struct, YAML schema, `glitchlab context eval` runner. 1 scenario per agent role (6 total). Run against live LLM with statistical pass threshold. | That context changes produce detectable behavior changes. |
| **2: Drift detection** | Store scenario results in history. Compare across runs. Flag regressions. Wire into TQM as `ContextDrift` pattern. | That slow context degradation is caught before it compounds. |
| **3: Auto-generation** | After a successful batch run, freeze the best-performing task/context pairs as new scenarios. Archivist agent proposes scenario text. | That the scenario corpus grows organically from production. |
| **4: Context packages** | Formalize config + scenarios + manifest as the unit of cross-org dependency. Ops-org declares expectations on eng-org outputs. | That multi-org context dependencies are explicit and testable. |

---

## Prior Art

- **Tessl, "Context Development Lifecycle"** (Feb 2026) — The CDLC framework: Generate → Evaluate → Distribute → Observe. Proposes treating context as an engineered artifact with its own quality lifecycle. Direct inspiration for this ADR's structure.
- **Tessl, "The Context Flywheel"** (Feb 2026) — Argues that accumulated context is the durable competitive advantage for AI coding teams. Models commoditize; context compounds. Validates Keiro's thesis from an independent source.
- **desplega-ai, Agent Swarm** — Multi-agent framework with persistent, self-modifying agent identity files. Demonstrates the failure mode this ADR guards against: mutable context with no evaluation or governance.
- **Keiro Batch Run #2** (2026-02-24) — 8 merged PRs demonstrated the pipeline works. But no mechanism exists to verify that the context configuration *responsible for those successes* hasn't regressed since.
- **W. Edwards Deming, *Out of the Crisis*** (1986) — "You cannot inspect quality into a product." Applied here: you cannot TQM quality into context. You must test context at the source, not just observe its downstream effects.

---

*This ADR should be revisited after Phase 1, when real scenario results reveal whether coarse-grained expectations provide sufficient signal or need refinement.*
