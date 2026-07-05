defmodule JidoCode.ControlPlane.Codecs.ConversationSnapshotCodec do
  @moduledoc """
  RDF projection codec for materialized conversation snapshots.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :conversation_snapshot
  @field_mappings %{
    conversation_snapshot_id: "conversationSnapshotId",
    conversation_id: "conversationId",
    managed_repo_id: "managedRepoId",
    work_item_id: "workItemId",
    source_key: "conversationSnapshotSourceKey",
    status: "recordStatus",
    admission_paused: "admissionPaused",
    child_execution_paused: "childExecutionPaused",
    active_turn_id: "activeTurnId",
    active_child_work_id: "activeChildWorkId",
    queued_turn_ids: "queuedTurnIdsJson",
    turns: "turnsJson",
    child_works: "childWorksJson",
    control_history: "controlHistoryJson",
    last_event_sequence: "lastEventSequence",
    event_count: "eventCount",
    events: "eventsJson",
    shared_context: "sharedContextJson",
    captured_at: "capturedAt",
    inserted_at: "insertedAt",
    updated_at: "updatedAt",
    metadata: "metadataJson"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :conversations
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record),
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :conversation_snapshot_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_conversation,
        predicate: "conversationSnapshotSourceKey",
        value: value_for(record, :source_key)
      }
    ]
  end

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
    record
    |> Map.put_new(:conversation_snapshot_id, value_for(record, :conversation_snapshot_id) || value_for(record, :id))
    |> Map.put_new(:source_key, value_for(record, :source_key) || value_for(record, :conversation_id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
