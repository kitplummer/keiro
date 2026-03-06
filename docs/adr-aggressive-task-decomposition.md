# ADR: Aggressive Task Decomposition

**Date:** 2026-02-26
**Author:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** Canary run analysis — 63% of failures were token-limit exhaustion (120k ceiling), simple tasks burning full budgets on exploration

---

## Context

Keiro's per-task token budget is currently 120k tokens (~15 tool turns). Canary runs show this is far too generous:

| Observation | Data |
|---|---|
| Token-limit failures | 4/17 failures in latest canary hit 120k ceiling |
| Typical successful task | 5-50k tokens |
| Wasted exploration | Implementer burns 3-5 turns on `list_files` before touching code |
| Decomposition effectiveness | Decomposed sub-tasks succeed at higher rates than monolithic tasks |

The planner's decomposition rules are tuned for a 120k budget:

- Decompose when touching 3+ files
- Decompose when requiring 4+ steps
- Decompose when a target file exceeds ~300 lines

These thresholds are too loose. A sub-task that touches 2 files and takes 3 steps can still burn 80k+ tokens if the implementer explores the crate structure, reads adjacent modules, and runs multiple test cycles.

### The 30k target

Reducing `max_tokens_per_task` from 120k to 30k (a 4x reduction) forces a structural shift:

- **30k tokens ≈ 5-7 tool turns.** Each turn costs ~2-5k tokens (request + response + tool results).
- A sub-task can realistically: read 1-2 pre-loaded files, make 1-2 edits, run `cargo check` once.
- This matches what efficient Claude Code sessions look like for atomic changes.

The planner must decompose more aggressively to produce sub-tasks that fit this budget.

---

## Decision

### 1. Reduce `max_tokens_per_task` to 30,000

In `.glitchlab/config.yaml`:

```yaml
limits:
  max_tokens_per_task: 30000
```

This is the hard ceiling enforced by the budget tracker. Tasks exceeding it are terminated with `BudgetExhausted`.

### 2. Tighten planner decomposition rules

Update the planner system prompt's decomposition section:

```
## Token budget constraint

The implementer has a STRICT budget of ~30K tokens per task (~5 tool turns).
A single file read costs 1-3K tokens. A test + build cycle costs 3-5K tokens.
That means each sub-task can realistically read 1-2 files and make 1-2 edits.

## Task decomposition

You MUST decompose the task when ANY of these conditions are true:
- It would touch 2+ files
- It would require 3+ steps
- Any target file is likely >150 lines
- It modifies a struct/type used across multiple modules
- estimated_complexity is "medium" or "large"

Each sub-task MUST:
- Touch exactly 1 file (2 only if the second is a test file)
- Require at most 1-2 edits
- Be completable within ~5 tool turns
- Include the specific file path AND line-range hints (e.g. "lines 200-250")
- Include a `files_likely_affected` array (this is used for file pre-loading)
```

Key changes from current prompt:
- File threshold: 3+ → 2+
- Step threshold: 4+ → 3+
- Line threshold: 300 → 150
- Sub-task file limit: 1-2 files → exactly 1 (+ optional test file)
- Sub-task turn limit: ~10 → ~5
- Sub-tasks must include `files_likely_affected` (currently only parent tasks do)

### 3. Propagate `files_likely_affected` through decomposition

Currently, `extract_sub_tasks()` in `orchestrator.rs` creates sub-Task objects with only `id`, `objective`, and `depends_on`. The `files_likely_affected` from the planner output is lost.

Two changes needed:

**a. Planner schema update:** Add `files_likely_affected` to the decomposition sub-task schema:

```json
{
  "decomposition": [
    {
      "id": "parent-part1",
      "objective": "Add error variant to ErrorKind enum",
      "depends_on": [],
      "files_likely_affected": ["crates/kernel/src/error.rs"]
    }
  ]
}
```

**b. Orchestrator propagation:** `extract_sub_tasks()` should store `files_likely_affected` on the sub-task's metadata so the planner (running on the sub-task) can use it, and the pre-seeding logic can load those files.

