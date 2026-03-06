# ADR: Implementer Token Efficiency

**Date:** 2026-02-26
**Author:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** Canary run analysis — implementer wastes 3-7 tool turns on file discovery despite pre-seeded context, repeated `list_files` loops account for 2/17 failures

---

## Context

The implementer agent is the most expensive stage in the pipeline. It's the only agent with multi-turn tool use, and its token consumption dominates the per-task budget. Canary runs reveal systematic inefficiency:

| Waste pattern | Token cost | Frequency |
|---|---|---|
| `list_files` on crate root to understand project structure | 2-4k per call | Nearly every task |
| `list_files` on subdirectories to find target file | 1-2k per call | Most tasks |
| `read_file` on files the planner already identified | 2-3k per file | Most tasks |
| Repeated `list_files` in stuck loops | 8-20k total | ~12% of tasks |
| Reading `Cargo.toml` / `mod.rs` to understand module relationships | 1-2k per file | Most Rust tasks |

A task that needs 1 edit in 1 known file can burn 15-20k tokens just finding that file. With the proposed 30k budget (see companion ADR), this leaves only 10-15k for actual work — dangerously thin.

### What already exists

The pre-seeding feature (landed in the short-circuit PR) loads `files_likely_affected` into the implementer's `file_context`. The Rust module map injects `pub mod` declarations so the LLM doesn't need to read `lib.rs`/`mod.rs` files.

But the implementer **ignores both**. It still calls `list_files` because:

1. The system prompt describes `list_files` as the primary navigation tool and doesn't mention pre-loaded context.
2. The pre-loaded files appear in the user message, but the LLM's trained behavior is to explore before editing.
3. For decomposed sub-tasks, `files_likely_affected` isn't propagated from the parent (separate fix in the decomposition ADR).

---

## Decision

### 1. Restructure the implementer system prompt

The current prompt describes tools neutrally. The new prompt should establish a **hierarchy of context sources** and make exploration a last resort.

Key additions to the implementer system prompt:

```
## Context hierarchy

You have been given pre-loaded context. Use it in this order:

1. **Pre-loaded files** (in the "Files" section below) — These are the files
   identified by the planner as needing changes. They are already loaded.
   DO NOT re-read them with `read_file`. DO NOT call `list_files` to find them.

2. **Rust Module Map** (if present below) — Shows `pub mod` and `pub use`
   declarations for relevant crates. Use this to understand module relationships
   instead of reading `lib.rs` or `mod.rs` files.

3. **Tools** — Only use `list_files` or `read_file` if you need a file that
   is NOT in the pre-loaded context. This should be rare for well-decomposed tasks.

## Budget constraint

You have ~5 tool turns. Each tool call costs budget. Prioritize:
1. Write the code change (1 turn)
2. Run `cargo check` or `cargo test` (1 turn)
3. Fix any errors (1-2 turns)
4. Final verification (1 turn)

Do NOT spend turns on exploration. The files you need are pre-loaded.
```

### 2. Remove `list_files` from short-circuit tasks

When a task is short-circuit eligible (1-2 files, ≤3 steps, pre-loaded context), the `list_files` tool should not be offered to the implementer. Removing the option eliminates the temptation entirely.

Implementation: in the tool dispatch setup for the implementer, conditionally filter out `list_files` when `use_short_circuit` is true.

This is aggressive but safe for short-circuit tasks — the files are pre-loaded, and if the implementer truly needs a file that wasn't predicted, the task should have been decomposed differently.

### 3. Add a `read_file` deduplication check

When the implementer calls `read_file` on a path that's already in `file_context`, return the cached content immediately without counting it as a tool turn. This prevents double-reading without breaking the tool interface.

Implementation: in the tool dispatcher, before executing `read_file`, check if the path exists in `ctx.agent_context.file_context`. If so, return the cached content with a note: `"[File already in context — returned from cache]"`.

### 4. Track tool-turn waste as a TQM signal

Add a counter for "redundant tool calls" — calls to `list_files` or `read_file` that return information already available in context. When this exceeds a threshold (e.g., 2 redundant calls per task), emit a TQM event that can inform prompt tuning.

Fields to track in the pipeline events:

