import Config

config :jido_ai,
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5-20251001",
    capable: "anthropic:claude-sonnet-4-20250514"
  }

# Env var overrides config/secrets.exs if set
if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :req_llm, :anthropic, api_key: api_key
end
