defmodule JidoCode.ControlPlane.Codecs.ConversationEventCodec do
  @moduledoc """
  RDF projection codec for append-only conversation event records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :conversation_event
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    conversation_event_id: "conversationEventId",
    conversation_id: "conversationId",
    work_item_id: "workItemId",
    source_key: "conversationEventSourceKey",
    sequence: "sequence",
    name: "eventName",
    actor: "actorJson",
    message_id: "messageId",
    turn_id: "turnId",
    child_work_id: "childWorkId",
    tool_call_id: "toolCallId",
    correlation: "correlationJson",
    payload: "payloadJson",
    occurred_at: "occurredAt",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :conversation_event_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_conversation_sequence,
        predicate: "conversationEventSourceKey",
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
    |> Map.put_new(:conversation_event_id, value_for(record, :conversation_event_id) || value_for(record, :id))
    |> Map.put_new(:source_key, source_key(record))
  end

  defp source_key(record) do
    value_for(record, :source_key) ||
      [value_for(record, :conversation_id), value_for(record, :sequence)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")
      |> case do
        "" -> nil
        value -> value
      end
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
