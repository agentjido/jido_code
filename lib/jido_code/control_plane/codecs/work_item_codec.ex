defmodule JidoCode.ControlPlane.Codecs.WorkItemCodec do
  @moduledoc """
  RDF projection codec for work item records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :work_item
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    work_item_id: "workItemId",
    assessment_id: "assessmentId",
    event_id: "eventId",
    external_object_id: "externalObjectId",
    observation_id: "observationId",
    intake_id: "intakeId",
    category: "category",
    status: "recordStatus",
    priority: "priority",
    recommended_action: "recommendedAction",
    summary: "summary",
    dedup_key: "dedupKey",
    initiating_actor: "initiatingActorJson",
    work_metadata: "workMetadataJson",
    audit_log: "auditLogJson",
    opened_at: "openedAt",
    last_assessed_at: "lastAssessedAt",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :work_item_id)

  @impl true
  def identity_queries(record) do
    [
      %{
        identity: :unique_managed_repo_work_item,
        predicates: ["managedRepoId", "workItemId"],
        values: [record[:managed_repo_id] || record["managed_repo_id"], record[:work_item_id] || record["work_item_id"]]
      }
    ]
  end

  @impl true
  def encode(record) when is_map(record) do
    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)
end
