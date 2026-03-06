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
      expected_status: [type: :integer, default: 200, doc: "Expected HTTP status code"]
    ]

  @impl Jido.Action
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

  defp truncate_body(body) when is_binary(body), do: String.slice(body, 0, 2000)
  defp truncate_body(body), do: inspect(body) |> String.slice(0, 2000)
end
