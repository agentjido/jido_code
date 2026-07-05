defmodule JidoCode.Accounts.ProviderIdentityLinkerTest do
  # covers: auth.provider_identity_linking.existing_identity_reuse
  # covers: auth.provider_identity_linking.verified_email_link
  # covers: auth.provider_identity_linking.auto_create_local_user
  # covers: auth.provider_identity_linking.auth_timestamps
  # covers: auth.provider_login_policy.blocked_before_linking
  use ExUnit.Case, async: false

  alias JidoCode.Accounts.{ProviderIdentityLinker, User, UserIdentityStore, UserStore}
  alias JidoCode.AuthProviders.ProviderConfigStore
  alias JidoCode.ControlPlane.StoreServer

  @initial_auth_at ~U[2026-03-15 16:00:00.000000Z]
  @follow_up_auth_at ~U[2026-03-15 17:00:00.000000Z]

  setup do
    setup_store!()
  end

  test "reuses an existing provider identity and refreshes the last authenticated timestamp" do
    enable_provider!(:github, "github.com")
    user = register_user!("provider-existing")

    {:ok, identity} =
      UserIdentityStore.upsert(%{
        user_id: user.id,
        provider: :github,
        provider_host: "github.com",
        provider_subject: "provider-user-1",
        provider_login: "existing-login",
        provider_email: user.email,
        email_verified: true,
        first_authenticated_at: @initial_auth_at,
        last_authenticated_at: @initial_auth_at
      })

    {:ok, result} =
      ProviderIdentityLinker.link(%{
        provider: :github,
        provider_host: "github.com",
        provider_subject: "provider-user-1",
        provider_login: "updated-login",
        provider_email: user.email,
        email_verified: true,
        authenticated_at: @follow_up_auth_at
      })

    assert result.resolution == :existing_identity
    assert result.user.id == user.id
    assert result.identity.id == identity.id
    assert result.identity.provider_login == "updated-login"
    assert result.identity.first_authenticated_at == @initial_auth_at
    assert result.identity.last_authenticated_at == @follow_up_auth_at
  end

  test "links a new provider subject to an existing user when the provider email is verified" do
    enable_provider!(:gitlab, "gitlab.com")
    user = register_user!("provider-link-email")

    {:ok, result} =
      ProviderIdentityLinker.link(%{
        provider: :gitlab,
        provider_host: "gitlab.com",
        provider_subject: "gitlab-user-1",
        provider_login: "gitlab-user",
        provider_email: user.email,
        email_verified: true,
        authenticated_at: @follow_up_auth_at
      })

    assert result.resolution == :linked_by_email
    assert result.user.id == user.id
    assert result.identity.user_id == user.id
    assert result.identity.first_authenticated_at == @follow_up_auth_at
    assert result.identity.last_authenticated_at == @follow_up_auth_at
  end

  test "auto-creates a local user once and links later verified identities to that same user" do
    enable_provider!(:github, "github.com")
    enable_provider!(:bitbucket, "bitbucket.org")
    email = "provider-created@example.com"

    {:ok, created_result} =
      ProviderIdentityLinker.link(%{
        provider: :github,
        provider_host: "github.com",
        provider_subject: "github-user-a",
        provider_login: "octocat-a",
        provider_email: email,
        email_verified: true,
        authenticated_at: @initial_auth_at
      })

    assert created_result.resolution == :created_user
    assert to_string(created_result.user.email) == email
    assert created_result.user.confirmed_at == @initial_auth_at
    assert created_result.identity.first_authenticated_at == @initial_auth_at

    {:ok, linked_result} =
      ProviderIdentityLinker.link(%{
        provider: :bitbucket,
        provider_host: "bitbucket.org",
        provider_subject: "bitbucket-user-b",
        provider_login: "octocat-b",
        provider_email: email,
        email_verified: true,
        authenticated_at: @follow_up_auth_at
      })

    assert linked_result.resolution == :linked_by_email
    assert linked_result.user.id == created_result.user.id

    {:ok, identities} = UserIdentityStore.list_for_user(created_result.user.id)

    assert length(identities) == 2
    assert Enum.sort(Enum.map(identities, & &1.provider)) == [:bitbucket, :github]

    assert {:ok, %User{} = same_user} = UserStore.get_by_email(email)
    assert same_user.id == created_result.user.id
  end

  test "blocked provider identities fail before local account creation" do
    {:ok, _config} =
      ProviderConfigStore.upsert(%{
        provider: :github,
        provider_host: "github.com",
        enabled: true,
        login_enabled: true,
        allowlist_mode: :organizations,
        allowlist_values: ["agentjido"]
      })

    assert {:error, error} =
             ProviderIdentityLinker.link(%{
               provider: :github,
               provider_host: "github.com",
               provider_subject: "blocked-user",
               provider_login: "blocked-user",
               provider_email: "blocked@example.com",
               email_verified: true,
               organizations: ["different-org"],
               authenticated_at: @initial_auth_at
             })

    assert error.error_type == "provider_identity_not_allowlisted"
    assert {:ok, nil} = UserStore.get_by_email("blocked@example.com")
  end

  defp register_user!(email_prefix) do
    unique_suffix = System.unique_integer([:positive])
    email = "#{email_prefix}-#{unique_suffix}@example.com"

    {:ok, user} =
      UserStore.upsert(%{
        email: email,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        is_admin: false
      })

    user
  end

  defp enable_provider!(provider, provider_host, overrides \\ []) do
    params =
      %{
        provider: provider,
        provider_host: provider_host,
        enabled: true,
        login_enabled: true,
        allowlist_mode: :none,
        allowlist_values: []
      }
      |> Map.merge(Enum.into(overrides, %{}))

    {:ok, config} = ProviderConfigStore.upsert(params)
    config
  end

  defp setup_store! do
    store_name = :"provider_identity_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_provider_identity/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
