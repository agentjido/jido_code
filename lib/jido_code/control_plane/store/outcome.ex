defmodule JidoCode.ControlPlane.Store.Outcome do
  @moduledoc """
  Common success shape returned by control-plane store implementations.
  """

  defstruct [
    :operation,
    :status,
    :record_type,
    :subject_iri,
    :record,
    :projection,
    :event_iri,
    records: [],
    projections: [],
    written_subject_iris: [],
    deleted_subject_iris: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          operation: atom(),
          status: atom(),
          record_type: atom() | nil,
          subject_iri: String.t() | nil,
          record: map() | nil,
          projection: map() | nil,
          event_iri: String.t() | nil,
          records: [map()],
          projections: [map()],
          written_subject_iris: [String.t()],
          deleted_subject_iris: [String.t()],
          metadata: map()
        }
end
