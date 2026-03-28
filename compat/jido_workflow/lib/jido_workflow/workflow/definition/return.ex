defmodule JidoWorkflow.Workflow.Definition.Return do
  @moduledoc """
  Return-value declaration for a workflow.
  """

  defstruct [:value, :transform]

  @type t :: %__MODULE__{
          value: String.t() | nil,
          transform: String.t() | nil
        }
end
