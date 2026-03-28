defmodule JidoWorkflow.Workflow.Definition do
  @moduledoc """
  In-memory contract for a workflow definition.
  """

  alias JidoWorkflow.Workflow.Definition.{Input, Return, Step}

  @enforce_keys [:name, :version]
  defstruct [
    :name,
    :version,
    :description,
    :enabled,
    inputs: [],
    steps: [],
    return: nil,
    triggers: [],
    settings: nil,
    signals: nil,
    error_handling: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          description: String.t() | nil,
          enabled: boolean(),
          inputs: [Input.t()],
          steps: [Step.t()],
          return: Return.t() | nil,
          triggers: [map()],
          settings: map() | nil,
          signals: map() | nil,
          error_handling: [map()]
        }
end
