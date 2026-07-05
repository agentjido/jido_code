defmodule JidoCode.AuthProviders.LoginPolicyTest do
  # covers: auth.provider_login_policy.provider_enablement
  # covers: auth.provider_login_policy.allowlist_evaluation
  # covers: auth.provider_login_policy.provider_neutral_logic
  use ExUnit.Case, async: false

  alias JidoCode.AuthProviders.{LoginPolicy, ProviderConfig, ProviderConfigStore}
  alias JidoCode.ControlPlane.StoreServer

  setup do
    setup_store!()
  end

  test "allows login when provider login is enabled without an allowlist" do
    enable_provider!(:github, "github.com", allowlist_mode: :none)

    assert {:ok, %ProviderConfig{} = config} =
             LoginPolicy.authorize(%{
               provider: :github,
               provider_host: "github.com",
               provider_login: "octocat"
             })

    assert config.login_enabled == true
  end

  test "rejects login when provider login is disabled" do
    enable_provider!(:github, "github.com", login_enabled: false)

    assert {:error, error} =
             LoginPolicy.authorize(%{
               provider: :github,
               provider_host: "github.com",
               provider_login: "octocat"
             })

    assert error.error_type == "provider_login_disabled"
  end

  test "enforces provider-neutral allowlist modes" do
    enable_provider!(:github, "github.com", allowlist_mode: :users, allowlist_values: ["octocat"])
    enable_provider!(:gitlab, "gitlab.com", allowlist_mode: :organizations, allowlist_values: ["agentjido"])
    enable_provider!(:bitbucket, "bitbucket.org", allowlist_mode: :workspaces, allowlist_values: ["epic"])

    assert {:ok, _config} =
             LoginPolicy.authorize(%{
               provider: :github,
               provider_host: "github.com",
               provider_login: "octocat"
             })

    assert {:ok, _config} =
             LoginPolicy.authorize(%{
               provider: :gitlab,
               provider_host: "gitlab.com",
               organizations: ["agentjido"]
             })

    assert {:ok, _config} =
             LoginPolicy.authorize(%{
               provider: :bitbucket,
               provider_host: "bitbucket.org",
               workspaces: ["epic"]
             })

    assert {:error, github_error} =
             LoginPolicy.authorize(%{
               provider: :github,
               provider_host: "github.com",
               provider_login: "someone-else"
             })

    assert github_error.error_type == "provider_identity_not_allowlisted"
  end

  test "team and group allowlists are compared case-insensitively" do
    enable_provider!(:github, "enterprise.github.example",
      allowlist_mode: :teams,
      allowlist_values: ["agentjido/platform"]
    )

    enable_provider!(:gitlab, "gitlab.internal", allowlist_mode: :groups, allowlist_values: ["infra/team"])

    assert {:ok, _config} =
             LoginPolicy.authorize(%{
               provider: :github,
               provider_host: "enterprise.github.example",
               teams: ["AgentJido/Platform"]
             })

    assert {:ok, _config} =
             LoginPolicy.authorize(%{
               provider: :gitlab,
               provider_host: "gitlab.internal",
               groups: ["INFRA/TEAM"]
             })
  end

  defp enable_provider!(provider, provider_host, overrides) do
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
    store_name = :"login_policy_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_login_policy/#{store_name}")

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
