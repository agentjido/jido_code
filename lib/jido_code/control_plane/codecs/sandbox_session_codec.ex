defmodule JidoCode.ControlPlane.Codecs.SandboxSessionCodec do
  @moduledoc """
  RDF projection codec for sandbox session records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :sandbox_session
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    sandbox_session_id: "sandboxSessionId",
    name: "name",
    phase: "recordStatus",
    runner_type: "runnerType",
    runner_config: "runnerConfigJson",
    runner_state: "runnerStateJson",
    spec: "specJson",
    sprite_id: "spriteId",
    sprite_name: "spriteName",
    last_checkpoint_id: "lastCheckpointId",
    execution_count: "executionCount",
    output_buffer: "outputSummary",
    last_error: "lastErrorJson",
    started_at: "startedAt",
    completed_at: "completedAt",
    last_activity_at: "lastActivityAt",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :sandbox_session_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_name,
        predicate: "name",
        value: value_for(record, :name)
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
    Map.put_new(record, :sandbox_session_id, value_for(record, :sandbox_session_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
