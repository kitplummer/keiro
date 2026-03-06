import Config

config :keiro,
  beads_bd_path: System.get_env("BEADS_BD_PATH") || "bd",
  fly_bin_path: System.get_env("FLY_BIN_PATH") || "~/.fly/bin/fly",
  git_bin_path: System.get_env("GIT_BIN_PATH") || "git",
  gh_bin_path: System.get_env("GH_BIN_PATH") || "gh"

import_config "#{config_env()}.exs"
