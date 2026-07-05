defmodule JidoCode.ControlPlane.Store.Errors.UnavailableError do
  @moduledoc """
  Store implementation or backend was unavailable.
  """

  defexception [:stage, :reason, message: "control-plane store unavailable"]

  @type t :: %__MODULE__{
          stage: atom() | nil,
          reason: term(),
          message: String.t()
        }
end
