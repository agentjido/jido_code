defmodule JidoWorkflow.Workflow.Definition.Step do
  @moduledoc """
  Normalized workflow step declaration.
  """

  @enforce_keys [:name, :type]
  defstruct [
    :name,
    :type,
    :module,
    :inputs,
    :outputs,
    :depends_on,
    :async,
    :mode,
    :timeout_ms,
    :condition,
    :workflow,
    :agent
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t(),
          module: String.t() | nil,
          inputs: map() | nil,
          outputs: [String.t()] | nil,
          depends_on: [String.t()] | nil,
          async: boolean() | nil,
          mode: String.t() | nil,
          timeout_ms: integer() | nil,
          condition: String.t() | nil,
          workflow: String.t() | nil,
          agent: String.t() | nil
        }
end
