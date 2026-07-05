defmodule JidoCode.ControlPlane.Codecs.ManagedRepoCodec do
  @moduledoc """
  RDF projection codec for managed repository records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :managed_repo
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    source_key: "managedSourceKey",
    source_repo_id: "sourceRepoRef",
    legacy_project_id: "legacyProjectId",
    display_name: "displayName",
    record_label: "recordLabel",
    workspace_path: "workspacePath",
    workspace_settings: "workspaceSettingsJson",
    execution_settings: "executionSettingsJson",
    integration_settings: "integrationSettingsJson",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :managed_repo_id)

  @impl true
  def identity_queries(record) do
    [
      identity(:unique_source_repo, "sourceRepoRef", record[:source_repo_id] || record["source_repo_id"]),
      identity(:unique_legacy_project_id, "legacyProjectId", record[:legacy_project_id] || record["legacy_project_id"]),
      identity(:unique_source_key, "managedSourceKey", record[:source_key] || record["source_key"])
    ]
    |> Enum.reject(&is_nil(&1.value))
  end

  @impl true
  def encode(record) when is_map(record) do
    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)

  defp identity(name, predicate, value), do: %{identity: name, predicate: predicate, value: value}
end
