# ADR: Observability and Continuous Operations

**Date:** 2026-02-28
**Authors:** Kit, with Claude analysis
**Status:** Draft
**Informed by:** Three batch runs (2026-02-27/28), Perplexity Computer architecture, production agent pipeline experience

---

## Context

Keiro runs as a batch process: load beads, execute N tasks, stop. Monitoring requires tailing log files and grepping for patterns. Three batch runs have produced useful data ($7+ spent, 7 PRs merged, ~60 tasks attempted) but every insight required manual log analysis.

This works for development but fails at scale. When Keiro operates LowEndInsight or runs continuously against its own backlog, we need:

1. **Real-time observability** — What is the system doing right now?
2. **Historical trends** — Is the system getting better or worse over time?
3. **Continuous operation** — Run indefinitely, not in fixed batches.
4. **Alerting** — When something goes wrong, how do we know?

Perplexity's Computer product (Feb 2026) validates the multi-model orchestration approach — they coordinate 19 models with a central orchestrator. But their $200/mo product still depends on users to verify output quality. Keiro's TQM and governance layers should provide automated quality assurance, and observability is the foundation for measuring whether that works.

---

## Decision

### 1. OpenTelemetry Integration

Instrument Keiro with OpenTelemetry (OTLP) for structured telemetry. Three signal types:

#### Traces

One trace per task execution, with spans for each pipeline stage:

```
Task gl-li2.1 (trace)
├── architect_triage (span, 1.8s, 1032 tokens)
├── planner (span, 20.8s, 12431 tokens)
├── budget_gate (span, 3ms, decision=decompose)
├── replan (span, 12.1s, 10792 tokens)
└── decompose (span, <1ms, 5 sub-tasks)
```

Each span carries attributes:
- `glitchlab.task_id`, `glitchlab.agent`, `glitchlab.model`
- `glitchlab.tokens.prompt`, `glitchlab.tokens.completion`, `glitchlab.tokens.total`
- `glitchlab.cost_usd`
- `glitchlab.status` (decomposed, pr_created, failed, etc.)
- `glitchlab.error` (if failed)

Sub-tasks link to parent traces via `parent_span_id`, creating a decomposition tree visible in any trace viewer (Jaeger, Grafana Tempo).

#### Metrics

Counters and histograms exported via OTLP:

| Metric | Type | Description |
|--------|------|-------------|
| `glitchlab.tasks.total` | Counter | Tasks attempted, by status |
| `glitchlab.tasks.duration_seconds` | Histogram | Time per task, by size |
| `glitchlab.tokens.used` | Counter | Tokens consumed, by model/role |
| `glitchlab.cost.usd` | Counter | Dollar cost, by model/role |
| `glitchlab.decompositions.total` | Counter | Tasks decomposed |
| `glitchlab.decompositions.depth` | Histogram | Nesting depth |
| `glitchlab.budget_gate.decisions` | Counter | Pass/decompose/reject |
| `glitchlab.prs.created` | Counter | PRs shipped |
| `glitchlab.prs.merged` | Counter | PRs merged (if tracked) |
| `glitchlab.failures.total` | Counter | By failure category |
| `glitchlab.model.latency_seconds` | Histogram | LLM call latency, by model |
| `glitchlab.model.errors` | Counter | Provider errors, by model |
| `glitchlab.tqm.patterns` | Counter | TQM patterns detected |
| `glitchlab.queue.depth` | Gauge | Pending tasks in queue |
| `glitchlab.queue.blocked` | Gauge | Tasks blocked by deps |

#### Logs

Structured logs (already using `tracing`) forwarded via OTLP or stdout JSON. Correlate with traces via `trace_id` and `span_id` context propagation.

### 2. Web Dashboard

A lightweight web UI for real-time monitoring. Not a full application — a read-only dashboard served by the CLI or a standalone binary.

#### Views

**Live Run View** — What's happening now:
- Current task ID, agent, model, elapsed time
- Token consumption gauge (budget used / remaining)
- Cost ticker (cumulative spend)
- Queue depth (pending / in-progress / completed / failed)
- Recent events feed (last 20 events, auto-scrolling)

**Task History View** — What happened:
- Sortable/filterable table of all task executions
- Columns: task_id, status, tokens, cost, duration, PR link
- Click-through to task detail (plan, files changed, test results)
- Decomposition tree visualization (parent → children)

**Trends View** — Is the system improving:
- Success rate over time (rolling 20-task window)
- Average tokens per successful task (trending down = good)
- Average cost per PR (efficiency metric)
- Budget gate catch rate (% of root tasks caught)
- Model distribution (which models are being used)
- TQM pattern frequency (are the same patterns recurring?)

**Model Performance View** — How are the models doing:
- Per-model: latency p50/p95/p99, error rate, tokens/call
- Cost breakdown by model
- Success rate by model (which model produces the most PRs?)

#### Technology

- **Backend:** Axum (already in dependency tree via router crate)
- **Frontend:** HTMX + minimal CSS — no JS build step, no SPA framework
- **Data source:** Dolt (already running), JSONL history (fallback)
- **Deployment:** `glitchlab dashboard` CLI command, serves on localhost:3000
- **Updates:** Server-Sent Events (SSE) for live view, polling for trends

### 3. Continuous Operation Mode

Beyond batch mode, add a continuous operation mode:

```
glitchlab continuous --repo . --budget-per-hour 5.00 --poll-interval 5m
```

