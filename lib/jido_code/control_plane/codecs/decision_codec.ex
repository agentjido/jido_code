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
    decision_key: "decisionKey",
    run_id: "runId",
    change_request_id: "changeRequestId",
    work_item_id: "workItemId",
    decision: "decisionOutcome",
    actor: "actorJson",
    rationale: "rationale",
    evidence_ids: "evidenceIdsJson",
    decision_metadata: "decisionMetadataJson",
    decided_at: "decidedAt",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :decision_id)

  @impl true
  def identity_queries(record),
    do: [%{identity: :unique_decision_key, predicate: "decisionKey", value: value_for(record, :decision_key)}]

  @impl true
  def encode(record) do
    record = normalized_record(record)

    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)

  defp normalized_record(record) do
    Map.put_new(record, :decision_id, value_for(record, :decision_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
