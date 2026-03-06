# ADR: Dev-Mode External Repository Operation

**Date:** 2026-03-02
**Authors:** Keiro (Patch), Kit
**Status:** Active
**Related:** [Discovered Seams](adr/agentic-corporation-framework-seams.md) (Seam 3: Workspace isolation)

---

## Context

Keiro is developed in its own repository (`~/Code/glitchlab`) but operates against *other* repositories. During active development of Keiro itself, we need a workflow that lets us iterate on the engine while running it against real target repos.

The first two target repositories are:

- **lowendinsight** — An Elixir library (`~/Code/lowendinsight`) that performs bus-factor and contributor analysis on Git repositories. v0.9.1, ~90% test coverage, Mix project with `mix test` as the quality gate.
- **lowendinsight-get** — An Elixir REST API (`~/Code/lowendinsight-get`) that wraps lowendinsight as an HTTP service. v0.9.3, Mix/Phoenix project with Redis and PostgreSQL dependencies. Quality gate: `mix test`.

Both are mature Elixir projects with no prior Keiro integration. Neither has a `.glitchlab/` directory or `.beads/` store.

---

## Decision

Use a **sibling-directory dev-mode** workflow: the Keiro source repository and all target repositories live as siblings under a common parent directory. The Keiro binary is built from source and invoked via `cargo run --` pointing at the sibling target.

### Why not just install the binary?

During active development, we rebuild Keiro frequently. Running `cargo run -- batch --repo ../lowendinsight` uses the latest source without a separate install step. Once Keiro stabilizes, we will publish a binary and the `--repo` flag will work from any location.

---

## Workflow

### Directory layout

```
~/Code/
  glitchlab/              # engine source (this repo)
  lowendinsight/          # target repo 1
  lowendinsight-get/      # target repo 2
```

### One-time setup per target repo

```bash
# From the glitchlab source directory:
cargo run -- init ../lowendinsight
cargo run -- init ../lowendinsight-get
```

This creates in each target repo:

```
.glitchlab/
  config.yaml         # project-specific overrides (committed)
  .gitignore           # excludes worktrees/ and logs/
  tasks/               # task YAML files
  worktrees/           # ephemeral worktrees (gitignored)
  logs/                # run logs (gitignored)
```

The target repo's `.glitchlab/config.yaml` should be committed to the target repo's git history. It contains project-specific configuration: routing preferences, boundaries (protected paths), limits, and Elixir-specific overrides.

### Running batch tasks

```bash
# From glitchlab source dir
cd ~/Code/glitchlab

# Against lowendinsight
cargo run -- batch --repo ../lowendinsight --budget 5.0 \
  --quality-gate "mix test" --auto-approve

# Against lowendinsight-get
cargo run -- batch --repo ../lowendinsight-get --budget 5.0 \
  --quality-gate "mix test" --auto-approve
```

### Running single tasks

```bash
cargo run -- run --repo ../lowendinsight --objective "Add typespecs to lib/lowendinsight.ex"
```

### Checking status

```bash
cargo run -- status --repo ../lowendinsight
cargo run -- status --repo ../lowendinsight-get
```

---

## What lives where

| Artifact | Location | Committed? |
|----------|----------|------------|
| Keiro engine source | `glitchlab/` | Yes (glitchlab repo) |
| Target project config | `TARGET/.glitchlab/config.yaml` | Yes (target repo) |
| Target task definitions | `TARGET/.glitchlab/tasks/` | Yes (target repo) |
| Beads (task graph) | `TARGET/.beads/` | Yes (target repo) |
| Ephemeral worktrees | `TARGET/.glitchlab/worktrees/` | No (gitignored) |
| Run logs | `TARGET/.glitchlab/logs/` | No (gitignored) |
| Run history (JSONL) | `TARGET/.glitchlab/history/` | Optional |

Nothing crosses between repositories. Keiro reads config from the target, creates beads in the target, and manages worktrees inside the target. The engine source is never modified by a batch run against an external target.

