defmodule JidoCode.ControlPlane.Codecs.PolicySetCodec do
  @moduledoc """
  RDF projection codec for governance policy-set records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :policy_set
  @field_mappings %{
    managed_repo_id: "managedRepoId",
    policy_set_id: "policySetId",
    name: "name",
    source_key: "policySetSourceKey",
    review_policy: "reviewPolicyJson",
    policy_metadata: "policyMetadataJson",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :policy_set_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_managed_repo_name, predicate: "policySetSourceKey", value: value_for(record, :source_key)}]
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
    |> Map.put_new(:policy_set_id, value_for(record, :policy_set_id) || value_for(record, :id))
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
