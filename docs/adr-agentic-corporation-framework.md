# ADR: The Agentic Corporation Framework

**Date:** 2026-02-21
**Authors:** Kit, Rob (Keiro), with Claude analysis
**Status:** Draft
**Supersedes:** None
**Informed by:** [Full Agentic Operations Gap Analysis](./analysis-full-agentic-ops-delta.md)

---

## Context

The [ops delta analysis](./analysis-full-agentic-ops-delta.md) assessed Keiro at 25-30% toward a fully autonomous software factory and identified the missing pieces: SRE, project management, token economy, and operational awareness. That analysis framed the gap as "more agents bolted onto Keiro."

This ADR reframes the problem. Keiro is not the factory. **Keiro is the engineering department.** The factory is a fully agentic business entity — a framework in which autonomous organizations handle discrete business functions (engineering, operations, finance, go-to-market, legal, product) under unified governance, shared institutional memory, and tunable human oversight.

The question is not "how do we add ops to Keiro?" but **"what is the organizational framework in which Keiro is one participant?"**

---

## Decision

### 1. Keiro Is the Engineering Org, Not the Whole Company

Keiro owns the inner development loop: plan, implement, test, debug, security scan, release assess, archive, and PR. It does this well. It should not expand to own deployment, monitoring, billing, project management, or go-to-market.

Instead, each business function is a separate **org** — an autonomous unit with its own agents, tools, pipeline shape, governance policies, and leadership model. Keiro is the first and most mature org. Others will follow.

### 2. The Org Construct

An org is defined by six properties:

| Property | Description |
|----------|-------------|
| **Agents** | Domain-specific LLM-powered workers with personas, system prompts, and output schemas |
| **Tools** | Sandboxed, allowlisted capabilities the org can use (CLI commands, APIs, file operations) |
| **Leader** | How work is routed within the org — deterministic controller, LLM agent, cron trigger, or hybrid |
| **Pipeline** | The execution model — linear (engineering), event-driven (ops), periodic (finance), or ad-hoc |
| **Governance** | Org-specific trust boundaries, autonomy levels, approval gates, and budget caps (via Zephyr) |
| **Memory** | Org-scoped task graph and institutional knowledge (via Beads), backed by shared versioned state (via Dolt) |

```
┌─────────────────────────────────────┐
│  Org                                │
│                                     │
│  ┌──────────┐    ┌───────────────┐  │
│  │ Agents   │    │ Tools         │  │
│  │ (LLM     │    │ (sandboxed,   │  │
│  │  workers) │    │  allowlisted) │  │
│  └────┬─────┘    └──────┬────────┘  │
│       │                 │           │
│  ┌────┴─────────────────┴────────┐  │
│  │  Leader + Pipeline            │  │
│  │  (routes work, manages flow)  │  │
│  └───────────────────────────────┘  │
│                                     │
│  Governance (Zephyr) │ Memory (Beads + Dolt)  │
└─────────────────────────────────────┘
```

The leader model varies by org maturity and risk profile:

| Org | Leader Model | Rationale |
|-----|-------------|-----------|
| Engineering | Deterministic controller | Pipeline is well-understood; you always plan, implement, test. No judgment needed for routing. |
| Operations | LLM agent (reactive) | Incident response requires judgment — is this alert noise or real? Rollback or investigate? |
| Finance | Cron + LLM agent | Routine reconciliation is periodic/deterministic; exceptions (unusual spend, reallocation) need judgment. |
| Product | LLM agent | Prioritization and roadmap decisions are inherently judgment-heavy. |
| CEO | LLM agent with tightest human gates | Cross-org allocation is high-stakes; the investor/board seat matters most here. |

### 3. The CEO Layer

Above the orgs sits a CEO layer. It is itself an org, but its "tools" are the other orgs. It does not write code, deploy services, or issue invoices. It:

- Receives high-level objectives (from the human investor/board)
- Decomposes objectives into org-scoped work
- Allocates budget across orgs
- Tracks cross-org progress
- Escalates when orgs are blocked, over-budget, or failing
- Reports status to the board (human)

The CEO layer routes work **between** orgs. Each org routes work **within** itself. This separation is critical — it prevents any single agent or controller from needing to understand the entire business.

