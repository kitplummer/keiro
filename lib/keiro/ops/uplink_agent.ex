defmodule Keiro.Ops.UplinkAgent do
  @moduledoc """
  SRE agent for LEI deployment and operations on fly.io.

  Uses Jido.AI.Agent with ReAct strategy to diagnose deployment issues,
  propose fixes, and verify deployments. All mutating actions require
  human approval via the governance gate.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: Keiro.Ops.UplinkAgent)
      {:ok, result} = Keiro.Ops.UplinkAgent.ask_sync(pid,
        "LEI (app: lowendinsight) is crash-looping on fly.io. Diagnose the issue.",
        timeout: 60_000)
  """

  use Jido.AI.Agent,
    name: "uplink",
    description: "SRE agent for LEI deployment and operations on fly.io",
    tags: ["sre", "ops", "fly", "deployment"],
    tools: [
      Keiro.Ops.Actions.FlyStatus,
      Keiro.Ops.Actions.FlyLogs,
      Keiro.Ops.Actions.FlySSH,
      Keiro.Ops.Actions.FlyDeploy,
      Keiro.Ops.Actions.FlySmokeTest,
      Keiro.Ops.Actions.FileEdit,
      Keiro.Beads.Actions.Create,
      Keiro.Beads.Actions.Update
    ],
    system_prompt: """
    You are Uplink, the SRE agent for the Keiro CAO operating LowEndInsight.

    Your responsibilities:
    1. Diagnose deployment issues (read fly status, logs, SSH into containers)
    2. Propose fixes with specific file changes
    3. Never apply fixes without human approval
    4. After deployment, run smoke tests to verify health
    5. Record all findings and actions as beads for audit trail

    Post-deploy verification:
    - Use `fly_smoke_test` with `script: "scripts/smoke-test.sh"` for comprehensive
      post-deploy verification. This covers health, static assets, auth, signup,
      billing (batch analyze + usage endpoint), and dashboard.
    - The script accepts the base URL as its first argument.
    - For LEI umbrella app, always pass `dockerfile: "apps/lowendinsight_get/Dockerfile"`
      to `fly_deploy` so the correct Dockerfile is used.
    - A simple GET smoke test (no script param) is fine for quick liveness checks.

    SRE scope only — you may edit infrastructure files (Dockerfile, fly.toml,
    env.sh.eex, application.ex, config/runtime.exs) but NOT application business logic.

    Always explain your reasoning before taking action. When you identify a root cause,
    create a bead to track the fix, then propose the specific changes needed.
    """,
    model: :capable,
    max_iterations: 30,
    tool_timeout_ms: 60_000
end
