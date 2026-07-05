defmodule JidoCode.ControlPlane.Codecs.ApiKeyCodec do
  @moduledoc """
  RDF projection codec for API key lifecycle metadata.

  Raw API keys and key hashes are intentionally not projectable.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :api_key
  @sensitive_fields [:api_key, :api_key_hash, :key_hash, :plaintext, :ciphertext, :token, :bearer_token]
  @field_mappings %{
    api_key_id: "apiKeyId",
    user_id: "userId",
    name: "displayName",
    expires_at: "expiresAt",
    revoked_at: "revokedAt",
    status: "recordStatus",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :api_key_id)
  @impl true
  def identity_queries(record),
    do: [%{identity: :unique_api_key_id, predicate: "apiKeyId", value: value_for(record, :api_key_id)}]

  @impl true
  def encode(record) when is_map(record) do
    with :ok <- reject_sensitive_fields(record),
         {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)

  defp reject_sensitive_fields(record) do
    case Enum.find(@sensitive_fields, &present?(record, &1)) do
      nil -> :ok
      field -> {:error, {:sensitive_field_not_projectable, field}}
    end
  end

  defp present?(record, field), do: not is_nil(value_for(record, field))
  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
