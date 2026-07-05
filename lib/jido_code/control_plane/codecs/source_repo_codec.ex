defmodule JidoCode.ControlPlane.Codecs.SourceRepoCodec do
  @moduledoc """
  RDF projection codec for source repository records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :source_repo
  @field_mappings %{
    source_repo_id: "sourceRepoId",
    source_key: "sourceKey",
    provider: "provider",
    owner: "owner",
    name: "name",
    full_name: "fullName",
    default_branch: "defaultBranch",
    source_metadata: "sourceMetadataJson",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :source_repo_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_provider_full_name, predicate: "sourceKey", value: record[:source_key]}]
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
    provider = value_for(record, :provider)
    full_name = value_for(record, :full_name)
    source_key = value_for(record, :source_key) || source_key(provider, full_name)

    record
    |> Map.put_new(:source_repo_id, value_for(record, :source_repo_id) || value_for(record, :id))
    |> Map.put_new(:source_key, source_key)
  end

  defp source_key(provider, full_name) when not is_nil(provider) and not is_nil(full_name) do
    "#{provider}:#{full_name}"
  end

  defp source_key(_provider, _full_name), do: nil

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
