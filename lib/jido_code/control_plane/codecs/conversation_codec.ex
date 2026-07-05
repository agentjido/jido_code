defmodule JidoCode.ControlPlane.Codecs.ConversationCodec do
  @moduledoc """
  RDF projection codec for conversation records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :conversation
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    conversation_id: "conversationId",
    work_item_id: "workItemId",
    status: "recordStatus",
    scope: "conversationScope",
    attachment_mode: "attachmentMode",
    source: "source",
    title: "title",
    objective: "objective",
    initiating_actor: "initiatingActorJson",
    source_metadata: "sourceMetadataJson",
    conversation_metadata: "conversationMetadataJson",
    started_at: "startedAt",
    last_activity_at: "lastActivityAt",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :conversation_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_conversation_id,
        predicate: "conversationId",
        value: value_for(record, :conversation_id)
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
    Map.put_new(record, :conversation_id, value_for(record, :conversation_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
