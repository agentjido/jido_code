defmodule JidoCode.Accounts.UserIdentityTest do
  # covers: auth.provider_foundation.local_user_identity_mapping
  use JidoCode.DataCase, async: false

  alias JidoCode.Accounts.User
  alias JidoCode.Accounts.UserIdentity
  alias JidoCode.ControlPlane.StoreServer

  setup do
    setup_store!()
  end

  test "provider identities are unique by provider host and subject" do
    user = register_user!("identity-owner")

    {:ok, identity} =
      UserIdentity.create(%{
        user_id: user.id,
        provider: :github,
        provider_host: "github.com",
        provider_subject: "12345",
        provider_login: "octocat",
        provider_email: "octocat@example.com",
        email_verified: true
      })

    assert identity.provider == :github
    assert identity.provider_host == "github.com"

    other_user = register_user!("identity-collision")

    assert {:error, error} =
             UserIdentity.create(%{
               user_id: other_user.id,
               provider: :github,
               provider_host: "github.com",
               provider_subject: "12345"
             })

    assert error.message =~ "has already been taken"
  end

  test "list_for_user/1 returns identities linked to one local user" do
    user = register_user!("identity-list")

    {:ok, _identity} =
      UserIdentity.create(%{
        user_id: user.id,
        provider: :gitlab,
        provider_host: "gitlab.com",
        provider_subject: "gitlab-user-1"
      })

    {:ok, identities} = UserIdentity.list_for_user(%{user_id: user.id})

    assert Enum.map(identities, & &1.provider) == [:gitlab]
  end

  defp register_user!(email_prefix) do
    unique_suffix = System.unique_integer([:positive])
    email = "#{email_prefix}-#{unique_suffix}@example.com"

    {:ok, user} =
      User.provision_from_provider_identity(%{
        email: email,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    user
  end

  defp setup_store! do
    store_name = :"user_identity_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_user_identity/#{store_name}")

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
