defmodule JidoCode.ControlPlane.Codecs.EventCodec do
  @moduledoc """
  RDF projection codec for append-only control-plane event records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :event
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    event_id: "eventId",
    external_object_id: "externalObjectId",
    observation_id: "observationId",
    intake_id: "intakeId",
    category: "category",
    summary: "summary",
    correlation_key: "correlationKey",
    source_metadata: "sourceMetadataJson",
    occurred_at: "occurredAt",
    inserted_at: "insertedAt",
    updated_at: "updatedAt",
    payload: "payloadJson"
  }

  @impl true
  def record_type, do: @record_type

  @impl true
  def graph_name, do: :control_plane_events

  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)

  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)

  @impl true
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :event_id)

  @impl true
  def identity_queries(record) do
    [
      %{
        identity: :append_event_id,
        predicates: ["managedRepoId", "eventId"],
        values: [record[:managed_repo_id] || record["managed_repo_id"], record[:event_id] || record["event_id"]]
      }
    ]
  end

  @impl true
  def encode(record) when is_map(record) do
    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)
end
