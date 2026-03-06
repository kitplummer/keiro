# ADR: TQM — Self-Improvement as First-Degree Architecture

**Date:** 2026-02-25
**Authors:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** Second Keiro batch run (2026-02-24, 10 tasks / $5.00 budget), decomposition loop incident (gl-5in.6-part1, 274 decompositions, $1.49), production outcomes (8 merged PRs)

---

## Context

Keiro's second batch run proved the pipeline works end-to-end: 8 merged PRs delivered real features (planner chunking, ollama tool-use, failure tracker, multi-org schema, ops config docs). But it also exposed a critical failure mode: task `gl-5in.6-part1` decomposed **274 times** in an infinite loop, consuming $1.49 of the $5.00 budget on a single task.

The decomposition loop is a system-level bug, not a task-level failure. The planner correctly identifies that a task is too large, decomposes it into sub-tasks — but those sub-tasks themselves get decomposed, ad infinitum. No depth limit existed.

The immediate fix (decomposition depth limit) is straightforward. But the deeper insight is: **why did Keiro need a human to notice this?** The orchestrator already has all the data to detect this pattern — it processes every pipeline result, tracks every status transition, records every cost. It simply doesn't look at the data after the run.

This is the same problem that TQM (Total Quality Management) solved in manufacturing: the production line should inspect its own output and feed defect patterns back into process improvement.

---

## Decision

### Keiro should improve itself as it runs.

This is a first-degree architectural principle, not a feature. Every component should be designed with the assumption that the system will analyze its own behavior and generate improvement tasks.

### 1. Post-Run Analysis (TQMAnalyzer)

After the orchestrator loop completes, a `TQMAnalyzer` scans `OrchestratorResult` + `Vec<TaskRunResult>` for known failure patterns and emits beads describing bugs and proposed fixes.

```
[Orchestrator Loop]
        |
        v
[OrchestratorResult + run_results]
        |
        v
[TQMAnalyzer::analyze()]
        |
        v
[Vec<Bead>] → injected into beads graph
```

### 2. Pattern Detection

The analyzer recognizes these failure signatures:

| Pattern | Signal | Threshold |
|---------|--------|-----------|
| Decomposition loop | >N sequential decompositions from same root | 3 |
| Scope creep | >N ScopeTooLarge obstacles in one batch | 3 |
| Model degradation | >N ParseFailure/ModelLimitation from same model | 3 |
| Stuck agents | >N max_stuck_turns hits | 3 |
| Test flakiness | >N TestFailure from same test file | 2 |
| Architect rejection rate | >N% ArchitectRejected in batch | 50% |
| Budget pressure | >N tasks hitting max_dollars_per_task | 3 |
| Provider failures | >N ExternalDependency from same service | 3 |

These thresholds are configurable via `TQMConfig`.

### 3. In-Loop Monitoring (Restart Intensity)

Borrowed from OTP: track failure frequency within a time window. If >N tasks fail within M minutes, the orchestrator emits `CeaseReason::SystemicFailure` and halts, preventing budget burn on systemic issues (provider outage, broken base branch, missing API keys).

### 4. Negative Context Injection

When a task is retried (Deferred or Retryable), the planner prompt includes structured context from previous failures. `OutcomeContext` already captures approach, obstacle, discoveries, and recommendation — wire these into the prompt so the agent learns from its own failures instead of repeating the same approach.

### 5. Priority Injection

TQM-generated beads that fix infrastructure bugs get elevated priority in the next batch. The system's self-improvement tasks should run before new feature work, because infrastructure bugs compound (as the decomposition loop demonstrated: one bug consumed 30% of the batch budget).

---

## Consequences

### Positive

- **Compounding improvement**: Each batch run makes the next one more efficient. The decomposition loop fix means future batches won't burn budget on infinite decomposition.
- **Reduced human supervision**: The system detects its own failure patterns instead of requiring a human to grep through logs.
- **Structural learning**: OutcomeContext injection means agents learn from prior attempts within the same batch, not just across batches.
- **Dogfooding**: Keiro uses its own issue tracker (beads) to track its own bugs. The system is a user of itself.

### Negative

- **Complexity**: Post-run analysis adds another system to maintain. Mitigated by keeping the analyzer stateless and pattern-based (no ML, no persistent state beyond beads).
- **False positives**: Pattern detection may flag normal behavior as anomalous. Mitigated by configurable thresholds and `auto_create_beads: false` as default (analysis only, no auto-creation until validated).
- **Recursive risk**: If TQM-generated beads themselves cause failures, the system could enter a meta-loop. Mitigated by labeling TQM beads and excluding them from TQM analysis.

### Trade-offs

- **Simplicity vs. sophistication**: Start with threshold-based pattern matching, not statistical analysis. The first patterns (decomposition loops, provider failures) are deterministic — counting is sufficient. Statistical detection can come later.
- **Auto-fix vs. auto-report**: Initially, TQMAnalyzer reports patterns as beads but does not auto-fix. The beads enter the normal backlog and are prioritized alongside feature work. Auto-fix (e.g., auto-adjusting thresholds) is a future capability.

---

## Implementation Plan

Seeded as beads in the Keiro backlog:

| Bead | Title | Priority |
|------|-------|----------|
| `gl-tqm` | TQM epic | P1 |
| `gl-tqm.1` | TQMAnalyzer: post-run pattern detection | P1 |
| `gl-tqm.2` | TQMConfig: config section + CLI flags | P1 |
| `gl-tqm.3` | Pattern-to-bead templates | P2 |
| `gl-tqm.4` | Queue priority injection for TQM beads | P2 |
| `gl-tqm.5` | Negative context injection (OutcomeContext → planner prompt) | P1 |
| `gl-tqm.6` | Restart intensity monitoring | P2 |

The decomposition depth limit (implemented in this same commit) is the first concrete fix that TQM *would have generated* if it existed. It serves as proof-of-concept for the pattern: observe failure → create bead → fix infrastructure.

---

## References

- OTP Design Principles: restart intensity, one-for-one supervision
- W. Edwards Deming, *Out of the Crisis* (1986) — PDCA cycle applied to software
- ADR: Supervision Trees and Failure-as-Learning (2026-02-24)
- Batch run 2 incident report: gl-5in.6-part1 decomposition loop
