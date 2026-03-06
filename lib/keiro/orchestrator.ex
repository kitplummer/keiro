defmodule Keiro.Orchestrator do
  @moduledoc """
  Minimal task router for Phase 0.

  Pulls ready beads from the task graph and routes them to the appropriate
  agent based on labels/type. For Phase 0, all ops beads go to UplinkAgent.

  ## Usage

      # Pull and route one bead
      {:ok, result} = Keiro.Orchestrator.run_next(repo_path: "/path/to/lei")

      # Process all ready beads
      results = Keiro.Orchestrator.run_all(repo_path: "/path/to/lei")
  """

  alias Keiro.Beads.Client, as: BeadsClient

  require Logger

  @doc """
  Pull the next ready bead and route it to the appropriate agent.

  Options:
  - `:repo_path` — path to the beads-enabled repo (required)
  - `:timeout` — agent timeout in ms (default: 60_000)
  """
  @spec run_next(keyword()) :: {:ok, map()} | {:error, String.t()} | :no_work
  def run_next(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    timeout = Keyword.get(opts, :timeout, 60_000)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, []} ->
        :no_work

      {:ok, [bead | _]} ->
        Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
        BeadsClient.update_status(client, bead.id, "in_progress")
        dispatch(bead, timeout)

      {:error, reason} ->
        {:error, "Failed to fetch ready beads: #{reason}"}
    end
  end

  @doc """
  Process all ready beads sequentially.
  """
  @spec run_all(keyword()) :: [map()]
  def run_all(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    client = BeadsClient.new(repo_path)

    case BeadsClient.ready(client) do
      {:ok, beads} ->
        Enum.map(beads, fn bead ->
          Logger.info("Orchestrator: routing bead #{bead.id} — #{bead.title}")
          BeadsClient.update_status(client, bead.id, "in_progress")
          result = dispatch(bead, Keyword.get(opts, :timeout, 60_000))
          %{bead_id: bead.id, title: bead.title, result: result}
        end)

      {:error, reason} ->
        Logger.error("Orchestrator: failed to fetch beads: #{reason}")
        []
    end
  end

  @doc """
  Route a bead to the appropriate agent based on labels.

  Phase 0: all beads with "ops" label go to UplinkAgent.
  """
  @spec route(Keiro.Beads.Bead.t()) :: {:ok, module()} | {:error, :no_matching_agent}
  def route(bead) do
    labels = bead.labels || []

    cond do
      "ops" in labels -> {:ok, Keiro.Ops.UplinkAgent}
      true -> {:error, :no_matching_agent}
    end
  end

  # -- private --

  defp dispatch(bead, timeout) do
    case route(bead) do
      {:ok, agent_module} ->
        prompt = "Bead #{bead.id}: #{bead.title}\n\n#{bead.description || "No description."}"

        case Jido.AgentServer.start(agent: agent_module) do
          {:ok, pid} ->
            result = agent_module.ask_sync(pid, prompt, timeout: timeout)
            GenServer.stop(pid, :normal)
            result

          {:error, reason} ->
            {:error, "Failed to start agent: #{inspect(reason)}"}
        end

      {:error, :no_matching_agent} ->
        Logger.warning(
          "Orchestrator: no agent for bead #{bead.id} (labels: #{inspect(bead.labels)})"
        )

        {:error, "no matching agent for labels: #{inspect(bead.labels)}"}
    end
  end
end
