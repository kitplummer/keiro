defmodule Keiro.Eng.Actions.ShellRun do
  @moduledoc """
  Jido Action: run shell commands.

  Read-only commands from the allowlist are auto-approved.
  All other commands require governance approval.
  """

  use Jido.Action,
    name: "shell_run",
    description: "Run a shell command in the repository directory",
    category: "Eng",
    tags: ["eng", "shell", "run"],
    vsn: "1.0.0",
    schema: [
      command: [type: :string, required: true, doc: "Command to run (e.g. \"mix test\")"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Governance.Approval

  @allowlist_prefixes [
    "mix test",
    "mix format --check",
    "mix compile --warnings-as-errors",
    "git status",
    "git diff",
    "git log"
  ]

  @impl Jido.Action
  def run(params, context) do
    command = params.command

    with :ok <- maybe_require_approval(command, context) do
      [program | args] = String.split(command)

      {output, exit_code} =
        System.cmd(program, args, cd: params.repo_path, stderr_to_stdout: true)

      {:ok, %{exit_code: exit_code, output: String.trim(output)}}
    end
  rescue
    e in ErlangError ->
      {:ok, %{exit_code: 127, output: "Command not found: #{inspect(e)}"}}
  end

  defp maybe_require_approval(command, context) do
    if allowlisted?(command) do
      :ok
    else
      case Approval.require("Shell: #{command}", context) do
        {:ok, :approved} -> :ok
        error -> error
      end
    end
  end

  defp allowlisted?(command) do
    Enum.any?(@allowlist_prefixes, &String.starts_with?(command, &1))
  end
end
