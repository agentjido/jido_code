defmodule JidoCode.ControlPlane.Codecs.SystemConfigCodec do
  @moduledoc """
  RDF projection codec for setup system configuration records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :system_config
  @field_mappings %{
    key: "systemConfigId",
    display_name: "displayName",
    metadata: "metadataJson",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :key)
  @impl true
  def identity_queries(record),
    do: [%{identity: :unique_key, predicate: "systemConfigId", value: record[:key] || record["key"]}]

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
