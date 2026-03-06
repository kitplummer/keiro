# ADR: Delivery and SRE — The Operations Org

**Date:** 2026-03-01
**Authors:** Kit, with Claude analysis
**Status:** Accepted
**Informed by:** [Agentic Corporation Framework](./adr-agentic-corporation-framework.md) (Phase 3), [Full Agentic Ops Delta](./analysis-full-agentic-ops-delta.md) (Uplink SRE agent spec), [Observability ADR](./adr-observability-and-continuous-operations.md), `crates/ops-org/` skeleton

---

## Context

Keiro ends at a merged PR. Nobody delivers to production or operates the service afterward. LowEndInsight (Elixir/Phoenix on fly.io, backed by Postgres, Redis, and Oban) is deployed manually — Kit runs `fly deploy` from a laptop. There is no health checking, no automated rollback, no incident response, no certificate renewal monitoring.

The [Agentic Corporation Framework ADR](./adr-agentic-corporation-framework.md) defines Phase 3 as "Stand up Ops org for LowEndInsight deployment." The [Ops Delta Analysis](./analysis-full-agentic-ops-delta.md) specifies the SRE agent (Uplink) and its fly.io tool allowlist. The [Observability ADR](./adr-observability-and-continuous-operations.md) defines telemetry and dashboards — but telemetry is what you *look at*, not what you *do*. This ADR defines what the Ops org actually does.

The `crates/ops-org/` skeleton already exists with `OpsPipelineStage {Monitor, Act, Report}`, `OpsConfig`, and `OpsGovernanceSettings`. That skeleton assumes a single linear pipeline. This ADR replaces that assumption with three distinct pipeline modes that match how operations actually works.

---

## Decision

**Platform decision: fly.io (confirmed).** LowEndInsight is deployed on fly.io. All tooling, runbooks, and agent configurations target fly.io as the sole deployment platform.

### 1. Ops Is Not Engineering with Different Prompts

Engineering is a linear pipeline: plan → implement → test → debug → security → release → archive → PR. Every task follows the same shape. The Controller is deterministic because the pipeline is deterministic.

Operations is not linear. Three fundamentally different execution modes exist:

| Mode | Trigger | Shape | Example |
|---|---|---|---|
| **Triggered** | External event (PR merged, deploy command) | Sequential with gates | PR merged → deploy → health check → done |
| **Reactive** | Alert or anomaly detection | Branch-and-converge | Alert → classify → (diagnose \| escalate) → respond → postmortem |
| **Periodic** | Cron schedule | Fan-out, read-only | Every 5m: health check, cert expiry, cost snapshot |

Attempting to force these into a single `Monitor → Act → Report` pipeline conflates three different concerns. The ops-org crate must support three pipeline modes, not one.

### 2. Three Pipeline Modes

#### Deploy Pipeline (Triggered)

Fires when engineering produces a deployable artifact — a green CI build on the release branch, or an explicit `glitchlab ops deploy` command.

```
PR merged / deploy command
        │
        ▼
┌─────────────────┐
│ Pre-deploy check │  ← CI green? Branch correct? Config valid?
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Oban drain wait │  ← LowEndInsight-specific: wait for Oban queue to drain
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   fly deploy     │  ← fly deploy --app lowendinsight --strategy rolling
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Health check    │  ← GET /health, verify 200, check BEAM node connectivity
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
 healthy   unhealthy
    │         │
    ▼         ▼
  done    rollback → alert → postmortem bead
```

The deploy pipeline is the highest-risk ops activity. It is always gated during burn-in (Phase 1). After burn-in, deploys of unchanged `fly.toml` with passing CI can be auto-approved.

#### Incident Pipeline (Reactive)

Fires when monitoring detects an anomaly — health check failure, error rate spike, BEAM crash, Redis disconnect.

```
Alert signal
    │
    ▼
┌──────────┐
│ Classify  │  ← Is this noise, degradation, or outage?
└────┬─────┘
     │
     ├── noise → log → done
     │
     ├── degradation
     │      │
     │      ▼
     │  ┌──────────┐
     │  │ Diagnose  │  ← Check logs, metrics, recent deploys
     │  └────┬─────┘
     │       │
     │       ▼
     │  ┌──────────┐
     │  │ Respond   │  ← Scale up, restart, or escalate to engineering
     │  └────┬─────┘
     │       │
     │       ▼
     │  postmortem bead (engineering namespace)
     │
     └── outage
            │
            ▼
       ┌──────────┐
       │ Rollback  │  ← Immediate, unconditional
       └────┬─────┘
            │
            ▼
       ┌──────────┐
       │ Diagnose  │  ← Root cause on rolled-back-to version
       └────┬─────┘
            │
            ▼
       postmortem bead + engineering escalation bead
```

