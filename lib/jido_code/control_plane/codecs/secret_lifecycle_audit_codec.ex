defmodule JidoCode.ControlPlane.Codecs.SecretLifecycleAuditCodec do
  @moduledoc """
  RDF projection codec for secret lifecycle audit metadata.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :secret_lifecycle_audit
  @field_mappings %{
    secret_lifecycle_audit_id: "secretLifecycleAuditId",
    secret_ref_id: "secretRefId",
    scope: "sourceKind",
    name: "sourceKey",
    action_type: "actionType",
    outcome_status: "outcomeStatus",
    actor_id: "actorId",
    actor_email: "actorEmail",
    occurred_at: "occurredAt",
    updated_at: "updatedAt",
    metadata: "metadataJson"
  }

  @impl true
  def record_type, do: @record_type

  @impl true
  def graph_name, do: :security

  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)

  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)

  @impl true
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :secret_lifecycle_audit_id)

  @impl true
  def identity_queries(record) do
    [
      %{
        identity: :unique_secret_lifecycle_audit_id,
        predicate: "secretLifecycleAuditId",
        value: record[:secret_lifecycle_audit_id] || record["secret_lifecycle_audit_id"]
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
