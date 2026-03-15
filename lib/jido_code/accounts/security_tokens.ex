defmodule JidoCode.Accounts.SecurityTokens do
  @moduledoc """
  Product-level token and API key status/revocation actions for `/settings/security`.
  """
  # covers: auth.system.revocable_credentials

  require Ash.Query

  alias AshAuthentication
  alias JidoCode.Accounts
  alias JidoCode.Accounts.{ApiKey, Token, User}

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
  @spec list_owner_credentials(Ecto.UUID.t() | String.t()) ::
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
  @spec revoke_owner_token(Ecto.UUID.t() | String.t(), String.t()) ::
          {:ok, revocation_audit_entry()} | {:error, typed_error()}
  def revoke_owner_token(owner_id, token_jti) when is_binary(token_jti) and token_jti != "" do
    with {:ok, _owner_id, owner_subject} <- owner_identity(owner_id),
         {:ok, token} <- fetch_owner_token(owner_subject, token_jti),
         :ok <- ensure_token_revocable(token),
         {:ok, revoked_token} <-
           Ash.update(token, %{}, action: :revoke, domain: Accounts, authorize?: false) do
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
  @spec revoke_owner_api_key(Ecto.UUID.t() | String.t(), Ecto.UUID.t() | String.t()) ::
          {:ok, revocation_audit_entry()} | {:error, typed_error()}
  def revoke_owner_api_key(owner_id, api_key_id)
      when is_binary(api_key_id) and api_key_id != "" do
    with {:ok, owner_id, _owner_subject} <- owner_identity(owner_id),
         {:ok, api_key} <- fetch_owner_api_key(owner_id, api_key_id),
         :ok <- ensure_api_key_revocable(api_key),
         {:ok, revoked_api_key} <-
           Ash.update(api_key, %{}, action: :revoke, domain: Accounts, authorize?: false) do
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
    Token
    |> Ash.Query.filter(subject == ^owner_subject)
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.read(domain: Accounts, authorize?: false)
  end

  defp read_owner_api_keys(owner_id) do
    ApiKey
    |> Ash.Query.filter(user_id == ^owner_id)
    |> Ash.Query.sort(expires_at: :desc)
    |> Ash.read(domain: Accounts, authorize?: false)
  end

  defp fetch_owner_token(owner_subject, token_jti) do
    query =
      Token
      |> Ash.Query.filter(subject == ^owner_subject and jti == ^token_jti)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: Accounts, authorize?: false) do
      {:ok, [token | _]} -> {:ok, token}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_owner_api_key(owner_id, api_key_id) do
    query =
      ApiKey
      |> Ash.Query.filter(user_id == ^owner_id and id == ^api_key_id)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: Accounts, authorize?: false) do
      {:ok, [api_key | _]} -> {:ok, api_key}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_token_revocable(%Token{purpose: "revocation"}), do: {:error, :already_revoked}
  defp ensure_token_revocable(%Token{}), do: :ok

  defp ensure_api_key_revocable(%ApiKey{revoked_at: nil}), do: :ok
  defp ensure_api_key_revocable(%ApiKey{}), do: {:error, :already_revoked}

  defp to_token_status(%Token{} = token) do
    revoked? = token.purpose == "revocation"
    expired? = DateTime.compare(token.expires_at, DateTime.utc_now()) == :lt

    %{
      id: token.jti,
      source: :session_token,
      status: to_status(revoked?, expired?),
      expires_at: token.expires_at,
      revoked_at: if(revoked?, do: token.updated_at, else: nil),
      purpose: token.purpose
    }
  end

  defp to_api_key_status(%ApiKey{} = api_key) do
    revoked? = not is_nil(api_key.revoked_at)
    expired? = DateTime.compare(api_key.expires_at, DateTime.utc_now()) == :lt

    %{
      id: api_key.id,
      source: :api_key,
      status: to_status(revoked?, expired?),
      expires_at: api_key.expires_at,
      revoked_at: api_key.revoked_at,
      purpose: nil
    }
  end

  defp to_status(true, _expired?), do: :revoked
  defp to_status(false, true), do: :expired
  defp to_status(false, false), do: :active

  defp owner_identity(owner_id) do
    with {:ok, owner_id} <- normalize_owner_id(owner_id) do
      {:ok, owner_id, AshAuthentication.user_to_subject(%User{id: owner_id})}
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

  defp to_token_revocation_audit(%Token{} = token) do
    %{
      source: :session_token,
      id: token.jti,
      status: :revoked,
      expires_at: token.expires_at,
      revoked_at: token.updated_at
    }
  end

  defp to_api_key_revocation_audit(%ApiKey{} = api_key) do
    %{
      source: :api_key,
      id: api_key.id,
      status: :revoked,
      expires_at: api_key.expires_at,
      revoked_at: api_key.revoked_at
    }
  end

  defp typed_error(error_type, message, recovery_instruction) do
    %{
      error_type: error_type,
      message: message,
      recovery_instruction: recovery_instruction
    }
  end
end
