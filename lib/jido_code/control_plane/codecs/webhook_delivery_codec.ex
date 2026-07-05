defmodule JidoCode.ControlPlane.Codecs.WebhookDeliveryCodec do
  @moduledoc """
  RDF projection codec for GitHub webhook delivery idempotency records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :webhook_delivery
  @field_mappings %{
    webhook_delivery_id: "webhookDeliveryId",
    github_delivery_id: "githubDeliveryId",
    managed_repo_id: "managedRepoId",
    repo_id: "githubRepoId",
    event_type: "eventType",
    action: "action",
    payload: "payloadJson",
    status: "recordStatus",
    error_message: "errorMessage",
    processed_at: "processedAt",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :webhook_delivery_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_github_delivery,
        predicate: "githubDeliveryId",
        value: value_for(record, :github_delivery_id)
      }
    ]
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
    Map.put_new(record, :webhook_delivery_id, value_for(record, :webhook_delivery_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
