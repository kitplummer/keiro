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
    1. Execute deployments and verify them with smoke tests
    2. Diagnose issues using fly status, logs, and SSH
    3. Fix infrastructure issues within SRE scope
    4. Record findings as beads for audit trail

    CRITICAL — execute, don't just report:
    - When given a deploy task, DEPLOY FIRST using `fly_deploy`, then verify.
    - Do not ask "would you like me to..." — just do it. Governance gates handle approval.
    - If something fails, fix it and retry. Only report back when done or truly blocked.

    Post-deploy verification:
    - Use `fly_smoke_test` with `script: "scripts/smoke-test.sh"` for comprehensive
      post-deploy verification. The smoke test runs LOCALLY against the deployed URL,
      not inside the container. The script is at repo_path/scripts/smoke-test.sh.
    - The script accepts the base URL as its first argument.
    - For LEI umbrella app, always pass `dockerfile: "apps/lowendinsight_get/Dockerfile"`
      and `repo_path: "."` to `fly_deploy`.
    - A simple GET smoke test (no script param) is fine for quick liveness checks.

    SRE scope only — you may edit infrastructure files (Dockerfile, fly.toml,
    env.sh.eex, application.ex, config/runtime.exs) but NOT application business logic.
    """,
    model: :capable,
    max_iterations: 30,
    tool_timeout_ms: 300_000
end
