defmodule JidoCode.Accounts.SessionTokens do
  @moduledoc """
  Product-owned signed session tokens backed by control-plane token metadata.
  """

  alias JidoCode.Accounts.{User, UserStore}
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError
  alias JidoCodeWeb.Endpoint

  @default_salt "account-session"
  @default_ttl_seconds 2_592_000

  @spec issue(User.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def issue(%User{} = user, opts \\ []) do
    expires_at = DateTime.utc_now() |> DateTime.add(ttl_seconds(opts), :second)
    jti = JidoCode.UUID.generate()

    token =
      Phoenix.Token.sign(Endpoint, salt(opts), %{
        "purpose" => "session",
        "jti" => jti,
        "user_id" => user.id,
        "email" => to_string(user.email)
      })

    record = %{
      token_id: jti,
      user_id: user.id,
      subject: to_string(user.email),
      purpose: "session",
      expires_at: expires_at,
      status: "active",
      updated_at: DateTime.utc_now(),
      metadata: %{}
    }

    with {:ok, _outcome} <- ProductStore.dispatch(:upsert, :token, record: record) do
      {:ok, token}
    end
  end

  @spec verify(String.t(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def verify(token, opts \\ [])

  def verify(token, opts) when is_binary(token) and token != "" do
    with {:ok, %{"purpose" => "session", "jti" => jti, "email" => email}} <-
           Phoenix.Token.verify(Endpoint, salt(opts), token, max_age: ttl_seconds(opts)),
         {:ok, record} <- get_token_record(jti),
         :ok <- ensure_active(record),
         {:ok, %User{} = user} <- UserStore.get_by_email(email) do
      {:ok, user}
    else
      {:ok, nil} -> {:error, :user_not_found}
      {:ok, _claims} -> {:error, :invalid_purpose}
      {:error, :invalid} -> {:error, :invalid_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_token, _opts), do: {:error, :invalid_token}

  @spec revoke(String.t(), keyword()) :: :ok | {:error, term()}
  def revoke(token, opts \\ [])

  def revoke(token, opts) when is_binary(token) and token != "" do
    with {:ok, %{"purpose" => "session", "jti" => jti}} <-
           Phoenix.Token.verify(Endpoint, salt(opts), token, max_age: ttl_seconds(opts)),
         {:ok, record} <- get_token_record(jti) do
      revoked =
        record
        |> normalize_record_for_write()
        |> Map.put(:revoked_at, DateTime.utc_now())
        |> Map.put(:status, "revoked")
        |> Map.put(:updated_at, DateTime.utc_now())

      case ProductStore.dispatch(:upsert, :token, record: revoked) do
        {:ok, _outcome} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def revoke(_token, _opts), do: {:error, :invalid_token}

  @spec revoke_all_for_user(User.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def revoke_all_for_user(%User{} = user, opts \\ []) do
    case ProductStore.dispatch(:list, :token, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        projections
        |> Enum.map(&Registry.decode(:token, &1))
        |> Enum.flat_map(fn
          {:ok, record} -> [record]
          {:error, _reason} -> []
        end)
        |> Enum.filter(&session_token_for_user?(&1, user))
        |> revoke_records(0)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_token_record(jti) do
    case ProductStore.dispatch(:get, :token, record: %{id: jti}) do
      {:ok, %{projection: projection}} -> Registry.decode(:token, projection)
      {:error, %NotFoundError{}} -> {:error, :token_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_active(%{status: "active", expires_at: %DateTime{} = expires_at} = record) do
    cond do
      present?(Map.get(record, :revoked_at)) -> {:error, :token_revoked}
      DateTime.compare(expires_at, DateTime.utc_now()) == :gt -> :ok
      true -> {:error, :token_expired}
    end
  end

  defp ensure_active(%{status: "active", expires_at: expires_at}) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, datetime, _offset} -> ensure_active(%{status: "active", expires_at: datetime, revoked_at: nil})
      _other -> {:error, :token_invalid}
    end
  end

  defp ensure_active(%{status: "revoked"}), do: {:error, :token_revoked}
  defp ensure_active(_record), do: {:error, :token_invalid}

  defp session_token_for_user?(record, %User{} = user) do
    record[:purpose] == "session" and
      (to_string(record[:user_id]) == to_string(user.id) or to_string(record[:subject]) == to_string(user.email))
  end

  defp revoke_records([], count), do: {:ok, count}

  defp revoke_records([record | rest], count) do
    revoked =
      record
      |> normalize_record_for_write()
      |> Map.put(:revoked_at, DateTime.utc_now())
      |> Map.put(:status, "revoked")
      |> Map.put(:updated_at, DateTime.utc_now())

    case ProductStore.dispatch(:upsert, :token, record: revoked) do
      {:ok, _outcome} -> revoke_records(rest, count + 1)
      {:error, reason} -> {:error, reason}
    end
  end

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

  defp salt(opts), do: Keyword.get(opts, :salt, Application.get_env(:jido_code, :session_token_salt, @default_salt))

  defp ttl_seconds(opts) do
    Keyword.get(opts, :ttl_seconds, Application.get_env(:jido_code, :session_token_ttl_seconds, @default_ttl_seconds))
  end
end
