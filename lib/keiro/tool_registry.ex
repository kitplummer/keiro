defmodule Keiro.ToolRegistry do
  @moduledoc """
  Registry for domain-specific agent tools.

  Agents declare tools in their module definition, but orgs may need
  to register additional domain-specific tools at runtime. The
  ToolRegistry provides a central place to register and discover tools
  by category, tag, or agent.

  ## Usage

      # Start the registry
      {:ok, _pid} = Keiro.ToolRegistry.start_link()

      # Register tools
      Keiro.ToolRegistry.register(:eng, Keiro.Eng.Actions.FileRead)
      Keiro.ToolRegistry.register(:ops, Keiro.Ops.Actions.FlyStatus)

      # Look up tools
      Keiro.ToolRegistry.tools(:eng)
      # => [Keiro.Eng.Actions.FileRead]

      Keiro.ToolRegistry.all()
      # => [Keiro.Eng.Actions.FileRead, Keiro.Ops.Actions.FlyStatus]
  """

  use GenServer

  @type category :: atom()

  # -- Public API --

  @doc "Start the tool registry."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Register a tool module under a category."
  @spec register(category(), module(), GenServer.server()) :: :ok
  def register(category, tool_module, server \\ __MODULE__) do
    GenServer.call(server, {:register, category, tool_module})
  end

  @doc "Register multiple tool modules under a category."
  @spec register_all(category(), [module()], GenServer.server()) :: :ok
  def register_all(category, tool_modules, server \\ __MODULE__) do
    GenServer.call(server, {:register_all, category, tool_modules})
  end

  @doc "Get all tools for a category."
  @spec tools(category(), GenServer.server()) :: [module()]
  def tools(category, server \\ __MODULE__) do
    GenServer.call(server, {:tools, category})
  end

  @doc "Get all registered tools across all categories."
  @spec all(GenServer.server()) :: [module()]
  def all(server \\ __MODULE__) do
    GenServer.call(server, :all)
  end

  @doc "Get all registered categories."
  @spec categories(GenServer.server()) :: [category()]
  def categories(server \\ __MODULE__) do
    GenServer.call(server, :categories)
  end

  @doc "Unregister a tool module from a category."
  @spec unregister(category(), module(), GenServer.server()) :: :ok
  def unregister(category, tool_module, server \\ __MODULE__) do
    GenServer.call(server, {:unregister, category, tool_module})
  end

  # -- GenServer callbacks --

  @impl GenServer
  def init(opts) do
    initial = Keyword.get(opts, :tools, %{})
    {:ok, initial}
  end

  @impl GenServer
  def handle_call({:register, category, tool_module}, _from, state) do
    existing = Map.get(state, category, [])

    state =
      if tool_module in existing do
        state
      else
        Map.put(state, category, existing ++ [tool_module])
      end

    {:reply, :ok, state}
  end

  def handle_call({:register_all, category, tool_modules}, _from, state) do
    existing = Map.get(state, category, [])
    new_tools = Enum.reject(tool_modules, &(&1 in existing))
    {:reply, :ok, Map.put(state, category, existing ++ new_tools)}
  end

  def handle_call({:tools, category}, _from, state) do
    {:reply, Map.get(state, category, []), state}
  end

  def handle_call(:all, _from, state) do
    all_tools = state |> Map.values() |> List.flatten() |> Enum.uniq()
    {:reply, all_tools, state}
  end

  def handle_call(:categories, _from, state) do
    {:reply, Map.keys(state), state}
  end

  def handle_call({:unregister, category, tool_module}, _from, state) do
    existing = Map.get(state, category, [])
    {:reply, :ok, Map.put(state, category, List.delete(existing, tool_module))}
  end
end
