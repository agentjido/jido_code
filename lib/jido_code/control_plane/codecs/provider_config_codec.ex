defmodule JidoCode.ControlPlane.Codecs.ProviderConfigCodec do
  @moduledoc """
  RDF projection codec for provider login configuration records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :provider_config
  @field_mappings %{
    provider_config_id: "providerConfigId",
    source_key: "sourceKey",
    provider: "provider",
    provider_host: "providerHost",
    enabled: "enabled",
    login_enabled: "loginEnabled",
    allowlist_mode: "allowlistMode",
    allowlist_values: "allowlistValuesJson",
    broker_issuer: "brokerIssuer",
    broker_audience: "brokerAudience",
    broker_base_url: "brokerBaseUrl",
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
    do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :provider_config_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)
    [%{identity: :unique_provider_host, predicate: "sourceKey", value: record[:source_key]}]
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
    source_key = value_for(record, :source_key) || source_key(provider, provider_host)

    record
    |> Map.put_new(:provider_config_id, value_for(record, :provider_config_id) || source_key)
    |> Map.put_new(:source_key, source_key)
  end

  defp source_key(provider, provider_host) when not is_nil(provider) and not is_nil(provider_host) do
    "#{provider}:#{provider_host}"
  end

  defp source_key(_provider, _provider_host), do: nil

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
