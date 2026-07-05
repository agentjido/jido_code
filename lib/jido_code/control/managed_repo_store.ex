defmodule JidoCode.Control.ManagedRepoStore do
  @moduledoc """
  Store-backed managed repository projections.
  """

  alias JidoCode.Control.ManagedRepo
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()
  @max_string_length 255

  @spec upsert(map(), keyword()) :: {:ok, ManagedRepo.t()} | {:error, term()}
  def upsert(attrs, opts \\ [])

  def upsert(attrs, opts) when is_map(attrs) do
    with {:ok, record} <- managed_repo_record(attrs, opts),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:upsert, :managed_repo, Keyword.merge([record: record], opts)) do
      {:ok, to_managed_repo(saved_record)}
    end
  end

  def upsert(_attrs, _opts), do: {:error, :invalid_managed_repo_attrs}

  @spec update(ManagedRepo.t() | String.t(), map(), keyword()) :: {:ok, ManagedRepo.t()} | {:error, term()}
  def update(managed_repo_or_id, attrs, opts \\ [])

  def update(%ManagedRepo{} = managed_repo, attrs, opts) when is_map(attrs) do
    update(managed_repo.id, attrs, opts)
  end

  def update(managed_repo_id, attrs, opts) when is_binary(managed_repo_id) and is_map(attrs) do
    with {:ok, %ManagedRepo{} = managed_repo} <- get_existing_by_id(managed_repo_id, opts),
         record <- update_record(managed_repo, attrs),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:upsert, :managed_repo, Keyword.merge([record: record], opts)) do
      {:ok, to_managed_repo(saved_record)}
    end
  end

  def update(_managed_repo, _attrs, _opts), do: {:error, :invalid_managed_repo_update}

  @spec get_by_id(String.t(), keyword()) :: {:ok, ManagedRepo.t() | nil} | {:error, term()}
  def get_by_id(managed_repo_id, opts \\ [])

  def get_by_id(managed_repo_id, opts) when is_binary(managed_repo_id) and managed_repo_id != "" do
    case ProductStore.dispatch(:get, :managed_repo, Keyword.merge([record: %{id: managed_repo_id}], opts)) do
      {:ok, %{projection: projection}} -> decode_managed_repo_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_by_id(_managed_repo_id, _opts), do: {:error, :invalid_managed_repo_id}

  @spec get_by_source_repo_id(String.t(), keyword()) :: {:ok, ManagedRepo.t() | nil} | {:error, term()}
  def get_by_source_repo_id(source_repo_id, opts \\ []) do
    source_repo_id
    |> normalize_optional_string()
    |> get_by_identity(:unique_source_repo, "sourceRepoRef", opts)
  end

  @spec get_by_legacy_project_id(String.t(), keyword()) :: {:ok, ManagedRepo.t() | nil} | {:error, term()}
  def get_by_legacy_project_id(project_id, opts \\ []) do
    project_id
    |> normalize_optional_string()
    |> get_by_identity(:unique_legacy_project_id, "legacyProjectId", opts)
  end

  @spec list(keyword()) :: {:ok, [ManagedRepo.t()]} | {:error, term()}
  def list(opts \\ []) do
    case ProductStore.dispatch(:list, :managed_repo, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        managed_repos =
          projections
          |> Enum.map(&decode_managed_repo_projection/1)
          |> Enum.flat_map(fn
            {:ok, managed_repo} -> [managed_repo]
            {:error, _reason} -> []
          end)
          |> Enum.sort_by(&(&1.display_name || ""))

        {:ok, managed_repos}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def to_managed_repo(record) when is_map(record) do
    %ManagedRepo{
      id: map_get(record, :managed_repo_id) || map_get(record, :id),
      display_name: map_get(record, :display_name),
      legacy_project_id: map_get(record, :legacy_project_id),
      source_repo_id: map_get(record, :source_repo_id),
      workspace_settings: decode_json_map(map_get(record, :workspace_settings, %{})),
      execution_settings: decode_json_map(map_get(record, :execution_settings, %{})),
      integration_settings: decode_json_map(map_get(record, :integration_settings, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp managed_repo_record(attrs, opts) do
    with {:ok, source_repo_id} <- required_string(map_get(attrs, :source_repo_id), :missing_source_repo_id),
         {:ok, display_name} <-
           required_string(map_get(attrs, :display_name) || map_get(attrs, :name), :missing_display_name),
         :ok <- validate_length(display_name, :display_name),
         {:ok, existing_managed_repo} <- get_by_source_repo_id(source_repo_id, opts) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      workspace_settings = attrs |> map_get(:workspace_settings, %{}) |> normalize_map()
      execution_settings = attrs |> map_get(:execution_settings, %{}) |> normalize_map()
      integration_settings = attrs |> map_get(:integration_settings, %{}) |> normalize_map()

      {:ok,
       %{
         managed_repo_id:
           (existing_managed_repo && existing_managed_repo.id) ||
             map_get(attrs, :managed_repo_id) ||
             map_get(attrs, :id) ||
             Ecto.UUID.generate(),
         source_key: map_get(attrs, :source_key),
         source_repo_id: source_repo_id,
         legacy_project_id: normalize_optional_string(map_get(attrs, :legacy_project_id)),
         display_name: display_name,
         record_label: display_name,
         workspace_path: workspace_settings |> map_get(:workspace_path) |> normalize_optional_string(),
         workspace_settings: workspace_settings,
         execution_settings: execution_settings,
         integration_settings: integration_settings,
         inserted_at: (existing_managed_repo && existing_managed_repo.inserted_at) || now,
         updated_at: now,
         metadata: attrs |> map_get(:metadata, %{}) |> normalize_map()
       }}
    end
  end

  defp update_record(%ManagedRepo{} = managed_repo, attrs) do
    workspace_settings =
      attrs
      |> map_get(:workspace_settings, managed_repo.workspace_settings || %{})
      |> normalize_map()

    execution_settings =
      attrs
      |> map_get(:execution_settings, managed_repo.execution_settings || %{})
      |> normalize_map()

    integration_settings =
      attrs
      |> map_get(:integration_settings, managed_repo.integration_settings || %{})
      |> normalize_map()

    %{
      managed_repo_id: managed_repo.id,
      source_repo_id: managed_repo.source_repo_id,
      legacy_project_id: managed_repo.legacy_project_id,
      display_name:
        attrs
        |> map_get(:display_name, managed_repo.display_name)
        |> normalize_optional_string(),
      record_label:
        attrs
        |> map_get(:display_name, managed_repo.display_name)
        |> normalize_optional_string(),
      source_key:
        managed_repo
        |> Map.get(:__metadata__, %{})
        |> map_get(:control_plane_record, %{})
        |> map_get(:source_key),
      workspace_path: workspace_settings |> map_get(:workspace_path) |> normalize_optional_string(),
      workspace_settings: workspace_settings,
      execution_settings: execution_settings,
      integration_settings: integration_settings,
      inserted_at: managed_repo.inserted_at,
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp get_existing_by_id(managed_repo_id, opts) do
    case get_by_id(managed_repo_id, opts) do
      {:ok, %ManagedRepo{} = managed_repo} -> {:ok, managed_repo}
      {:ok, nil} -> {:error, :managed_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_by_identity(nil, _identity_name, _predicate, _opts), do: {:ok, nil}

  defp get_by_identity(value, identity_name, predicate, opts) do
    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: identity_name,
            predicate_iri: RDF.iri(@control_plane_ns <> predicate),
            value: value
          }
        ],
        opts
      )

    case ProductStore.dispatch(:get, :managed_repo, request_opts) do
      {:ok, %{projection: projection}} -> decode_managed_repo_projection(projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_managed_repo_projection(projection) do
    with {:ok, record} <- Registry.decode(:managed_repo, projection) do
      {:ok, to_managed_repo(record)}
    end
  end

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
      {:ok, decoded} when is_map(decoded) -> normalize_map(decoded)
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: normalize_map(value)
  defp decode_json_map(_value), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
