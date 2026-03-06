# ADR: Implementation Strategy — Native Tool Use vs. Raw LLM API

**Date:** 2026-02-22
**Author:** Kit, with Claude analysis
**Status:** Accepted
**Informed by:** PR #2 post-mortem (Keiro self-dogfooding attempt)

---

## Context

Keiro's pipeline calls LLM APIs directly for implementation: the implementer agent sends a single prompt and expects a JSON blob containing all file changes (creates, modifies, deletes) with full file content or unified diffs. PR #2 — the first successful end-to-end pipeline run — revealed fundamental limitations of this approach:

1. **The implementer produced incomplete changes.** `greeting.rs` was created with only a test module but no actual function. `lib.rs` was never modified (no `mod greeting;` added).
2. **Tests "passed" because the orphan file was never compiled.** Without a `mod` declaration, Rust ignores the file entirely.
3. **Modify actions with null content silently did nothing.** The pipeline wrote no error, created no warning — it just skipped the file and moved on.

The root cause is not prompting quality. The root cause is architectural: **code implementation is an iterative, tool-using task that cannot be reliably reduced to a single-shot JSON generation.**

A system like Claude Code succeeds at the same task because it can read files, edit specific lines, run `cargo check`, see compiler errors, and iterate. The raw API cannot.

---

## Decision

**Keiro will build its own provider-agnostic tool-use execution loop for the implementer and debugger agents, rather than depending on any vendor-specific agent runtime (Claude Code, Codex CLI, etc.).**

### Why Not Ride on Claude Code (Gastown Approach)?

Gastown's architecture delegates implementation to a Claude Code session. This is pragmatically effective but creates a hard dependency on a single vendor's agent runtime:

| Concern | Impact |
|---------|--------|
| **Vendor lock-in** | Claude Code is Anthropic-only. Cannot use Gemini, GPT, Llama, Mistral, or local models for implementation. |
| **No local model support** | A core project objective is running on local models when viable. Claude Code cannot be pointed at a local llama.cpp server. |
| **Opaque execution** | Claude Code is a black box. Keiro cannot inspect, govern, or budget individual tool calls within a Claude Code session. |
| **Governance gap** | Zephyr cannot enforce tool policies inside Claude Code's execution — it has its own permission model. |
| **Availability dependency** | If Anthropic's agent infrastructure has an outage, Keiro cannot implement anything. |

### What We Will Build Instead

A tool-use execution loop in the router/agent layer that:

1. **Sends the initial prompt** to any LLM via the existing provider-agnostic router (Anthropic, OpenAI, Gemini, local models).
2. **Exposes a tool schema** with a small set of code-editing tools: `read_file`, `write_file`, `edit_file`, `run_command`, `list_files`.
3. **Executes tool calls** returned by the LLM in a sandboxed environment (the git worktree), governed by Keiro's existing tool allowlist and blocked patterns.
4. **Returns tool results** to the LLM for the next turn.
5. **Iterates** until the LLM signals completion or the budget is exhausted.

This gives us Claude Code's iterative capability without Claude Code's vendor lock-in.

### Tool Schema (Minimal Viable Set)

```yaml
tools:
  - name: read_file
    description: Read the contents of a file in the repository
    parameters:
      path: string  # relative to repo root

  - name: write_file
    description: Create or overwrite a file
    parameters:
      path: string
      content: string

  - name: edit_file
    description: Replace an exact string in a file with new content
    parameters:
      path: string
      old_string: string
      new_string: string

  - name: run_command
    description: Run a shell command (subject to allowlist)
    parameters:
      command: string

  - name: list_files
    description: List files matching a glob pattern
    parameters:
      pattern: string
```

This is deliberately minimal. Five tools cover file I/O, command execution, and discovery. The LLM decides how to use them based on the task.

### Provider Compatibility

Tool use / function calling is supported by all major providers:

| Provider | Tool Use Support |
|----------|-----------------|
| Anthropic (Claude) | Native tool_use blocks |
| OpenAI (GPT) | function_calling / tools |
| Google (Gemini) | function_declarations |
| Local (llama.cpp, Ollama, vLLM) | OpenAI-compatible tool calling |

