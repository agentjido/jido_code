defmodule JidoCode.ControlPlane.Codecs.RunCodec do
  @moduledoc """
  RDF projection codec for orchestration run records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :run
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    run_id: "runId",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :run_id)
  @impl true
  def identity_queries(record),
    do: [
      %{
        identity: :unique_managed_repo_run_id,
        predicate: "sourceKey",
        value: record[:source_key] || record["source_key"]
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
