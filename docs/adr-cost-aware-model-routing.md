# ADR: Cost-Aware Model Routing

**Date:** 2026-02-22
**Author:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** Gemini provider integration, dogfooding cost analysis ($0.50/run Anthropic vs $0.02/run Gemini Flash)

---

## Context

Keiro's router currently uses a static `role → model` map defined in config. Every call for a given role goes to the same model regardless of task complexity, remaining budget, or the nature of the work. This was fine for getting the pipeline running, but dogfooding has made the cost problem concrete:

| Model | Approx. cost/run | Quality |
|-------|-------------------|---------|
| Claude Sonnet | ~$0.50 | High — reliable tool use, strong reasoning |
| Gemini 2.5 Flash | ~$0.02 | Good — capable for most tasks, 25x cheaper |
| Gemini 2.5 Flash Lite | ~$0.008 | Adequate — fine for simple/mechanical tasks |
| Local (Ollama) | $0.00 | Variable — no API cost, quality depends on model |

The pipeline runs 6 agents per task. Not all agents need the same model quality:

- **Planner**: Needs strong reasoning to decompose tasks. Benefits from an expensive model.
- **Implementer**: Needs reliable tool use across multiple turns. Mid-tier or high-tier depending on task complexity.
- **Debugger**: Reads test output, makes targeted fixes. Often mechanical — cheap model usually suffices.
- **Security**: Reviews diffs for vulnerabilities. Focused analytical task — mid-tier is fine.
- **Release**: Determines version bump and changelog. Mechanical — cheap model works.
- **Archivist**: Summarizes what happened. Straightforward — cheap model works.

A single `role → model` mapping cannot capture this. A 3-line typo fix shouldn't burn $0.50 on Claude Sonnet for the planner. A complex architectural refactor shouldn't be routed to Flash Lite for implementation.

### What exists in the ecosystem

The LLM routing space has matured significantly:

**Embeddable approaches (no hosted dependency):**
- **RouteLLM** (LMSYS, ICLR 2025) — trained routers for binary cheap/expensive decisions. Matrix factorization router is fast, no GPU needed. 85% cost reduction with 95% quality retention.
- **RoRF** (Not Diamond) — random forest classifiers for model pair routing. Lightweight, portable to Rust via `smartcore`/`linfa`.
- **FrugalGPT cascade** (Stanford) — try cheap model first, escalate on low confidence. 98% cost reduction claimed. Maps directly to Keiro's existing `parse_error: true` fallback pattern.
- **Hybrid LLM** (Microsoft, ICLR 2024) — single threshold parameter controls cost-quality tradeoff. 78% of queries to cheap model with <1% quality drop.

**Hosted services (pattern references, not dependencies):**
- OpenRouter (inverse-price weighting + latency tracking), LiteLLM (cost-based routing + budget enforcement), Portkey (conditional routing rules), Unify.ai (quality/cost/speed sliders).

**Rust-native tools:**
- `llm_router` crate (load balancer, not smart routing), Traceloop Hub (gateway), `ai-gateway` (fallback/latency routing). None do cost-intelligent routing.

No existing Rust library solves this problem. The Python libraries provide good algorithmic references but would need to be ported or the approaches reimplemented.

---

## Decision

**Keiro will implement cost-aware model routing in three tiers, each building on the last. Tier 1 requires zero ML dependencies and addresses the immediate cost problem. Tiers 2-3 add intelligence over time.**

### Tier 1: Rule-Based Cost Routing (immediate)

Extend the router with a `ModelChooser` that selects a model based on deterministic rules:

```rust
pub struct ModelChooser {
    /// Available models with metadata.
    models: Vec<ModelProfile>,
    /// Per-role preferences: min capability tier, max cost preference.
    role_preferences: HashMap<String, RolePreference>,
    /// Global cost-quality threshold: 0.0 = always expensive, 1.0 = always cheap.
    cost_quality_threshold: f64,
}

pub struct ModelProfile {
    pub model_string: String,          // "gemini/gemini-2.5-flash"
    pub input_cost_per_m: f64,         // $/million input tokens
    pub output_cost_per_m: f64,        // $/million output tokens
    pub capabilities: HashSet<String>, // {"tool_use", "long_context", "code", "vision"}
    pub tier: ModelTier,               // Economy, Standard, Premium
}

pub enum ModelTier {
    Economy,  // Flash Lite, Haiku, local models
    Standard, // Flash, Sonnet, GPT-4o-mini
    Premium,  // Pro, Opus, GPT-4o
}
```

Selection logic:

1. Filter models by required capabilities (e.g., implementer requires `tool_use`).
2. Apply role preference for minimum tier (e.g., planner prefers `Standard` or above).
3. Check remaining budget — if budget is tight, bias toward cheaper models regardless of preference.
4. Among eligible models, pick the cheapest.

