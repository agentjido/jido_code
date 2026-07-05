defmodule JidoCode.GitHub.RepoStore do
  @moduledoc """
  Store-backed GitHub repository anchors.

  This facade keeps the legacy `JidoCode.GitHub.Repo` projection shape at product
  call sites while source identity and repository settings are persisted through
  the embedded control-plane stores.
  """

  alias JidoCode.Control.{ManagedRepo, ManagedRepoStore, RepoBridge, SourceRepo, SourceRepoStore}
  alias JidoCode.ControlPlane.Store.ActorContext
  alias JidoCode.GitHub.Repo

  @github_settings_key "github_repo"
  @webhook_secret_placeholder "__managed_by_secret_ref__"

  @spec list(keyword()) :: {:ok, [Repo.t()]} | {:error, term()}
  def list(opts \\ []) do
    opts = store_opts(opts)

    with {:ok, managed_repos} <- ManagedRepoStore.list(opts),
         {:ok, source_repos} <- SourceRepoStore.list(opts) do
      source_by_id = Map.new(source_repos, &{&1.id, &1})

      repos =
        managed_repos
        |> Enum.flat_map(fn managed_repo ->
          case Map.get(source_by_id, managed_repo.source_repo_id) do
            %SourceRepo{provider: :github} = source_repo ->
              if deleted?(managed_repo), do: [], else: [to_repo(managed_repo, source_repo)]

            _other ->
              []
          end
        end)
        |> Enum.sort_by(&String.downcase(&1.full_name || ""))

      {:ok, repos}
    end
  end

  @spec get_by_id(String.t(), keyword()) :: {:ok, Repo.t() | nil} | {:error, term()}
  def get_by_id(id, opts \\ [])

  def get_by_id(id, opts) when is_binary(id) and id != "" do
    opts = store_opts(opts)

    case ManagedRepoStore.get_by_id(id, opts) do
      {:ok, %ManagedRepo{} = managed_repo} ->
        repo_for_managed_repo(managed_repo, opts)

      {:ok, nil} ->
        with {:ok, %SourceRepo{} = source_repo} <- SourceRepoStore.get_by_id(id, opts),
             {:ok, %ManagedRepo{} = managed_repo} <- ManagedRepoStore.get_by_source_repo_id(source_repo.id, opts) do
          if deleted?(managed_repo), do: {:ok, nil}, else: {:ok, to_repo(managed_repo, source_repo)}
        else
          {:ok, nil} -> {:ok, nil}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_by_id(_id, _opts), do: {:ok, nil}

  @spec get_by_id!(String.t(), keyword()) :: Repo.t()
  def get_by_id!(id, opts \\ []) do
    case get_by_id(id, opts) do
      {:ok, %Repo{} = repo} -> repo
      {:ok, nil} -> raise KeyError, key: id, term: Repo
      {:error, reason} -> raise RuntimeError, "GitHub repo lookup failed: #{inspect(reason)}"
    end
  end

  @spec get_by_full_name(String.t(), keyword()) :: {:ok, Repo.t() | nil} | {:error, term()}
  def get_by_full_name(full_name, opts \\ [])

  def get_by_full_name(full_name, opts) when is_binary(full_name) do
    opts = store_opts(opts)

    with {:ok, %SourceRepo{} = source_repo} <- SourceRepoStore.get_by_provider_and_full_name(:github, full_name, opts),
         {:ok, %ManagedRepo{} = managed_repo} <- ManagedRepoStore.get_by_source_repo_id(source_repo.id, opts) do
      if deleted?(managed_repo), do: {:ok, nil}, else: {:ok, to_repo(managed_repo, source_repo)}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_by_full_name(_full_name, _opts), do: {:ok, nil}

  @spec get_by_installation_id(integer(), keyword()) :: {:ok, Repo.t() | nil} | {:error, term()}
  def get_by_installation_id(installation_id, opts \\ [])

  def get_by_installation_id(installation_id, opts) when is_integer(installation_id) do
    with {:ok, repos} <- list(opts) do
      {:ok, Enum.find(repos, &(&1.github_app_installation_id == installation_id))}
    end
  end

  def get_by_installation_id(_installation_id, _opts), do: {:ok, nil}

  @spec create(map(), keyword()) :: {:ok, Repo.t()} | {:error, term()}
  def create(attrs, opts \\ [])

  def create(attrs, opts) when is_map(attrs) do
    opts = store_opts(opts)

    with {:ok, full_name} <- full_name(attrs),
         {:ok, %{managed_repo: managed_repo, source_repo: source_repo}} <-
           RepoBridge.upsert_managed_repo(%{
             full_name: full_name,
             name: map_get(attrs, :name),
             default_branch: map_get(attrs, :default_branch, "main")
           }),
         {:ok, managed_repo} <- update_github_settings(managed_repo, attrs, opts) do
      {:ok, to_repo(managed_repo, source_repo)}
    end
  end

  def create(_attrs, _opts), do: {:error, :invalid_repo_attrs}

  @spec update(Repo.t() | String.t(), map(), keyword()) :: {:ok, Repo.t()} | {:error, term()}
  def update(repo_or_id, attrs, opts \\ []) when is_map(attrs) do
    opts = store_opts(opts)

    with {:ok, %Repo{} = repo} <- repo_from(repo_or_id, opts),
         {:ok, %ManagedRepo{} = managed_repo} <- ManagedRepoStore.get_by_id(repo.id, opts),
         {:ok, managed_repo} <- update_github_settings(managed_repo, attrs, opts),
         {:ok, %SourceRepo{} = source_repo} <- SourceRepoStore.get_by_id(managed_repo.source_repo_id, opts) do
      {:ok, to_repo(managed_repo, source_repo)}
    else
      {:ok, nil} -> {:error, :repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec enable(Repo.t() | String.t(), keyword()) :: {:ok, Repo.t()} | {:error, term()}
  def enable(repo_or_id, opts \\ []), do: update(repo_or_id, %{enabled: true}, opts)

  @spec disable(Repo.t() | String.t(), keyword()) :: {:ok, Repo.t()} | {:error, term()}
  def disable(repo_or_id, opts \\ []), do: update(repo_or_id, %{enabled: false}, opts)

  @spec delete(Repo.t() | String.t(), keyword()) :: :ok | {:error, term()}
  def delete(repo_or_id, opts \\ []) do
    case update(repo_or_id, %{enabled: false, deleted: true}, opts) do
      {:ok, %Repo{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp repo_from(%Repo{} = repo, _opts), do: {:ok, repo}
  defp repo_from(id, opts) when is_binary(id), do: get_by_id(id, opts)
  defp repo_from(_repo, _opts), do: {:error, :repo_not_found}

  defp repo_for_managed_repo(%ManagedRepo{} = managed_repo, opts) do
    with {:ok, %SourceRepo{} = source_repo} <- SourceRepoStore.get_by_id(managed_repo.source_repo_id, opts) do
      if deleted?(managed_repo), do: {:ok, nil}, else: {:ok, to_repo(managed_repo, source_repo)}
    end
  end

  defp update_github_settings(%ManagedRepo{} = managed_repo, attrs, opts) do
    current = github_settings(managed_repo)

    next =
      current
      |> Map.merge(%{
        "enabled" => map_get(attrs, :enabled, Map.get(current, "enabled", true)),
        "deleted" => map_get(attrs, :deleted, Map.get(current, "deleted", false)),
        "settings" => normalize_map(map_get(attrs, :settings, Map.get(current, "settings", %{}))),
        "webhook_id" => normalize_optional_integer(map_get(attrs, :webhook_id, Map.get(current, "webhook_id"))),
        "github_app_installation_id" =>
          normalize_optional_integer(
            map_get(attrs, :github_app_installation_id, Map.get(current, "github_app_installation_id"))
          )
      })

    integration_settings =
      managed_repo.integration_settings
      |> normalize_map()
      |> Map.put(@github_settings_key, next)

    ManagedRepoStore.update(managed_repo, %{integration_settings: integration_settings}, opts)
  end

  defp to_repo(%ManagedRepo{} = managed_repo, %SourceRepo{} = source_repo) do
    settings = github_settings(managed_repo)

    %Repo{
      id: managed_repo.id,
      owner: source_repo.owner,
      name: source_repo.name,
      full_name: source_repo.full_name,
      webhook_secret: @webhook_secret_placeholder,
      webhook_id: normalize_optional_integer(Map.get(settings, "webhook_id")),
      enabled: Map.get(settings, "enabled", true) == true,
      settings: normalize_map(Map.get(settings, "settings", %{})),
      github_app_installation_id: normalize_optional_integer(Map.get(settings, "github_app_installation_id")),
      inserted_at: managed_repo.inserted_at || source_repo.inserted_at,
      updated_at: managed_repo.updated_at || source_repo.updated_at
    }
  end

  defp deleted?(%ManagedRepo{} = managed_repo), do: Map.get(github_settings(managed_repo), "deleted") == true

  defp github_settings(%ManagedRepo{} = managed_repo) do
    managed_repo.integration_settings
    |> normalize_map()
    |> Map.get(@github_settings_key, %{})
    |> normalize_map()
  end

  defp github_settings(_repo), do: %{}

  defp full_name(attrs) do
    candidate = map_get(attrs, :full_name) || joined_full_name(map_get(attrs, :owner), map_get(attrs, :name))

    case normalize_optional_string(candidate) do
      nil -> {:error, :missing_full_name}
      full_name -> {:ok, full_name}
    end
  end

  defp joined_full_name(owner, name) do
    with owner when is_binary(owner) <- normalize_optional_string(owner),
         name when is_binary(name) <- normalize_optional_string(name) do
      "#{owner}/#{name}"
    else
      _other -> nil
    end
  end

  defp map_get(map, key, default \\ nil)
  defp map_get(%{} = map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value

  defp normalize_optional_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp normalize_optional_integer(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      Map.put(acc, to_string(key), normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp store_opts(opts) do
    case Keyword.get(opts, :actor) do
      %ActorContext{} -> opts
      nil -> opts
      _legacy_actor -> Keyword.delete(opts, :actor)
    end
  end
end