### 4. Add `max_tool_turns` enforcement

The current `max_tool_turns: 15` in config is not enforced — the implementer tool loop runs until tokens are exhausted or the LLM stops calling tools. Wire this into the implementer's tool-use loop as a hard stop.

At 30k tokens, 5-7 turns is the natural ceiling, but explicit enforcement prevents runaway loops that burn tokens on repeated failed attempts.

---

## Consequences

### Positive

- **Token waste eliminated.** Tasks that currently burn 80-120k tokens on exploration will be forced to complete in 30k or be decomposed further.
- **Higher success rate.** Smaller, more focused sub-tasks are more likely to succeed. The implementer receives pre-loaded files and doesn't need to explore.
- **More parallelizable.** Many small sub-tasks can run concurrently (when dependency-free) vs. one large task running sequentially.
- **Faster feedback.** A 30k task completes in ~30 seconds vs. ~5 minutes for a 120k task. Failures surface faster.
- **Cost reduction.** At $0.15/M tokens (Gemini Flash), 30k costs ~$0.005 vs. ~$0.018 for 120k. Per task this is small, but across 40+ tasks per run it compounds.

### Negative

- **More sub-tasks per run.** A task that was 1 monolithic unit becomes 3-5 sub-tasks. The orchestrator processes more items, and dependency chains get longer.
- **Decomposition quality is critical.** Bad decomposition (missing files, wrong line ranges, unclear objectives) wastes more budget because each failed sub-task has less room to self-correct.
- **Cross-file changes are harder.** A refactor touching 5 files becomes 5+ sequential sub-tasks with dependency chains. The implementer can't see the full picture.
- **Planner cost increases slightly.** More decomposition means the planner prompt is more complex and its output is larger. Offset by savings in implementer.

### Risk: 30k is too tight

If 30k proves too restrictive (high failure rate on legitimate tasks), the escape hatch is straightforward:
- Increase to 40k or 50k
- Adjust planner thresholds accordingly
- The architecture doesn't change — only the numbers

---

## Alternatives Considered

### 1. Keep 120k, improve the implementer

Teach the implementer to be more efficient within the existing budget. Don't force decomposition.

Rejected because:
- The implementer is an LLM — its token efficiency depends on prompt engineering, not code. You can't guarantee it won't explore.
- 120k is enough rope to hang itself. A tight budget is a structural constraint the LLM can't ignore.
- This is addressed separately in the companion ADR (implementer token efficiency), but it's a belt-and-suspenders situation — both constraints are needed.

### 2. Dynamic budget based on complexity

Give trivial tasks 20k, small tasks 40k, medium tasks 80k, large tasks 120k.

Deferred because:
- Adds config complexity.
- The planner's complexity label is unreliable (see short-circuit fix — it says "medium" for everything).
- A uniform 30k ceiling forces the planner to decompose, which is the desired behavior.
- Can be revisited if the uniform ceiling proves too rigid.

### 3. 50k as a compromise

Split the difference between 30k (aggressive) and 120k (current).

Possible fallback, but:
- 50k still allows ~10 tool turns, which is enough for the implementer to waste turns on exploration.
- The goal is to make exploration impossible, not merely expensive.
- Start at 30k, loosen if needed. Easier to relax a constraint than to tighten one.

---

## Implementation Path

| Phase | What | Validates |
|---|---|---|
| **1** | Update planner prompt with new decomposition rules and budget constraint | Planner produces smaller sub-tasks |
| **2** | Add `files_likely_affected` to decomposition schema + propagate through orchestrator | Sub-tasks carry file context |
| **3** | Enforce `max_tool_turns` in implementer tool loop | Runaway loops are impossible |
| **4** | Set `max_tokens_per_task: 30000` in config | Hard ceiling active |
| **5** | Canary run to validate | Success rate, token usage, failure modes |

Phases 1-3 should land before Phase 4. Dropping the token limit without the decomposition improvements would cause mass failures.

---

*This ADR should be revisited after one full canary run at the 30k ceiling. If the failure rate exceeds 30%, consider loosening to 40-50k and investigating which task types fail.*
