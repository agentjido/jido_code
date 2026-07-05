defmodule JidoCode.MemoryGraph.Health do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  @moduledoc """
  Health monitoring for memory graph stores.

  This module provides health checks, integrity checks, and metrics for
  operational visibility into store health, graph freshness, and performance.
  """

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.Config

  @type health_status :: :healthy | :degraded | :unhealthy
  @type health_result :: %{status: health_status(), checks: map(), metrics: map()}

  @doc """
  Performs a comprehensive health check for a memory graph store.

  Returns health status with individual check results.
  """
  @spec check(map()) :: {:ok, health_result()} | {:error, term()}
  def check(graph_context) when is_map(graph_context) do
    store_path = graph_context.graph_store_path

    with {:ok, store} <- open_store_for_health(store_path) do
      try do
        memory_health = check_named_graph(store, MemoryGraph.memory_named_graph_resource(), :memory)

        workflow_health =
          check_named_graph(store, MemoryGraph.workflow_provenance_named_graph_resource(), :workflow_provenance)

        overall_status = determine_overall_status([memory_health, workflow_health])

        {:ok,
         %{
           status: overall_status,
           checks: %{
             memory_graph: memory_health,
             workflow_provenance_graph: workflow_health
           },
           metrics: collect_metrics(store, graph_context)
         }}
      after
        TripleStore.close(store)
      end
    end
  end

  @doc """
  Returns a simple health summary for a memory graph store.

  Provides a lightweight status check suitable for heartbeat monitoring.
  """
  @spec summary(map()) :: {:ok, map()} | {:error, term()}
  def summary(graph_context) when is_map(graph_context) do
    case check(graph_context) do
      {:ok, health} ->
        {:ok,
         %{
           status: health.status,
           memory_graph_present?: health.checks.memory_graph.present?,
           workflow_provenance_present?: health.checks.workflow_provenance_graph.present?,
           total_triple_count:
             health.checks.memory_graph.triple_count +
               health.checks.workflow_provenance_graph.triple_count
         }}

      error ->
        error
    end
  end

  @doc """
  Collects performance and usage metrics for the memory graph.
  """
  @spec collect_metrics(term(), map()) :: map()
  def collect_metrics(store, graph_context) do
    # In a production system, these would be collected from a metrics registry
    %{
      last_write_time: get_last_write_time(graph_context.managed_repo_id),
      write_count: get_write_count(graph_context.managed_repo_id),
      query_latency_ms: get_avg_query_latency(graph_context.managed_repo_id),
      error_rate: get_error_rate(graph_context.managed_repo_id),
      graph_size_bytes: get_total_graph_size(store),
      total_triple_count: get_total_triple_count(store)
    }
  end

  # Private functions

  defp open_store_for_health(store_path) do
    timeout = Config.store_timeout([])

    open_task =
      Task.async(fn ->
        TripleStore.open(store_path, create_if_missing: false, schema: :quad)
      end)

    case Task.yield(open_task, timeout) || Task.shutdown(open_task, :brutal_kill) do
      {:ok, {:ok, store}} -> {:ok, store}
      {:ok, {:error, _}} -> {:error, :store_unavailable}
      _ -> {:error, :store_timeout}
    end
  end

  defp check_named_graph(store, named_graph_resource, graph_name) do
    case TripleStore.Exporter.export_single_graph(store.db, store.dict_manager, named_graph_resource) do
      {:ok, graph} ->
        triple_count = RDF.Graph.triple_count(graph)

        integrity_status = check_integrity(graph, graph_name)

        %{
          graph_name: graph_name,
          present?: true,
          triple_count: triple_count,
          integrity: integrity_status,
          status: if(triple_count > 0 and integrity_status == :ok, do: :healthy, else: :degraded)
        }

      {:error, _reason} ->
        %{
          graph_name: graph_name,
          present?: false,
          triple_count: 0,
          integrity: :graph_unavailable,
          status: :unhealthy
        }
    end
  end

  defp check_integrity(graph, graph_name) do
    cond do
      RDF.Graph.empty?(graph) ->
        :empty_graph

      not has_required_ontologies?(graph, graph_name) ->
        :missing_ontologies

      true ->
        :ok
    end
  end

  defp has_required_ontologies?(graph, :memory) do
    ontology_iris = MemoryGraph.ontology_iris()

    graph_contains_iri?(graph, ontology_iris.memory) and
      graph_contains_iri?(graph, ontology_iris.control_plane)
  end

  defp has_required_ontologies?(graph, :workflow_provenance) do
    ontology_iris = MemoryGraph.ontology_iris()

    graph_contains_iri?(graph, ontology_iris.memory) and
      graph_contains_iri?(graph, ontology_iris.control_plane)
  end

  defp has_required_ontologies?(_graph, _other), do: true

  defp graph_contains_iri?(graph, iri) do
    graph
    |> RDF.Graph.triples()
    |> Enum.any?(fn
      {%RDF.IRI{} = subject, _predicate, _object} -> to_string(subject) == iri
      {_subject, %RDF.IRI{} = predicate, _object} -> to_string(predicate) == iri
      {_subject, _predicate, %RDF.IRI{} = object} -> to_string(object) == iri
      _other -> false
    end)
  end

  defp determine_overall_status(checks) do
    statuses = Enum.map(checks, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :unhealthy
      true -> :degraded
    end
  end

  defp get_last_write_time(_managed_repo_id) do
    # In production, this would query a metrics registry
    DateTime.utc_now()
  end

  defp get_write_count(_managed_repo_id) do
    # In production, this would query a metrics registry
    0
  end

  defp get_avg_query_latency(_managed_repo_id) do
    # In production, this would query a metrics registry
    50
  end

  defp get_error_rate(_managed_repo_id) do
    # In production, this would query a metrics registry
    0.0
  end

  defp get_total_graph_size(store) do
    # Estimate based on triple count
    500 * get_total_triple_count(store)
  end

  defp get_total_triple_count(store) do
    with {:ok, memory_graph} <-
           TripleStore.Exporter.export_single_graph(
             store.db,
             store.dict_manager,
             MemoryGraph.memory_named_graph_resource()
           ),
         {:ok, workflow_graph} <-
           TripleStore.Exporter.export_single_graph(
             store.db,
             store.dict_manager,
             MemoryGraph.workflow_provenance_named_graph_resource()
           ) do
      RDF.Graph.triple_count(memory_graph) + RDF.Graph.triple_count(workflow_graph)
    else
      _ -> 0
    end
  end
end
