defmodule JidoCode.SourceProviders.BitbucketAdapter do
  @moduledoc """
  Placeholder adapter for future Bitbucket service integration.
  """

  # covers: source.provider_adapter.placeholder_adapters

  @behaviour JidoCode.SourceProviders.Adapter

  @impl true
  def provider, do: :bitbucket

  @impl true
  def config, do: %{provider: :bitbucket, paths: []}

  @impl true
  def path_definitions, do: []

  @impl true
  def resolve_service_credential(_credential) do
    {:error, :unsupported_provider,
     %{
       error_type: "bitbucket_service_adapter_not_implemented",
       detail: "Bitbucket service credentials are not implemented yet.",
       remediation: "Use GitHub integration until Bitbucket service support is added."
     }}
  end

  @impl true
  def resolve_api_token(_definition), do: nil

  @impl true
  def list_accessible_repositories(_path, _token, _opts) do
    {:error,
     %{
       error_type: "bitbucket_service_adapter_not_implemented",
       detail: "Bitbucket repository access checks are not implemented yet.",
       remediation: "Use GitHub integration until Bitbucket service support is added."
     }}
  end
end
