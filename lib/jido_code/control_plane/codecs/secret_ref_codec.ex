defmodule JidoCode.ControlPlane.Codecs.SecretRefCodec do
  @moduledoc """
  RDF projection codec for secret reference metadata.

  Secret material and credential hashes are intentionally rejected instead of
  serialized into RDF projections.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :secret_ref
  @sensitive_fields [
    :plaintext,
    :value,
    :ciphertext,
    :encrypted_blob,
    :password,
    :password_hash,
    :api_key,
    :api_key_hash,
    :token,
    :bearer_token,
    :webhook_secret,
    :private_key
  ]
  @field_mappings %{
    secret_ref_id: "secretRefId",
    canonical_key: "canonicalKey",
    scope: "sourceKind",
    name: "sourceKey",
    display_name: "displayName",
    provider: "provider",
    provider_host: "providerHost",
    source: "credentialSource",
    key_version: "keyVersion",
    last_rotated_at: "lastRotatedAt",
    expires_at: "expiresAt",
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
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :secret_ref_id)

  @impl true
  def identity_queries(record) do
    [
      %{
        identity: :unique_scope_name,
        predicate: "canonicalKey",
        value: record[:canonical_key] || record["canonical_key"]
      }
    ]
  end

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

  defp present?(record, field), do: not is_nil(Map.get(record, field) || Map.get(record, to_string(field)))
end
