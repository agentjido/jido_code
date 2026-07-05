defmodule JidoCode.ControlPlane.Codecs.RuntimeEventCodec do
  @moduledoc """
  RDF projection codec for execution runtime event records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :runtime_event
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    runtime_event_id: "runtimeEventId",
    sandbox_session_id: "sandboxSessionId",
    exec_session_sequence: "execSessionSequence",
    event_type: "eventName",
    source_kind: "sourceKind",
    title: "title",
    occurred_at: "occurredAt",
    payload: "payloadJson",
    inserted_at: "insertedAt",
    updated_at: "updatedAt",
    metadata: "metadataJson"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :execution_runtime
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record),
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :runtime_event_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_runtime_event_id,
        predicate: "runtimeEventId",
        value: value_for(record, :runtime_event_id)
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
    |> Map.put_new(:runtime_event_id, value_for(record, :runtime_event_id) || value_for(record, :id))
    |> Map.put_new(:payload, value_for(record, :payload) || value_for(record, :data))
    |> Map.put_new(:event_type, value_for(record, :event_type) || value_for(record, :name))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
