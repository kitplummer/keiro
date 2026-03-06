defmodule Keiro.TQM.RestartIntensity do
  @moduledoc """
  Time-windowed failure counter inspired by OTP restart intensity.

  Tracks failures within a sliding window. When the count exceeds
  `max_failures`, signals that the system should halt to prevent
  budget burn on systemic issues.

  ## Usage

      tracker = RestartIntensity.new(max_failures: 5, window_ms: 300_000)
      {action, tracker} = RestartIntensity.record_failure(tracker)
      # action is :ok or :halt
  """

  @type t :: %__MODULE__{
          max_failures: pos_integer(),
          window_ms: pos_integer(),
          failures: [integer()]
        }

  defstruct max_failures: 5,
            window_ms: 300_000,
            failures: []

  @doc "Create a new tracker."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_failures: Keyword.get(opts, :max_failures, 5),
      window_ms: Keyword.get(opts, :window_ms, 300_000),
      failures: []
    }
  end

  @doc """
  Record a failure. Returns `{:ok, tracker}` if within limits,
  or `{:halt, tracker}` if restart intensity exceeded.
  """
  @spec record_failure(t()) :: {:ok | :halt, t()}
  def record_failure(%__MODULE__{} = tracker) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - tracker.window_ms

    failures =
      [now | tracker.failures]
      |> Enum.filter(fn ts -> ts > cutoff end)

    tracker = %{tracker | failures: failures}

    if length(failures) > tracker.max_failures do
      {:halt, tracker}
    else
      {:ok, tracker}
    end
  end

  @doc "Record a success. Doesn't clear failures but keeps the window sliding."
  @spec record_success(t()) :: t()
  def record_success(%__MODULE__{} = tracker) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - tracker.window_ms
    %{tracker | failures: Enum.filter(tracker.failures, fn ts -> ts > cutoff end)}
  end

  @doc "Current failure count within the window."
  @spec failure_count(t()) :: non_neg_integer()
  def failure_count(%__MODULE__{} = tracker) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - tracker.window_ms
    Enum.count(tracker.failures, fn ts -> ts > cutoff end)
  end
end
