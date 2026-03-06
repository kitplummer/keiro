# ADR: Dual-Product Evolution Strategy

**Date:** 2026-03-01
**Authors:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** [Agentic Corporation Framework](./adr-agentic-corporation-framework.md) (lifecycle staging), [Delivery and SRE ADR](./adr-delivery-and-sre-ops-org.md), production experience with LowEndInsight and Keiro

---

## Context

Two products exist simultaneously:

1. **LowEndInsight** — An Elixir-based open-source risk analysis library and REST API, deployed on fly.io. It has real users, a real deployment, and generates real operational needs. It is the *customer* of Keiro.

2. **Keiro** — A Rust-based agentic development engine being ported from Python. It builds software autonomously but cannot yet deploy or operate what it builds. It is the *platform* that serves LowEndInsight.

Building both products at once creates a resource allocation problem. Platform work (fixing the Keiro implementer, building the ops org, adding context assembly) competes with product work (LowEndInsight features, bug fixes, deployments). Without explicit allocation rules, two failure modes emerge:

- **Platform starvation:** All effort goes to product features. Keiro never improves. Manual work compounds.
- **Product starvation:** All effort goes to platform architecture. LowEndInsight stagnates. No customer value ships. The platform has no real workload to validate against.

The [Corporation Framework ADR](./adr-agentic-corporation-framework.md) defines lifecycle staging (Pre-Seed → Seed → Growth → Scale → Exit) and milestone-gated org expansion, but does not address how to allocate effort *between* products or when to invest in platform vs. product.

---

## Decision

### 1. LowEndInsight Is the Customer, Keiro Is the Platform

This is a framing decision, not a technical one. It determines how priorities are set:

- **Product needs drive platform roadmap.** Keiro features are justified by LowEndInsight needs, not by architectural elegance.
- **Platform capabilities are measured by product outcomes.** A Keiro improvement that doesn't help ship LowEndInsight faster, cheaper, or more reliably is premature.
- **LowEndInsight is not a test case.** It is the primary customer. Treating it as a demo project leads to toy implementations.

```
┌─────────────────────────────────────────────┐
│                                             │
│   LowEndInsight (customer)                  │
│   "I need feature X deployed to fly.io"     │
│                                             │
│          │ need                              │
│          ▼                                   │
│                                             │
│   Keiro (platform)                      │
│   "I can build X, but I can't deploy it"    │
│                                             │
│          │ gap identified                    │
│          ▼                                   │
│                                             │
│   Platform investment                       │
│   "Build deploy pipeline (ops org)"         │
│                                             │
│          │ capability built                  │
│          ▼                                   │
│                                             │
│   LowEndInsight ships faster                │
│   "Feature X deployed autonomously"         │
│                                             │
└─────────────────────────────────────────────┘
```

### 2. The Dual Flywheel

Product work and platform work are not in opposition. They form a flywheel:

```
    LowEndInsight need
           │
           ▼
    Keiro capability built
           │
           ▼
    Cost of shipping drops
           │
           ▼
    More product shipped
           │
           ▼
    More needs surface
           │
           └──────▶ (back to top)
```

Each cycle produces:
- A delivered product feature (customer value)
- A reusable platform capability (compounding returns)
- Validated platform behavior (real workload, not synthetic tests)

The flywheel stalls when either side is starved:
- No product work → no real needs → platform capabilities are speculative
- No platform work → same manual effort each time → product shipping slows

### 3. Budget Allocation: 60% Product / 40% Platform

Default allocation of agentic budget (LLM spend, human attention, batch-run tasks):

| Allocation | Target | Examples |
|---|---|---|
| **60% product** | LowEndInsight features, bugs, deployments | New API endpoints, dependency analysis improvements, performance fixes |
| **40% platform** | Keiro capabilities that serve the product | Implementer reliability, ops org, context assembly, decomposition improvements |

**Adjustments by phase:**