The router already abstracts provider differences. Adding tool-call marshaling to the provider trait is a natural extension.

### Governance Integration

Every tool call passes through Keiro's existing governance layer:

- `run_command` checked against `allowed_tools` and `blocked_patterns`
- `write_file` / `edit_file` checked against `boundaries.protected_paths`
- All tool calls tracked in the budget (token cost of the turn that produced them)
- Maximum turns per task enforced via `limits.max_tool_turns` (new config field)

This is the critical advantage over delegating to Claude Code: **Keiro governs every tool invocation**, not just the initial prompt.

---

## Consequences

### Positive

- **Provider agnostic.** Any model that supports tool use can be the implementer — Claude, GPT, Gemini, Llama, Mistral, or whatever ships next.
- **Local model support.** A local model served via Ollama or vLLM with OpenAI-compatible tool calling works out of the box.
- **Full governance.** Every tool call is visible to Zephyr, logged, budgeted, and policy-checked.
- **Debuggable.** The tool-call transcript is stored in history — you can see exactly what the LLM read, wrote, and ran.
- **Iterative implementation.** The LLM can read a file, edit it, run `cargo check`, see the error, and fix it — just like a human developer.

### Negative

- **More code to build and maintain.** The tool execution loop, sandbox, and provider-specific tool-call marshaling are real implementation work.
- **Slower than single-shot.** Multi-turn tool use means multiple LLM round-trips per implementation. A 5-turn implementation costs ~5x a single-shot call in latency and tokens.
- **Tool-use quality varies by model.** Smaller/local models may struggle with multi-step tool use. The pipeline needs graceful degradation (fall back to single-shot JSON if tool use fails).
- **New failure modes.** Infinite loops, tool-call hallucinations (calling tools that don't exist), and budget exhaustion mid-implementation all need handling.

### Transitional

The existing single-shot JSON implementation continues to work as a fallback. The tool-use loop is an enhancement to the implementer and debugger agents, not a replacement of the entire pipeline. Planning, security review, release assessment, and archiving remain single-shot — they are analysis tasks where one-shot works well.

---

## Alternatives Considered

### 1. Ride on Claude Code (Gastown approach)

Spawn a Claude Code subprocess for implementation. Gets tool use for free. Rejected because it hard-locks the implementer to Anthropic and prevents local model use. See detailed comparison above.

### 2. Ride on OpenAI Codex CLI

Same trade-off as Claude Code but locked to OpenAI. Additionally, Codex CLI is newer and less proven than Claude Code. Rejected for the same vendor lock-in reasons.

### 3. Use an open-source agent framework (SWE-agent, Aider, etc.)

These provide tool-use loops but with their own opinions about prompting, context management, and execution. Integrating one means adopting its abstractions, which may conflict with Keiro's governance model. Additionally, most are Python-only. Rejected because Keiro needs to own the execution loop to enforce governance.

### 4. Keep single-shot JSON, just improve prompting

Better prompts and structured output enforcement could improve single-shot quality. But the fundamental limitation remains: the LLM cannot verify its own output without tools. A perfect prompt still can't make the LLM run `cargo check`. This is a ceiling, not a quality knob. Rejected as insufficient.

---

## Implementation Path

| Phase | What | Validates |
|-------|------|-----------|
| **0** | Add `ToolCall` and `ToolResult` types to kernel | Type system supports tool-use conversations |
| **1** | Extend `Provider` trait with `complete_with_tools` | Router can marshal tool schemas per provider |
| **2** | Implement tool executor in eng-org (sandboxed, governed) | Tools execute in worktree, respect allowlist |
| **3** | Add tool-use loop to implementer agent | Implementer iterates: prompt → tool calls → results → next turn |
| **4** | Add tool-use loop to debugger agent | Debugger can read test output, edit files, re-run tests |
| **5** | Add `max_tool_turns` to config, budget tracking per turn | Governance controls iteration depth |
| **6** | Test with local model (Ollama + llama.cpp) | Validates provider-agnostic claim |

Phases 0-3 are the critical path. Phases 4-6 can follow incrementally.

---

*This ADR should be revisited after Phase 3, when the tool-use loop has been validated against real implementation tasks with multiple providers.*