Classification requires judgment — this is why the Corporation Framework ADR specifies an LLM agent as the ops leader, not a deterministic controller. The classifier examines error logs, recent deploy history, and baseline metrics to distinguish noise from real incidents.

#### Maintenance Pipeline (Periodic)

Runs on a cron schedule. Entirely read-only — it never mutates infrastructure without escalating to the deploy or incident pipeline.

| Check | Interval | Action on Failure |
|---|---|---|
| Health endpoint (`GET /health`) | 5 min | Escalate to incident pipeline |
| TLS certificate expiry | Daily | Alert if < 14 days remaining |
| Fly.io machine status | 15 min | Alert if any machine stopped/failed |
| Postgres connection count | 15 min | Alert if > 80% of pool |
| Redis connectivity | 5 min | Escalate to incident pipeline |
| Cost snapshot | Daily | Log to cost bead; alert if > 2x daily average |
| Oban queue depth | 15 min | Alert if growing unboundedly |

The maintenance pipeline produces data. It does not act on it — escalation to other pipelines handles action.

### 3. Three Agents

The [Ops Delta Analysis](./analysis-full-agentic-ops-delta.md) specified a single "Uplink" SRE agent. The target architecture splits this into three agents, each with a narrow scope, for safety and testability:

| Agent | Name | Pipeline(s) | Capabilities |
|---|---|---|---|
| **Deployer** | Uplink-Deploy | Deploy | Pre-deploy validation, `fly deploy`, health check, rollback |
| **Monitor** | Uplink-Watch | Maintenance, Incident (classification) | Health checks, metrics collection, anomaly classification |
| **Responder** | Uplink-Respond | Incident (diagnosis + response) | Log analysis, scaling, restarts, postmortem bead creation |

**Phase 1 simplification:** Implementation starts with a single **Uplink** agent (`UplinkSreAgent`) that combines deploy verification and health assessment. This agent is assessment-only — it interprets smoke test results and recommends actions but never executes deploys or rollbacks. The pipeline orchestrator acts on its recommendations. The split into Deployer/Monitor/Responder happens in Phase 2-3 as the tool allowlist expands.

Each agent has its own system prompt, tool subset, and governance profile. A single "Uplink" agent with all capabilities would have too broad a tool allowlist and too much authority.

### 4. Tool Allowlist

Ops agents can only invoke tools on this allowlist. Everything else is denied.

| Tool | Agents | Notes |
|---|---|---|
| `fly deploy` | Deployer | `--strategy rolling` only; canary deferred |
| `fly status` | All | Read-only |
| `fly logs` | Monitor, Responder | Read-only; time-bounded queries |
| `fly releases` | Deployer | For rollback target selection |
| `fly releases rollback` | Deployer | Unconditional on health check failure |
| `fly scale show` | Monitor | Read-only |
| `fly scale count` | Responder | Gated; requires approval |
| `fly scale vm` | Responder | Gated; requires approval |
| `fly secrets list` | — | **Denied.** Secret names are visible; values never enter LLM context. |
| `fly secrets set` | — | **Denied.** Secrets managed by human only. |
| `fly certs list` | Monitor | Read-only; for expiry checks |
| `fly certs show` | Monitor | Read-only |
| `fly ssh console` | — | **Denied.** Too broad. |
| `fly postgres` | Monitor | Read-only status checks only |
| `fly volumes list` | Monitor | Read-only |
| `curl` | Monitor | Scoped: only `GET` to the app's own health endpoint. Not general-purpose. |

**Denied categories:**
- `fly secrets set/unset` — secrets never flow through LLM context
- `fly ssh` — interactive shell access is too broad for autonomous agents
- `fly apps create/destroy` — lifecycle management is human-only
- `fly machine` commands — low-level machine management deferred to Phase 3+

### 5. Governance

Governance rules are defined per pipeline mode and agent:

| Rule | Deploy Pipeline | Incident Pipeline | Maintenance Pipeline |
|---|---|---|---|
| **Default gate** | Gated (human approval) | Auto (except scaling) | Auto (read-only) |
| **Auto-rollback** | Unconditional on health failure | Unconditional on outage classification | N/A |
| **Scaling changes** | N/A | Gated (human approval) | N/A |
| **Database migrations** | Always gated, always human | N/A | N/A |
| **Budget cap per action** | $0.50 (LLM calls for deploy logic) | $2.00 (diagnosis may require multiple LLM calls) | $0.10 (classification is cheap) |

