defmodule Keiro.Eng.EngineerAgent do
  @moduledoc """
  Software engineer agent — implements, tests, and creates PRs.

  Uses Jido.AI.Agent with ReAct strategy to pick up engineering beads,
  write code, run tests, and open pull requests. All mutating actions
  require human approval via the governance gate.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: Keiro.Eng.EngineerAgent)
      {:ok, result} = Keiro.Eng.EngineerAgent.ask_sync(pid,
        "Bead gl-042: Add greeting function to lib/greeting.ex",
        timeout: 120_000)
  """

  use Jido.AI.Agent,
    name: "engineer",
    description: "Software engineer agent — implements, tests, and creates PRs",
    tags: ["eng", "code", "pr", "implementation"],
    tools: [
      Keiro.Eng.Actions.FileRead,
      Keiro.Eng.Actions.FileWrite,
      Keiro.Eng.Actions.ShellRun,
      Keiro.Eng.Actions.GitBranch,
      Keiro.Eng.Actions.GitCommit,
      Keiro.Eng.Actions.GitPush,
      Keiro.Eng.Actions.GhCreatePr,
      Keiro.Beads.Actions.Update
    ],
    system_prompt: """
    You are Engineer, the software development agent for the Keiro CAO.

    Your workflow for each bead:
    1. Read the bead to understand requirements
    2. Create branch eng/<bead-id>-<short-description>
    3. Read existing code to understand patterns and conventions
    4. Implement incrementally — run `mix test` after each change
    5. Fix any test failures before proceeding
    6. Run `mix format` to ensure code is formatted
    7. Run `mix compile --warnings-as-errors` to check for warnings
    8. Stage all changed files, commit with a descriptive message
    9. Push the branch and create a pull request
    10. Update the bead status

    Rules:
    - Never commit failing tests or compiler warnings
    - Follow existing code conventions in the repository
    - Write tests for all new functionality
    - Keep commits atomic and well-described
    - If tests fail, diagnose and fix before moving on
    """,
    model: :capable,
    max_iterations: 50,
    tool_timeout_ms: 120_000
end
