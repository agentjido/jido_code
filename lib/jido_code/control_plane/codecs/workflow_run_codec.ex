defmodule JidoCode.ControlPlane.Codecs.WorkflowRunCodec do
  @moduledoc """
  RDF projection codec for workflow-run compatibility records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :workflow_run
  @field_mappings %{
    workflow_run_id: "workflowRunId",
    managed_repo_id: "managedRepoId",
    legacy_project_id: "legacyProjectId",
    run_id: "sourceRunId",
    workflow_name: "workflowName",
    workflow_version: "workflowVersion",
    status: "recordStatus",
    current_step: "currentStep",
    trigger: "triggerJson",
    inputs: "inputsJson",
    input_metadata: "inputMetadataJson",
    initiating_actor: "initiatingActorJson",
    step_results: "stepResultsJson",
    error: "errorJson",
    status_transitions: "statusTransitionsJson",
    retry_of_run_id: "retryOfRunId",
    retry_attempt: "retryAttempt",
    retry_lineage: "retryLineageJson",
    started_at: "startedAt",
    completed_at: "completedAt",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :workflow_run_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_workflow_run, predicate: "workflowRunId", value: value_for(record, :workflow_run_id)}]
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
    Map.put_new(record, :workflow_run_id, value_for(record, :workflow_run_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
