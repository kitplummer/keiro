defmodule Keiro.Tools.Registry do
  @moduledoc """
  Registry for agent tools.

  Allows orgs to register domain-specific tools that agents can
  discover at runtime, rather than hardcoding tools in agent modules.

  Tools are grouped by domain (e.g., "eng", "ops", "beads") and can
  be queried by domain, tag, or capability.

  ## Usage

      registry = Keiro.Tools.Registry.new()
      |> Keiro.Tools.Registry.register("eng", Keiro.Eng.Actions.FileRead,
           tags: ["filesystem", "read"], description: "Read file contents")
      |> Keiro.Tools.Registry.register("eng", Keiro.Eng.Actions.FileWrite,
           tags: ["filesystem", "write"], description: "Write file contents")

      tools = Keiro.Tools.Registry.for_domain(registry, "eng")
      tools = Keiro.Tools.Registry.for_tags(registry, ["filesystem"])
  """

  alias Keiro.Tools.ToolEntry

  @type t :: %__MODULE__{
          entries: [ToolEntry.t()]
        }

  defstruct entries: []

  @doc "Create an empty registry."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Create a registry pre-loaded with the default Keiro tools."
  @spec defaults() :: t()
  def defaults do
    new()
    |> register("eng", Keiro.Eng.Actions.FileRead, tags: ["filesystem", "read"])
    |> register("eng", Keiro.Eng.Actions.FileWrite, tags: ["filesystem", "write"])
    |> register("eng", Keiro.Eng.Actions.ShellRun, tags: ["shell", "exec"])
    |> register("eng", Keiro.Eng.Actions.GitBranch, tags: ["git", "branch"])
    |> register("eng", Keiro.Eng.Actions.GitCommit, tags: ["git", "commit"])
    |> register("eng", Keiro.Eng.Actions.GitPush, tags: ["git", "push"])
    |> register("eng", Keiro.Eng.Actions.GhCreatePr, tags: ["github", "pr"])
    |> register("ops", Keiro.Ops.Actions.FlyStatus, tags: ["fly", "status"])
    |> register("ops", Keiro.Ops.Actions.FlyLogs, tags: ["fly", "logs"])
    |> register("ops", Keiro.Ops.Actions.FlySSH, tags: ["fly", "ssh"])
    |> register("ops", Keiro.Ops.Actions.FlySmokeTest, tags: ["fly", "test"])
    |> register("ops", Keiro.Ops.Actions.FileEdit, tags: ["filesystem", "write"])
    |> register("beads", Keiro.Beads.Actions.Create, tags: ["beads", "create"])
    |> register("beads", Keiro.Beads.Actions.Update, tags: ["beads", "update"])
    |> register("beads", Keiro.Beads.Actions.List, tags: ["beads", "read"])
    |> register("beads", Keiro.Beads.Actions.Ready, tags: ["beads", "read"])
  end

  @doc "Register a tool module under a domain."
  @spec register(t(), String.t(), module(), keyword()) :: t()
  def register(%__MODULE__{} = registry, domain, module, opts \\ []) do
    entry = %ToolEntry{
      domain: domain,
      module: module,
      tags: Keyword.get(opts, :tags, []),
      description: Keyword.get(opts, :description)
    }

    %{registry | entries: registry.entries ++ [entry]}
  end

  @doc "Get all tool modules for a domain."
  @spec for_domain(t(), String.t()) :: [module()]
  def for_domain(%__MODULE__{entries: entries}, domain) do
    entries
    |> Enum.filter(fn e -> e.domain == domain end)
    |> Enum.map(fn e -> e.module end)
  end

  @doc "Get all tool modules matching any of the given tags."
  @spec for_tags(t(), [String.t()]) :: [module()]
  def for_tags(%__MODULE__{entries: entries}, tags) do
    tag_set = MapSet.new(tags)

    entries
    |> Enum.filter(fn e ->
      e.tags |> MapSet.new() |> MapSet.intersection(tag_set) |> MapSet.size() > 0
    end)
    |> Enum.map(fn e -> e.module end)
  end

  @doc "Get all tool entries (full metadata)."
  @spec all(t()) :: [ToolEntry.t()]
  def all(%__MODULE__{entries: entries}), do: entries

  @doc "List all registered domains."
  @spec domains(t()) :: [String.t()]
  def domains(%__MODULE__{entries: entries}) do
    entries |> Enum.map(fn e -> e.domain end) |> Enum.uniq()
  end

  @doc "Count of registered tools."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{entries: entries}), do: length(entries)
end
