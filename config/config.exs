import Config

config :keiro,
  beads_bd_path: System.get_env("BEADS_BD_PATH") || "bd",
  fly_bin_path: System.get_env("FLY_BIN_PATH") || "~/.fly/bin/fly",
  git_bin_path: System.get_env("GIT_BIN_PATH") || "git",
  gh_bin_path: System.get_env("GH_BIN_PATH") || "gh"

config :keiro, :orchestrator,
  repo_path: System.get_env("KEIRO_REPO_PATH"),
  poll_interval: String.to_integer(System.get_env("KEIRO_POLL_INTERVAL") || "30000")

config :keiro, :lei,
  smoke_test_url: System.get_env("LEI_SMOKE_TEST_URL") || "https://lowendinsight.fly.dev",
  fly_app: System.get_env("LEI_FLY_APP") || "lowendinsight"

import_config "#{config_env()}.exs"

if File.exists?(Path.expand("secrets.exs", __DIR__)) do
  import_config "secrets.exs"
end