**Burn-in progression:**

| Phase | Deploy Gate | Incident Gate | Rationale |
|---|---|---|---|
| Phase 1 (first 10 deploys) | Human approval required | Human approval required | Build trust |
| Phase 2 (deploys 11-50) | Auto if CI green + unchanged fly.toml | Auto for classification; gated for response | Routine deploys are safe |
| Phase 3 (50+ deploys) | Auto for all standard deploys | Auto for known runbook responses | Trust established through history |

Burn-in is tracked via a deploy counter bead. The governance policy reads this counter to determine the current gate level.

### 6. Handoff Contract: Engineering → Ops

The boundary between engineering and ops is a contract, not an informal understanding.

**Engineering delivers:**
- A green CI build on the release branch (all tests pass, clippy clean, fmt clean)
- A valid `fly.toml` in the repository root
- A `Dockerfile` that produces a working image
- Migration files (if any) clearly marked in the PR description

**Ops takes over at:**
- The merge event on the release branch (triggered pipeline) or
- An explicit `glitchlab ops deploy` command (manual trigger)

**Ops produces:**
- A running deployment with verified health
- A deploy bead recording: commit SHA, deploy timestamp, health check result, rollback (if any)

**Feedback loop:**
- Production incidents create beads in the **engineering** namespace with `caused-by` links to the deploy bead and the originating PR
- Engineering's backlog review picks up these beads as bug reports
- Ops never modifies code — it escalates to engineering via beads

```
Engineering                          Ops
    │                                 │
    │  merge to release branch        │
    │ ──────────────────────────────▶ │
    │                                 │  deploy pipeline
    │                                 │  ──────────────
    │                                 │  health ✓ → deploy bead
    │                                 │  health ✗ → rollback + incident bead
    │                                 │
    │  ◀──────────────────────────── │  incident bead (engineering namespace)
    │                                 │
    │  fix bug, merge                 │
    │ ──────────────────────────────▶ │
    │                                 │  redeploy
```

### 7. LowEndInsight-Specific Operational Concerns

LowEndInsight is an Elixir/Phoenix application with characteristics that require ops-specific handling:

| Concern | What | How |
|---|---|---|
| **Oban queue drain** | Background jobs (repo analysis) must complete before deploy | Pre-deploy: poll Oban queue via `fly postgres connect` + SQL query; wait for drain or timeout (5 min) |
| **Ecto migration sequencing** | Migrations must run before new code deploys | `fly deploy --strategy rolling` runs migrations in release phase; verify via `fly logs` |
| **BEAM crash detection** | Erlang VM crashes produce distinctive log patterns | Monitor watches for `erl_crash.dump`, `** (EXIT)`, BEAM heartbeat failures in `fly logs` |
| **Redis connectivity** | LowEndInsight uses Redis for caching; disconnect degrades but doesn't crash | Monitor checks Redis connectivity via health endpoint; classify as degradation, not outage |
| **Phoenix LiveView state** | Rolling deploys disconnect LiveView websockets | Accepted — LiveView clients reconnect automatically. No special handling needed. |
| **Postgres connection pool** | fly.io Postgres has connection limits | Monitor tracks connection count; alert at 80% capacity |

These are encoded in the Monitor agent's system prompt as domain knowledge, not as generic ops rules.

### 8. Smoke and Canary Tests

Post-deploy verification uses declarative smoke test definitions. The smoke runner is deterministic code (HTTP requests + response matching); the LLM agent interprets results in context.

#### Smoke Test Endpoints

| # | Method | Path | Expected Status | Body Check | Required |
|---|--------|------|-----------------|------------|----------|
| 1 | GET | `/` | 200 | Contains "LowEndInsight" | Yes |
| 2 | GET | `/v1/cache/stats` | 200 | Valid JSON | Yes |
| 3 | GET | `/doc` | 200 | — | No |
| 4 | POST | `/v1/analyze` | 200/202 | — | No |

#### Decision Matrix

| Required Checks | Optional Checks | Assessment | Action |
|-----------------|-----------------|------------|--------|
| All pass | All pass | **healthy** | Deploy verified, done |
| All pass | Some fail | **degraded** | Investigate, no rollback |
| Any fail | — | **unhealthy** | Rollback immediately |
| No data | — | **deploy_failed** | Rollback immediately |

