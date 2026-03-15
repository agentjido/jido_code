defmodule JidoCode.AuthProviders.ProviderConfigTest do
  # covers: auth.provider_foundation.provider_catalog
  # covers: auth.provider_foundation.provider_login_configuration
  use JidoCode.DataCase, async: true

  alias JidoCode.AuthProviders.ProviderConfig

  test "upsert/1 persists provider-host login configuration" do
    {:ok, config} =
      ProviderConfig.upsert(
        %{
          provider: :github,
          provider_host: "github.com",
          enabled: true,
          login_enabled: true,
          allowlist_mode: :organizations,
          allowlist_values: ["agentjido"],
          broker_issuer: "https://auth.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://auth.example.com"
        },
        authorize?: false
      )

    assert config.provider == :github
    assert config.allowlist_mode == :organizations
    assert config.allowlist_values == ["agentjido"]

    {:ok, persisted} =
      ProviderConfig.get_by_provider_host(:github, "github.com", authorize?: false)

    assert persisted.id == config.id
    assert persisted.login_enabled == true
  end

  test "provider config rejects providers outside the initial catalog" do
    assert {:error, error} =
             ProviderConfig.create(
               %{
                 provider: :sourcehut,
                 provider_host: "git.example.com"
               },
               authorize?: false
             )

    assert Exception.message(error) =~ "must be one of"
  end
end
