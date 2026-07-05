defmodule JidoCode.Accounts.UserStore do
  @moduledoc """
  Store-backed local user projections for auth services.
  """

  alias JidoCode.Accounts.User
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()

  @spec upsert(map(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def upsert(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, email} <- normalize_email(map_get(attrs, :email)),
         record <- user_record(attrs, email),
         {:ok, %{record: saved_record}} <- ProductStore.dispatch(:upsert, :user, Keyword.merge([record: record], opts)) do
      {:ok, to_user(saved_record)}
    end
  end

  @spec get_by_email(String.t(), keyword()) :: {:ok, User.t() | nil} | {:error, term()}
  def get_by_email(email, opts \\ []) do
    with {:ok, normalized_email} <- normalize_email(email) do
      get_by_identity(:unique_email, "sourceKey", normalized_email, opts)
    end
  end

  @spec get_by_id(String.t(), keyword()) :: {:ok, User.t() | nil} | {:error, term()}
  def get_by_id(user_id, opts \\ [])

  def get_by_id(user_id, opts) when is_binary(user_id) and user_id != "" do
    case ProductStore.dispatch(:get, :user, Keyword.merge([record: %{id: user_id}], opts)) do
      {:ok, %{projection: projection}} -> decode_user_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_by_id(_user_id, _opts), do: {:error, :invalid_user_id}

  @spec list(keyword()) :: {:ok, [User.t()]} | {:error, term()}
  def list(opts \\ []) do
    case ProductStore.dispatch(:list, :user, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        users =
          projections
          |> Enum.map(&decode_user_projection/1)
          |> Enum.flat_map(fn
            {:ok, user} -> [user]
            {:error, _reason} -> []
          end)

        {:ok, users}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def to_user(record) when is_map(record) do
    %User{
      id: map_get(record, :user_id) || map_get(record, :id),
      email: map_get(record, :email),
      is_admin: truthy?(map_get(record, :is_admin, false)),
      confirmed_at: normalize_datetime(map_get(record, :confirmed_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  def normalize_email(value) when is_binary(value) do
    email = value |> String.trim() |> String.downcase()
    if email == "", do: {:error, :missing_email}, else: {:ok, email}
  end

  def normalize_email(_value), do: {:error, :missing_email}

  defp get_by_identity(identity_name, predicate, value, opts) do
    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: identity_name,
            predicate_iri: RDF.iri(@control_plane_ns <> predicate),
            value: value
          }
        ],
        opts
      )

    case ProductStore.dispatch(:get, :user, request_opts) do
      {:ok, %{projection: projection}} -> decode_user_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp user_record(attrs, email) do
    now = DateTime.utc_now()

    %{
      user_id: map_get(attrs, :user_id) || map_get(attrs, :id) || Ecto.UUID.generate(),
      email: email,
      is_admin: truthy?(map_get(attrs, :is_admin, false)),
      confirmed_at: normalize_datetime(map_get(attrs, :confirmed_at)),
      updated_at: map_get(attrs, :updated_at) || now,
      metadata: attrs |> map_get(:metadata, %{}) |> decode_json_map()
    }
  end

  defp decode_user_projection(projection) do
    with {:ok, record} <- Registry.decode(:user, projection) do
      {:ok, to_user(record)}
    end
  end

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_value), do: false

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: value
  defp decode_json_map(_value), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
