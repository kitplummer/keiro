defmodule Keiro.Ops.Shape do
  @moduledoc """
  Pipeline shape for operations beads.

  Matches beads with the "ops" label and returns a single-stage pipeline
  using UplinkAgent.
  """

  @behaviour Keiro.Pipeline.Shape

  alias Keiro.Pipeline.Stage

  @impl true
  def match?(bead) do
    "ops" in (bead.labels || [])
  end

  @impl true
  def stages(_bead, opts) do
    timeout = Keyword.get(opts, :timeout, 120_000)

    [
      %Stage{
        name: "ops",
        agent_module: Keiro.Ops.UplinkAgent,
        prompt_fn: &ops_prompt/2,
        timeout: timeout
      }
    ]
  end

  defp ops_prompt(bead, _prev_stages) do
    """
    Bead #{bead.id}: #{bead.title}

    #{bead.description || "No description."}

    After completing ops work, run a smoke test against https://lowendinsight.dev
    to verify the deployment is healthy (expected: HTTP 200).

    The fly.io app name is "lowendinsight". Use fly_status to check app state,
    fly_logs for recent logs, and fly_smoke_test with url "https://lowendinsight.dev"
    to verify.
    """
  end
end
