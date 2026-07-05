defmodule JidoCode.ControlPlane.Codecs.DecisionCodec do
  @moduledoc """
  RDF projection codec for governance decision records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :decision
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    decision_id: "decisionId",
    title: "title",
    summary: "summary",
    source_key: "sourceKey",
    updated_at: "updatedAt",
    metadata: "metadataJson"
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :decision_id)
  @impl true
  def identity_queries(record),
    do: [%{identity: :unique_decision_key, predicate: "sourceKey", value: record[:source_key] || record["source_key"]}]

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
