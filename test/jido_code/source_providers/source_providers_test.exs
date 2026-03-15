defmodule JidoCode.SourceProvidersTest do
  # covers: source.provider_adapter.provider_catalog
  # covers: source.provider_adapter.placeholder_adapters
  use ExUnit.Case, async: true

  alias JidoCode.SourceProviders
  alias JidoCode.SourceProviders.{BitbucketAdapter, GitHubAdapter, GitLabAdapter}

  test "registry resolves supported source provider adapters" do
    assert Enum.sort(SourceProviders.known_providers()) == [:bitbucket, :github, :gitlab]
    assert {:ok, GitHubAdapter} = SourceProviders.adapter(:github)
    assert {:ok, GitLabAdapter} = SourceProviders.adapter("gitlab")
    assert {:ok, BitbucketAdapter} = SourceProviders.adapter(:bitbucket)
    assert {:error, :unsupported_provider} = SourceProviders.adapter(:sourcehut)
  end

  test "placeholder adapters expose explicit not-implemented boundaries" do
    assert GitLabAdapter.path_definitions() == []
    assert BitbucketAdapter.path_definitions() == []

    assert {:error, :unsupported_provider, gitlab_error} =
             GitLabAdapter.resolve_service_credential(:token)

    assert gitlab_error.error_type == "gitlab_service_adapter_not_implemented"

    assert {:error, bitbucket_error} =
             BitbucketAdapter.list_accessible_repositories(:pat, "token", [])

    assert bitbucket_error.error_type == "bitbucket_service_adapter_not_implemented"
  end
end
