defmodule JidoCode.ControlPlane.Codecs.ExecSessionCodec do
  @moduledoc """
  RDF projection codec for bounded execution session summaries.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :exec_session
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    exec_session_id: "execSessionId",
    sandbox_session_id: "sandboxSessionId",
    sequence: "sequence",
    status: "recordStatus",
    command: "command",
    exit_code: "exitCode",
    output: "outputSummary",
    output_size_bytes: "outputSizeBytes",
    error: "errorJson",
    cost_usd: "costUsd",
    duration_ms: "durationMs",
    sprites_session_id: "spritesSessionId",
    started_at: "startedAt",
    completed_at: "completedAt",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :exec_session_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_exec_session_id,
        predicate: "execSessionId",
        value: value_for(record, :exec_session_id)
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
    Map.put_new(record, :exec_session_id, value_for(record, :exec_session_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
