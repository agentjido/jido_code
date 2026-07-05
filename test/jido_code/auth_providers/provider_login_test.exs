defmodule JidoCode.AuthProviders.ProviderLoginTest do
  # covers: auth.provider_login_flow.local_user_resolution
  # covers: auth.provider_login_flow.local_session_issuance
  # covers: auth.provider_login_flow.provider_neutral_session_service
  use ExUnit.Case, async: false

  alias JidoCode.Accounts.UserIdentityStore
  alias JidoCode.AuthProviders.{ProviderConfigStore, ProviderLogin}
  alias JidoCode.ControlPlane.StoreServer

  setup do
    setup_store!()
  end

  test "sign_in/1 links a broker-validated provider identity and returns a session token" do
    enable_provider_login!(:github, "github.com")

    {:ok, result} =
      ProviderLogin.sign_in(%{
        "provider" => "github",
        "provider_host" => "github.com",
        "provider_subject" => "github-user-1",
        "provider_login" => "octocat",
        "provider_email" => "octocat@example.com",
        "email_verified" => true
      })

    assert result.resolution == :created_user
    assert to_string(result.user.email) == "octocat@example.com"
    assert is_binary(result.token)
    assert result.session_user.__metadata__.token == result.token
    assert result.identity.provider == :github
    assert result.identity.provider_host == "github.com"
    assert result.identity.provider_subject == "github-user-1"

    {:ok, identities} = UserIdentityStore.list_for_user(result.user.id)
    assert Enum.map(identities, & &1.provider_subject) == ["github-user-1"]
  end

  defp enable_provider_login!(provider, provider_host) do
    {:ok, config} =
      ProviderConfigStore.upsert(%{
        provider: provider,
        provider_host: provider_host,
        enabled: true,
        login_enabled: true,
        allowlist_mode: :none,
        allowlist_values: [],
        broker_issuer: "https://broker.example.com",
        broker_audience: "jido-code",
        broker_base_url: "https://broker.example.com"
      })

    config
  end

  defp setup_store! do
    store_name = :"provider_login_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_provider_login/#{store_name}")

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
