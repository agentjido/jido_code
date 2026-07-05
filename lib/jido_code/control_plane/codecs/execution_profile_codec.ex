defmodule JidoCode.ControlPlane.Codecs.ExecutionProfileCodec do
  @moduledoc """
  RDF projection codec for execution profile records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :execution_profile
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    execution_profile_id: "executionProfileId",
    name: "name",
    source_key: "executionProfileSourceKey",
    sandbox_profile: "sandboxProfileJson",
    repo_prep_plan: "repoPrepPlanJson",
    validation_plan: "validationPlanJson",
    governed_stages: "governedStagesJson",
    checkpoint_strategy: "checkpointStrategy",
    resume_strategy: "resumeStrategy",
    profile_metadata: "profileMetadataJson",
    source: "source",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :execution_profile_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_managed_repo_name,
        predicate: "executionProfileSourceKey",
        value: value_for(record, :source_key)
      }
    ]
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
    |> Map.put_new(:execution_profile_id, value_for(record, :execution_profile_id) || value_for(record, :id))
    |> Map.put_new(:source_key, source_key(record))
  end

  defp source_key(record) do
    value_for(record, :source_key) ||
      [value_for(record, :managed_repo_id), value_for(record, :name)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")
      |> case do
        "" -> nil
        value -> value
      end
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
