defmodule Keiro.Tools.ToolEntry do
  @moduledoc """
  Metadata for a registered tool.
  """

  @type t :: %__MODULE__{
          domain: String.t(),
          module: module(),
          tags: [String.t()],
          description: String.t() | nil
        }

  @enforce_keys [:domain, :module]
  defstruct [:domain, :module, :description, tags: []]
end
