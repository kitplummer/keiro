# ADR: Layered Security Review — Code Scanning + Strategic Risk Analysis

**Date:** 2026-02-27
**Authors:** Kit, with Claude analysis
**Status:** Implemented
**Informed by:** Keiro canary batch runs, OWASP risk assessment methodology, NIST SP 800-30 risk framework

---

## Context

Keiro's engineering pipeline has always included a security review stage. The Security agent (Firewall Frankie) scans diffs for code-level vulnerabilities: SQL injection, XSS, hardcoded secrets, insecure deserialization, and other OWASP Top 10 patterns. This works well for catching tactical mistakes in individual files.

But code-level scanning has a blind spot: **it cannot assess aggregate risk.** A change that passes every line-level check can still be dangerous if it:

- Crosses a trust boundary (e.g., user input now flows into a privileged operation)
- Has a wide blast radius (e.g., modifying a core trait that 15 downstream consumers depend on)
- Introduces operational risk (e.g., a schema migration with no rollback path)
- Triggers compliance implications (e.g., changing how PII is stored or transmitted)
- Compounds with other recent changes to create systemic exposure

These are **strategic risk** concerns — they require understanding the change in context, not just scanning for vulnerability patterns. In a human organization, this is the difference between a security engineer reviewing a PR and a CISO reviewing a release. Both are necessary. They operate at different abstraction levels.

The first three canary batch runs confirmed this gap. Tasks that touched `crates/kernel` (governance, budget, pipeline traits) passed security scanning cleanly but represented high-risk changes to trust boundaries. The pipeline had no mechanism to flag them for elevated review beyond the existing protected-path boundary check (which blocks changes entirely rather than gating them through risk assessment).

---

## Decision

### Split security review into two complementary stages

The pipeline now runs two sequential agents in the review phase:

| Stage | Agent | Persona | Scope | Default Model |
|-------|-------|---------|-------|---------------|
| **10a. Security Scan** | SecurityAgent | Firewall Frankie | Code-level vulnerability detection | gemini-2.5-flash |
| **10b. CISO Risk Analysis** | CisoAgent | Sentinel | Strategic risk assessment | gemini-2.5-flash |

The CISO stage runs immediately after security scanning and receives the security agent's findings as input, along with the diff, the original plan, and the implementation summary. This allows Sentinel to incorporate Frankie's code-level findings into the aggregate risk picture.

### Separation of concerns

| Concern | Security Agent (Frankie) | CISO Agent (Sentinel) |
|---------|------------------------|----------------------|
| **Abstraction level** | Line/function level | System/organizational level |
| **Question answered** | "Does this code have vulnerabilities?" | "Does this change create unacceptable risk?" |
| **Input** | Diff only | Diff + plan + implementation summary + security findings |
| **Output** | pass / warn / block + issue list | accept / conditional / escalate + risk score + blast radius |
| **Failure mode** | False negatives (missed vulnerability) | False positives (over-cautious escalation) |
| **Tuning** | Pattern-based (add new vulnerability patterns) | Threshold-based (adjust risk score thresholds) |

### CISO output schema

The CISO agent produces structured JSON covering five risk dimensions:

```json
{
  "risk_verdict": "accept|conditional|escalate",
  "risk_score": 1-10,
  "blast_radius": "isolated|module|cross-module|system-wide",
  "trust_boundary_crossings": [
    {
      "from": "source zone",
      "to": "destination zone",
      "data_type": "what crosses",
      "concern": "why this matters"
    }
  ],
  "data_flow_concerns": ["..."],
  "compliance_flags": ["..."],
  "operational_risk": {
    "rollback_complexity": "trivial|moderate|complex",
    "monitoring_gaps": ["..."],
    "failure_modes": ["..."]
  },
  "aggregate_assessment": "1-2 sentence summary",
  "conditions": ["conditions for conditional verdict"],
  "escalation_reason": "reason for escalate verdict"
}
```

### Pipeline behavior by verdict

| Verdict | Pipeline Action | When Used |
|---------|----------------|-----------|
| **accept** | Continue to release assessment | Risk is manageable, no special conditions |
| **conditional** | Continue, but conditions are recorded in PR description | Risk exists but is bounded; conditions flag follow-up work |
| **escalate** | Pipeline halts with `PipelineStatus::Escalated` | Human security review required before proceeding |

### Escalation rules

- If the security agent blocks (`verdict: "block"`), the CISO **must** escalate. This is enforced in the CISO system prompt.
- The CISO may escalate independently for strategic risk reasons even when the security scan passes.
- Escalation produces a structured `PipelineStatus::Escalated` outcome that surfaces to the orchestrator and TQM, not a generic failure.

### Risk score guide

