# Keiro: Full Agentic Operations Gap Analysis

**Date:** 2026-02-19
**Author:** Kit (via Claude analysis)
**Scope:** Assess Keiro's readiness to run a full engineering project — dev, build, deliver, and operate an API service on fly.io — with agentic personas for Developer, Test, SRE, and Project Manager roles.

---

## 1. What Exists Today

Keiro is a local-first, repo-agnostic, multi-agent development engine. It breaks tasks into structured plans and executes them autonomously under strict governance. Here's a candid assessment of the current state.

### 1.1 Core Architecture

| Component | Status | Notes |
|-----------|--------|-------|
| **Controller (Brainstem)** | Solid | Deterministic orchestrator. Manages the full agent pipeline sequentially. |
| **LLM Router** | Solid | Vendor-agnostic via LiteLLM. Budget tracking (tokens + dollars). Retry with backoff. |
| **Workspace Isolation** | Solid | Ephemeral git worktrees per task. Clean branch naming (`glitchlab/{task_id}`). |
| **Tool Executor** | Solid | Allowlist-based sandboxed execution. Blocked patterns (rm -rf, curl, eval). |
| **Governance / Boundaries** | Solid | Protected paths, human intervention gates, budget caps. |
| **Task History** | Solid | JSONL append-only log. Failure context fed back into planner. |
| **Prelude Integration** | Present | Bridges external `prelude-context` for codebase memory. Optional. |
| **Parallel Execution** | Present | Thread pool for multi-task batch runs. Auto-approve mode. |
| **CLI** | Functional | `run`, `interactive`, `init`, `batch`, `status`, `history` commands via Typer. |

### 1.2 Agent Roster (Current)

| Agent | Persona | Role | Model |
|-------|---------|------|-------|
| Planner | Professor Zap | Breaks task into structured execution plan | Gemini Flash |
| Implementer | Patch | Writes code changes + tests | Claude Sonnet |
| Debugger | Reroute | Fixes test failures (up to 4 attempts) | Claude Sonnet |
| Security | Firewall Frankie | Scans diff for vulnerabilities | Gemini Flash |
| Release | Semver Sam | Assesses version bump (semver) | Gemini Flash |
| Archivist | Nova | Writes ADRs and doc updates | Gemini Flash |

### 1.3 What Keiro Can Do Right Now

- Accept tasks from GitHub issues, local YAML, or interactive prompt
- Plan implementation with structured JSON output (steps, files, risk level)
- Write code in any language (Rust, Python, TypeScript, Go, etc.)
- Automatically add/update tests
- Run test suites and debug failures in a loop
- Scan for security issues before PR creation
- Assess semver impact
- Generate Architecture Decision Records
- Create GitHub PRs with detailed summaries
- Run multiple tasks concurrently
- Learn from past failures via history
- Enforce protected paths and budget limits
- Support human-in-the-loop approval at every critical gate

### 1.4 What It Cannot Do (The Honest Part)

- **No deployment capability.** Pipeline ends at PR creation. No fly.io, no Docker, no CI/CD triggers.
- **No operational awareness.** Cannot monitor, alert, rollback, or respond to production incidents.
- **No SRE persona.** No agent understands infrastructure, observability, or runbooks.
- **No project management.** No backlog management, sprint planning, dependency tracking across tasks, or progress reporting.
- **No test persona distinct from implementer.** The implementer writes tests; there's no dedicated QA agent that designs test strategies, writes integration/e2e tests, or validates acceptance criteria.
- **No API management.** No authn/authz scaffolding, rate limiting, API key management, or gateway configuration.
- **No service lifecycle.** Cannot create, configure, scale, or destroy fly.io apps.
- **No persistent state across runs.** Each task is isolated. No project-level memory beyond history.jsonl and Prelude.
- **No inter-agent communication.** Agents run in a fixed pipeline. No negotiation, escalation, or feedback loops between agents.
- **No external service integration.** Cannot talk to Slack, PagerDuty, Datadog, Stripe, or any external API.
- **No payment/billing.** No token economy, no metering, no marketplace.

---

## 2. The Target State

Full agentic operations of an API service running on fly.io, with:

