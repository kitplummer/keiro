defmodule Keiro.Failure.ObstacleKind do
  @moduledoc """
  Structured failure reasons for task execution.

  Each obstacle kind carries specific metadata to enable pattern detection
  and inform retry strategies.
  """

  @type t ::
          {:missing_prerequisite, task_id: String.t(), reason: String.t()}
          | {:architectural_gap, description: String.t()}
          | {:model_limitation, model: String.t(), error_class: String.t()}
          | {:external_dependency, service: String.t()}
          | {:scope_too_large, estimated_files: non_neg_integer(), max_files: non_neg_integer()}
          | {:unknown, reason: String.t()}

  @doc "Create a missing_prerequisite obstacle."
  @spec missing_prerequisite(String.t(), String.t()) :: t()
  def missing_prerequisite(task_id, reason) do
    {:missing_prerequisite, task_id: task_id, reason: reason}
  end

  @doc "Create an architectural_gap obstacle."
  @spec architectural_gap(String.t()) :: t()
  def architectural_gap(description) do
    {:architectural_gap, description: description}
  end

  @doc "Create a model_limitation obstacle."
  @spec model_limitation(String.t(), String.t()) :: t()
  def model_limitation(model, error_class) do
    {:model_limitation, model: model, error_class: error_class}
  end

  @doc "Create an external_dependency obstacle."
  @spec external_dependency(String.t()) :: t()
  def external_dependency(service) do
    {:external_dependency, service: service}
  end

  @doc "Create a scope_too_large obstacle."
  @spec scope_too_large(non_neg_integer(), non_neg_integer()) :: t()
  def scope_too_large(estimated_files, max_files) do
    {:scope_too_large, estimated_files: estimated_files, max_files: max_files}
  end

  @doc "Create an unknown obstacle."
  @spec unknown(String.t()) :: t()
  def unknown(reason) do
    {:unknown, reason: reason}
  end

  @doc "Extract the kind atom from an obstacle."
  @spec kind(t()) :: atom()
  def kind({kind, _opts}), do: kind
end
