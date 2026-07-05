defmodule JidoCode.ControlPlane.Codecs.RunCodec do
  @moduledoc """
  RDF projection codec for orchestration run records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :run
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    run_record_id: "runId",
    workflow_run_id: "runWorkflowRunId",
    work_item_id: "workItemId",
    execution_profile_id: "executionProfileId",
    legacy_project_id: "legacyProjectId",
    run_id: "sourceRunId",
    workflow_name: "workflowName",
    workflow_version: "workflowVersion",
    status: "recordStatus",
    current_step: "currentStep",
    current_stage: "currentStage",
    governed_stages: "governedStagesJson",
    stage_statuses: "stageStatusesJson",
    trigger: "triggerJson",
    inputs: "inputsJson",
    input_metadata: "inputMetadataJson",
    initiating_actor: "initiatingActorJson",
    execution_engine: "executionEngine",
    workflow_state_ref: "workflowStateRefJson",
    run_metadata: "runMetadataJson",
    error: "errorJson",
    retry_of_run_id: "retryOfRunId",
    retry_attempt: "retryAttempt",
    retry_lineage: "retryLineageJson",
    started_at: "startedAt",
    completed_at: "completedAt",
    source_key: "runSourceKey",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :run_record_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    cond do
      value_for(record, :workflow_run_id) ->
        [%{identity: :unique_workflow_run, predicate: "runWorkflowRunId", value: value_for(record, :workflow_run_id)}]

      value_for(record, :source_key) ->
        [%{identity: :unique_managed_repo_run_id, predicate: "runSourceKey", value: value_for(record, :source_key)}]

      true ->
        []
    end
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
    |> Map.put_new(:run_record_id, value_for(record, :run_record_id) || value_for(record, :id))
    |> Map.put_new(:source_key, source_key(record))
  end

  defp source_key(record) do
    value_for(record, :source_key) ||
      [value_for(record, :managed_repo_id), value_for(record, :run_id)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")
      |> case do
        "" -> nil
        value -> value
      end
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