### 4. Governance Is the Substrate, Not a Dependency (Zephyr)

Zephyr provides the trust boundary and policy enforcement layer for the entire framework. It is integrated into the framework, not consumed as an external dependency. This is a deliberate architectural choice — governance at this level of autonomy cannot be outsourced.

Governance is not "check after the fact." It is "define what is possible before execution."

```
❌  Agent → does work → governance checks result
✓  Governance defines what agent CAN do → agent works within boundary
```

Keiro already implements this pattern (tool allowlisting, blocked patterns, protected paths, budget caps). Zephyr generalizes it across all orgs with:

| Concern | What Zephyr Provides |
|---------|---------------------|
| **Tool policies** | Per-org, per-agent, per-context tool permissions |
| **Blast radius** | Protected resources scoped to each org's domain (files, services, accounts, financial thresholds) |
| **Autonomy levels** | Tunable dial, not a binary switch (see Section 5) |
| **Credential access** | Secret vaulting with per-agent scoped access; secrets never enter LLM context |
| **Audit** | Decision trail backed by Dolt — every agent action is versioned |
| **Escalation** | Policies for when an org must escalate to the CEO layer or to a human |

### 5. Autonomy Is a Tunable, Multi-Axis Dial

Autonomy is not "on" or "off." It is adjustable along five axes, and can shift over the lifecycle of the business:

| Axis | Low Autonomy | High Autonomy |
|------|-------------|---------------|
| **By business function** | Legal: human approves every output | Engineering: auto-merge passing PRs |
| **By lifecycle stage** | Pre-seed: human reviews every plan | Scale: routine ops fully autonomous |
| **By transaction value** | Auto-approve < $1 LLM call | Board approval > $10K infra change |
| **By reversibility** | Auto-rollback on health check failure | Human approval for database migration |
| **By novelty** | First deploy to new region: gated | 100th deploy to existing region: autonomous |

Zephyr encodes these as policies. Each org declares its autonomy profile, and the CEO layer (or human board) can override.

### 6. Institutional Memory (Beads + Dolt)

A business has institutional memory — customer relationships, financial history, product decisions, legal obligations, past incidents. Each org needs persistent state, and the CEO layer needs a unified view.

