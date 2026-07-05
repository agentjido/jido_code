defmodule JidoCode.ControlPlane.RecordStore do
  @moduledoc """
  Shared map-level helpers for product services backed by the control-plane store.
  """

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.SemanticIdentity
  alias JidoCode.ControlPlane.Store.ActorContext
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  @control_plane_ns SemanticIdentity.ontology_namespace()

  @spec create(atom(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(record_type, record, opts \\ []) when is_atom(record_type) and is_map(record) do
    with {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:create, record_type, Keyword.merge([record: record], store_opts(opts))) do
      {:ok, saved_record}
    end
  end

  @spec upsert(atom(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def upsert(record_type, record, opts \\ []) when is_atom(record_type) and is_map(record) do
    with {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:upsert, record_type, Keyword.merge([record: record], store_opts(opts))) do
      {:ok, saved_record}
    end
  end

  @spec update(atom(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def update(record_type, record, opts \\ []) when is_atom(record_type) and is_map(record) do
    with {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:update, record_type, Keyword.merge([record: record], store_opts(opts))) do
      {:ok, saved_record}
    end
  end

  @spec get_by_identity(atom(), atom(), String.t(), term(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_by_identity(record_type, identity_name, predicate_local, value, opts \\ [])

  def get_by_identity(_record_type, _identity_name, _predicate_local, nil, _opts), do: {:ok, nil}

  def get_by_identity(record_type, identity_name, predicate_local, value, opts)
      when is_atom(record_type) and is_atom(identity_name) and is_binary(predicate_local) do
    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: identity_name,
            predicate_iri: RDF.iri(@control_plane_ns <> predicate_local),
            value: value
          }
        ],
        store_opts(opts)
      )

    case ProductStore.dispatch(:get, record_type, request_opts) do
      {:ok, %{projection: projection}} -> decode(record_type, projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list(atom(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list(record_type, filters \\ %{}, opts \\ []) when is_atom(record_type) and is_map(filters) do
    query = Keyword.get(opts, :query, %{limit: 500, offset: 0})

    request_opts =
      opts
      |> Keyword.delete(:query)
      |> store_opts()
      |> Keyword.merge(query: query)

    case ProductStore.dispatch(:list, record_type, request_opts) do
      {:ok, %{projections: projections}} ->
        records =
          projections
          |> Enum.map(&decode(record_type, &1))
          |> Enum.flat_map(fn
            {:ok, record} -> [record]
            {:error, _reason} -> []
          end)
          |> Enum.filter(&matches_filters?(&1, filters))

        {:ok, records}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec decode(atom(), map()) :: {:ok, map()} | {:error, term()}
  def decode(record_type, projection), do: Registry.decode(record_type, projection)

  def store_opts(opts) do
    case Keyword.get(opts, :actor) do
      %ActorContext{} -> opts
      nil -> opts
      _legacy_actor -> Keyword.delete(opts, :actor)
    end
  end

  defp matches_filters?(record, filters) do
    Enum.all?(filters, fn {key, expected} ->
      actual = Map.get(record, key) || Map.get(record, to_string(key))

      case expected do
        expected_values when is_list(expected_values) -> actual in expected_values
        expected_value -> actual == expected_value
      end
    end)
  end
end