| Score | Meaning | Typical Changes |
|-------|---------|-----------------|
| 1-2 | Cosmetic or documentation, no behavioral impact | README edits, comment updates |
| 3-4 | Low-risk functional changes within well-tested boundaries | Bug fixes in leaf modules |
| 5-6 | Moderate risk — new functionality, moderate blast radius | New agent, new pipeline stage |
| 7-8 | High risk — cross-module changes, trust boundary crossings | Governance changes, router modifications |
| 9-10 | Critical — governance infrastructure, security mechanisms, data handling | Kernel trait changes, boundary enforcement |

### Graceful degradation

If the CISO agent fails (LLM error, timeout, parse failure), the pipeline does **not** block. It falls back to `risk_verdict: "accept"` with a logged warning. The security scan (Frankie) is the hard gate; the CISO is an advisory layer. This prevents a flaky CISO model from blocking the entire pipeline while preserving the code-level security guarantee.

### Short-circuit bypass

For short-circuit-eligible tasks (trivial complexity, ≤2 files, ≤3 steps, sub-tasks), both the security scan and CISO review are skipped. These tasks are structurally low-risk and the overhead of two LLM calls is not justified. The boundary check (protected paths) still runs for all tasks regardless of short-circuit status.

---

## Consequences

### Positive

- **Strategic risk is now visible.** Changes that are technically clean but strategically dangerous (trust boundary crossings, wide blast radius, compliance implications) are flagged before merge.
- **Escalation is structured.** High-risk changes produce `PipelineStatus::Escalated` rather than silently passing or producing a generic failure. The human reviewer gets the CISO's risk assessment, not just a "something went wrong" message.
- **Security findings compound.** The CISO receives the security agent's findings and can assess aggregate risk — a "warn" from Frankie plus a cross-module blast radius from Sentinel might warrant escalation even though neither alone would.
- **The review phase scales.** Adding the CISO agent required no changes to the pipeline architecture — it's another stage in the linear sequence. Future review agents (compliance, performance) follow the same pattern.

### Negative

- **Additional LLM cost per task.** The CISO call adds ~2K-4K tokens per non-short-circuit task. At flash-tier pricing this is $0.001-0.002 — negligible relative to implementation cost.
- **Potential for over-escalation.** The CISO agent may be conservative, especially on tasks touching core infrastructure. Mitigated by: tunable risk score thresholds, the conditional verdict (proceed with conditions vs. hard block), and the ability to configure the CISO model independently.
- **Two agents for security creates coordination questions.** If the security agent says "pass" but the CISO says "escalate," which is the source of truth? Answer: the CISO incorporates Frankie's findings — it's a strictly higher-level assessment, not a conflicting one.

### Trade-offs

- **Hard gate (security) vs. advisory gate (CISO).** The security agent's "block" verdict halts the pipeline unconditionally. The CISO's "escalate" verdict also halts but through a different status code. The CISO's failure mode is graceful degradation (accept), while the security agent's failure mode is also graceful degradation (pass with `parse_error: true`). Both err on the side of allowing progress when the agent itself fails, while erring on the side of caution when the agent succeeds and detects risk.

---

## Relationship to Existing ADRs

| ADR | Relationship |
|-----|-------------|
| **Supervision and Failure-as-Learning** | CISO escalation is a new supervision signal. `PipelineStatus::Escalated` routes through the same outcome taxonomy (Section 2 of that ADR). |
| **Agentic Corporation Framework** | The CISO role maps to the Security/Compliance org in the business lifecycle staging (Scale phase). In the current single-org model, Sentinel operates within the engineering pipeline. In the multi-org future, it may become part of a dedicated security org. |
| **TQM Self-Improvement** | High CISO escalation rates become a TQM-detectable pattern. If Sentinel escalates >30% of tasks, the Circuit agent should investigate whether the risk thresholds need tuning or whether the codebase genuinely has systemic risk issues. |
| **Context Evaluation Lifecycle** | The CISO agent's risk assessment quality should be covered by context scenarios — frozen diffs with known risk profiles to verify Sentinel's scoring remains calibrated. |

---

## Implementation Notes

- **File:** `crates/eng-org/src/agents/ciso.rs`
- **Pipeline stage:** 10b (between security scan and release assessment)
- **Config field:** `routing.ciso` in `.glitchlab/config.yaml`
- **Event kind:** `EventKind::CisoReview` in kernel
- **Stage output key:** `"ciso"` in `PipelineContext.stage_outputs`
- **Default model:** `anthropic/claude-haiku-4-5-20251001` (configurable to flash-tier models for production)

---

*This ADR should be revisited after 100+ tasks have run through the CISO stage, to assess escalation rates, false positive rates, and whether the risk score distribution matches expectations.*