The `cost_quality_threshold` provides a single knob: at `0.0` every role gets its preferred tier; at `1.0` every role gets the cheapest capable model. This maps to the Hybrid LLM insight that a single tunable threshold captures most of the cost-quality tradeoff.

Configuration:

```yaml
routing:
  # Model pool with cost/capability metadata
  models:
    - model: "gemini/gemini-2.5-flash-lite"
      tier: economy
      capabilities: [tool_use, code]
    - model: "gemini/gemini-2.5-flash"
      tier: standard
      capabilities: [tool_use, code, long_context]
    - model: "anthropic/claude-sonnet-4-20250514"
      tier: premium
      capabilities: [tool_use, code, long_context, vision]

  # Per-role preferences
  roles:
    planner:
      min_tier: standard
    implementer:
      min_tier: standard
      requires: [tool_use]
    debugger:
      min_tier: economy
      requires: [tool_use]
    security:
      min_tier: economy
    release:
      min_tier: economy
    archivist:
      min_tier: economy

  # Global knob: 0.0 = quality-first, 1.0 = cost-first
  cost_quality_threshold: 0.7
```

### Tier 2: Cascade with Confidence Check (near-term)

Add the FrugalGPT pattern to the tool-use loop:

1. Route to the cheapest eligible model.
2. If the response has `parse_error: true`, fails JSON validation, or contains refusal markers — escalate to the next tier.
3. Track escalation rates per role to auto-tune thresholds.

This builds on infrastructure that already exists: the pipeline's fallback output and the debugger's retry loop. The key addition is making escalation a first-class routing decision rather than a failure path.

```rust
impl ModelChooser {
    /// Select model, trying cheapest first.
    /// Returns an ordered list: primary choice + fallbacks.
    fn select_with_fallbacks(
        &self,
        role: &str,
        budget_remaining: f64,
    ) -> Vec<&ModelProfile> {
        // ... returns [economy, standard, premium] ordered by cost
        // Router tries each in order, escalating on quality failure
    }
}
```

### Tier 3: Learned Routing (future)

When enough dogfooding data exists (hundreds of runs with outcome tracking), train a lightweight router:

- **Input features**: task description embedding (via a small local model), agent role, remaining budget, historical success rate for this task type.
- **Output**: model selection.
- **Algorithm**: Matrix factorization (from RouteLLM) or random forest (from RoRF). Both are trivially implementable in Rust with `ndarray` or `smartcore` — no Python, no GPU.
- **Training data**: Keiro's own history entries, which already record model used, cost, and outcome (success/failure/parse_error).

This tier is explicitly deferred until the data exists to train it. Premature ML routing without data would be worse than the Tier 1 rules.

### Where this lives in the architecture

```
config.yaml
    │
    ▼
ModelChooser (new, in router crate)
    │
    ├── resolves role + budget + capabilities → model string
    │
    ▼
Router::complete() / complete_with_tools()
    │
    ├── dispatches to Provider (Anthropic, Gemini, OpenAI)
    │
    ▼
Response + cost tracking
    │
    ├── feeds back to ModelChooser (budget update, escalation signal)
```

The `ModelChooser` sits between config and the existing `Router`. The `Router` continues to handle provider dispatch, retries, and budget tracking. The chooser is a new layer that answers "which model?" before the router answers "which provider?".

---

## Consequences

### Positive

- **Immediate cost reduction.** Tier 1 alone should cut dogfooding costs 5-10x by routing mechanical agents (debugger, release, archivist) to Flash Lite.
- **Budget-aware degradation.** When budget is tight, the system automatically shifts to cheaper models rather than failing outright.
- **No new dependencies for Tier 1.** Pure config + Rust logic. No ML libraries, no external services.
- **Data flywheel.** History entries already capture model, cost, and outcome. Tier 3 training data accumulates naturally during Tiers 1-2.
- **Provider-agnostic.** The chooser works with any provider — adding a new model is a config entry, not a code change.

### Negative

- **Config complexity increases.** The flat `role → model` map was trivially understandable. Model profiles with tiers and capabilities are more to reason about.
- **Tier 2 adds latency.** Cascade means occasionally paying for two LLM calls when the cheap one fails. Net cost should still be lower, but individual task latency may spike.
- **Tier 3 is speculative.** The learned router may never be worth the complexity if Tier 1+2 capture most of the savings. Should be validated by data before building.

### Migration

The current static `role → model` config continues to work as-is. The chooser is opt-in: if `routing.models` is absent, the router falls back to the existing `role → model_string` map. No breaking changes.

---