| Phase | Product | Platform | Rationale |
|---|---|---|---|
| Current (implementer broken) | 20% | 80% | Can't ship product if the platform doesn't work |
| Implementer stable | 60% | 40% | Default allocation |
| Pre-launch push | 80% | 20% | Ship features for a deadline |
| Post-incident | 30% | 70% | Fix platform reliability before shipping more |

The allocation is a guideline, not a hard constraint. It is reviewed at each batch-run planning session. The key discipline: every batch run must include *some* product work and *some* platform work. Pure-platform sprints are a smell.

### 4. The Two-Failure Rule

A platform capability is justified when the same product task has failed or been too expensive **twice**. One failure could be a fluke — bad decomposition, model hiccup, unlucky context. Two failures indicate a structural gap.

| Scenario | First occurrence | Second occurrence | Action |
|---|---|---|---|
| Implementer fails on multi-file Elixir change | Retry with better decomposition | Build Elixir-specific planner hints | Platform investment justified |
| Deploy fails because no ops pipeline | Deploy manually | — | Platform investment justified (manual = expensive every time) |
| Context window overflow on large module | Increase token budget | Build context assembly truncation | Platform investment justified |
| Test failure on unfamiliar framework | Retry with more context | — | Not yet justified; may be one-off |

**Exceptions to the two-failure rule:**
- **Security concerns** — one occurrence justifies investment (e.g., secrets leaking into LLM context)
- **Data integrity** — one occurrence justifies investment (e.g., bead corruption)
- **Recurring manual toil** — if a manual step happens every deploy, it's justified after the first deploy (every occurrence is a "failure" of automation)

### 5. Milestone-Gated Org Expansion

Each org in the [Corporation Framework](./adr-agentic-corporation-framework.md) is justified by a concrete business milestone, not by architectural completeness. An org that exists before its milestone is premature complexity.

| Milestone | Org / Capability | Rationale |
|---|---|---|
| **First successful deploy** | Ops: deploy pipeline | You've deployed once manually; now automate it |
| **30 days healthy in production** | Ops: monitor + incident pipelines | Enough operational history to know what to monitor |
| **First external user (non-Kit)** | Docs + onboarding | Someone else needs to understand the product |
| **First paying customer** | Finance: cost tracking + invoicing | Revenue creates financial obligations |
| **10 customers** | GTM: marketing + developer relations | Growth requires intentional outreach |
| **$1k MRR** | Finance: full ledger + reporting | Revenue at scale requires accounting |
| **$10k MRR** | CEO layer | Cross-org allocation decisions have real financial impact |

**Current state:** LowEndInsight has been deployed manually but has no automated deploy pipeline. The next milestone is "first successful automated deploy" → ops deploy pipeline.

### 6. Near-Term Sequencing

Based on current state (Keiro implementer unreliable, no ops pipeline, LowEndInsight deployed manually):

```
Now                                                            Future
 │                                                               │
 ▼                                                               ▼
Fix implementer ──▶ Manual deploy ──▶ Batch-run product ──▶ Build deploy
reliability          (document the      features for          pipeline
                      process)           LowEndInsight         (automate)
     │                    │                   │                    │
     │                    │                   │                    │
  Platform             Platform            Product             Platform
  (80/20)              (Phase 0            (60/40)             (60/40 but
                        of ops ADR)                             ops-focused)
```

| Step | Type | What | Why Now |
|---|---|---|---|
| 1. Fix implementer | Platform | Resolve reliability failures in Claude Code implementer integration | Can't ship anything autonomously until this works |
| 2. Document manual deploy | Platform | Write `docs/runbook-lowendinsight-deploy.md` | Phase 0 of ops ADR; understand before automating |
| 3. Batch-run product features | Product | Run Keiro against LowEndInsight backlog | Ship customer value; validate implementer fix |
| 4. Build deploy pipeline | Platform | Implement `glitchlab ops deploy` | Automate the documented manual process |
| 5. Batch-run with deploy | Both | Keiro builds features + ops deploys them | Validate the full inner+outer loop |

