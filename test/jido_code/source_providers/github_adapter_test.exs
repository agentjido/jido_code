defmodule JidoCode.SourceProviders.GitHubAdapterTest do
  # covers: source.provider_adapter.behavior_contract
  # covers: source.provider_adapter.github_adapter
  # covers: source.provider_adapter.github_app_preferred
  use ExUnit.Case, async: false

  alias JidoCode.SourceProviders.GitHubAdapter

  @app_env_keys [:github_app_installation_token]
  @system_env_keys ["GITHUB_APP_INSTALLATION_TOKEN"]

  setup do
    original_app_env =
      Map.new(@app_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    original_system_env =
      Map.new(@system_env_keys, fn key ->
        value = System.get_env(key)
        {key, if(value == nil, do: :__missing__, else: value)}
      end)

    original_client = Application.get_env(:jido_code, :setup_github_http_client, :__missing__)
    original_options = Application.get_env(:jido_code, :setup_github_http_client_options, :__missing__)

    on_exit(fn ->
      Enum.each(original_app_env, fn {key, value} ->
        restore_app_env(key, value)
      end)

      Enum.each(original_system_env, fn {key, value} ->
        restore_system_env(key, value)
      end)

      restore_app_env(:setup_github_http_client, original_client)
      restore_app_env(:setup_github_http_client_options, original_options)
    end)

    :ok
  end

  test "path_definitions keeps GitHub App ahead of PAT fallback" do
    assert [%{path: :github_app}, %{path: :pat}] = GitHubAdapter.path_definitions()
  end

  test "resolve_api_token uses deployment-local GitHub App installation token sources" do
    [github_app_definition | _rest] = GitHubAdapter.path_definitions()

    System.put_env("GITHUB_APP_INSTALLATION_TOKEN", "installation-token-env")
    assert GitHubAdapter.resolve_api_token(github_app_definition) == "installation-token-env"

    System.delete_env("GITHUB_APP_INSTALLATION_TOKEN")
    Application.put_env(:jido_code, :github_app_installation_token, "installation-token-app")

    assert GitHubAdapter.resolve_api_token(github_app_definition) == "installation-token-app"
  end

  test "list_accessible_repositories delegates through the adapter boundary" do
    Application.put_env(:jido_code, :setup_github_http_client_options, base_url: "https://github.example")

    Application.put_env(:jido_code, :setup_github_http_client, fn auth_mode, token, opts ->
      send(self(), {:adapter_request, auth_mode, token, opts})

      {:ok,
       [
         %{full_name: "owner/repo-one", owner: "owner", name: "repo-one"}
       ]}
    end)

    assert {:ok, [%{full_name: "owner/repo-one"}]} =
             GitHubAdapter.list_accessible_repositories(
               :github_app,
               "installation-token",
               owner_context: "owner@example.com"
             )

    assert_receive {:adapter_request, :github_app, "installation-token", opts}
    assert opts[:base_url] == "https://github.example"
    assert opts[:owner_context] == "owner@example.com"
  end

  defp restore_app_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_app_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp restore_system_env(key, :__missing__), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