- **Developer agents** that write features, fix bugs, and refactor code
- **Test agents** that design test strategies, write comprehensive test suites, and validate quality
- **SRE agents** that deploy, monitor, respond to incidents, manage infrastructure
- **Project Manager agents** that prioritize work, track progress, manage the backlog, and coordinate the team
- **AuthN/AuthZ** for the API service itself (not just Keiro's internal security)
- **API management** — rate limiting, versioning, documentation, key management
- **Token-based payment** — humans and other agents pay with tokens to build and run projects

---

## 3. The Delta: What Needs to Be Built

### 3.1 New Agent Personas

#### 3.1.1 QA/Test Agent — "Circuit"

**Purpose:** Dedicated quality assurance that goes beyond "implementer writes some tests."

| Capability | Description |
|------------|-------------|
| Test strategy design | Given a feature/change, design a comprehensive test plan (unit, integration, e2e, contract, load) |
| Test implementation | Write tests independently from the implementer, covering edge cases and failure modes |
| Acceptance validation | Verify that implementation meets acceptance criteria defined in the task |
| Regression detection | Compare behavior before/after changes; flag regressions |
| Coverage analysis | Assess test coverage and identify gaps |
| Contract testing | For API services: validate request/response contracts against OpenAPI specs |
| Load/stress testing | Generate load test configurations (k6, locust, etc.) |

**Delta:** New agent class, new prompt engineering, new tool allowlist entries (test runners, coverage tools, contract validators).

#### 3.1.2 SRE Agent — "Uplink"

**Purpose:** Infrastructure, deployment, monitoring, and incident response.

| Capability | Description |
|------------|-------------|
| Deployment | Deploy to fly.io (`fly deploy`, `fly scale`, `fly secrets`) |
| Infrastructure-as-Code | Generate/modify `fly.toml`, Dockerfiles, health checks |
| Monitoring setup | Configure observability (metrics, logs, traces) |
| Incident response | Detect anomalies, diagnose issues, execute runbooks |
| Rollback | Revert to previous deployment on failure |
| Scaling | Adjust fly.io machine count, regions, sizing |
| Secret management | Rotate secrets, manage env vars via `fly secrets` |
| Health checks | Define and validate health/readiness probes |
| Certificate management | TLS configuration via fly.io |
| Runbook execution | Follow predefined incident response procedures |

**Delta:** This is the biggest single gap. Requires:
- New agent class with infrastructure-aware prompts
- Significant expansion of the tool allowlist (`fly` CLI commands, `docker` commands, `curl` for health checks)
- New governance rules (deployment approval gates, rollback triggers)
- Monitoring integration (read metrics, parse logs)
- Runbook format definition and executor
- fly.io API client or CLI wrapper

#### 3.1.3 Project Manager Agent — "Compass"

**Purpose:** Orchestrate work across agents, manage the backlog, track progress, report status.

| Capability | Description |
|------------|-------------|
| Backlog management | Create, prioritize, and refine tasks from high-level objectives |
| Sprint/iteration planning | Group tasks into coherent work batches |
| Dependency tracking | Understand task dependencies and optimal execution order |
| Progress reporting | Summarize what's done, what's in-flight, what's blocked |
| Risk assessment | Flag tasks that are stalling, over-budget, or high-risk |
| Agent coordination | Decide which persona handles which task; escalate when needed |
| Stakeholder communication | Generate status updates, changelogs, release notes |
| Retrospective analysis | Analyze history to improve future planning |
| Scope management | Break large objectives into right-sized tasks |
| Estimation | Use historical data to estimate effort/cost for new tasks |

**Delta:** This changes the architecture significantly. Today, the Controller is a dumb pipeline. A PM agent would sit *above* the Controller:
- New orchestration layer that manages a task queue
- Task dependency graph (not just linear pipeline)
- Cross-task state and memory
- Integration with GitHub Projects / Issues for backlog
- Reporting/summary generation
- Budget allocation across tasks (not just per-task)

#### 3.1.4 Enhanced Developer Agent — "Patch" (upgraded)

The current Implementer is solid but needs expansion for full-service development:

| Capability | Description |
|------------|-------------|
| API design | Generate OpenAPI specs, design REST/gRPC endpoints |
| AuthN/AuthZ scaffolding | Implement JWT/OAuth2 flows, RBAC, API key validation |
| Database migrations | Generate and apply schema migrations |
| Configuration management | Manage environment-specific configs |
| Dependency management | Add/update/audit dependencies |

**Delta:** Prompt engineering upgrades, expanded tool allowlist, new templates for API patterns.

### 3.2 Infrastructure & Deployment Layer

This is entirely new. Keiro today has zero deployment capability.

```
                    ┌─────────────────────────────────┐
                    │         Target Architecture       │
                    │                                   │
   Task Input ──▶   │  Compass (PM)                    │
                    │    ├── Plans & prioritizes        │
                    │    ├── Assigns to agents          │
                    │    └── Tracks progress            │
                    │         │                         │
                    │    ┌────┴────┐                    │
                    │    │Controller│ (enhanced)        │
                    │    └────┬────┘                    │
                    │    ┌────┴────────────────┐        │
                    │    │   Agent Pipeline     │       │
                    │    │  Planner             │       │
                    │    │  Implementer (Patch) │       │
                    │    │  Tester (Circuit)    │       │
                    │    │  Debugger (Reroute)  │       │
                    │    │  Security (Frankie)  │       │
                    │    │  SRE (Uplink)        │       │
                    │    │  Release (Sam)       │       │
                    │    │  Archivist (Nova)    │       │
                    │    └────┬────────────────┘        │
                    │         │                         │
                    │    ┌────┴────┐                    │
                    │    │ Deploy   │──▶ fly.io         │
                    │    │ Monitor  │◀── metrics/logs   │
                    │    │ Operate  │──▶ scale/rollback │
                    │    └─────────┘                    │
                    └─────────────────────────────────┘
```

#### Required New Components

| Component | Description | Effort |
|-----------|-------------|--------|
| `fly.toml` generator | Template-based fly.io configuration | Medium |
| Dockerfile generator | Multi-stage Dockerfile for API services | Medium |
| Deploy executor | Wraps `fly deploy`, handles secrets, regions | Large |
| Health check validator | Verify service health post-deploy | Small |
| Rollback executor | `fly releases rollback` on failure | Medium |
| Log aggregator | `fly logs` parser for incident detection | Medium |
| Metrics reader | Prometheus/fly metrics for scaling decisions | Large |
| Secret manager | `fly secrets set/unset` with rotation | Medium |
| Scale manager | `fly scale count/memory/vm` | Small |

### 3.3 AuthN/AuthZ & API Management

For the API service itself (not Keiro's internal security).

| Feature | Description | Approach |
|---------|-------------|----------|
| **JWT Authentication** | Issue and validate JWTs for API consumers | Implement in API service code; SRE agent manages signing keys via fly secrets |
| **API Key Management** | Issue, rotate, revoke API keys | Key store (Postgres on fly.io or Turso), admin endpoints |
| **RBAC** | Role-based access control for API endpoints | Middleware + policy definitions |
| **OAuth2 Provider** | If acting as an OAuth2 provider for other agents | Significant — consider using an existing library |
| **Rate Limiting** | Per-key/per-user rate limits | In-app middleware or fly.io proxy config |
| **API Versioning** | URL or header-based API versioning | Convention + Release agent awareness |
| **OpenAPI Documentation** | Auto-generated API docs | Code-first OpenAPI generation |
| **API Gateway** | Central entry point with routing, auth, rate limiting | fly.io's built-in proxy or a lightweight gateway |
| **Audit Logging** | Log all API access for compliance | Structured logging to fly.io log drain |
| **CORS / Security Headers** | Proper cross-origin and security headers | Middleware configuration |

**Delta:** The Developer agent needs API-specific prompt templates and the ability to scaffold auth middleware. The SRE agent needs to manage secrets and certificates. The Test agent needs contract testing capability.

### 3.4 Token-Based Payment System

For humans and agents paying to build and run projects.

| Feature | Description | Priority |
|---------|-------------|----------|
| **Token ledger** | Track token balances, transactions, and usage | High |
| **Metering** | Measure compute (LLM calls, fly.io usage, build time) | High |
| **Token issuance** | Mint tokens for users/agents on payment | Medium |
| **Usage billing** | Convert metered usage to token charges | High |
| **Agent-to-agent payment** | Agents can pay for sub-tasks or external services | Medium |
| **Rate card** | Define costs per operation type | Medium |
| **Budget enforcement** | Refuse work if token balance insufficient | High (partially exists for LLM costs) |
| **Transaction history** | Audit trail of all token movements | Medium |
| **Settlement** | Convert tokens to/from fiat (Stripe, etc.) | Later (per your note) |

**Delta:** This is a new subsystem. The existing budget tracking (tokens + dollars per task) is a starting point, but needs to be generalized into a proper ledger. Key design decision: is the token ledger a separate service, or embedded in Keiro?

### 3.5 Orchestration & Pipeline Changes

The current pipeline is linear:

```
Plan → Implement → Test → Debug → Security → Release → Archive → PR
```

Full agentic operations needs:

```
                        Compass (PM)
                            │
                    ┌───────┼───────┐
                    │       │       │
                    ▼       ▼       ▼
                 Feature  Bugfix  Infra
                  Task    Task    Task
                    │       │       │
                    ▼       ▼       ▼
              ┌─────────────────────────┐
              │   Enhanced Controller    │
              │  (parallel pipelines,    │
              │   conditional stages,    │
              │   agent negotiation)     │
              └─────────────────────────┘
                    │       │       │
              ┌─────┘       │       └─────┐
              ▼             ▼             ▼
          Dev Pipeline  Test Pipeline  Ops Pipeline
          Plan→Code→    Strategy→     Deploy→
          Test→Debug    Write Tests→  Monitor→
                        Validate      Scale
```

Key changes needed:

| Change | Description |
|--------|-------------|
| **Non-linear pipeline** | Agents can run in any order based on task type (not always Plan→Implement→...) |
| **Conditional stages** | Skip Release agent for infra tasks; skip Deploy for library changes |
| **Pipeline templates** | `feature`, `bugfix`, `infra`, `incident-response`, `maintenance` pipeline types |
| **Cross-task dependencies** | Task B waits for Task A's deployment before starting |
| **Agent escalation** | If SRE can't resolve, escalate to PM who may create a new developer task |
| **Feedback loops** | Test results inform Developer; monitoring informs SRE; SRE informs PM |
| **Long-running operations** | Deployments and monitoring aren't instant — need async execution model |

### 3.6 Tool Allowlist Expansion

Current allowlist is development-focused. Operations requires:

```yaml
# New fly.io tools
- "fly deploy"
- "fly status"
- "fly scale"
- "fly secrets"
- "fly logs"
- "fly releases"
- "fly apps"
- "fly ips"
- "fly certs"
- "fly proxy"
- "fly ssh"
- "fly volumes"

# Docker tools
- "docker build"
- "docker push"

# Database tools (for API service)
- "fly postgres"
- "fly proxy"  # for DB connections

# Monitoring
- "fly logs"
- "curl"  # currently blocked — needed for health checks

# Infrastructure
- "fly machine"
- "fly regions"
```

Note: `curl` is currently in the blocked patterns list. Health checking requires either unblocking it with constraints or building a dedicated health check tool.

---

## 4. Effort Estimation (T-Shirt Sizing)

| Work Item | Size | Rationale |
|-----------|------|-----------|
| QA/Test Agent (Circuit) | **L** | New agent class, prompt engineering, contract testing integration |
| SRE Agent (Uplink) | **XL** | Entirely new domain. fly.io integration, monitoring, runbooks, rollback. Largest single piece. |
| PM Agent (Compass) | **XL** | Changes the architecture. Sits above Controller. Task graph, cross-task state, reporting. |
| Enhanced Developer (API patterns) | **M** | Prompt templates for auth, API design, migrations. Builds on existing agent. |
| Deployment pipeline | **L** | fly.toml generation, Dockerfile templates, deploy/rollback executor |
| AuthN/AuthZ scaffolding | **L** | JWT, API keys, RBAC middleware — mostly code templates + Developer agent awareness |
| API Management features | **M** | Rate limiting, versioning, OpenAPI — largely Developer agent work |
| Token payment system | **L** | Ledger, metering, budget enforcement. New subsystem. |
| Pipeline restructuring | **L** | Non-linear pipelines, conditional stages, pipeline templates |
| Orchestration layer | **XL** | PM-driven task assignment, cross-task deps, feedback loops, async execution |
| Tool allowlist expansion | **S** | Config changes + governance rules for new tools |
| External integrations | **M** | Slack, PagerDuty, Datadog (optional but valuable for SRE) |

---

## 5. Recommended Build Order

Phase 0 is "get the engine running" — the existing codebase isn't tested or deployed yet.

### Phase 0: Foundation (Make What Exists Work)

1. **Write tests for Keiro itself.** There are zero tests today. The `tests/` directory doesn't exist despite pytest being a dev dependency.
2. **Create a sample target project.** A minimal API service (FastAPI, Hono, or Axum) to serve as the guinea pig.
3. **Validate the existing pipeline end-to-end.** Run `glitchlab run` on a real task and fix what breaks.
4. **Set up CI for Keiro.** Dogfood: use Keiro to build Keiro (after it works).

### Phase 1: Enhanced Development (Weeks 1-3)

1. **QA/Test Agent (Circuit)** — Immediately improves output quality.
2. **Enhanced Developer prompts** — API-aware templates (auth middleware, OpenAPI, migrations).
3. **Pipeline templates** — `feature`, `bugfix`, `refactor` as distinct flows.

### Phase 2: Infrastructure & Deployment (Weeks 3-6)

1. **SRE Agent (Uplink)** — fly.io deployment, health checks, basic monitoring.
2. **Deployment pipeline** — `fly.toml` generation, Dockerfile templates, deploy executor.
3. **Tool allowlist expansion** — fly CLI, docker, health check support.
4. **Rollback capability** — Critical safety net for automated deployment.

### Phase 3: Orchestration & Management (Weeks 6-10)

1. **PM Agent (Compass)** — Task prioritization, backlog management, progress tracking.
2. **Orchestration layer** — Non-linear pipelines, cross-task dependencies, async execution.
3. **Agent escalation & feedback loops** — Agents can request help from each other.

### Phase 4: API Management & Auth (Weeks 8-12, overlaps Phase 3)

1. **AuthN/AuthZ scaffolding** — JWT, API keys, RBAC as code templates the Developer agent can use.
2. **API management features** — Rate limiting, versioning, OpenAPI generation.
3. **Audit logging** — Structured access logs for compliance.

### Phase 5: Token Economy (Weeks 12-16)

1. **Token ledger** — Balances, transactions, usage tracking.
2. **Metering** — Measure LLM costs, compute time, fly.io usage.
3. **Budget enforcement** — Refuse work without sufficient token balance.
4. **Agent-to-agent payment** — Sub-task billing.

---

## 6. Key Architectural Decisions Ahead

These need to be made before or during implementation:

| Decision | Options | Recommendation |
|----------|---------|----------------|
| **Where does the PM agent live?** | Above Controller (orchestrator pattern) vs. peer agent | Above Controller — it's a fundamentally different role |
| **Sync vs. async pipeline?** | Current sync pipeline vs. event-driven | Event-driven for ops (deploys take time); sync OK for dev |
| **Token ledger location** | Embedded in Keiro vs. separate service | Separate service (it's shared state, potentially multi-tenant) |
| **fly.io integration depth** | CLI wrapper vs. API client | CLI wrapper first, API client later for monitoring |
| **How do agents communicate?** | Shared context (current) vs. message passing | Message passing for cross-pipeline coordination |
| **Multi-tenancy** | Single-tenant (your projects) vs. multi-tenant (marketplace) | Start single-tenant, design for multi from Phase 3 |
| **Config format for ops** | Extend existing YAML vs. separate ops config | Separate `ops.yaml` alongside `config.yaml` |
| **Incident response: auto vs. gated?** | Auto-rollback vs. human approval | Auto-rollback on health check failure; human approval for other actions |

---

## 7. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| **SRE agent deploys broken code** | Critical | Mandatory health check gate, auto-rollback, canary deploys |
| **PM agent creates infinite task loops** | High | Task count limits, budget caps, human review of generated backlog |
| **Token ledger inconsistency** | High | Transaction isolation, audit log, reconciliation checks |
| **fly.io API changes break automation** | Medium | Pin CLI version, integration tests, fallback to manual |
| **Agent hallucination in ops context** | Critical | Strict output schemas, validation layers, never execute unvalidated commands |
| **Cost runaway with parallel ops** | High | Per-task and per-project budget caps, real-time cost dashboard |
| **Secret exposure through agent context** | Critical | Never pass secrets through LLM context; use env vars and fly secrets only |

---

## 8. Summary

**Keiro today is a solid inner-loop development engine.** It can plan, implement, test, debug, review, and PR. The code is well-structured, the governance model is thoughtful, and the agent pipeline is clean.

**The gap to full agentic operations is significant but tractable.** The three biggest pieces are:

1. **SRE Agent + Deployment Pipeline** — The engine needs to reach beyond PR creation into the real world.
2. **PM Agent + Orchestration Layer** — The engine needs to manage work, not just execute it.
3. **Token Economy** — The engine needs a value exchange mechanism for multi-party usage.

The existing architecture is a good foundation. The agent pattern, governance model, tool sandboxing, and budget tracking all extend naturally to the operational domain. The main architectural evolution is moving from a linear pipeline to an event-driven orchestration model with a PM agent at the top.

**Gastown comparison:** If the aspiration is something like a fully autonomous software factory (plan, build, test, deploy, operate, bill), Keiro is roughly 25-30% of the way there. The development inner loop is the part that exists. The outer loop (operations, management, commerce) is the part that doesn't.

---

*This analysis is a snapshot. The recommendations should be revisited as Keiro evolves and as the target API service requirements become clearer.*
