defmodule JidoCode.Accounts.SecurityTokens do
  @moduledoc """
  Product-level token and API key status/revocation actions for `/settings/security`.
  """

  # covers: auth.system.revocable_credentials

  alias JidoCode.Accounts.UserStore
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @status_error_recovery_instruction """
  Refresh this screen and retry. If status loading keeps failing, verify database health and continue containment from the security playbook.
  """

  @token_not_found_recovery_instruction """
  Refresh this screen and confirm the token still exists before retrying revocation.
  """

  @token_already_revoked_recovery_instruction """
  Token is already revoked. Validate API callers are now unauthorized and rotate signing credentials if compromise is suspected.
  """

  @token_revocation_failed_recovery_instruction """
  Retry revocation. If retry fails, rotate signing credentials and run manual incident containment from the security playbook.
  """

  @api_key_not_found_recovery_instruction """
  Refresh this screen and confirm the API key still exists before retrying revocation.
  """

  @api_key_already_revoked_recovery_instruction """
  API key is already revoked. Confirm integrations now fail closed and rotate any leaked credentials.
  """

  @api_key_revocation_failed_recovery_instruction """
  Retry API key revocation. If retry fails, disable the affected integration and rotate credentials manually.
  """

  @typedoc """
  Typed revocation/status failure payload with recovery guidance.
  """
  @type typed_error :: %{
          error_type: String.t(),
          message: String.t(),
          recovery_instruction: String.t()
        }

  @typedoc """
  Security status row rendered in `/settings/security`.
  """
  @type credential_status :: %{
          id: String.t(),
          source: :session_token | :api_key,
          status: :active | :expired | :revoked,
          expires_at: DateTime.t(),
          revoked_at: DateTime.t() | nil,
          purpose: String.t() | nil
        }

  @typedoc """
  Revocation audit entry rendered in `/settings/security`.
  """
  @type revocation_audit_entry :: %{
          source: :session_token | :api_key,
          id: String.t(),
          status: :revoked,
          expires_at: DateTime.t(),
          revoked_at: DateTime.t()
        }

  @doc """
  Lists session-token and API key status for an owner account.
  """
  @spec list_owner_credentials(JidoCode.UUID.t() | String.t()) ::
          {:ok, %{tokens: [credential_status()], api_keys: [credential_status()]}}
          | {:error, typed_error()}
  def list_owner_credentials(owner_id) do
    with {:ok, owner_id, owner_subject} <- owner_identity(owner_id),
         {:ok, tokens} <- read_owner_tokens(owner_subject),
         {:ok, api_keys} <- read_owner_api_keys(owner_id) do
      {:ok,
       %{
         tokens: Enum.map(tokens, &to_token_status/1),
         api_keys: Enum.map(api_keys, &to_api_key_status/1)
       }}
    else
      {:error, _reason} ->
        {:error,
         typed_error(
           "token_status_unavailable",
           "Unable to load token and API key status.",
           @status_error_recovery_instruction
         )}
    end
  end

  @doc """
  Revokes a stored session token for the owner account.
  """
  @spec revoke_owner_token(JidoCode.UUID.t() | String.t(), String.t()) ::
          {:ok, revocation_audit_entry()} | {:error, typed_error()}
  def revoke_owner_token(owner_id, token_jti) when is_binary(token_jti) and token_jti != "" do
    with {:ok, _owner_id, owner_subject} <- owner_identity(owner_id),
         {:ok, token} <- fetch_owner_token(owner_subject, token_jti),
         :ok <- ensure_token_revocable(token),
         {:ok, revoked_token} <- revoke_token_record(token) do
      {:ok, to_token_revocation_audit(revoked_token)}
    else
      {:error, :not_found} ->
        {:error,
         typed_error(
           "token_not_found",
           "Token could not be found for this owner.",
           @token_not_found_recovery_instruction
         )}

      {:error, :already_revoked} ->
        {:error,
         typed_error(
           "token_already_revoked",
           "Token is already revoked.",
           @token_already_revoked_recovery_instruction
         )}

      {:error, _reason} ->
        {:error,
         typed_error(
           "token_revocation_failed",
           "Token revocation failed. Token state is unchanged.",
           @token_revocation_failed_recovery_instruction
         )}
    end
  end

  def revoke_owner_token(_owner_id, _token_jti) do
    {:error,
     typed_error(
       "token_revocation_failed",
       "Token revocation failed. Token state is unchanged.",
       @token_revocation_failed_recovery_instruction
     )}
  end

  @doc """
  Revokes an API key for the owner account.
  """
  @spec revoke_owner_api_key(JidoCode.UUID.t() | String.t(), JidoCode.UUID.t() | String.t()) ::
          {:ok, revocation_audit_entry()} | {:error, typed_error()}
  def revoke_owner_api_key(owner_id, api_key_id)
      when is_binary(api_key_id) and api_key_id != "" do
    with {:ok, owner_id, _owner_subject} <- owner_identity(owner_id),
         {:ok, api_key} <- fetch_owner_api_key(owner_id, api_key_id),
         :ok <- ensure_api_key_revocable(api_key),
         {:ok, revoked_api_key} <- revoke_api_key_record(api_key) do
      {:ok, to_api_key_revocation_audit(revoked_api_key)}
    else
      {:error, :not_found} ->
        {:error,
         typed_error(
           "api_key_not_found",
           "API key could not be found for this owner.",
           @api_key_not_found_recovery_instruction
         )}

      {:error, :already_revoked} ->
        {:error,
         typed_error(
           "api_key_already_revoked",
           "API key is already revoked.",
           @api_key_already_revoked_recovery_instruction
         )}

      {:error, _reason} ->
        {:error,
         typed_error(
           "api_key_revocation_failed",
           "API key revocation failed. API key state is unchanged.",
           @api_key_revocation_failed_recovery_instruction
         )}
    end
  end

  def revoke_owner_api_key(_owner_id, _api_key_id) do
    {:error,
     typed_error(
       "api_key_revocation_failed",
       "API key revocation failed. API key state is unchanged.",
       @api_key_revocation_failed_recovery_instruction
     )}
  end

  defp read_owner_tokens(owner_subject) do
    with {:ok, tokens} <- list_records(:token) do
      {:ok,
       tokens
       |> Enum.filter(&(normalize_optional_string(Map.get(&1, :subject)) == owner_subject))
       |> Enum.sort_by(&sort_datetime(Map.get(&1, :updated_at)), {:desc, DateTime})}
    end
  end

  defp read_owner_api_keys(owner_id) do
    with {:ok, api_keys} <- list_records(:api_key) do
      {:ok,
       api_keys
       |> Enum.filter(&(normalize_optional_string(Map.get(&1, :user_id)) == owner_id))
       |> Enum.sort_by(&sort_datetime(Map.get(&1, :expires_at)), {:desc, DateTime})}
    end
  end

  defp fetch_owner_token(owner_subject, token_jti) do
    case get_record(:token, token_jti) do
      {:ok, token} ->
        if normalize_optional_string(Map.get(token, :subject)) == owner_subject do
          {:ok, token}
        else
          {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_owner_api_key(owner_id, api_key_id) do
    case get_record(:api_key, api_key_id) do
      {:ok, api_key} ->
        if normalize_optional_string(Map.get(api_key, :user_id)) == owner_id do
          {:ok, api_key}
        else
          {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_token_revocable(%{} = token) do
    if revoked_token?(token), do: {:error, :already_revoked}, else: :ok
  end

  defp ensure_api_key_revocable(%{} = api_key) do
    if present?(Map.get(api_key, :revoked_at)), do: {:error, :already_revoked}, else: :ok
  end

  defp to_token_status(%{} = token) do
    expires_at = normalize_datetime(Map.get(token, :expires_at)) || DateTime.utc_now()
    revoked_at = normalize_datetime(Map.get(token, :revoked_at)) || normalize_datetime(Map.get(token, :updated_at))
    revoked? = revoked_token?(token)
    expired? = DateTime.compare(expires_at, DateTime.utc_now()) == :lt

    %{
      id: Map.get(token, :token_id) || Map.get(token, :id),
      source: :session_token,
      status: to_status(revoked?, expired?),
      expires_at: expires_at,
      revoked_at: if(revoked?, do: revoked_at, else: nil),
      purpose: Map.get(token, :purpose)
    }
  end

  defp to_api_key_status(%{} = api_key) do
    expires_at = normalize_datetime(Map.get(api_key, :expires_at)) || DateTime.utc_now()
    revoked_at = normalize_datetime(Map.get(api_key, :revoked_at))
    revoked? = not is_nil(revoked_at)
    expired? = DateTime.compare(expires_at, DateTime.utc_now()) == :lt

    %{
      id: Map.get(api_key, :api_key_id) || Map.get(api_key, :id),
      source: :api_key,
      status: to_status(revoked?, expired?),
      expires_at: expires_at,
      revoked_at: revoked_at,
      purpose: nil
    }
  end

  defp to_status(true, _expired?), do: :revoked
  defp to_status(false, true), do: :expired
  defp to_status(false, false), do: :active

  defp owner_identity(owner_id) do
    with {:ok, owner_id} <- normalize_owner_id(owner_id) do
      owner_subject =
        case UserStore.get_by_id(owner_id) do
          {:ok, %{email: email}} -> normalize_optional_string(email) || owner_id
          _other -> owner_id
        end

      {:ok, owner_id, owner_subject}
    end
  end

  defp normalize_owner_id(owner_id) when is_binary(owner_id) and owner_id != "",
    do: {:ok, owner_id}

  defp normalize_owner_id(nil), do: {:error, :owner_not_found}

  defp normalize_owner_id(owner_id) do
    owner_id
    |> to_string()
    |> case do
      "" -> {:error, :owner_not_found}
      normalized_owner_id -> {:ok, normalized_owner_id}
    end
  rescue
    Protocol.UndefinedError -> {:error, :owner_not_found}
  end

  defp to_token_revocation_audit(%{} = token) do
    %{
      source: :session_token,
      id: Map.get(token, :token_id) || Map.get(token, :id),
      status: :revoked,
      expires_at: normalize_datetime(Map.get(token, :expires_at)) || DateTime.utc_now(),
      revoked_at:
        normalize_datetime(Map.get(token, :revoked_at)) ||
          normalize_datetime(Map.get(token, :updated_at)) ||
          DateTime.utc_now()
    }
  end

  defp to_api_key_revocation_audit(%{} = api_key) do
    %{
      source: :api_key,
      id: Map.get(api_key, :api_key_id) || Map.get(api_key, :id),
      status: :revoked,
      expires_at: normalize_datetime(Map.get(api_key, :expires_at)) || DateTime.utc_now(),
      revoked_at: normalize_datetime(Map.get(api_key, :revoked_at)) || DateTime.utc_now()
    }
  end

  defp list_records(record_type) when record_type in [:token, :api_key] do
    case ProductStore.dispatch(:list, record_type, query: %{limit: 500, offset: 0}) do
      {:ok, %{projections: projections}} ->
        records =
          projections
          |> Enum.map(&Registry.decode(record_type, &1))
          |> Enum.flat_map(fn
            {:ok, record} -> [normalize_record(record)]
            {:error, _reason} -> []
          end)

        {:ok, records}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_record(record_type, id) when record_type in [:token, :api_key] and is_binary(id) do
    case ProductStore.dispatch(:get, record_type, record: %{id: id}) do
      {:ok, %{projection: projection}} ->
        with {:ok, record} <- Registry.decode(record_type, projection) do
          {:ok, normalize_record(record)}
        end

      {:error, %NotFoundError{}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp revoke_token_record(%{} = token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    token
    |> normalize_record_for_write()
    |> Map.put(:status, "revoked")
    |> Map.put(:revoked_at, now)
    |> Map.put(:updated_at, now)
    |> upsert_record(:token)
  end

  defp revoke_api_key_record(%{} = api_key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    api_key
    |> normalize_record_for_write()
    |> Map.put(:status, "revoked")
    |> Map.put(:revoked_at, now)
    |> Map.put(:updated_at, now)
    |> upsert_record(:api_key)
  end

  defp upsert_record(record, record_type) do
    case ProductStore.dispatch(:upsert, record_type, record: record) do
      {:ok, %{record: saved_record}} -> {:ok, normalize_record(saved_record)}
      {:ok, _outcome} -> {:ok, normalize_record(record)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_record(record) when is_map(record) do
    record
    |> Map.put_new(:token_id, Map.get(record, :id))
    |> Map.put_new(:api_key_id, Map.get(record, :id))
  end

  defp normalize_record_for_write(record) do
    record
    |> Map.drop([:record_type, :subject_iri])
    |> decode_metadata()
  end

  defp decode_metadata(record) do
    Map.update(record, :metadata, %{}, &decode_json_map/1)
  end

  defp decode_json_map(value) when is_map(value), do: value

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(_value), do: %{}

  defp revoked_token?(%{} = token) do
    Map.get(token, :status) == "revoked" or
      Map.get(token, :purpose) == "revocation" or
      present?(Map.get(token, :revoked_at))
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp sort_datetime(value), do: normalize_datetime(value) || ~U[0000-01-01 00:00:00Z]

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp typed_error(error_type, message, recovery_instruction) do
    %{
      error_type: error_type,
      message: message,
      recovery_instruction: recovery_instruction
    }
  end
end
