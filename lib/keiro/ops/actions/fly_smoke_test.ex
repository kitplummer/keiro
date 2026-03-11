defmodule Keiro.Ops.Actions.FlySmokeTest do
  @moduledoc "Jido Action: HTTP smoke test against a deployed endpoint."

  use Jido.Action,
    name: "fly_smoke_test",
    description: "Run an HTTP smoke test against a URL to verify deployment health",
    category: "Ops",
    tags: ["fly", "smoke-test", "ops", "health"],
    vsn: "1.0.0",
    schema: [
      url: [type: :string, required: true, doc: "URL to test"],
      expected_status: [type: :integer, default: 200, doc: "Expected HTTP status code"],
      script: [type: :string, doc: "Path to smoke test script (overrides simple GET)"],
      repo_path: [type: :string, doc: "Repo path for script resolution"]
    ]

  @impl Jido.Action
  def run(%{script: script} = params, context) when is_binary(script) do
    repo_path = params[:repo_path] || Map.get(context, :repo_path)
    script_path = resolve_script(script, repo_path)

    if File.exists?(script_path) do
      case System.cmd("bash", [script_path, params.url], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, %{healthy: true, output: truncate_body(output)}}

        {output, code} ->
          {:ok, %{healthy: false, exit_code: code, output: truncate_body(output)}}
      end
    else
      {:ok, %{healthy: false, error: "script not found: #{script_path}"}}
    end
  end

  def run(params, _context) do
    expected = Map.get(params, :expected_status, 200)

    case Req.get(params.url, receive_timeout: 10_000, retry: false) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok,
         %{
           healthy: status == expected,
           status_code: status,
           body: truncate_body(body)
         }}

      {:error, reason} ->
        {:ok, %{healthy: false, status_code: nil, error: inspect(reason)}}
    end
  end

  defp resolve_script(script, nil), do: script
  defp resolve_script(script, repo_path), do: Path.join(repo_path, script)

  defp truncate_body(body) when is_binary(body), do: String.slice(body, 0, 2000)
  defp truncate_body(body), do: inspect(body) |> String.slice(0, 2000)
end
