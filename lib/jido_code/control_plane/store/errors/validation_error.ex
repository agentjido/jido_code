defmodule JidoCode.ControlPlane.Store.Errors.ValidationError do
  @moduledoc """
  Store request validation failure.
  """

  defexception [:stage, :field, :reason, errors: [], message: "control-plane store validation failed"]

  @type t :: %__MODULE__{
          stage: atom() | nil,
          field: atom() | nil,
          reason: term(),
          errors: [map()],
          message: String.t()
        }
end
