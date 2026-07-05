defmodule JidoCode.ControlPlane.Codecs.ObservationCodec do
  @moduledoc """
  RDF projection codec for observation records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :observation
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    observation_id: "observationId",
    external_object_id: "externalObjectId",
    source: "source",
    category: "category",
    summary: "summary",
    payload: "payloadJson",
    source_metadata: "sourceMetadataJson",
    captured_by: "capturedByJson",
    observed_at: "observedAt",
    inserted_at: "insertedAt",
    updated_at: "updatedAt"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :control_plane
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :observation_id)
  @impl true
  def identity_queries(_record), do: []

  @impl true
  def encode(record) when is_map(record) do
    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)
end
