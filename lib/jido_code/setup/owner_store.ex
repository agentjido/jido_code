defmodule JidoCode.Setup.OwnerStore do
  @moduledoc """
  Store-backed owner account helper for setup bootstrap flows.
  """

  alias JidoCode.Accounts.User
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()

  @spec list_users(keyword()) :: {:ok, [User.t()]} | {:error, term()}
  def list_users(opts \\ []) do
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

  @spec get_by_email(String.t(), keyword()) :: {:ok, User.t() | nil} | {:error, term()}
  def get_by_email(email, opts \\ []) do
    with {:ok, normalized_email} <- normalize_email(email) do
      request_opts =
        Keyword.merge(
          [
            identity: %{
              identity: :unique_email,
              predicate_iri: RDF.iri(@control_plane_ns <> "sourceKey"),
              value: normalized_email
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
  end

  @spec create_owner(map(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def create_owner(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, email} <- normalize_email(map_get(attrs, :email)),
         {:ok, record} <- owner_record(email, attrs),
         {:ok, %{record: saved_record}} <- ProductStore.dispatch(:upsert, :user, Keyword.merge([record: record], opts)) do
      {:ok, to_user(saved_record)}
    end
  end

  @spec promote_to_admin(User.t(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def promote_to_admin(%User{} = user, opts \\ []) do
    record = %{
      user_id: user.id,
      email: to_string(user.email),
      is_admin: true,
      confirmed_at: user.confirmed_at || DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: metadata_for(user)
    }

    case ProductStore.dispatch(:upsert, :user, Keyword.merge([record: record], opts)) do
      {:ok, %{record: saved_record}} -> {:ok, to_user(saved_record)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete_all_users(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete_all_users(opts \\ []) do
    with {:ok, users} <- list_users(opts) do
      users
      |> Enum.reduce_while({:ok, 0}, fn user, {:ok, count} ->
        case delete_user(user, opts) do
          :ok -> {:cont, {:ok, count + 1}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp delete_user(%User{id: user_id}, opts) when is_binary(user_id) do
    subject_iri = "https://jido.run/control/users/#{user_id}"

    case ProductStore.dispatch(:delete, :user, Keyword.merge([subject_iri: subject_iri], opts)) do
      {:ok, _outcome} -> :ok
      {:error, %NotFoundError{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp owner_record(email, attrs) do
    now = DateTime.utc_now()

    {:ok,
     %{
       user_id: map_get(attrs, :user_id) || JidoCode.UUID.generate(),
       email: email,
       is_admin: true,
       confirmed_at: now,
       updated_at: now,
       metadata: %{
         "credential_state" => "pending_auth_service_migration",
         "created_by" => "setup_owner_bootstrap"
       }
     }}
  end

  defp decode_user_projection(projection) do
    with {:ok, record} <- Registry.decode(:user, projection) do
      {:ok, to_user(record)}
    end
  end

  defp to_user(record) when is_map(record) do
    %User{
      id: map_get(record, :user_id),
      email: map_get(record, :email),
      is_admin: truthy?(map_get(record, :is_admin, false)),
      confirmed_at: normalize_datetime(map_get(record, :confirmed_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp metadata_for(%User{} = user) do
    user
    |> Map.get(:__metadata__, %{})
    |> Map.get(:control_plane_record, %{})
    |> map_get(:metadata, %{})
    |> decode_json_map()
  end

  defp normalize_email(value) when is_binary(value) do
    email = value |> String.trim() |> String.downcase()

    if email == "" do
      {:error, :missing_email}
    else
      {:ok, email}
    end
  end

  defp normalize_email(_value), do: {:error, :missing_email}

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
