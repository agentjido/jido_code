defmodule JidoCode.Accounts.ProviderIdentityLinkerTest do
  # covers: auth.provider_identity_linking.existing_identity_reuse
  # covers: auth.provider_identity_linking.verified_email_link
  # covers: auth.provider_identity_linking.auto_create_local_user
  # covers: auth.provider_identity_linking.auth_timestamps
  use JidoCode.DataCase, async: true

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy
  alias JidoCode.Accounts.ProviderIdentityLinker
  alias JidoCode.Accounts.User
  alias JidoCode.Accounts.UserIdentity

  @initial_auth_at ~U[2026-03-15 16:00:00.000000Z]
  @follow_up_auth_at ~U[2026-03-15 17:00:00.000000Z]

  test "reuses an existing provider identity and refreshes the last authenticated timestamp" do
    user = register_user!("provider-existing")

    {:ok, identity} =
      UserIdentity.create(
        %{
          user_id: user.id,
          provider: :github,
          provider_host: "github.com",
          provider_subject: "provider-user-1",
          provider_login: "existing-login",
          provider_email: user.email,
          email_verified: true,
          first_authenticated_at: @initial_auth_at,
          last_authenticated_at: @initial_auth_at
        },
        authorize?: false
      )

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

    identities =
      UserIdentity.list_for_user(%{user_id: created_result.user.id}, authorize?: false)
      |> elem(1)

    assert length(identities) == 2
    assert Enum.sort(Enum.map(identities, & &1.provider)) == [:bitbucket, :github]

    assert {:ok, %User{} = same_user} = User.get_by_email(%{email: email}, authorize?: false)
    assert same_user.id == created_result.user.id
  end

  defp register_user!(email_prefix) do
    unique_suffix = System.unique_integer([:positive])
    email = "#{email_prefix}-#{unique_suffix}@example.com"
    password = "provider-password-123"
    strategy = Info.strategy!(User, :password)

    {:ok, user} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    user
  end
end
