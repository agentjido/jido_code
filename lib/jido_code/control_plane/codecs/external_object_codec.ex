defmodule JidoCode.ControlPlane.Codecs.ExternalObjectCodec do
  @moduledoc """
  RDF projection codec for external provider objects.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :external_object
  @field_mappings %{
    external_object_id: "externalObjectId",
    managed_repo_id: "managedRepoId",
    provider: "provider",
    provider_host: "providerHost",
    object_type: "objectType",
    external_id: "externalId",
    canonical_key: "canonicalKey",
    canonical_reference: "canonicalReference",
    title: "title",
    url: "url",
    status: "recordStatus",
    payload: "payloadJson",
    source_metadata: "sourceMetadataJson",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :external_object_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_canonical_key, predicate: "canonicalKey", value: record[:canonical_key]}]
  end

  @impl true
  def encode(record) when is_map(record) do
    record = normalized_record(record)

    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)

  defp normalized_record(record) do
    record
    |> Map.put_new(:external_object_id, value_for(record, :external_object_id) || value_for(record, :id))
    |> Map.put_new(:provider_host, value_for(record, :provider_host) || "github.com")
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
