defmodule JidoCode.AuthProviders.LoginPolicyTest do
  # covers: auth.provider_login_policy.provider_enablement
  # covers: auth.provider_login_policy.allowlist_evaluation
  # covers: auth.provider_login_policy.provider_neutral_logic
  use JidoCode.DataCase, async: true

  alias JidoCode.AuthProviders.LoginPolicy
  alias JidoCode.AuthProviders.ProviderConfig

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

    {:ok, config} = ProviderConfig.upsert(params, authorize?: false)
    config
  end
end
