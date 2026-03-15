defmodule JidoCode.SourceProviders do
  @moduledoc """
  Registry for source control service adapters used by setup and automation.
  """

  # covers: source.provider_adapter.provider_catalog
  # covers: source.provider_adapter.placeholder_adapters

  alias JidoCode.SourceProviders.{BitbucketAdapter, GitHubAdapter, GitLabAdapter}

  @providers %{
    github: GitHubAdapter,
    gitlab: GitLabAdapter,
    bitbucket: BitbucketAdapter
  }

  @spec known_providers() :: [atom()]
  def known_providers, do: Map.keys(@providers)

  @spec adapter(atom() | String.t()) :: {:ok, module()} | {:error, :unsupported_provider}
  def adapter(provider) do
    case Map.fetch(@providers, normalize_provider(provider)) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unsupported_provider}
    end
  end

  @spec adapter!(atom() | String.t()) :: module()
  def adapter!(provider) do
    case adapter(provider) do
      {:ok, module} -> module
      {:error, :unsupported_provider} -> raise ArgumentError, "unsupported source provider: #{inspect(provider)}"
    end
  end

  defp normalize_provider(:github), do: :github
  defp normalize_provider(:gitlab), do: :gitlab
  defp normalize_provider(:bitbucket), do: :bitbucket
  defp normalize_provider("github"), do: :github
  defp normalize_provider("gitlab"), do: :gitlab
  defp normalize_provider("bitbucket"), do: :bitbucket
  defp normalize_provider(_provider), do: :unsupported
end
