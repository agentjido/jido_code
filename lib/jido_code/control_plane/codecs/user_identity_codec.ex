defmodule JidoCode.ControlPlane.Codecs.UserIdentityCodec do
  @moduledoc """
  RDF projection codec for external provider identity links.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :user_identity
  @field_mappings %{
    user_identity_id: "userIdentityId",
    source_key: "sourceKey",
    user_id: "userId",
    provider: "provider",
    provider_host: "providerHost",
    provider_subject: "externalId",
    provider_login: "displayName",
    provider_email: "providerEmail",
    email_verified: "emailVerified",
    first_authenticated_at: "firstAuthenticatedAt",
    last_authenticated_at: "lastAuthenticatedAt",
    updated_at: "updatedAt",
    metadata: "metadataJson"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :auth
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record),
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :user_identity_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_provider_subject, predicate: "sourceKey", value: record[:source_key]}]
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
    provider_host = value_for(record, :provider_host)
    provider_subject = value_for(record, :provider_subject)
    source_key = value_for(record, :source_key) || source_key(provider, provider_host, provider_subject)

    record
    |> Map.put_new(:user_identity_id, value_for(record, :user_identity_id) || source_key)
    |> Map.put_new(:source_key, source_key)
  end

  defp source_key(provider, provider_host, provider_subject)
       when not is_nil(provider) and not is_nil(provider_host) and not is_nil(provider_subject) do
    "#{provider}:#{provider_host}:#{provider_subject}"
  end

  defp source_key(_provider, _provider_host, _provider_subject), do: nil

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
