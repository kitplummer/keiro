defmodule Keiro.Config.Secrets do
  @moduledoc """
  Reads secrets from `~/.config/keiro/secrets.yaml`.

  Falls back to environment variables when the file is absent or a key is missing.

  ## File format

      # ~/.config/keiro/secrets.yaml
      anthropic_api_key: sk-ant-...
  """

  @secrets_path Path.expand("~/.config/keiro/secrets.yaml")

  @doc """
  Read a secret by key (atom). Checks the YAML file first, then the
  corresponding environment variable (uppercased key).

  ## Examples

      Keiro.Config.Secrets.get(:anthropic_api_key)
      # reads from file, or falls back to ANTHROPIC_API_KEY env var
  """
  @spec get(atom(), String.t() | nil) :: String.t() | nil
  def get(key, default \\ nil) do
    from_file(key) || from_env(key) || default
  end

  @doc "Returns the path to the secrets file."
  @spec path() :: String.t()
  def path, do: @secrets_path

  defp from_file(key) do
    case read_secrets() do
      {:ok, secrets} -> Map.get(secrets, Atom.to_string(key))
      _ -> nil
    end
  end

  defp from_env(key) do
    key
    |> Atom.to_string()
    |> String.upcase()
    |> System.get_env()
  end

  defp read_secrets do
    path = @secrets_path

    if File.exists?(path) do
      YamlElixir.read_from_file(path)
    else
      {:error, :not_found}
    end
  end
end
