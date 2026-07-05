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
    title: "title",
    summary: "summary",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :conversation_id)
  @impl true
  def identity_queries(record),
    do: [
      %{
        identity: :unique_conversation_id,
        predicate: "conversationId",
        value: record[:conversation_id] || record["conversation_id"]
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
