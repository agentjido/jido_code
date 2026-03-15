defmodule JidoCode.Accounts.ProviderIdentityLinker do
  # covers: auth.provider_identity_linking.existing_identity_reuse
  # covers: auth.provider_identity_linking.verified_email_link
  # covers: auth.provider_identity_linking.auto_create_local_user
  # covers: auth.provider_identity_linking.auth_timestamps
  # covers: auth.provider_login_policy.blocked_before_linking
  require Ash.Query

  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Accounts.UserIdentity
  alias JidoCode.AuthProviders.LoginPolicy

  @type resolution :: :existing_identity | :linked_by_email | :created_user

  @type result :: %{
          resolution: resolution(),
          user: User.t(),
          identity: UserIdentity.t()
        }

  def link(params, opts \\ [])
  @spec link(map(), Keyword.t()) :: {:ok, result()} | {:error, term()}
  def link(params, opts) when is_map(params) do
    with {:ok, input} <- normalize_input(params),
         :ok <- authorize_provider_login(input, opts),
         {:ok, result} <- link_identity(input, opts) do
      {:ok, result}
    end
  end

  def link(_params, _opts), do: {:error, :invalid_provider_identity_input}

  defp authorize_provider_login(input, opts) do
    if Keyword.get(opts, :skip_login_policy?, false) do
      :ok
    else
      do_authorize_provider_login(input)
    end
  end

  defp do_authorize_provider_login(input) do
    case LoginPolicy.authorize(input) do
      {:ok, _config} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp link_identity(input, opts) do
    case find_identity(input.provider, input.provider_host, input.provider_subject) do
      {:ok, %UserIdentity{} = identity} ->
        refresh_existing_identity(identity, input)

      {:ok, nil} ->
        resolve_by_email_or_create(input, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refresh_existing_identity(%UserIdentity{} = identity, input) do
    with {:ok, updated_identity} <- update_identity(identity, input),
         {:ok, %User{} = user} <- load_user(updated_identity.user_id) do
      {:ok, %{resolution: :existing_identity, user: user, identity: updated_identity}}
    end
  end

  defp resolve_by_email_or_create(input, opts) do
    case verified_email_user(input.provider_email, input.email_verified) do
      {:ok, %User{} = user} ->
        attach_identity(user, input, :linked_by_email)

      {:ok, nil} ->
        with {:ok, %User{} = user} <- create_user(input, opts) do
          attach_identity(user, input, :created_user)
        else
          {:error, _reason} = error ->
            recover_or_return_create_error(input, opts, error)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_or_return_create_error(input, opts, error) do
    case verified_email_user(input.provider_email, input.email_verified) do
      {:ok, %User{} = user} ->
        attach_identity(user, input, :linked_by_email)

      {:ok, nil} ->
        case find_identity(input.provider, input.provider_host, input.provider_subject) do
          {:ok, %UserIdentity{} = identity} ->
            refresh_existing_identity(identity, input)

          {:ok, nil} ->
            maybe_retry_unverified_email_create(input, opts, error)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_retry_unverified_email_create(input, _opts, error) do
    case {input.provider_email, input.email_verified} do
      {email, false} when is_binary(email) ->
        with {:ok, %User{} = user} <- find_user_by_email(email),
             {:ok, result} <- attach_identity(user, input, :linked_by_email) do
          {:ok, result}
        else
          _other -> error
        end

      _other ->
        error
    end
  end

  defp attach_identity(%User{} = user, input, resolution) do
    case create_identity(user, input) do
      {:ok, %UserIdentity{} = identity} ->
        {:ok, %{resolution: resolution, user: user, identity: identity}}

      {:error, _reason} ->
        case find_identity(input.provider, input.provider_host, input.provider_subject) do
          {:ok, %UserIdentity{} = identity} ->
            refresh_existing_identity(identity, input)

          {:ok, nil} = not_found ->
            not_found

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp create_identity(%User{} = user, input) do
    UserIdentity.create(
      %{
        user_id: user.id,
        provider: input.provider,
        provider_host: input.provider_host,
        provider_subject: input.provider_subject,
        provider_login: input.provider_login,
        provider_email: input.provider_email,
        email_verified: input.email_verified,
        first_authenticated_at: input.authenticated_at,
        last_authenticated_at: input.authenticated_at
      },
      authorize?: false
    )
  end

  defp update_identity(%UserIdentity{} = identity, input) do
    update_params = %{
      provider_login: input.provider_login,
      provider_email: input.provider_email,
      email_verified: input.email_verified,
      last_authenticated_at: input.authenticated_at
    }

    update_params =
      if is_nil(identity.first_authenticated_at) do
        Map.put(update_params, :first_authenticated_at, input.authenticated_at)
      else
        update_params
      end

    UserIdentity.update(identity, update_params, authorize?: false)
  end

  defp create_user(input, _opts) do
    case input.provider_email do
      email when is_binary(email) ->
        confirmed_at =
          if input.email_verified do
            input.authenticated_at
          else
            nil
          end

        User.provision_from_provider_identity(
          %{
            email: email,
            confirmed_at: confirmed_at
          },
          authorize?: false
        )

      _other ->
        {:error, :provider_email_required_for_auto_create}
    end
  end

  defp verified_email_user(email, true) when is_binary(email) do
    find_user_by_email(email)
  end

  defp verified_email_user(_email, _email_verified), do: {:ok, nil}

  defp load_user(user_id) do
    case Ash.get(User, user_id, domain: Accounts, authorize?: false) do
      {:ok, %User{} = user} -> {:ok, user}
      {:ok, nil} -> {:error, :linked_user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_identity(provider, provider_host, provider_subject) do
    UserIdentity
    |> Ash.Query.filter(
      provider == ^provider and provider_host == ^provider_host and provider_subject == ^provider_subject
    )
    |> Ash.read_one(domain: Accounts, authorize?: false)
  end

  defp find_user_by_email(email) do
    User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one(domain: Accounts, authorize?: false)
  end

  defp normalize_input(params) do
    authenticated_at =
      params
      |> map_get(:authenticated_at, "authenticated_at")
      |> normalize_authenticated_at()

    with {:ok, provider} <- fetch_required(params, :provider, "provider"),
         {:ok, provider_host} <- fetch_required(params, :provider_host, "provider_host"),
         {:ok, provider_subject} <- fetch_required(params, :provider_subject, "provider_subject") do
      {:ok,
       %{
         provider: provider,
         provider_host: provider_host,
         provider_subject: provider_subject,
         provider_login: optional_trimmed(params, :provider_login, "provider_login"),
         provider_email: params |> map_get(:provider_email, "provider_email") |> normalize_optional_email(),
         email_verified: map_get(params, :email_verified, "email_verified") || false,
         organizations: normalize_string_list(map_get(params, :organizations, "organizations")),
         teams: normalize_string_list(map_get(params, :teams, "teams")),
         groups: normalize_string_list(map_get(params, :groups, "groups")),
         workspaces: normalize_string_list(map_get(params, :workspaces, "workspaces")),
         authenticated_at: authenticated_at
       }}
    end
  end

  defp fetch_required(params, atom_key, string_key) do
    case optional_trimmed(params, atom_key, string_key) do
      nil -> {:error, {:missing_required_field, atom_key}}
      value -> {:ok, value}
    end
  end

  defp optional_trimmed(params, atom_key, string_key) do
    params
    |> map_get(atom_key, string_key)
    |> case do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end

      value ->
        value
    end
  end

  defp normalize_optional_email(nil), do: nil
  defp normalize_optional_email(""), do: nil
  defp normalize_optional_email(email) when is_binary(email), do: email |> String.trim() |> blank_to_nil()
  defp normalize_optional_email(email), do: email |> to_string() |> normalize_optional_email()

  defp normalize_string_list(nil), do: []

  defp normalize_string_list(values) when is_list(values),
    do: values |> Enum.map(&normalize_optional_email/1) |> Enum.reject(&is_nil/1)

  defp normalize_string_list(value), do: value |> List.wrap() |> normalize_string_list()

  defp normalize_authenticated_at(%DateTime{} = authenticated_at),
    do: DateTime.truncate(authenticated_at, :microsecond)

  defp normalize_authenticated_at(nil), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp normalize_authenticated_at(_other), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp map_get(map, atom_key, string_key) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
