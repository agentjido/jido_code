defmodule JidoCode.ControlPlane.Codecs.RepoPostureCodec do
  @moduledoc """
  RDF projection codec for repository posture records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :repo_posture
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    repo_posture_id: "repoPostureId",
    source_key: "repoPostureSourceKey",
    summary: "summary",
    overall_trust: "overallTrust",
    execution_readiness: "executionReadiness",
    validation_reliability: "validationReliability",
    review_burden: "reviewBurden",
    drift_rate: "driftRate",
    recovery_resilience: "recoveryResilience",
    requirements_confidence: "requirementsConfidence",
    supervision_mode: "supervisionMode",
    escalation_status: "escalationStatus",
    algedonic_check_id: "algedonicCheckId",
    contributing_check_ids: "contributingCheckIdsJson",
    posture_metadata: "postureMetadataJson",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :repo_posture_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_managed_repo, predicate: "repoPostureSourceKey", value: value_for(record, :source_key)}]
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
    record
    |> Map.put_new(:repo_posture_id, value_for(record, :repo_posture_id) || value_for(record, :id))
    |> Map.put_new(:source_key, value_for(record, :source_key) || value_for(record, :managed_repo_id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
