defmodule JidoCode.Accounts.ApiKeys do
  @moduledoc """
  Product-owned signed API keys backed by control-plane lifecycle metadata.
  """

  alias JidoCode.Accounts.{User, UserStore}
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError
  alias JidoCodeWeb.Endpoint

  @default_salt "account-api-key"
  @default_ttl_seconds 31_536_000
  @prefix "agentjido"

  @spec issue(User.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def issue(%User{} = user, opts \\ []) do
    api_key_id = JidoCode.UUID.generate()
    expires_at = DateTime.utc_now() |> DateTime.add(Keyword.get(opts, :ttl_seconds, @default_ttl_seconds), :second)

    key =
      Phoenix.Token.sign(Endpoint, salt(opts), %{
        "purpose" => "api_key",
        "api_key_id" => api_key_id,
        "user_id" => user.id,
        "email" => to_string(user.email)
      })

    record = %{
      api_key_id: api_key_id,
      user_id: user.id,
      name: Keyword.get(opts, :name, "API key"),
      expires_at: expires_at,
      status: "active",
      updated_at: DateTime.utc_now(),
      metadata: %{"prefix" => @prefix}
    }

    with {:ok, _outcome} <- ProductStore.dispatch(:upsert, :api_key, record: record) do
      {:ok, %{id: api_key_id, api_key: @prefix <> "_" <> key, expires_at: expires_at}}
    end
  end

  @spec verify(String.t(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def verify(api_key, opts \\ [])

  def verify(api_key, opts) when is_binary(api_key) and api_key != "" do
    with {:ok, token} <- unwrap(api_key),
         {:ok, %{"purpose" => "api_key", "api_key_id" => api_key_id, "email" => email}} <-
           Phoenix.Token.verify(Endpoint, salt(opts), token, max_age: Keyword.get(opts, :max_age, @default_ttl_seconds)),
         {:ok, record} <- get_record(api_key_id),
         :ok <- ensure_active(record),
         {:ok, %User{} = user} <- UserStore.get_by_email(email) do
      {:ok, user}
    else
      {:ok, nil} -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_api_key, _opts), do: {:error, :invalid_api_key}

  @spec revoke(String.t(), keyword()) :: :ok | {:error, term()}
  def revoke(api_key_id, opts \\ [])

  def revoke(api_key_id, _opts) when is_binary(api_key_id) and api_key_id != "" do
    with {:ok, record} <- get_record(api_key_id) do
      revoked =
        record
        |> normalize_record_for_write()
        |> Map.put(:revoked_at, DateTime.utc_now())
        |> Map.put(:status, "revoked")
        |> Map.put(:updated_at, DateTime.utc_now())

      case ProductStore.dispatch(:upsert, :api_key, record: revoked) do
        {:ok, _outcome} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def revoke(_api_key_id, _opts), do: {:error, :invalid_api_key}

  defp get_record(api_key_id) do
    case ProductStore.dispatch(:get, :api_key, record: %{id: api_key_id}) do
      {:ok, %{projection: projection}} -> Registry.decode(:api_key, projection)
      {:error, %NotFoundError{}} -> {:error, :api_key_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_active(%{status: "active", expires_at: %DateTime{} = expires_at} = record) do
    cond do
      present?(Map.get(record, :revoked_at)) -> {:error, :api_key_revoked}
      DateTime.compare(expires_at, DateTime.utc_now()) == :gt -> :ok
      true -> {:error, :api_key_expired}
    end
  end

  defp ensure_active(%{status: "active", expires_at: expires_at}) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, datetime, _offset} -> ensure_active(%{status: "active", expires_at: datetime, revoked_at: nil})
      _other -> {:error, :api_key_invalid}
    end
  end

  defp ensure_active(%{status: "revoked"}), do: {:error, :api_key_revoked}
  defp ensure_active(_record), do: {:error, :api_key_invalid}

  defp normalize_record_for_write(record) do
    record
    |> Map.put(:metadata, decode_json_map(Map.get(record, :metadata, %{})))
    |> Map.drop([:record_type, :subject_iri])
  end

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: value
  defp decode_json_map(_value), do: %{}

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp unwrap(api_key) do
    prefix = @prefix <> "_"

    if String.starts_with?(api_key, prefix) do
      {:ok, String.replace_prefix(api_key, prefix, "")}
    else
      {:error, :invalid_api_key}
    end
  end

  defp salt(opts), do: Keyword.get(opts, :salt, Application.get_env(:jido_code, :api_key_salt, @default_salt))
end