## Alternatives Considered

### 1. Use a hosted routing service (OpenRouter Auto, Not Diamond, Martian)

Route all calls through a third-party smart router. Gets intelligent routing immediately with no implementation work.

Rejected because:
- Adds a network hop and vendor dependency to every LLM call.
- Cannot route to local models.
- Opaque routing decisions conflict with Keiro's governance model.
- Cost of the routing service itself may offset savings on small-scale dogfooding.

### 2. Embed RouteLLM's matrix factorization router directly

Port RouteLLM's MF router to Rust. Gets learned routing immediately using their pre-trained weights.

Deferred (Tier 3) because:
- Pre-trained weights are calibrated for general chat benchmarks, not agentic coding tasks. Would need fine-tuning on Keiro's own data.
- Requires an embedding model for prompt encoding — adds a dependency and inference cost for the routing decision itself.
- Tier 1 rules likely capture 80% of the savings with 10% of the complexity.

### 3. Port LiteLLM's routing layer to Rust

LiteLLM is the closest existing solution to what Keiro needs: unified provider abstraction, cost-based routing, budget enforcement per model/user, fallback chains, and cost tracking. It supports 100+ providers and has a mature, battle-tested routing engine.

A port would mean reimplementing LiteLLM's routing strategies (simple-shuffle, least-busy, usage-based, latency-based, cost-based) and its model cost database in Rust, either directly in the `router` crate or as a standalone library.

Deferred because:
- LiteLLM is ~50k lines of Python. A faithful port is a multi-month project that would stall the immediate cost problem.
- Most of LiteLLM's complexity is in provider compatibility (100+ backends, streaming, embedding, image generation). Keiro only needs 3-4 providers.
- The routing strategies themselves are simple — the value is in the provider coverage, not the routing algorithms.
- Cherry-picking LiteLLM's cost-routing logic (the useful 5%) is essentially what Tier 1 does, without inheriting the other 95%.

Worth revisiting if Keiro's router grows to support many more providers and the provider abstraction becomes the bottleneck.

### 4. Build a standalone Rust crate for LLM cost routing

Extract the `ModelChooser` as a general-purpose `llm-costrouter` crate on crates.io. This would be the Rust ecosystem's answer to LiteLLM's routing layer — a library any Rust project could embed for cost-aware model selection.

Not rejected, but deferred:
- Building for Keiro first, extracting later, is the right sequencing. Premature generalization before the API is proven by a real consumer leads to bad abstractions.
- The `ModelProfile` / `ModelChooser` types are designed to be crate-extractable. No Keiro-specific types leak into the chooser interface — it takes role strings, capability sets, and budget numbers.
- If the chooser proves useful through Tiers 1-2, extraction into a standalone crate is a natural Phase 7. The Rust ecosystem currently has nothing in this space (the existing `llm_router` crate is a load balancer, not a cost router).

This is the long-term play: own the Rust LLM cost-routing niche the way LiteLLM owns the Python one, but start by solving our own problem first.

### 5. Always use the cheapest model, escalate on failure

Pure cascade with no per-role preferences. Every call starts at the cheapest model.

Rejected because:
- Wastes tokens on guaranteed escalations. The planner will almost always fail on Flash Lite for complex tasks — paying for a failed cheap call before the real call is pure waste.
- Per-role preferences encode known capability requirements cheaply.

### 6. Keep static routing, just pick cheaper defaults

Change `config.yaml` to route everything to Gemini Flash and call it done.

This is what we've done today. It works for cost but sacrifices quality uniformly. The chooser adds the ability to spend more where it matters (planning, complex implementation) and less where it doesn't (release notes, archiving).

---

## Implementation Path

| Phase | What | Validates |
|-------|------|-----------|
| **1** | `ModelProfile` and `ModelChooser` types in router crate | Type system for model metadata and selection |
| **2** | Config parsing for `routing.models` and `routing.roles` | Chooser is configurable via YAML |
| **3** | Wire chooser into `Router::complete()` / `complete_with_tools()` | Dynamic model selection replaces static map |
| **4** | Budget-pressure logic: shift to cheaper models as budget depletes | Graceful degradation under budget pressure |
| **5** | Cascade fallback in tool-use loop (Tier 2) | Escalation on parse failure / low quality |
| **6** | Escalation rate tracking in history | Data for Tier 3 and threshold tuning |

Phases 1-4 are the critical path (Tier 1). Phase 5 is Tier 2. Phase 6 provides the data foundation for an eventual Tier 3.

---

*This ADR should be revisited after Phase 4, when Tier 1 routing has been validated against real dogfooding runs with mixed model pools. Tier 3 should not be started until at least 200 pipeline runs with outcome data have been recorded.*