The Uplink agent receives smoke test results as structured input and applies this matrix to produce its assessment. The pipeline orchestrator reads the agent's `recommendation` field and executes the appropriate action (rollback, escalation, or no-op).

Canary testing (percentage-based traffic splitting) is deferred to Phase 3+ when fly.io machine-level routing is implemented.

---

## Implementation Phases

| Phase | What | Validates | Depends On |
|---|---|---|---|
| **0** | Deploy runbook (`docs/runbook-lowendinsight-fly-deploy.md`) + Uplink SRE agent implementation in `crates/ops-org/` | We understand our own process; agent can assess health | Nothing |
| **1** | Deploy pipeline — `glitchlab ops deploy` wrapping fly CLI with smoke test verification via Uplink agent | Triggered pipeline works; smoke tests gate deploys; governance gates work | Phase 0 |
| **2** | Maintenance pipeline — periodic health checks, cert/cost monitoring; split Uplink into Deployer + Monitor | Periodic pipeline works; Monitor agent classifies correctly | Phase 1 |
| **3** | Incident pipeline — classification, diagnosis, response, postmortem beads; add Responder agent | Reactive pipeline works; Responder agent follows runbooks | Phase 2 |
| **4** | Engineering ↔ Ops handoff — merge event triggers deploy; incident beads appear in engineering backlog | Inter-org communication works | Phase 3 + Beads cross-namespace links |

Phase 0 is deliberately manual documentation. Automating a process you don't fully understand produces automation you can't debug.

---

## Relationship to Existing Architecture

### ops-org Crate Evolution

The `crates/ops-org/` skeleton defines `OpsPipelineStage {Monitor, Act, Report}` as a single enum. This ADR replaces that with a pipeline-mode enum and per-mode stage definitions:

```
Current:  OpsPipelineStage { Monitor, Act, Report }

Target:   OpsPipelineMode { Deploy, Incident, Maintenance }
          DeployStage { PreCheck, Drain, Deploy, HealthCheck, Rollback }
          IncidentStage { Classify, Diagnose, Respond, Postmortem }
          MaintenanceStage { Check, Report }
```

The `OpsGovernanceSettings` struct gains per-mode gate configuration and the burn-in counter threshold.

### Corporation Framework Alignment

This ADR implements Phase 3 of the [Corporation Framework ADR](./adr-agentic-corporation-framework.md). Key alignment points:

- **Leader model:** LLM agent (reactive) — confirmed. The incident pipeline's classify step requires judgment.
- **Pipeline type:** Event-driven — confirmed, but refined to three modes (triggered, reactive, periodic) rather than a single event-driven model.
- **Governance:** Zephyr policies — the burn-in progression is a concrete instance of the "autonomy by novelty" axis.
- **Memory:** Beads for deploy/incident records, with cross-namespace links for engineering feedback.

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Auto-rollback causes data loss** | Critical | Rollback reverts code only; database state is forward-only. Migrations are never auto-rolled-back. |
| **Health check false positive** | High | Health endpoint must check all critical dependencies (Postgres, Redis, Oban), not just return 200. Classify timeout as degradation, not healthy. |
| **Oban drain timeout** | Medium | 5-minute timeout with configurable override. On timeout: proceed with deploy (jobs are crash-safe) but log a warning bead. |
| **BEAM crash misclassified as noise** | High | Monitor agent's system prompt includes explicit BEAM crash log patterns. Classification confidence threshold: if < 80% confident it's noise, escalate. |
| **LLM hallucination in incident response** | Critical | Responder agent operates from runbooks (predefined response playbooks), not freeform reasoning. Unknown incident types always escalate to human. |
| **Burn-in counter gamed** | Low | Counter is append-only in beads. Governance reads the bead, not agent-reported state. |

---

## References

- [ADR: Agentic Corporation Framework](./adr-agentic-corporation-framework.md) — org construct, Phase 3, lifecycle staging
- [ADR: Observability and Continuous Operations](./adr-observability-and-continuous-operations.md) — telemetry that feeds the Monitor agent
- [Full Agentic Operations Gap Analysis](./analysis-full-agentic-ops-delta.md) — Uplink SRE agent spec, fly.io tool list
- `crates/ops-org/src/config.rs` — skeleton types being evolved
- Beads gl-3n4 through gl-3n4.5 — ops org implementation tasks

---

*This ADR should be revisited after Phase 1, when the deploy pipeline has been used for 10+ real deployments to LowEndInsight. The burn-in progression, tool allowlist, and governance gates should be validated against actual deploy outcomes.*
