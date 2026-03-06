import Config

config :keiro,
  beads_bd_path: System.get_env("BEADS_BD_PATH") || "bd",
  fly_bin_path: System.get_env("FLY_BIN_PATH") || "~/.fly/bin/fly"

import_config "#{config_env()}.exs"
