defmodule Keiro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Keiro.Jido] ++ orchestrator_child()

    opts = [strategy: :one_for_one, name: Keiro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp orchestrator_child do
    case Application.get_env(:keiro, :orchestrator) do
      config when is_list(config) ->
        if Keyword.get(config, :repo_path) do
          [{Keiro.Orchestrator, config}]
        else
          []
        end

      _ ->
        []
    end
  end
end
