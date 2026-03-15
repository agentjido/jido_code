defmodule JidoCode.Accounts.UserIdentityTest do
  # covers: auth.provider_foundation.local_user_identity_mapping
  use JidoCode.DataCase, async: true

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Accounts.UserIdentity

  test "provider identities are unique by provider host and subject" do
    user = register_user!("identity-owner")

    {:ok, identity} =
      Ash.create(
        UserIdentity,
        %{
          user_id: user.id,
          provider: :github,
          provider_host: "github.com",
          provider_subject: "12345",
          provider_login: "octocat",
          provider_email: "octocat@example.com",
          email_verified: true
        },
        domain: Accounts,
        authorize?: false
      )

    assert identity.provider == :github
    assert identity.provider_host == "github.com"

    other_user = register_user!("identity-collision")

    assert {:error, error} =
             Ash.create(
               UserIdentity,
               %{
                 user_id: other_user.id,
                 provider: :github,
                 provider_host: "github.com",
                 provider_subject: "12345"
               },
               domain: Accounts,
               authorize?: false
             )

    assert Exception.message(error) =~ "has already been taken"
  end

  test "list_for_user/1 returns identities linked to one local user" do
    user = register_user!("identity-list")

    {:ok, _identity} =
      Ash.create(
        UserIdentity,
        %{
          user_id: user.id,
          provider: :gitlab,
          provider_host: "gitlab.com",
          provider_subject: "gitlab-user-1"
        },
        domain: Accounts,
        authorize?: false
      )

    {:ok, identities} = UserIdentity.list_for_user(%{user_id: user.id}, authorize?: false)

    assert Enum.map(identities, & &1.provider) == [:gitlab]
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
