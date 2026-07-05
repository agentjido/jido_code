defmodule JidoCode.ControlPlane.Codecs.RuntimeEventCodec do
  @moduledoc """
  RDF projection codec for execution runtime event records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :runtime_event
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    runtime_event_id: "runtimeEventId",
    source_kind: "sourceKind",
    title: "title",
    occurred_at: "occurredAt",
    payload: "payloadJson",
    updated_at: "updatedAt"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :execution_runtime
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :runtime_event_id)
  @impl true
  def identity_queries(record),
    do: [
      %{
        identity: :unique_runtime_event_id,
        predicate: "runtimeEventId",
        value: record[:runtime_event_id] || record["runtime_event_id"]
      }
    ]

  @impl true
  def encode(record),
    do:
      with(
        {:ok, subject_iri} <- subject_iri(record),
        do: MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
      )

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)
end
