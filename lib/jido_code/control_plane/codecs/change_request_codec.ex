defmodule JidoCode.ControlPlane.Codecs.ChangeRequestCodec do
  @moduledoc """
  RDF projection codec for governed change request records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :change_request
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    change_request_id: "changeRequestId",
    run_id: "runId",
    source_key: "changeRequestSourceKey",
    work_item_id: "workItemId",
    status: "recordStatus",
    summary: "summary",
    review_context: "reviewContextJson",
    request_metadata: "requestMetadataJson",
    evidence_ids: "evidenceIdsJson",
    requested_at: "requestedAt",
    resolved_at: "resolvedAt",
    inserted_at: "insertedAt",
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
  def subject_iri(record),
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :change_request_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_run, predicate: "changeRequestSourceKey", value: value_for(record, :source_key)}]
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
    |> Map.put_new(:change_request_id, value_for(record, :change_request_id) || value_for(record, :id))
    |> Map.put_new(:source_key, value_for(record, :source_key) || value_for(record, :run_id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