Steps 1-2 are sequential (platform-heavy, unblocking). Steps 3-5 alternate product and platform work per the 60/40 allocation.

---

## Consequences

### Positive

- **Platform work is always grounded in observed need.** No speculative architecture. Every Keiro capability traces to a LowEndInsight requirement.
- **Product ships continuously.** The 60% product allocation ensures LowEndInsight doesn't stagnate while the platform is being built.
- **The flywheel compounds.** Each platform capability reduces the cost of future product work. Each product iteration surfaces the next platform need.
- **Org expansion is justified, not aspirational.** No org exists before its milestone. This prevents premature complexity.

### Negative

- **Some pain is felt longer than speculative investment would allow.** The two-failure rule means the first occurrence of a problem is endured, not fixed. This is by design — premature optimization of the platform delays product value.
- **The 60/40 split requires discipline.** Platform work is architecturally more interesting than product work. The temptation to over-invest in the platform is real and must be actively resisted.
- **Milestone gates may feel slow.** Waiting for "first paying customer" before building finance tooling means operating without proper cost tracking during early growth. Accepted — manual tracking is sufficient until revenue exists.
- **Single-customer risk.** LowEndInsight as the sole customer creates a risk that Keiro over-fits to its needs. Mitigated by the Corporation Framework's three test case projects (LowEndInsight, Zephyr, Keiro itself).

---

## Alternatives Considered

### 1. Build the full platform first, then ship product

Complete Keiro (all orgs, full lifecycle) before using it to build LowEndInsight.

Rejected because:
- No real workload to validate against. Platform capabilities would be designed in the abstract.
- LowEndInsight stagnates for months. No customer value ships.
- The Corporation Framework ADR explicitly warns against this: "Scope creep — building all orgs before any org works reliably."

### 2. Ship product manually, build platform later

Focus entirely on LowEndInsight features. Deploy manually. Build Keiro when there's time.

Rejected because:
- Manual work doesn't compound. Each deploy, each feature, each bug fix costs the same effort.
- Keiro never improves because it's never the priority.
- The whole point of an agentic development engine is to reduce the marginal cost of shipping.

### 3. Fixed 50/50 split with no phase adjustment

Always allocate exactly 50% to each product.

Rejected because:
- Ignores reality. When the implementer is broken, spending 50% on product features that can't be implemented is waste.
- Phase-appropriate allocation (80/20 during platform crises, 60/40 at steady state) reflects actual needs.

---

## Verification

This strategy is validated by asking three questions at each batch-run planning session:

1. **Is LowEndInsight shipping?** If not, product allocation is too low or the platform is broken.
2. **Is shipping getting cheaper?** If the cost per feature is flat or rising, platform investment is insufficient or misdirected.
3. **Has any manual step happened twice?** If yes, platform automation is overdue (two-failure rule triggered).

---

## References

- [ADR: Agentic Corporation Framework](./adr-agentic-corporation-framework.md) — org construct, lifecycle staging, Phase 3
- [ADR: Delivery and SRE — The Operations Org](./adr-delivery-and-sre-ops-org.md) — what the ops org does, implementation phases
- [ADR: Observability and Continuous Operations](./adr-observability-and-continuous-operations.md) — telemetry and continuous mode
- [Full Agentic Operations Gap Analysis](./analysis-full-agentic-ops-delta.md) — 25-30% readiness assessment
- Beads gl-3n4 through gl-3n4.5 — ops org implementation tasks

---

*This ADR should be revisited when either (a) a second product beyond LowEndInsight becomes a Keiro customer, requiring multi-customer allocation rules, or (b) LowEndInsight reaches the "first paying customer" milestone, triggering Finance org expansion and changing the budget allocation calculus.*