Behavior:
- **Poll for work:** Check beads backlog every `poll-interval` for new/unblocked tasks
- **Budget pacing:** Spread budget across the hour, don't burst-spend
- **Idle detection:** If no work available, sleep until new beads appear
- **Graceful shutdown:** Finish current task on SIGINT, checkpoint state
- **Health endpoint:** `/health` returns current status for external monitoring
- **Watchdog:** Self-restart if no progress in 30 minutes (configurable)

This transforms Keiro from "run a batch" to "run continuously" — the foundation for operating LowEndInsight as a product.

### 4. Alerting

Feed OpenTelemetry metrics to any OTLP-compatible alerting system (Grafana, Datadog, PagerDuty). Default alert rules:

- **SystemicFailure:** Restart intensity threshold exceeded
- **BudgetBurn:** >50% of budget consumed with <20% success rate
- **ModelDegradation:** >5 consecutive failures from same model
- **QueueStarvation:** Queue empty for >1 hour in continuous mode
- **CostSpike:** Single task exceeds 2x average cost

Alerts are TQM patterns with external notification. The TQMAnalyzer already detects these — alerting just adds the notification channel.

---

## Implementation

### Phase 0: Tracing Foundation (Priority 1)

Add `tracing-opentelemetry` and `opentelemetry-otlp` to the router and eng-org crates. Wrap existing `tracing` spans with OTLP export. This is purely additive — existing logging continues to work.

Files:
- `crates/router/Cargo.toml` — add opentelemetry deps
- `crates/router/src/router.rs` — add span attributes (model, tokens, cost)
- `crates/eng-org/src/pipeline.rs` — add task-level trace spans
- `crates/eng-org/src/orchestrator.rs` — add orchestrator-level spans
- `crates/cli/src/main.rs` — initialize OTLP exporter if `--otlp-endpoint` provided

### Phase 1: Metrics (Priority 1)

Add `opentelemetry` meter provider with the metrics table above. Counters and histograms at pipeline stage boundaries.

Files:
- `crates/eng-org/src/metrics.rs` — new module, metric definitions
- `crates/eng-org/src/pipeline.rs` — record metrics at stage transitions
- `crates/eng-org/src/orchestrator.rs` — record task-level metrics

### Phase 2: Dashboard (Priority 2)

Build the web dashboard. Start with Live Run View only — the most immediately useful.

Files:
- `crates/cli/src/commands/dashboard.rs` — new command
- `crates/eng-org/src/dashboard.rs` — already exists (event-based), extend to HTTP
- Templates: HTMX fragments for each view section

### Phase 3: Continuous Mode (Priority 2)

Add `glitchlab continuous` command. Builds on batch mode with polling, pacing, and graceful shutdown.

Files:
- `crates/cli/src/commands/continuous.rs` — new command
- `crates/eng-org/src/orchestrator.rs` — add poll/pace/idle logic

### Phase 4: Trends + Alerting (Priority 3)

Trends view in dashboard (requires historical data accumulation). Alert rules as TQM patterns with webhook/notification support.

---

## Rationale

### Why OpenTelemetry?

- **Standard:** OTLP is the industry standard for observability. Any backend works (Jaeger, Grafana, Datadog, stdout).
- **Already half-done:** We use `tracing` everywhere. `tracing-opentelemetry` bridges to OTLP with minimal code.
- **Composable:** Traces + metrics + logs from one SDK. No vendor lock-in.
- **LowEndInsight ready:** When Keiro operates LowEndInsight, the same telemetry pipeline works.

### Why HTMX, not a SPA?

- **No build step:** HTMX is a single JS include. No webpack, no node_modules, no npm.
- **Server-rendered:** Templates in Rust (askama/maud). Full-stack in one language.
- **Sufficient:** A monitoring dashboard doesn't need React. Live updates via SSE.
- **Matches architecture:** Keiro is a Rust system. The dashboard should be too.

### Why continuous mode?

Batch mode requires human initiation. Continuous mode is the foundation for:
- Operating LowEndInsight as a product (always-on)
- Self-improvement cycles (TQM detects pattern → creates bead → continuous mode picks it up)
- Multi-org coordination (CEO dispatches work, orgs pick it up continuously)

---

## Risks

1. **OTLP overhead:** Negligible. LLM calls take seconds; exporting spans takes milliseconds.
2. **Dashboard scope creep:** Keep it read-only. No task management, no configuration. That stays in CLI/beads.
3. **Continuous mode budget safety:** Must have hard budget caps per hour AND per day. A runaway loop could burn $100 in minutes.
4. **Dolt as metrics backend:** Dolt is great for versioned data but may not scale for high-frequency metrics. Use OTLP export to a dedicated metrics backend (Prometheus, InfluxDB) for production.

---

## References

- [OpenTelemetry Rust SDK](https://docs.rs/opentelemetry)
- [tracing-opentelemetry bridge](https://docs.rs/tracing-opentelemetry)
- [HTMX](https://htmx.org)
- [Perplexity Computer](https://venturebeat.com/technology/perplexity-launches-computer-ai-agent-that-coordinates-19-models-priced-at) — multi-model orchestration at scale
- ADR: Supervision Trees and Failure-as-Learning — TQM pattern detection feeds alerting
- ADR: TQM — Self-improvement patterns become alert rules
- ADR: Cost-Aware Model Routing — model performance metrics enable learned routing (Tier 3)
