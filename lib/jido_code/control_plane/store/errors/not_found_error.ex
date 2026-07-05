defmodule JidoCode.ControlPlane.Store.Errors.NotFoundError do
  @moduledoc """
  Requested control-plane record was not found.
  """

  defexception [:record_type, :subject_iri, message: "control-plane record not found"]

  @type t :: %__MODULE__{
          record_type: atom() | nil,
          subject_iri: String.t() | nil,
          message: String.t()
        }
end
