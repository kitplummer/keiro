defmodule Keiro.MixProject do
  use Mix.Project

  def project do
    [
      app: :keiro,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Keiro.Application, []}
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.0"},
      {:jido_ai, "2.0.0-rc.0"},
      {:req_llm, "~> 1.6"},
      {:jason, "~> 1.4"},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp aliases do
    []
  end
end
