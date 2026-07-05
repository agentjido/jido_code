defmodule JidoCode.AuthProviders.ProviderConfigTest do
  # covers: auth.provider_foundation.provider_catalog
  # covers: auth.provider_foundation.provider_login_configuration
  use ExUnit.Case, async: false

  alias JidoCode.AuthProviders.{ProviderConfig, ProviderConfigStore}
  alias JidoCode.ControlPlane.StoreServer

  setup do
    setup_store!()
  end

  test "upsert/1 persists provider-host login configuration" do
    {:ok, config} =
      ProviderConfigStore.upsert(%{
        provider: :github,
        provider_host: "github.com",
        enabled: true,
        login_enabled: true,
        allowlist_mode: :organizations,
        allowlist_values: ["agentjido"],
        broker_issuer: "https://auth.example.com",
        broker_audience: "jido-code",
        broker_base_url: "https://auth.example.com"
      })

    assert %ProviderConfig{} = config
    assert config.provider == :github
    assert config.allowlist_mode == :organizations
    assert config.allowlist_values == ["agentjido"]

    {:ok, persisted} = ProviderConfigStore.get_by_provider_host(:github, "github.com")

    assert persisted.id == config.id
    assert persisted.login_enabled == true
  end

  test "provider config rejects providers outside the initial catalog" do
    assert {:error, {:invalid_provider, :sourcehut}} =
             ProviderConfigStore.upsert(%{
               provider: :sourcehut,
               provider_host: "git.example.com"
             })
  end

  defp setup_store! do
    store_name = :"provider_config_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_provider_config/#{store_name}")

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
