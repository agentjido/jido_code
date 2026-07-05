defmodule JidoCode.Control.SourceRepoStore do
  @moduledoc """
  Store-backed source repository projections.
  """

  alias JidoCode.Control.SourceRepo
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()
  @providers [:github, :gitlab, :bitbucket]
  @max_string_length 255

  @spec upsert(map(), keyword()) :: {:ok, SourceRepo.t()} | {:error, term()}
  def upsert(attrs, opts \\ [])

  def upsert(attrs, opts) when is_map(attrs) do
    with {:ok, record} <- source_repo_record(attrs, opts),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:upsert, :source_repo, Keyword.merge([record: record], opts)) do
      {:ok, to_source_repo(saved_record)}
    end
  end

  def upsert(_attrs, _opts), do: {:error, :invalid_source_repo_attrs}

  @spec get_by_id(String.t(), keyword()) :: {:ok, SourceRepo.t() | nil} | {:error, term()}
  def get_by_id(source_repo_id, opts \\ [])

  def get_by_id(source_repo_id, opts) when is_binary(source_repo_id) and source_repo_id != "" do
    case ProductStore.dispatch(:get, :source_repo, Keyword.merge([record: %{id: source_repo_id}], opts)) do
      {:ok, %{projection: projection}} -> decode_source_repo_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_by_id(_source_repo_id, _opts), do: {:error, :invalid_source_repo_id}

  @spec get_by_provider_and_full_name(atom() | String.t(), String.t(), keyword()) ::
          {:ok, SourceRepo.t() | nil} | {:error, term()}
  def get_by_provider_and_full_name(provider, full_name, opts \\ []) do
    with {:ok, provider} <- normalize_provider(provider),
         {:ok, full_name} <- required_string(full_name, :missing_full_name),
         source_key <- source_key(provider, full_name) do
      request_opts =
        Keyword.merge(
          [
            identity: %{
              identity: :unique_provider_full_name,
              predicate_iri: RDF.iri(@control_plane_ns <> "sourceKey"),
              value: source_key
            }
          ],
          opts
        )

      case ProductStore.dispatch(:get, :source_repo, request_opts) do
        {:ok, %{projection: projection}} -> decode_source_repo_projection(projection)
        {:error, %NotFoundError{}} -> {:ok, nil}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec list(keyword()) :: {:ok, [SourceRepo.t()]} | {:error, term()}
  def list(opts \\ []) do
    case ProductStore.dispatch(:list, :source_repo, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        source_repos =
          projections
          |> Enum.map(&decode_source_repo_projection/1)
          |> Enum.flat_map(fn
            {:ok, source_repo} -> [source_repo]
            {:error, _reason} -> []
          end)
          |> Enum.sort_by(&(&1.full_name || ""))

        {:ok, source_repos}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec source_key(atom() | String.t(), String.t()) :: String.t()
  def source_key(provider, full_name), do: "#{provider}:#{full_name}"

  def to_source_repo(record) when is_map(record) do
    %SourceRepo{
      id: map_get(record, :source_repo_id) || map_get(record, :id),
      provider: normalize_provider!(map_get(record, :provider, :github)),
      owner: map_get(record, :owner),
      name: map_get(record, :name),
      full_name: map_get(record, :full_name),
      default_branch: map_get(record, :default_branch) || "main",
      source_metadata: decode_json_map(map_get(record, :source_metadata, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp source_repo_record(attrs, opts) do
    with {:ok, provider} <- normalize_provider(map_get(attrs, :provider, :github)),
         {:ok, full_name} <- full_name(attrs),
         {:ok, owner, name, full_name} <- normalize_repo_identity(full_name),
         {:ok, default_branch} <- required_string(map_get(attrs, :default_branch, "main"), :invalid_default_branch),
         :ok <- validate_length(default_branch, :default_branch),
         {:ok, existing_source_repo} <- get_by_provider_and_full_name(provider, full_name, opts) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      source_repo_id = existing_source_repo && existing_source_repo.id

      {:ok,
       %{
         source_repo_id:
           source_repo_id ||
             map_get(attrs, :source_repo_id) ||
             map_get(attrs, :id) ||
             JidoCode.UUID.generate(),
         source_key: source_key(provider, full_name),
         provider: Atom.to_string(provider),
         owner: owner,
         name: name,
         full_name: full_name,
         default_branch: default_branch,
         source_metadata: attrs |> map_get(:source_metadata, %{}) |> normalize_map(),
         inserted_at: (existing_source_repo && existing_source_repo.inserted_at) || now,
         updated_at: now,
         metadata: attrs |> map_get(:metadata, %{}) |> normalize_map()
       }}
    end
  end

  defp full_name(attrs) do
    candidate =
      map_get(attrs, :full_name) ||
        map_get(attrs, :github_full_name) ||
        map_get(attrs, :source_identifier)

    case normalize_optional_string(candidate) do
      nil ->
        owner = normalize_optional_string(map_get(attrs, :owner))
        name = normalize_optional_string(map_get(attrs, :name))

        if owner && name do
          {:ok, "#{owner}/#{name}"}
        else
          {:error, :missing_full_name}
        end

      full_name ->
        {:ok, full_name}
    end
  end

  defp normalize_repo_identity(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" -> {:ok, owner, name, full_name}
      _other -> {:error, :invalid_full_name}
    end
  end

  defp decode_source_repo_projection(projection) do
    with {:ok, record} <- Registry.decode(:source_repo, projection) do
      {:ok, to_source_repo(record)}
    end
  end

  defp normalize_provider(provider) when provider in @providers, do: {:ok, provider}

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> case do
      "github" -> {:ok, :github}
      "gitlab" -> {:ok, :gitlab}
      "bitbucket" -> {:ok, :bitbucket}
      _other -> {:error, {:invalid_provider, provider}}
    end
  end

  defp normalize_provider(provider), do: {:error, {:invalid_provider, provider}}
  defp normalize_provider!(provider), do: elem(normalize_provider(provider), 1)

  defp required_string(value, error) do
    case normalize_optional_string(value) do
      nil -> {:error, error}
      normalized_value -> {:ok, normalized_value}
    end
  end

  defp validate_length(value, field) when is_binary(value) do
    if String.length(value) <= @max_string_length, do: :ok, else: {:error, {:too_long, field}}
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> normalize_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_datetime(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: normalize_map(value)
  defp decode_json_map(_value), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