```rust
pub struct ImplementerEfficiency {
    pub total_tool_calls: u32,
    pub redundant_tool_calls: u32,
    pub list_files_calls: u32,
    pub tokens_on_exploration: u64,
    pub tokens_on_edits: u64,
}
```

This data feeds into the TQM loop: if redundant calls remain high after prompt changes, the system can self-diagnose the pattern and flag it.

---

## Consequences

### Positive

- **3-5x token reduction on typical tasks.** Eliminating file discovery saves 10-20k tokens per task. Combined with the 30k ceiling, tasks become very focused.
- **Fewer stuck loops.** `list_files` loops (12% failure rate) are eliminated for short-circuit tasks and discouraged for others.
- **Faster completion.** Fewer tool turns means fewer LLM round-trips. A 5-turn task completes in ~15-30 seconds vs. 2-5 minutes for a 15-turn task.
- **Observable waste.** The TQM signal makes token waste visible and trackable across runs.

### Negative

- **Prompt sensitivity.** The implementer's behavior depends heavily on prompt wording. Different models may respond differently to "don't explore" instructions.
- **Brittle if pre-loading fails.** If `files_likely_affected` is wrong or incomplete, the implementer has no escape hatch on short-circuit tasks (no `list_files`). This makes planner accuracy critical.
- **Over-optimization risk.** A 5-turn budget leaves no room for unexpected complications (import changes, type errors cascading). Some tasks will fail that would have succeeded with 10 turns.

### Mitigation for brittleness

- The short-circuit path is already conservative (1-2 files, ≤3 steps). If pre-loading is wrong for these trivially scoped tasks, the planner is badly broken.
- Non-short-circuit tasks retain `list_files` — the restriction only applies to the fast path.
- The `read_file` cache means "wasted" reads are free, so the downside of a cautious implementer is minimal.

---

## Alternatives Considered

### 1. Fine-tune the implementer model on efficient tool use

Train or prompt-tune a model that naturally avoids exploration when context is pre-loaded.

Deferred because:
- Requires a training dataset of efficient vs. wasteful tool-use traces.
- Model fine-tuning is expensive and model-specific (would need separate tunes for Gemini Flash, Claude, etc.).
- Prompt engineering achieves 80% of the benefit at 1% of the cost.

### 2. Rate-limit `list_files` calls

Allow `list_files` but cap it at 1 call per task. After that, return an error.

Rejected because:
- Arbitrary limits create confusing failure modes. The LLM doesn't understand "you're rate-limited."
- Better to not offer the tool (short-circuit) or de-prioritize it in the prompt (full pipeline).

### 3. Replace `list_files` with a smarter index tool

Instead of raw directory listings, provide a `search_codebase` tool that returns relevant file paths for a query.

Deferred because:
- Requires building/maintaining a code search index.
- The module map already provides structural navigation for Rust projects.
- Pre-loaded files eliminate the need for search in most cases.
- Worth revisiting for polyglot repos where the module map doesn't apply.

### 4. Do nothing — let the 30k ceiling naturally constrain waste

The tight budget means wasteful exploration fails fast (budget exhaustion). The implementer "learns" by retry with a fresh budget.

Rejected because:
- Burning 30k tokens on exploration and then retrying is worse than not exploring in the first place.
- Retries cost 2x. Prevention costs nothing.
- The TQM loop can detect waste but can't prevent it mid-task.

---

## Implementation Path

| Phase | What | Validates |
|---|---|---|
| **1** | Restructure implementer system prompt with context hierarchy and budget guidance | Reduced `list_files` calls in canary |
| **2** | Remove `list_files` from short-circuit tool set | Zero exploration on trivial tasks |
| **3** | Add `read_file` deduplication in tool dispatcher | No double-reads |
| **4** | Add `ImplementerEfficiency` tracking to pipeline events | Observable waste metrics |
| **5** | Canary run to validate | Token usage per task, redundant call rate |

Phase 1 is the highest-leverage change and should land first. Phase 2 depends on the short-circuit fix (already landed). Phases 3-4 are independent and can be done in parallel.

---

*This ADR should be revisited after one canary run with the new prompt. Key metrics: average tokens per successful task, `list_files` calls per task, redundant call rate. Target: <15k tokens average for short-circuit tasks, <25k for full-pipeline tasks.*
