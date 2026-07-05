defmodule JidoCode.ControlPlane.Codecs.CheckpointCodec do
  @moduledoc """
  RDF projection codec for execution checkpoint records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :checkpoint
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    checkpoint_id: "checkpointId",
    sandbox_session_id: "sandboxSessionId",
    sprites_checkpoint_id: "spritesCheckpointId",
    name: "name",
    exec_session_sequence: "execSessionSequence",
    runner_state_snapshot: "runnerStateSnapshotJson",
    created_at: "createdAt",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :checkpoint_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_checkpoint_id,
        predicate: "checkpointId",
        value: value_for(record, :checkpoint_id)
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
    Map.put_new(record, :checkpoint_id, value_for(record, :checkpoint_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
