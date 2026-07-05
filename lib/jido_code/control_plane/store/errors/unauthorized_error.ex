defmodule JidoCode.ControlPlane.Store.Errors.UnauthorizedError do
  @moduledoc """
  Store request was denied by explicit authorization context.
  """

  defexception [:operation, :record_type, :actor, :reason, message: "control-plane store request unauthorized"]

  @type t :: %__MODULE__{
          operation: atom() | nil,
          record_type: atom() | nil,
          actor: term(),
          reason: term(),
          message: String.t()
        }
end
