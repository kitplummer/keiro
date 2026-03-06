# ADR: Implementation Language for the Agentic Corporation Framework

**Date:** 2026-02-21
**Author:** Kit, with Claude analysis
**Status:** Superseded — Keiro uses Elixir/BEAM with Jido as the agent runtime. Protocol boundaries (A2A, MCP) make agents polyglot. This ADR is retained for historical context.
**Context:** Choosing between Python and Rust for the framework that hosts Keiro and future business-function orgs

---

## The Question

Keiro exists today as ~3,900 lines of Python. The [corporation framework ADR](docs/adr-agentic-corporation-framework.md) defines a system where Keiro is one org among many, running on a shared kernel that provides agent execution, governance (Zephyr), institutional memory (Beads + Dolt), and inter-org communication.

Should the framework be written in Python (extending Keiro's existing codebase) or Rust?

---

## The Case for Python

### 1. Keiro already exists and works

Rob built 3,900 lines of functioning Python. The Controller, all 6 agents, the CLI, workspace isolation, governance, budget tracking, history — it's all there. Rewriting means throwing away working code and re-implementing it. The architecture is clean and modular; it's not legacy debt.

### 2. The LLM ecosystem is Python-first

Every major LLM provider ships a Python SDK first. LiteLLM supports 100+ providers today. Pydantic gives you structured output validation that maps 1:1 to LLM JSON mode. LangChain, LlamaIndex, Instructor — the entire tooling ecosystem is Python. When Anthropic ships a new feature (extended thinking, prompt caching, tool use), the Python SDK gets it first, sometimes months before other languages.

### 3. Agents are I/O bound, not CPU bound

Keiro's agents are thin wrappers that build prompts, call an API, and parse JSON responses. The bottleneck is network latency to LLM providers (200ms-30s per call), not CPU. Python's speed disadvantage is irrelevant when you're waiting on HTTP responses. The GIL doesn't matter for I/O-bound work — asyncio handles concurrent API calls fine.

### 4. Faster iteration on prompt engineering

Agent development is fundamentally prompt engineering. You change a system prompt, run it, look at the output, adjust. Python's REPL, hot reloading, and dynamic typing make this loop fast. Rust's compile-edit-run cycle adds friction to the part of the work that requires the most experimentation.

### 5. Rob's expertise and investment

Rob is the Keiro author. If the framework forces a language change, he's either rewriting his own tool or maintaining a polyglot system. That's a tax on the collaboration.

### 6. Time to validation

The framework needs to prove its architecture (multi-org, governance, memory) before it proves its performance. Python gets you to Phase 3 (standing up a second org, discovering the seams) faster. Architectural mistakes are more expensive to fix in Rust because refactoring is slower.

### 7. Dependencies are simple

Keiro's dependencies (LiteLLM, Pydantic, Typer, Rich, GitPython, httpx, tenacity, PyYAML, loguru) are all mature, well-maintained libraries. The Python dependency story has improved significantly with uv/rye. It's not 2019 anymore.

---

## The Case for Rust

### 1. This is not a dev tool — it's business infrastructure

Keiro-the-dev-tool generates PRs. The agentic corporation framework manages deployments, financial ledgers, governance policies, secrets, and autonomous agents making irreversible real-world decisions. A finance org issuing invoices via Stripe. An ops org scaling production infrastructure. A governance layer enforcing trust boundaries that protect real money and real services.

The reliability bar for infrastructure is categorically different from a developer productivity tool. Python's runtime characteristics — uncaught TypeErrors in production, no compile-time safety, GIL-limited parallelism, memory leaks in long-running processes — are acceptable for a tool you run and discard. They are not acceptable for a system that runs continuously, manages state, and takes autonomous action.

### 2. Type safety is governance

The framework's entire value proposition is governed autonomy — agents can only do what governance allows. In Python, governance policies are runtime checks that can be bypassed by bugs, missed edge cases, or type confusion. A Python function that expects a `ZephyrPolicy` but receives a `dict` won't fail until that code path executes in production.

In Rust, governance is encoded in the type system. If an agent needs a `ToolPermission` to execute a command, the compiler enforces it. If a financial transaction requires a `BudgetApproval`, you can't construct one without going through the approval gate. The type system becomes a second layer of governance that catches violations at compile time, not at 3am when the ops agent is autonomously scaling infrastructure.

```rust
// This is governance as types — you cannot construct an ApprovedAction
// without going through the governance gate
pub struct ApprovedAction<T> {
    inner: T,
    approval: GovernanceReceipt,  // proof that Zephyr approved this
}

impl<T: Action> ApprovedAction<T> {
    // Only constructable through the governance module
    pub(crate) fn new(action: T, receipt: GovernanceReceipt) -> Self { ... }
}
```

Python has no equivalent. Type hints are advisory. `mypy` catches some things but not all, and it's optional. In a system where governance violations have real-world consequences, "advisory" is insufficient.

### 3. True concurrency for multi-org orchestration

The corporation framework runs multiple orgs concurrently. Engineering is building a feature while Ops monitors a deployment while Finance reconciles the ledger. Python's GIL means only one thread executes Python bytecode at a time. Multi-processing adds IPC complexity and memory overhead (each process copies the interpreter).

Rust with Tokio gives you:
- True async concurrency across all orgs on a single process
- Channels for inter-org message passing (typed, zero-copy)
- Work-stealing scheduler for optimal CPU utilization
- No GIL — 64 cores means 64 concurrent org operations

When you're running 5 orgs with 30+ agents making concurrent LLM calls, file operations, database writes, and subprocess invocations, Rust's concurrency model is not a performance optimization — it's an architectural requirement.

### 4. The Rust LLM ecosystem is now viable

As of February 2026, the ecosystem has matured significantly:

| Need | Crate | Maturity |
|------|-------|----------|
| Multi-provider LLM client | `rig-core` 0.31 (5,900 stars) | Strong. Supports Anthropic, Gemini, OpenAI, 20+ more. Streaming, tool use, structured outputs. |
| Thin unified LLM client | `genai` 0.6.0-beta | Good. Closest to LiteLLM in Rust. All major providers. |
| OpenAI client | `async-openai` 0.33 (3.1M downloads) | Production-grade. De facto standard. |
| Structured outputs | `schemars` 1.2 (167M downloads) + serde | Rock solid. Derive JSON schemas from Rust types. |
| Database (Dolt) | `sqlx` 0.8 (73M downloads) | Production-grade. Compile-time checked SQL queries against Dolt's MySQL interface. |
| Subprocess (Beads) | `tokio::process` | Standard library quality. Async subprocess with piped I/O. |
| LLM gateway/routing | TensorZero (9,700 stars, $7.3M funding) | Production-grade. Sub-millisecond P99. Written in Rust. |
| Agent framework | AutoAgents 0.3 | Early but purpose-built for multi-agent coordination. |

This is not the wasteland it was 18 months ago. `rig-core` alone covers what LiteLLM + LangChain provide in Python. `sqlx` is more mature than any Python MySQL connector. `schemars` + `serde` is more rigorous than Pydantic for schema derivation.

### 5. Memory safety for long-running services

The framework runs continuously — monitoring deployments, watching for incidents, processing task queues, maintaining the financial ledger. Python's reference counting + cycle collector leads to memory fragmentation and unpredictable GC pauses in long-running processes. Rust has no garbage collector. Memory is deterministic. A framework that's been running for 30 days uses the same memory profile as day 1.

### 6. Single binary deployment

`cargo build --release` produces one binary. No virtualenv, no pip, no Python version management, no `LD_LIBRARY_PATH` issues, no "it works on my machine." The framework deploys to fly.io as a single binary in a minimal container. This matters when the framework itself needs to be reliable infrastructure.

### 7. Error handling is exhaustive

Rust's `Result<T, E>` forces you to handle every error path. Python's exceptions are opt-in — you handle the ones you think of, and the rest crash at runtime. In a system where an unhandled error in the finance org could leave a ledger in an inconsistent state, or an unhandled error in the ops org could leave a deployment half-complete, exhaustive error handling is not a luxury.

### 8. The ecosystem alignment

Beads is Go. Dolt is Go. Gastown is Go. Zephyr is Rob's (language TBD). The systems-level tooling in this stack is not Python. Rust interops naturally with systems tools via subprocess, FFI, and shared protocols (MySQL, JSON, CLI). Python wrapping Go binaries via subprocess is the same pattern but with more runtime overhead and less type safety at the boundaries.

---

## The Honest Weaknesses of Each

### Python's real weaknesses for this use case

- **No compile-time governance.** Every policy check is a runtime assertion that could be missed.
- **GIL limits true parallelism.** Multi-org concurrent execution requires multiprocessing with IPC overhead.
- **Long-running memory issues.** Memory leaks, GC pauses, and fragmentation in processes that run for weeks.
- **Dynamic typing is a liability at scale.** Type hints are advisory. mypy is optional. Production type errors are inevitable.
- **Dependency hell persists.** Despite uv/rye improvements, transitive dependency conflicts in a growing framework are real.
- **No exhaustive error handling.** Unhandled exceptions crash the process. In a multi-org system, one org's unhandled exception can take down the entire framework.

### Rust's real weaknesses for this use case

- **Rob's codebase is Python.** Keiro must be rewritten or wrapped. This is real work and requires Rob's buy-in.
- **Compile times.** A full build of a framework this size takes 30-90 seconds. Incremental builds are faster but still slower than Python's zero-compile workflow.
- **Pre-1.0 LLM crates.** `rig-core` is 0.31, `genai` is 0.6-beta. APIs may change. You're on the leading edge.
- **Prompt engineering friction.** Changing a system prompt requires recompile. Can be mitigated with runtime-loaded prompt files, but it's extra architecture.
- **Smaller talent pool.** If this becomes a team effort, Rust developers are harder to find than Python developers.
- **Higher initial development time.** The same feature takes longer to write in Rust, especially for developers still learning the borrow checker.

---

## The Hybrid Option (and Why I Reject It)

The obvious compromise: Rust kernel, Python orgs. Build the framework infrastructure in Rust, let Keiro stay Python, communicate via IPC/subprocess/HTTP.

This sounds elegant but creates three problems:

1. **Two build systems, two dependency trees, two deployment artifacts.** The operational complexity doubles. CI builds both. Docker images need both runtimes. Debugging crosses a language boundary.

2. **The boundary is in the wrong place.** The governance layer (Zephyr) must wrap agent execution. If agents are Python and governance is Rust, every agent invocation crosses the language boundary. The overhead and complexity of that bridge undermines the governance guarantees.

3. **It never converges.** The Python side never gets rewritten because "it works." The Rust side gets more capable. You end up maintaining two systems indefinitely, with the Python side as permanent technical debt that limits what the Rust kernel can enforce.

The hybrid approach is the "Python now, Rust later" option in disguise — and "later" never comes.

---

## My Recommendation: Rust

The agentic corporation framework should be written in Rust. Here's why I land here despite the real costs:

**The decisive factor is governance.** The entire framework's value proposition is that autonomous agents operate within enforced boundaries. In Python, those boundaries are runtime assertions — checked when exercised, invisible when not. In Rust, they are types — checked at compile time, enforced by the compiler, impossible to circumvent without explicit `unsafe`.

When the ops org is autonomously scaling production infrastructure and the finance org is autonomously processing transactions, "the type checker guarantees this action was approved by governance" is a fundamentally different safety property than "we wrote a runtime check and hope it's on every code path."

**The cost is real but bounded.** Keiro is 3,900 lines. That's 2-4 weeks of porting for someone who knows both languages. The architecture is clean — the agent pattern, controller pipeline, config system, and governance model all translate directly to Rust with stronger guarantees. The Rust LLM ecosystem (rig-core, sqlx, tokio, schemars) covers every dependency Keiro currently uses.

**The practical path:**

1. Start a new Rust workspace for the framework. Call it what it will become, not what Keiro is today.
2. Implement the kernel first: org trait, agent trait, tool sandbox, governance engine, Dolt-backed history, Beads integration.
3. Port Keiro's agents as the first org running on the kernel. The prompts are text — they copy verbatim. The parsing logic is straightforward serde.
4. Validate against LowEndInsight as the first target project.
5. Stand up Ops as the second org. Discover the seams — now in Rust, with the type system helping you define the right abstractions.

**What about Rob?** This is a conversation that needs to happen. The framework is not Keiro — it's the platform Keiro runs on. Rob can continue developing Keiro in Python as a standalone tool. The framework port is a separate artifact that happens to implement the same agent pipeline. If the framework proves its value, the Python version becomes the prototype that validated the architecture, not wasted work.

---

## Implementation Plan (If Rust Is Chosen)

### Phase 0: Rust Workspace Bootstrap

Create a new Rust workspace with the following crate structure:

```
framework/
├── Cargo.toml              (workspace root)
├── crates/
│   ├── kernel/             (core traits: Org, Agent, Tool, Pipeline, Governance)
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── org.rs          (Org trait + OrgConfig)
│   │       ├── agent.rs        (Agent trait + AgentContext)
│   │       ├── tool.rs         (ToolExecutor + allowlist/blocklist)
│   │       ├── governance.rs   (ZephyrPolicy, BoundaryEnforcer, ApprovedAction<T>)
│   │       ├── pipeline.rs     (Pipeline trait + linear/event-driven/periodic variants)
│   │       ├── budget.rs       (BudgetTracker, UsageRecord)
│   │       └── error.rs        (framework error types)
│   │
│   ├── memory/             (Dolt + Beads integration)
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── dolt.rs         (DoltConnection, DoltHistory, schema management)
│   │       ├── beads.rs        (BeadsClient - subprocess wrapper for bd CLI)
│   │       └── history.rs      (HistoryBackend trait, JSONL fallback)
│   │
│   ├── router/             (LLM routing)
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── router.rs       (model resolution, multi-provider routing)
│   │       ├── response.rs     (RouterResponse, structured output parsing)
│   │       └── providers.rs    (provider-specific adapters via rig-core or genai)
│   │
│   ├── eng-org/            (Keiro port — the engineering org)
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── agents/         (Planner, Implementer, Debugger, Security, Release, Archivist)
│   │       ├── pipeline.rs     (engineering-specific linear pipeline)
│   │       ├── workspace.rs    (git worktree management)
│   │       └── indexer.rs      (repo file discovery)
│   │
│   └── cli/                (binary crate)
│       ├── Cargo.toml
│       └── src/
│           └── main.rs         (clap-based CLI: run, next, status, init, batch, history)
│
└── tests/                  (integration tests)
    ├── kernel_tests.rs
    ├── memory_tests.rs
    ├── router_tests.rs
    └── eng_org_tests.rs
```

### Key Dependencies (Cargo.toml)

```toml
[workspace.dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
sqlx = { version = "0.8", features = ["runtime-tokio", "mysql"] }
rig-core = "0.31"              # or genai = "0.6.0-beta"
schemars = "1.2"
clap = { version = "4", features = ["derive"] }
tracing = "0.1"
tracing-subscriber = "0.3"
thiserror = "2"
anyhow = "1"
uuid = { version = "1", features = ["v4"] }
chrono = { version = "0.4", features = ["serde"] }
```

### Phase 0 Steps

| Step | What | Files | Verification |
|------|------|-------|-------------|
| 0.1 | Workspace + kernel crate with core traits | `kernel/src/*.rs` | `cargo check` compiles |
| 0.2 | Agent trait + AgentContext with serde | `kernel/src/agent.rs` | Unit tests pass |
| 0.3 | ToolExecutor with allowlist/blocklist | `kernel/src/tool.rs` | `cargo test` — allowed/blocked commands |
| 0.4 | BoundaryEnforcer + ApprovedAction<T> | `kernel/src/governance.rs` | Compile-time governance proof |
| 0.5 | BudgetTracker | `kernel/src/budget.rs` | Budget exceeded tests |
| 0.6 | Pipeline trait (linear variant) | `kernel/src/pipeline.rs` | Pipeline runs stages in order |
| 0.7 | Org trait composing all above | `kernel/src/org.rs` | Org can be constructed and run |

### Phase 1 Steps

| Step | What | Files | Verification |
|------|------|-------|-------------|
| 1.1 | DoltConnection + schema init | `memory/src/dolt.rs` | Connects to dolt sql-server, creates tables |
| 1.2 | DoltHistory (HistoryBackend impl) | `memory/src/history.rs` | Record + query tasks via SQL |
| 1.3 | BeadsClient (subprocess wrapper) | `memory/src/beads.rs` | `bd ready --json` parsed correctly |
| 1.4 | JSONL fallback history | `memory/src/history.rs` | Works without Dolt installed |
| 1.5 | Router crate with rig-core | `router/src/*.rs` | LLM call returns structured response |
| 1.6 | Port Planner agent | `eng-org/src/agents/planner.rs` | Prompt matches, JSON output parses |
| 1.7 | Port remaining 5 agents | `eng-org/src/agents/*.rs` | All agents produce valid output |
| 1.8 | Port workspace (git worktree) | `eng-org/src/workspace.rs` | Create, commit, cleanup worktree |
| 1.9 | Port indexer | `eng-org/src/indexer.rs` | Index Keiro repo correctly |
| 1.10 | Engineering pipeline (Controller port) | `eng-org/src/pipeline.rs` | Full plan->implement->test->debug->security->release->PR |
| 1.11 | CLI | `cli/src/main.rs` | `run`, `next`, `status`, `init`, `history` commands |

### Phase 2 Steps

| Step | What | Verification |
|------|------|-------------|
| 2.1 | E2E: run against LowEndInsight | PR created on lowendinsight repo |
| 2.2 | E2E: run against Keiro itself | PR created on glitchlab repo |
| 2.3 | Beads integration: `next` command | Pulls from ready queue, runs, closes bead |
| 2.4 | Dolt history: query past runs | `status` command shows SQL-queried history |
| 2.5 | Stand up Ops org skeleton | Second org compiles, registers with kernel |

---

## Risks of the Rust Path

| Risk | Severity | Mitigation |
|------|----------|------------|
| Rob disagrees with language choice | High | This ADR is input to that conversation, not a unilateral decision. Keiro-Python can coexist as a standalone tool. |
| rig-core breaking changes (pre-1.0) | Medium | Pin version. Wrap in internal adapter trait so provider can be swapped. |
| Development takes 2x longer than Python | Medium | Offset by fewer runtime bugs, no debugging type errors in production, less rework. |
| Prompt engineering friction | Low | Load prompts from YAML/TOML files at runtime, not compiled in. Hot-reload in dev mode. |
| Compile times slow iteration | Low | Use `cargo-watch` for auto-rebuild. Workspace structure means only changed crates recompile. |

---

## Decision

**Recommendation: Rust.**

The framework is business infrastructure, not a dev tool. Governance must be enforced at the type level. Concurrency must be real, not GIL-limited. The system runs continuously and manages state with real-world consequences. The Rust LLM ecosystem is now mature enough. The cost of the port is bounded (3,900 lines, clean architecture). The cost of building on Python and discovering its limitations at scale is unbounded.

Start the Rust workspace. Port Keiro as the first org. Validate against LowEndInsight. Discuss with Rob.
