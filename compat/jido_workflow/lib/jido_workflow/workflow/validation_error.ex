defmodule JidoWorkflow.Workflow.ValidationError do
  @moduledoc """
  Minimal validation error shape returned by the compatibility loader.
  """

  @enforce_keys [:path, :code, :message]
  defstruct [:path, :code, :message]

  @type t :: %__MODULE__{
          path: [String.t()],
          code: atom(),
          message: String.t()
        }
end