**Dolt** (version-controlled SQL database) provides:
- Branch-per-agent workflows with cell-level merge
- Full audit trail — every cell change is versioned with diffs
- SQL-queryable state for selective context retrieval (agents query what they need, not load everything)
- Cross-org shared tables (the company's source of truth)
- Transaction isolation for concurrent multi-agent writes

**Beads** (distributed graph issue tracker) provides:
- Task graph with hierarchical work items (epic → task → subtask)
- Agent-to-agent messaging via mailboxes
- Graph relationships between work items (blocks, caused-by, relates-to)
- Semantic memory decay — old decisions compressed, recent context at full fidelity
- Crash-resilient persistence (survives agent session restarts)

Together:

| Business Need | Layer |
|---------------|-------|
| Customer records, financial ledger, contract state | Dolt tables (shared, versioned) |
| Product backlog, sprint work, incident tickets | Beads graph (org-scoped + cross-org links) |
| Agent memory across sessions | Beads with semantic decay |
| Compliance and audit trail | Dolt diff history |
| Cross-org coordination | Beads relationships + Dolt shared tables |

### 7. Inter-Org Communication

Orgs communicate through a hybrid model:

| Layer | Role | Mechanism |
|-------|------|-----------|
| **Dolt** | Source of truth | Shared tables. Orgs read/write versioned state. Branch-per-org prevents conflicts. |
| **Beads** | Coordination | Task graph with cross-org links. Engineering bead completes → unblocks ops bead. Agent mailboxes for direct messaging. |
| **Events** | Reactivity | Real-time signals for time-sensitive cross-org triggers (deploy completed, alert fired, budget exhausted). |

Dolt is the ledger. Beads is the task board. Events are the pager. Each layer has a clear responsibility and failure mode.

### 8. Business Lifecycle Staging

Not every business function exists from day one. Orgs accrete as the business grows:

**Pre-Seed (Idea → Spec)**

| Org | Function |
|-----|----------|
| Product | Spec generation from problem statement — user stories, acceptance criteria |
| Legal | Template-driven incorporation, IP assignment, founder agreements |
| CEO | Human-as-CEO with agent assistance for market analysis |

**Seed (Build → First Users)**

| Org | Function |
|-----|----------|
| Engineering | **Keiro** — plan, implement, test, debug, PR |
| Operations | Deploy, monitor, respond (SRE agent on fly.io) |
| Product | Refine specs from early user feedback |
| Finance | Token ledger, cost tracking, runway projection |

**Growth (Users → Revenue)**

| Org | Function |
|-----|----------|
| GTM | Landing pages, docs, content, developer marketing |
| Sales | Pipeline management, proposals, lead scoring |
| Customer Success | Support triage, onboarding, retention |
| Analytics | Metrics pipelines, dashboards, board reporting |
| Finance (expanded) | Invoicing, accounts receivable, usage billing |

**Scale (Revenue → Efficiency)**

| Org | Function |
|-----|----------|
| Platform/Infra | Multi-region, fleet management, database sharding |
| Security/Compliance | SOC2 prep, audit, pen testing, vulnerability management |
| Product (mature) | Roadmap from usage data, competitive analysis |
| HR | If human contractors enter — payroll, compliance |

**Exit**

| Org | Function |
|-----|----------|
| Legal | Due diligence prep, data room assembly, contract review |
| Finance | Audited financials, cap table, reconciliation |
| Executive | Human. Judgment and relationships. |

The framework does not require building all orgs upfront. The CEO layer stands up new orgs as the lifecycle demands.

---

## Practical Path: Option A → Option C

Three architectural options were considered for how orgs relate to Keiro:

**Option A — Same binary, different config.** Each org is a Keiro instance with different agents, tools, and pipeline config. Simplest. Discovers where engineering assumptions leak.

**Option B — Each org has an LLM lead agent (Gastown-style).** More flexible but non-deterministic. Expensive. Hard to audit.

**Option C — Kernel extraction.** Keiro's general pattern (agent runtime, tool sandbox, governance, memory) becomes the framework. Each org is a module that registers its specific agents, tools, pipeline shape, and leader model. Most architecturally sound. Most complex.

**Decision: Start with Option A, evolve to Option C.**

1. **Today:** Keiro is the engineering org. It works as-is.
2. **Next:** Stand up Operations as a second Keiro instance with different config. Immediately discover where the Controller assumes "engineering-shaped" work.
3. **Then:** Extract the kernel. The places where Ops didn't fit become the seams. The general pattern separates from the specific patterns.
4. **Eventually:** Each org is a module that registers with the kernel. The kernel provides execution, governance, memory, and inter-org communication.

```python
# Target org construct (illustrative)
class Org:
    name: str                          # "engineering", "operations", "finance"
    agents: list[Agent]                # domain-specific workers
    tools: ToolAllowlist               # what this org can touch
    leader: Controller | Agent | Cron  # how work gets routed
    pipeline: Pipeline                 # linear, event-driven, periodic, ad-hoc
    governance: ZephyrPolicy           # org-specific trust boundaries
    memory: BeadsNamespace             # org-scoped beads + shared Dolt tables
```

The seam discovery in step 2 is the critical learning moment. Do not skip it by designing the kernel in the abstract.

---

## Test Cases

Three projects validate the framework against three different business models:

### LowEndInsight / LowEndInsight-GET
- **Model:** SaaS / API-as-a-Service (with air-gap enterprise variant)
- **Stack:** Elixir library + REST API (Plug/Cowboy, Redis, Oban/Postgres)
- **Orgs exercised:** Engineering (features), Ops (deploy to fly.io, manage Redis/Postgres), GTM (docs, developer marketing), Finance (API key metering, usage billing), Compliance (SBOM mandates, government positioning)
- **Why:** Real product, real API contract, real infra needs, real revenue model. Exercises the full org chart.

### Zephyr
- **Model:** Open-source infrastructure / framework
- **Stack:** TBD (Rob's project, integrating toward open release)
- **Orgs exercised:** Engineering (build the framework), Product (define governance primitives), Community (contributors, docs, adoption)
- **Why:** The governance layer governing itself. Maximum dogfooding. Tests the open-source business model where the "customer" is other projects.

### Keiro
- **Model:** Developer tool / open-core
- **Stack:** Python, LiteLLM, Typer, Pydantic
- **Orgs exercised:** Engineering (Keiro building itself), Product (roadmap from ops delta ADR), Community (CONTRIBUTING.md flow)
- **Why:** Maximum recursion — the agentic corporation framework building itself. Simplest starting point because the engineering org already exists.

---

## Build Phases

| Phase | What | Validates |
|-------|------|-----------|
| **0** | Keiro runs reliably (tests, e2e validation, CI) | Engineering org works |
| **1** | Integrate Beads + Dolt for institutional memory | Memory layer works across sessions |
| **2** | Integrate Zephyr as governance substrate | Policy enforcement works beyond Keiro's built-in boundaries |
| **3** | Stand up Ops org for LowEndInsight deployment (Option A: second Keiro instance, different config) | Two orgs coexist; discover where abstractions leak |
| **4** | Stand up Finance org (token ledger in Dolt, metering) | Cross-org state works; budget flows between orgs |
| **5** | CEO layer (cross-org routing, budget allocation, progress tracking) | Multi-org coordination works |
| **6** | Kernel extraction (refactor based on seams discovered in Phases 3-5) | Option C realized; orgs are modular |
| **7** | GTM org for LowEndInsight as first external product | Full lifecycle: build, deploy, sell, support |

---

## Key Architectural Decisions Remaining

| Decision | Options | When to Decide |
|----------|---------|---------------|
| **Event bus implementation** | In-process pub/sub, Redis Streams, Dolt triggers, Beads graph polling | Phase 3 (when two orgs need real-time signals) |
| **Dolt schema design** | Per-org schemas vs. shared schema with row-level org scoping | Phase 1 (when Dolt is integrated) |
| **Beads namespace isolation** | Per-org Beads instances vs. shared instance with namespace tagging | Phase 1 (when Beads is integrated) |
| **CEO agent model** | Deterministic router vs. LLM agent vs. human-only | Phase 5 (when CEO layer is built) |
| **Multi-tenancy** | Single-tenant (your projects only) vs. multi-tenant (marketplace) | Phase 7+ (defer as long as possible) |
| **Token settlement** | Internal accounting only vs. fiat conversion (Stripe) | Phase 7+ (defer until revenue exists) |

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Premature kernel extraction** — designing the framework before discovering real seams | High | Stick to Option A through Phase 3. Let the Ops org reveal what's engineering-specific vs. general. |
| **Governance complexity explosion** — Zephyr policies become unmanageable across many orgs | Medium | Start with Keiro's existing boundary model. Generalize only what's proven. |
| **Memory bloat** — Dolt + Beads accumulate unbounded state | Medium | Beads semantic decay. Dolt branch pruning. Explicit retention policies per org. |
| **Inter-org coupling** — orgs become dependent on each other's internal state | High | Orgs communicate through Beads (tasks) and Dolt (shared tables), never through direct internal access. Enforce interface boundaries. |
| **CEO layer hallucination** — LLM making bad cross-org allocation decisions | Critical | Tightest human gates. Budget caps per org. CEO proposes, human approves until trust is established. |
| **Scope creep** — building all orgs before any org works reliably | High | Phase 0 exists for a reason. Engineering org must be solid before standing up Ops. |

---

## Summary

Keiro is the engineering department. The agentic corporation is the company. The framework provides the primitives — agent execution, tool sandboxing, governance (Zephyr), institutional memory (Beads + Dolt), and inter-org communication — that each business function org composes to operate autonomously.

The practical path is incremental: start with Keiro as the only org, add Ops as a second Keiro instance to discover the seams, then extract the kernel. Each phase is validated against real projects (LowEndInsight, Zephyr, Keiro itself) representing three different business models.

The human sits at the board level — setting strategy, approving high-stakes decisions, and tuning the autonomy dial per org, per lifecycle stage, per transaction value, per reversibility, and per novelty. The goal is not to remove the human. It is to make the human's judgment count where it matters most.

---

*This ADR should be revisited after Phase 3, when the Ops org has been stood up and the real seams between "engineering-specific" and "general" are known.*
