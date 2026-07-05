defmodule JidoCode.ControlPlane.Diagnostics do
  @moduledoc """
  Safe diagnostic queries for the embedded control-plane store.
  """

  alias JidoCode.ControlPlane.{Health, StoreQuery, StoreServer}

  @type query_name :: :health | :graph_counts | :list_records

  @spec safe_query(query_name(), keyword()) :: {:ok, map()} | {:error, term()}
  def safe_query(query_name, opts \\ [])

  def safe_query(:health, opts) do
    server = Keyword.get(opts, :server, StoreServer)
    {:ok, Health.status(server)}
  end

  def safe_query(:graph_counts, opts) do
    server = Keyword.get(opts, :server, StoreServer)

    try do
      health = StoreServer.health(server)

      {:ok,
       %{
         status: :query_succeeded,
         query: :graph_counts,
         graph_counts:
           health.graph_counts
           |> Enum.sort_by(fn {graph_iri, _count} -> graph_iri end)
           |> Enum.map(fn {graph_iri, count} -> %{graph_iri: graph_iri, quad_count: count} end),
         graph_count: map_size(health.graph_counts),
         total_quad_count: health.graph_counts |> Map.values() |> Enum.sum()
       }}
    catch
      :exit, reason -> {:error, {:store_unavailable, reason}}
    end
  end

  def safe_query(:list_records, opts) do
    record_type = Keyword.get(opts, :record_type)

    if is_atom(record_type) do
      StoreQuery.list_by_class(record_type, opts)
    else
      {:error, :missing_record_type}
    end
  end

  @spec raw_sparql(String.t(), keyword()) :: {:ok, map()} | {:error, atom(), map()} | {:error, atom()}
  def raw_sparql(sparql, opts \\ [])

  def raw_sparql(sparql, opts) when is_binary(sparql) do
    if Keyword.get(opts, :allow_raw?, false) do
      StoreQuery.diagnostics_query(sparql, opts)
    else
      {:error, :raw_sparql_requires_allow_raw}
    end
  end

  def raw_sparql(_sparql, _opts), do: {:error, :invalid_sparql}
end
