defmodule JidoCode.MemoryGraph.Query do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  @moduledoc false

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.Config
  alias JidoCode.MemoryGraph.ResourceLimits

  @type graph_context :: map()

  @spec run(graph_context(), String.t()) :: {:ok, map()} | {:error, atom(), map()}
  def run(graph_context, sparql) when is_map(graph_context) and is_binary(sparql) do
    with :ok <- reject_explicit_graph_clause(sparql),
         {:ok, query} <- parse_query(sparql),
         {:ok, store} <- open_store(graph_context.dataset_metadata.graph_store_path),
         {:ok, graph} <- export_named_graph(store, graph_context) do
      try do
        execute_query(graph, query, graph_context, sparql)
      after
        TripleStore.close(store)
      end
    end
  end

  defp parse_query(sparql) do
    default_prefixes =
      ElixirOntologies.NS.prefix_map()
      |> Keyword.merge(
        jido: "https://jido.run/ontology/memory#",
        prov: "http://www.w3.org/ns/prov#",
        owl: "http://www.w3.org/2002/07/owl#",
        xsd: "http://www.w3.org/2001/XMLSchema#"
      )

    case SPARQL.Query.new(sparql, default_prefixes: default_prefixes) do
      %SPARQL.Query{} = query ->
        {:ok, query}

      {:error, reason} ->
        {:error, :memory_graph_invalid_query,
         %{
           stage: :parse_query,
           reason: inspect(reason),
           library: :sparql
         }}
    end
  rescue
    error ->
      {:error, :memory_graph_invalid_query,
       %{
         stage: :parse_query,
         reason: Exception.message(error),
         library: :sparql
       }}
  end

  defp execute_query(graph, query, graph_context, sparql) do
    timeout = Config.query_timeout([])

    query_task =
      Task.async(fn ->
        do_execute_query(graph, query, graph_context, sparql)
      end)

    case Task.yield(query_task, timeout) || Task.shutdown(query_task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        {:error, :memory_graph_query_timeout,
         failure_diagnostics(graph_context, :execute_query, :timeout, timeout_ms: timeout)}
    end
  end

  defp do_execute_query(graph, query, graph_context, sparql) do
    case SPARQL.execute_query(graph, query) do
      {:error, reason} ->
        {:error, :memory_graph_query_failed, failure_diagnostics(graph_context, :execute_query, reason)}

      %SPARQL.Query.Result{} = result ->
        build_result_with_limit(result, graph_context, sparql, query)

      %RDF.Graph{} = result_graph ->
        build_graph_result_with_limit(result_graph, graph_context, sparql, query)

      other ->
        {:error, :memory_graph_query_failed,
         failure_diagnostics(graph_context, :execute_query, "Unexpected SPARQL result: #{inspect(other)}")}
    end
  rescue
    error ->
      {:error, :memory_graph_query_failed, failure_diagnostics(graph_context, :execute_query, Exception.message(error))}
  end

  defp open_store(store_path) do
    timeout = Config.store_timeout([])

    open_task =
      Task.async(fn ->
        TripleStore.open(store_path, create_if_missing: false, schema: :quad)
      end)

    case Task.yield(open_task, timeout) || Task.shutdown(open_task, :brutal_kill) do
      {:ok, {:ok, store}} ->
        {:ok, store}

      {:ok, {:error, reason}} ->
        {:error, :memory_graph_query_failed,
         %{
           stage: :open_store,
           reason: inspect(reason),
           graph_store_path: store_path,
           library: :sparql
         }}

      {:ok, other} ->
        {:error, :memory_graph_query_failed,
         %{
           stage: :open_store,
           reason: inspect(other),
           graph_store_path: store_path,
           library: :sparql
         }}

      nil ->
        {:error, :memory_graph_query_failed,
         %{
           stage: :open_store,
           reason: :timeout,
           timeout_ms: timeout,
           graph_store_path: store_path,
           library: :sparql
         }}
    end
  end

  defp export_named_graph(store, graph_context) do
    case TripleStore.Exporter.export_single_graph(
           store.db,
           store.dict_manager,
           MemoryGraph.named_graph_resource(graph_context.selected_graph_name)
         ) do
      {:ok, graph} ->
        {:ok, graph}

      {:error, reason} ->
        {:error, :memory_graph_query_failed, failure_diagnostics(graph_context, :export_named_graph, reason)}
    end
  end

  defp reject_explicit_graph_clause(sparql) do
    if Regex.match?(~r/\bGRAPH\b/i, sparql) do
      {:error, :memory_graph_invalid_query,
       %{
         stage: :validate_query,
         reason:
           "Explicit GRAPH clauses are not allowed; queries target one repository-local memory graph automatically.",
         library: :sparql
       }}
    else
      :ok
    end
  end

  defp build_result(%SPARQL.Query.Result{results: boolean} = result, graph_context, sparql, query)
       when is_boolean(boolean) do
    %{
      status: :query_succeeded,
      graph_name: graph_context.selected_graph_name,
      named_graph_iri: graph_context.selected_named_graph_iri,
      engine: :sparql,
      library: :sparql,
      form: query.form,
      sparql: sparql,
      variables: result.variables || [],
      bindings: [],
      row_count: 0,
      boolean: boolean,
      empty?: not boolean,
      target: %{
        backend: :triple_store,
        graph_name: graph_context.selected_graph_name,
        named_graph_iri: graph_context.selected_named_graph_iri
      },
      latest_validation_status: graph_context.latest_validation_status
    }
  end

  defp build_result(%SPARQL.Query.Result{} = result, graph_context, sparql, query) do
    bindings = Enum.map(result.results, &format_solution/1)

    %{
      status: :query_succeeded,
      graph_name: graph_context.selected_graph_name,
      named_graph_iri: graph_context.selected_named_graph_iri,
      engine: :sparql,
      library: :sparql,
      form: query.form,
      sparql: sparql,
      variables: result.variables || [],
      bindings: bindings,
      row_count: length(bindings),
      boolean: nil,
      empty?: bindings == [],
      target: %{
        backend: :triple_store,
        graph_name: graph_context.selected_graph_name,
        named_graph_iri: graph_context.selected_named_graph_iri
      },
      latest_validation_status: graph_context.latest_validation_status
    }
  end

  defp build_result_with_limit(%SPARQL.Query.Result{} = result, graph_context, sparql, query) do
    bindings = Enum.map(result.results, &format_solution/1)

    case ResourceLimits.validate_query_results(bindings, []) do
      {:ok, _} ->
        {:ok, build_result(result, graph_context, sparql, query)}

      {:error, :result_limit_exceeded, limit_info} ->
        # Return truncated results with warning
        {:ok,
         build_result(result, graph_context, sparql, query)
         |> Map.put(:row_count, limit_info.result_count)
         |> Map.put(:bindings, limit_info.truncated_results)
         |> Map.put(:result_limit_exceeded?, true)
         |> Map.put(:result_limit_info, Map.take(limit_info, [:result_count, :max_results]))}
    end
  end

  defp build_graph_result(%RDF.Graph{} = graph, graph_context, sparql, query) do
    triple_count = RDF.Graph.triple_count(graph)

    %{
      status: :query_succeeded,
      graph_name: graph_context.selected_graph_name,
      named_graph_iri: graph_context.selected_named_graph_iri,
      engine: :sparql,
      library: :sparql,
      form: query.form,
      sparql: sparql,
      variables: [],
      bindings: [],
      row_count: triple_count,
      boolean: nil,
      empty?: RDF.Graph.empty?(graph),
      result_graph: %{
        triple_count: triple_count,
        name: graph.name && to_string(graph.name)
      },
      target: %{
        backend: :triple_store,
        graph_name: graph_context.selected_graph_name,
        named_graph_iri: graph_context.selected_named_graph_iri
      },
      latest_validation_status: graph_context.latest_validation_status
    }
  end

  defp build_graph_result_with_limit(%RDF.Graph{} = graph, graph_context, sparql, query) do
    triple_count = RDF.Graph.triple_count(graph)
    max_results = Config.max_query_results([])

    if triple_count > max_results do
      # Return warning about limit exceeded
      {:ok,
       build_graph_result(graph, graph_context, sparql, query)
       |> Map.put(:result_limit_exceeded?, true)
       |> Map.put(:result_limit_info, %{triple_count: triple_count, max_results: max_results})}
    else
      {:ok, build_graph_result(graph, graph_context, sparql, query)}
    end
  end

  defp format_solution(solution) when is_map(solution) do
    solution
    |> Map.drop([:__id__])
    |> Map.new(fn {variable, value} -> {variable, format_value(value)} end)
  end

  defp format_value(%RDF.IRI{} = iri), do: %{type: :iri, value: to_string(iri)}

  defp format_value(%RDF.BlankNode{} = blank_node),
    do: %{type: :blank_node, value: RDF.BlankNode.value(blank_node)}

  defp format_value(%RDF.Literal{} = literal) do
    %{
      type: :literal,
      value: RDF.Literal.value(literal),
      lexical: RDF.Literal.lexical(literal),
      datatype: RDF.Literal.datatype_id(literal) && to_string(RDF.Literal.datatype_id(literal)),
      language: RDF.Literal.language(literal)
    }
  end

  defp format_value(value), do: %{type: :value, value: value}

  defp failure_diagnostics(graph_context, stage, reason, opts \\ []) do
    base = %{
      stage: stage,
      reason: inspect(reason),
      graph_name: graph_context.selected_graph_name,
      named_graph_iri: graph_context.selected_named_graph_iri,
      graph_store_path: graph_context.dataset_metadata.graph_store_path,
      library: :sparql
    }

    case Keyword.get(opts, :timeout_ms) do
      nil -> base
      timeout -> Map.put(base, :timeout_ms, timeout)
    end
  end
end