---

## Elixir-specific considerations

### Test command detection

Keiro's `detect_test_command()` already recognizes `mix.exs` and returns `mix test`. No configuration needed — it works out of the box for both repos.

### Recommended config overrides for Elixir targets

```yaml
# .glitchlab/config.yaml for an Elixir project

boundaries:
  protected_paths:
    - "mix.lock"           # don't modify lockfile
    - ".formatter.exs"     # don't modify formatter config

limits:
  max_tool_turns: 12
  max_dollars_per_task: 2.00
```

### lowendinsight specifics

- Pure library with no external service dependencies at test time
- Quality gate: `mix test` (runs ~50 tests)
- Has a `config/` directory with runtime configuration — protect it from modification
- Schema files in `schema/` define JSON output format — useful context for agents

### lowendinsight-get specifics

- REST API with Redis and PostgreSQL dependencies
- Quality gate: `mix test` (requires running database, or mock setup)
- Docker Compose available (`docker-compose.yml`) for standing up test dependencies
- Consider `docker compose up -d && mix test` as the quality gate, or ensure services are running before batch
- Has a `dump.rdb` (Redis dump) — add to `protected_paths`

---

## Relationship to Seam 3

The [Discovered Seams ADR](adr/agentic-corporation-framework-seams.md) identifies Seam 3: the Orchestrator couples Git worktree isolation to the execution model. For dev-mode operation against external repos, this coupling works well — both target repos are Git repositories, and worktree-per-task isolation is the correct model.

When Keiro gains a `WorkspaceProvider` trait (Phase 6 extraction), the external repo workflow will not change. The `--repo` flag already cleanly separates "where is the engine" from "where is the target." The workspace provider will simply formalize what the Orchestrator already does.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Worktree leakage to target's main branch | High | Always run from a feature branch in the target, or ensure worktree cleanup runs on interrupts |
| Elixir dependency compilation cost | Medium | First run compiles all deps; subsequent runs use cache. Budget accordingly. |
| lowendinsight-get needs running services | Medium | Document service startup in target config; use `--quality-gate "docker compose up -d && mix test"` |
| Keiro source changes break mid-run | Low | Dev-mode only; rebuild between runs, not during |
| Beads store conflicts on target repo | Low | `.beads/` is append-only JSONL; merge conflicts are rare and trivially resolved |

---

## Near-term: Multi-repo batch

Working on lowendinsight-get will drive the creation of new agent types (SRE/Ops org) because it is a deployed service with infrastructure concerns (Redis, PostgreSQL, Docker). This means Keiro development and target-repo work are coupled: changes to the engine (new agents, new pipeline shapes) are motivated by what we discover running against the targets.

A multi-repo batch mode is required to support this workflow — a single invocation that:

1. Runs self-maintenance tasks on `glitchlab/` (TQM, backlog review, internal beads)
2. Then runs target-repo tasks on `lowendinsight/` and/or `lowendinsight-get/`
3. Shares a single budget across all repos in the run

This is not a convenience feature — it is the mechanism by which running against real targets feeds discoveries back into the engine as beads.

```bash
# Desired interface (not yet implemented)
glitchlab batch --repos glitchlab,../lowendinsight,../lowendinsight-get --budget 10.0
```

### SRE org connection

lowendinsight-get's operational concerns (service health, deployment, scaling, incident response) will be the forcing function for the SRE/Ops org described in the [Delivery and SRE Ops ADR](adr-delivery-and-sre-ops-org.md). The seams discovered working lei-get will directly inform which kernel traits need extraction (see [Discovered Seams](adr/agentic-corporation-framework-seams.md)).

---

## Other future work

- **`glitchlab init` enhancements**: Auto-detect language and suggest config overrides (Elixir: protect mix.lock, suggest mix test gate)
- **Installed binary mode**: Once stable, `cargo install glitchlab` and drop the sibling-directory requirement
