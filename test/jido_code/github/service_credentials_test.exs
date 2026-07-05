defmodule JidoCode.GitHub.ServiceCredentialsTest do
  # covers: auth.github_service_credentials.secret_ref_names
  # covers: auth.github_service_credentials.login_service_split
  # covers: auth.github_service_credentials.secret_resolution
  use JidoCode.DataCase, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Security.SecretRefs

  @app_env_keys [:github_app_id, :github_app_private_key, :github_webhook_secret, :github_pat]
  @system_env_keys ["GITHUB_APP_ID", "GITHUB_APP_PRIVATE_KEY", "GITHUB_WEBHOOK_SECRET", "GITHUB_PAT"]

  setup do
    setup_store!()

    original_app_env =
      Enum.map(@app_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    original_system_env =
      Enum.map(@system_env_keys, fn key ->
        {key, fetch_system_env(key)}
      end)

    on_exit(fn ->
      Enum.each(original_app_env, fn {key, value} ->
        restore_app_env(key, value)
      end)

      Enum.each(original_system_env, fn {key, value} ->
        restore_system_env(key, value)
      end)
    end)

    Enum.each(@app_env_keys, &Application.delete_env(:jido_code, &1))
    Enum.each(@system_env_keys, &System.delete_env/1)

    :ok
  end

  test "config/0 separates provider-login broker fields from deployment-local service secrets" do
    config = ServiceCredentials.config()

    assert config.provider == :github
    assert config.secret_scope == :integration
    assert config.login_config_resource == JidoCode.AuthProviders.ProviderConfig
    assert config.login_config_fields == [:broker_issuer, :broker_audience, :broker_base_url]
    assert config.service_secret_refs.app_id == "vcs/github/app_id"
    assert config.service_secret_refs.app_private_key == "vcs/github/app_private_key"
    assert config.service_secret_refs.webhook_secret == "vcs/github/webhook_secret"
    assert config.service_secret_refs.pat == "vcs/github/pat"

    github_app_path =
      Enum.find(config.paths, fn path_definition -> path_definition.path == :github_app end)

    assert github_app_path.credential_keys == [:app_id, :app_private_key]
    refute :broker_issuer in github_app_path.credential_keys
  end

  test "resolve/1 prefers root env over encrypted SecretRefs" do
    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: ServiceCredentials.service_secret_ref_name(:pat),
               value: "ghp-db-token",
               source: :onboarding
             })

    System.put_env("GITHUB_PAT", "ghp-env-token")

    assert {:ok, "ghp-env-token", diagnostics} = ServiceCredentials.resolve(:pat)
    assert diagnostics.selected_source == :env
    assert diagnostics.env_var == "GITHUB_PAT"
    assert diagnostics.secret_ref_name == "vcs/github/pat"
    assert is_nil(diagnostics.secret_ref_key_version)
  end

  test "resolve/1 falls back to encrypted SecretRefs when env and app env are absent" do
    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: ServiceCredentials.service_secret_ref_name(:app_private_key),
               value: "-----BEGIN PRIVATE KEY-----test-----END PRIVATE KEY-----",
               source: :rotation
             })

    assert {:ok, value, diagnostics} = ServiceCredentials.resolve(:app_private_key)
    assert value =~ "PRIVATE KEY"
    assert diagnostics.selected_source == :secret_ref
    assert diagnostics.secret_ref_name == "vcs/github/app_private_key"
    assert diagnostics.secret_ref_key_version == 1
    assert diagnostics.secret_ref_source == :rotation
  end

  test "resolve/1 reports secret_unavailable when no deployment-local credential source exists" do
    assert {:error, :secret_unavailable, diagnostics} = ServiceCredentials.resolve(:webhook_secret)
    assert diagnostics.selected_source == :unavailable
    assert diagnostics.secret_ref_name == "vcs/github/webhook_secret"
  end

  defp restore_app_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_app_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp fetch_system_env(key) do
    case System.get_env(key) do
      nil -> :__missing__
      value -> value
    end
  end

  defp restore_system_env(key, :__missing__), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

  defp setup_store! do
    store_name = :"github_service_credentials_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_github_service_credentials/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_app_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end
end
