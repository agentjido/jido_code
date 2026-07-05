defmodule JidoCode.ControlPlane.Store.Errors.ConflictError do
  @moduledoc """
  Identity or subject conflict detected by a store implementation.
  """

  defexception [
    :record_type,
    :identity,
    :subject_iri,
    :conflicting_subject_iri,
    message: "control-plane store conflict"
  ]

  @type t :: %__MODULE__{
          record_type: atom() | nil,
          identity: term(),
          subject_iri: String.t() | nil,
          conflicting_subject_iri: String.t() | nil,
          message: String.t()
        }
end
