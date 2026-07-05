defmodule JidoCode.Accounts.UserIdentityStore do
  @moduledoc """
  Store-backed provider identity links.
  """

  alias JidoCode.Accounts.UserIdentity
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()

  @spec upsert(map(), keyword()) :: {:ok, UserIdentity.t()} | {:error, term()}
  def upsert(attrs, opts \\ []) when is_map(attrs) do
    record = identity_record(attrs)

    with :ok <- ensure_provider_subject_available(record, opts),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:upsert, :user_identity, Keyword.merge([record: record], opts)) do
      {:ok, to_identity(saved_record)}
    end
  end

  @spec get_by_provider_subject(atom() | String.t(), String.t(), String.t(), keyword()) ::
          {:ok, UserIdentity.t() | nil} | {:error, term()}
  def get_by_provider_subject(provider, provider_host, provider_subject, opts \\ []) do
    source_key = source_key(provider, provider_host, provider_subject)

    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: :unique_provider_subject,
            predicate_iri: RDF.iri(@control_plane_ns <> "sourceKey"),
            value: source_key
          }
        ],
        opts
      )

    case ProductStore.dispatch(:get, :user_identity, request_opts) do
      {:ok, %{projection: projection}} -> decode_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_for_user(String.t(), keyword()) :: {:ok, [UserIdentity.t()]} | {:error, term()}
  def list_for_user(user_id, opts \\ []) do
    case ProductStore.dispatch(:list, :user_identity, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        identities =
          projections
          |> Enum.map(&decode_projection/1)
          |> Enum.flat_map(fn
            {:ok, identity} -> [identity]
            {:error, _reason} -> []
          end)
          |> Enum.filter(&(to_string(&1.user_id) == to_string(user_id)))

        {:ok, identities}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def source_key(provider, provider_host, provider_subject) do
    "#{provider}:#{provider_host}:#{provider_subject}"
  end

  defp ensure_provider_subject_available(record, opts) do
    with {:ok, %UserIdentity{} = existing} <-
           get_by_provider_subject(record.provider, record.provider_host, record.provider_subject, opts),
         false <- to_string(existing.user_id) == to_string(record.user_id) do
      {:error,
       %{
         type: :conflict,
         field: :provider_subject,
         message: "provider subject has already been taken"
       }}
    else
      {:ok, nil} -> :ok
      true -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def to_identity(record) when is_map(record) do
    %UserIdentity{
      id: map_get(record, :user_identity_id),
      user_id: map_get(record, :user_id),
      provider: normalize_provider(map_get(record, :provider)),
      provider_host: map_get(record, :provider_host),
      provider_subject: map_get(record, :provider_subject),
      provider_login: map_get(record, :provider_login),
      provider_email: map_get(record, :provider_email),
      email_verified: truthy?(map_get(record, :email_verified, false)),
      first_authenticated_at: normalize_datetime(map_get(record, :first_authenticated_at)),
      last_authenticated_at: normalize_datetime(map_get(record, :last_authenticated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp identity_record(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    provider = map_get(attrs, :provider)
    provider_host = map_get(attrs, :provider_host)
    provider_subject = map_get(attrs, :provider_subject)
    source_key = map_get(attrs, :source_key) || source_key(provider, provider_host, provider_subject)

    %{
      user_identity_id: map_get(attrs, :user_identity_id) || map_get(attrs, :id) || source_key,
      source_key: source_key,
      user_id: map_get(attrs, :user_id),
      provider: provider,
      provider_host: provider_host,
      provider_subject: provider_subject,
      provider_login: map_get(attrs, :provider_login),
      provider_email: map_get(attrs, :provider_email),
      email_verified: truthy?(map_get(attrs, :email_verified, false)),
      first_authenticated_at: normalize_datetime(map_get(attrs, :first_authenticated_at)),
      last_authenticated_at: normalize_datetime(map_get(attrs, :last_authenticated_at)),
      updated_at: map_get(attrs, :updated_at) || now,
      metadata: map_get(attrs, :metadata, %{})
    }
  end

  defp decode_projection(projection) do
    with {:ok, record} <- Registry.decode(:user_identity, projection) do
      {:ok, to_identity(record)}
    end
  end

  defp normalize_provider(value) when is_atom(value), do: value
  defp normalize_provider(value) when is_binary(value), do: String.to_existing_atom(value)
  defp normalize_provider(value), do: value

  defp normalize_datetime(%DateTime{} = datetime), do: normalize_precision(datetime)

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_precision(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_precision(%DateTime{microsecond: {microsecond, _precision}} = datetime) do
    %{datetime | microsecond: {microsecond, 6}}
  end

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_value), do: false

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
