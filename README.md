# Keiro

**Corporate Agentic Organization (CAO) framework.**

Keiro (経路, "path/route") is an orchestration framework for autonomous multi-org agent systems. It manages the full lifecycle of agentic work — task routing, governance gates, budget enforcement, self-improvement loops — across business-function orgs (engineering, operations, finance, GTM, legal).

Built on Elixir/BEAM with [Jido](https://jido.run) as the agent runtime. Polyglot at the agent boundary via [A2A](https://google.github.io/A2A/) and [MCP](https://modelcontextprotocol.io/) protocols.

## Architecture

```
Keiro CAO
├── Orchestrator ─── continuous polling loop, circuit breaker, task routing
│   ├── Governance ── input validation, prompt assembly, approval gates
│   ├── TQM ──────── pattern detection, remediation beads, dedup cooldown
│   └── Pipeline ──── multi-stage runner with structured outcomes
│
├── Orgs
│   ├── Engineering
│   │   ├── EngineerAgent ── Claude Code in isolated git worktrees
│   │   └── Actions ──────── file I/O, shell, git commit/push, gh pr create
│   ├── Operations
│   │   ├── UplinkAgent ──── fly deploy, smoke test, SSH, logs
│   │   └── HealthMonitor ── periodic checks, investigation beads
│   └── Architecture
│       └── ArchitectAgent ── issue triage, backlog review, ADR gap analysis
│
├── Workspace Isolation
│   ├── GitWorktree ── branch-per-task, fetch from origin, cleanup after
│   ├── TempDir ────── ephemeral scratch directories
│   └── Directory ──── passthrough (no isolation)
│
└── Memory
    ├── Beads ── distributed task graph (bd CLI)
    └── Git ──── repo state, worktrees, audit trail
```

## Why

Existing agentic frameworks make you choose: easy orchestration (Python/LangGraph) or robust concurrency (build your own). None provide governance, budget enforcement, or multi-org coordination as first-class primitives.

Keiro's thesis:
- **BEAM is the right runtime for agent orchestration.** Lightweight processes, supervision trees, fault isolation, preemptive scheduling — what Python frameworks are rebuilding from scratch, Erlang/OTP has had for 30 years.
- **Agents should be polyglot.** The orchestrator manages governance and routing. Agents are services that speak A2A/MCP. Claude Code, a Python crew, a Rust binary — all participate equally.
- **Governance is not optional.** Budget caps, approval gates, and autonomy dials are architectural primitives, not afterthoughts.
- **Failure is a signal, not a bug.** OTP-inspired supervision: structured outcomes (Completed, Deferred, Decomposed, Blocked, Retryable, Escalated), negative context injection, self-repair via TQM.

## Status

**Phase 1 — Autonomous Loop.** Keiro runs continuous batch sessions end-to-end: engineering tasks are picked from the beads backlog, implemented in isolated git worktrees, tested, committed, pushed, and PRs opened — then deploy beads are created and handed off to the ops org for fly.io deployment and smoke testing.

Working today:
- **Continuous mode** (`mix keiro.continuous`) — budget-paced polling loop with stall watchdog and graceful shutdown
- **Engineer pipeline** — Claude Code subprocess in isolated git worktrees, NDJSON streaming with idle/max timeout
- **Ops org** — UplinkAgent with fly deploy, smoke test, SSH, and log actions
- **Architect org** — GitHub issue triage, backlog review, ADR gap analysis, periodic scans
- **Governance** — input validation, prompt assembly, batch auto-approval
- **TQM** — pattern detection on batch results, remediation bead creation with dedup cooldown
- **Circuit breaker** — trips after N failures in a time window, manual resume
- **Health monitoring** — periodic HTTP + fly status checks, auto-creates investigation beads
- **Telemetry** — structured spans for dispatch, pipeline, and agent execution

The first Keiro instance operates [LowEndInsight](https://lowendinsight.dev) — an open-source software risk analysis product. LEI is the product of this CAO: built, deployed, and operated by its agents. It serves as the das blinkenlights — proof the system works end-to-end, from engineering through delivery.

## ADRs

Architectural decisions that define Keiro. Migrated from the prior prototype; the thinking transfers, the implementation is new.

| ADR | Summary |
|-----|---------|
| [Agentic Corporation Framework](docs/adr-agentic-corporation-framework.md) | Multi-org autonomous business with CEO layer and autonomy dial |
| [Cost-Aware Model Routing](docs/adr-cost-aware-model-routing.md) | 3-tier cascade: rule-based, confidence-checked, learned |
| [TQM Self-Improvement](docs/adr-tqm-self-improvement-architecture.md) | Pattern detection, remediation beads, self-repair |
| [Supervision & Failure-as-Learning](docs/adr-supervision-and-failure-as-learning.md) | OTP-inspired supervision with structured outcome taxonomy |
| [Context Evaluation Lifecycle](docs/adr-context-evaluation-lifecycle.md) | CDLC: generate, evaluate, distribute, observe context quality |
| [Aggressive Task Decomposition](docs/adr-aggressive-task-decomposition.md) | 30K token budgets force smaller, parallelizable, retryable tasks |
| [Delivery & SRE Ops Org](docs/adr-delivery-and-sre-ops-org.md) | Deploy, incident, maintenance pipelines with burn-in governance |
| [Multi-Org Beads Namespaces](docs/adr-multi-org-beads-namespaces.md) | Prefix-partitioned task graph with cross-org references |
| [Observability & Continuous Ops](docs/adr-observability-and-continuous-operations.md) | Structured telemetry, health checks, anomaly classification |
| [Layered Security Review](docs/adr-layered-security-review.md) | Security + CISO agents with blast-radius analysis |
| [Untrusted Input Defense](docs/adr-untrusted-input-defense.md) | Defense against prompt injection and input manipulation |

## Getting Started

```bash
git clone https://github.com/kitplummer/keiro.git && cd keiro
mix deps.get
mix compile
mix test     # 436 tests + 1 doctest
```

Requires Elixir 1.17+, Erlang/OTP 26+, and [bd](https://github.com/beads-org/beads-cli) for task management.

### Running the continuous loop

```bash
# Point at a beads-enabled repo with eng/ops/arch beads in the backlog
mix keiro.continuous --repo-path /path/to/repo --budget 5 --hours 2
```

This polls for ready beads, routes them to the appropriate agent, and loops until budget or time is exhausted.

## License

Apache 2.0
