# Keiro

**Corporate Agentic Organization (CAO) framework.**

Keiro (経路, "path/route") is an orchestration framework for autonomous multi-org agent systems. It manages the full lifecycle of agentic work — task routing, governance gates, budget enforcement, self-improvement loops — across business-function orgs (engineering, operations, finance, GTM, legal).

Built on Elixir/BEAM with [Jido](https://jido.run) as the agent runtime. Polyglot at the agent boundary via [A2A](https://google.github.io/A2A/) and [MCP](https://modelcontextprotocol.io/) protocols.

## Architecture

```
Keiro CAO
├── Orchestrator (Elixir/Jido)
│   ├── Governance ── budget caps, approval gates, autonomy dial
│   ├── TQM ──────── pattern detection, self-improvement beads
│   └── Router ────── cost-aware model selection (3-tier cascade)
│
├── Protocol Boundaries
│   ├── A2A ── agent-to-agent (polyglot: any language, any runtime)
│   └── MCP ── tool/context interface (standardized tool discovery)
│
├── Orgs (accreted as the business grows)
│   ├── Engineering ── planner, implementer, debugger, security, archivist
│   ├── Operations ─── deployer, monitor, responder (SRE)
│   ├── Finance ────── budget enforcement, cost tracking, ledger
│   └── ... ─────────── GTM, Legal, Product (future)
│
└── Memory
    ├── Beads ── distributed task graph, agent mailboxes
    ├── Dolt ─── version-controlled SQL (branch-per-agent)
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

**Phase 0 — Foundation.** Jido runtime integrated. ADRs migrated from prior Rust prototype.

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
git clone <repo-url> && cd keiro
mix deps.get
mix compile
mix test
```

Requires Elixir 1.17+ and Erlang/OTP 26+.

## License

Apache 2.0
