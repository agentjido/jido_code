defmodule JidoCode.SourceCodeGraph.Query do
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc false

  alias JidoCode.SourceCodeGraph

  @type graph_context :: map()

  @spec run(graph_context(), String.t()) :: {:ok, map()} | {:error, atom(), map()}
  def run(graph_context, sparql) when is_map(graph_context) and is_binary(sparql) do
    with :ok <- reject_explicit_graph_clause(sparql),
         {:ok, query} <- parse_query(sparql),
         {:ok, store} <- open_store(graph_context.dataset_metadata.graph_store_path) do
      try do
        with {:ok, graph} <- export_named_graph(store),
             {:ok, raw_result} <- execute_query(graph, query, graph_context) do
          build_result(raw_result, graph_context, sparql, query)
        end
      after
        TripleStore.close(store)
      end
    else
      {:error, reason, diagnostics} ->
        {:error, reason, diagnostics}
    end
  end

  defp parse_query(sparql) do
    case SPARQL.Query.new(sparql, default_prefixes: ElixirOntologies.NS.prefix_map()) do
      %SPARQL.Query{} = query ->
        {:ok, query}

      {:error, reason} ->
        {:error, :source_code_graph_invalid_query,
         %{
           stage: :parse_query,
           reason: inspect(reason),
           library: :sparql
         }}
    end
  rescue
    error ->
      {:error, :source_code_graph_invalid_query,
       %{
         stage: :parse_query,
         reason: Exception.message(error),
         library: :sparql
       }}
  end

  defp execute_query(graph, query, graph_context) do
    case SPARQL.execute_query(graph, query) do
      {:error, reason} ->
        {:error, :source_code_graph_query_failed, failure_diagnostics(graph_context, :execute_query, reason)}

      result ->
        {:ok, result}
    end
  rescue
    error ->
      {:error, :source_code_graph_query_failed,
       failure_diagnostics(graph_context, :execute_query, Exception.message(error))}
  end

  defp open_store(store_path) do
    case TripleStore.open(store_path, create_if_missing: false, schema: :quad) do
      {:ok, store} -> {:ok, store}
      {:error, reason} -> {:error, :open_store, reason}
    end
  end

  defp export_named_graph(store) do
    case TripleStore.Exporter.export_single_graph(
           store.db,
           store.dict_manager,
           SourceCodeGraph.named_graph_resource()
         ) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, :export_named_graph, reason}
    end
  end

  defp reject_explicit_graph_clause(sparql) do
    if Regex.match?(~r/\bGRAPH\b/i, sparql) do
      {:error, :source_code_graph_invalid_query,
       %{
         stage: :validate_query,
         reason:
           "Explicit GRAPH clauses are not allowed; queries target the repository-local source_code graph automatically.",
         library: :sparql
       }}
    else
      :ok
    end
  end

  defp build_result(%SPARQL.Query.Result{results: boolean} = result, graph_context, sparql, query)
       when is_boolean(boolean) do
    {:ok,
     %{
       status: :query_succeeded,
       graph_name: graph_context.graph_name,
       named_graph_iri: SourceCodeGraph.named_graph_iri(),
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
         graph_name: graph_context.graph_name,
         named_graph_iri: SourceCodeGraph.named_graph_iri()
       },
       latest_import_status: graph_context.latest_import_status
     }}
  end

  defp build_result(%SPARQL.Query.Result{} = result, graph_context, sparql, query) do
    bindings = Enum.map(result.results, &format_solution/1)

    {:ok,
     %{
       status: :query_succeeded,
       graph_name: graph_context.graph_name,
       named_graph_iri: SourceCodeGraph.named_graph_iri(),
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
         graph_name: graph_context.graph_name,
         named_graph_iri: SourceCodeGraph.named_graph_iri()
       },
       latest_import_status: graph_context.latest_import_status
     }}
  end

  defp build_result(%RDF.Graph{} = graph, graph_context, sparql, query) do
    {:ok,
     %{
       status: :query_succeeded,
       graph_name: graph_context.graph_name,
       named_graph_iri: SourceCodeGraph.named_graph_iri(),
       engine: :sparql,
       library: :sparql,
       form: query.form,
       sparql: sparql,
       variables: [],
       bindings: [],
       row_count: RDF.Graph.triple_count(graph),
       boolean: nil,
       empty?: RDF.Graph.empty?(graph),
       result_graph: %{
         triple_count: RDF.Graph.triple_count(graph),
         name: graph.name && to_string(graph.name)
       },
       target: %{
         backend: :triple_store,
         graph_name: graph_context.graph_name,
         named_graph_iri: SourceCodeGraph.named_graph_iri()
       },
       latest_import_status: graph_context.latest_import_status
     }}
  end

  defp build_result(other, graph_context, _sparql, _query) do
    {:error, :source_code_graph_query_failed,
     failure_diagnostics(graph_context, :execute_query, "Unexpected SPARQL result: #{inspect(other)}")}
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

  defp failure_diagnostics(graph_context, stage, reason) do
    %{
      stage: stage,
      reason: inspect(reason),
      graph_name: graph_context.graph_name,
      named_graph_iri: SourceCodeGraph.named_graph_iri(),
      graph_store_path: graph_context.dataset_metadata.graph_store_path,
      library: :sparql
    }
  end
end
