defmodule JidoWorkflow.Workflow.Definition.Input do
  @moduledoc """
  Workflow input declaration.
  """

  @enforce_keys [:name, :type]
  defstruct [:name, :type, :required, :default, :description]

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t(),
          required: boolean(),
          default: term(),
          description: String.t() | nil
        }
end
