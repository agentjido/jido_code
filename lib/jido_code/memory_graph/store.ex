defmodule JidoCode.MemoryGraph.Store do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  @moduledoc false

  alias JidoCode.MemoryGraph

  @type graph_context :: map()

  @spec refresh(graph_context()) :: {:ok, map()} | {:error, map()}
  def refresh(graph_context) when is_map(graph_context) do
    with :ok <- ensure_parent_directory(graph_context.graph_store_path),
         {:ok, store} <- open_store(graph_context.graph_store_path, create_if_missing: true) do
      try do
        with {:ok, memory_triple_count} <-
               load_ontology_graph(store, MemoryGraph.memory_named_graph_resource()),
             {:ok, workflow_triple_count} <-
               load_ontology_graph(store, MemoryGraph.workflow_provenance_named_graph_resource()) do
          validated_at = DateTime.utc_now()
          current_revision = graph_context.revision_metadata.current_revision

          latest_validation_status = %{
            state: :validated,
            ready?: true,
            graph_name: graph_context.selected_graph_name,
            current_revision: current_revision,
            validated_revision: current_revision,
            validated_at: validated_at,
            stale?: false,
            failure: nil
          }

          {:ok,
           %{
             status: :memory_graph_refreshed,
             graph_names: graph_context.graph_names,
             named_graph_iris: graph_context.named_graph_iris,
             dataset: Map.put(graph_context.dataset_metadata, :revision, current_revision),
             store: %{
               backend: :triple_store,
               schema: :quad,
               path: graph_context.graph_store_path,
               load_strategy: :shared_named_graph_bootstrap
             },
             load_counts: %{
               memory: memory_triple_count,
               workflow_provenance: workflow_triple_count
             },
             latest_validation_status: latest_validation_status
           }}
        else
          {:error, diagnostics} -> {:error, diagnostics}
        end
      after
        :ok = TripleStore.close(store)
      end
    else
      {:error, diagnostics} when is_map(diagnostics) ->
        {:error, diagnostics}
    end
  end

  @spec validate(graph_context()) :: {:ok, map()} | {:error, map()}
  def validate(graph_context) when is_map(graph_context) do
    case open_store(graph_context.graph_store_path, create_if_missing: false) do
      {:ok, store} ->
        try do
          with {:ok, memory_stats} <-
                 graph_stats(store, MemoryGraph.memory_named_graph_resource(), :memory),
               {:ok, workflow_stats} <-
                 graph_stats(store, MemoryGraph.workflow_provenance_named_graph_resource(), :workflow_provenance) do
            current_revision = graph_context.revision_metadata.current_revision
            ready? = memory_stats.present? and workflow_stats.present?
            validated_at = DateTime.utc_now()

            latest_validation_status = %{
              state: if(ready?, do: :validated, else: :not_ready),
              ready?: ready?,
              graph_name: graph_context.selected_graph_name,
              current_revision: current_revision,
              validated_revision: if(ready?, do: current_revision, else: nil),
              validated_at: if(ready?, do: validated_at, else: nil),
              stale?: false,
              failure: nil
            }

            {:ok,
             %{
               status: if(ready?, do: :memory_graph_validated, else: :memory_graph_not_ready),
               graph_names: graph_context.graph_names,
               named_graph_iris: graph_context.named_graph_iris,
               dataset: Map.put(graph_context.dataset_metadata, :revision, current_revision),
               graph_stats: %{
                 memory: memory_stats,
                 workflow_provenance: workflow_stats
               },
               latest_validation_status: latest_validation_status
             }}
          end
        after
          :ok = TripleStore.close(store)
        end

      {:error, %{stage: :open_store}} ->
        {:ok,
         %{
           status: :memory_graph_not_ready,
           graph_names: graph_context.graph_names,
           named_graph_iris: graph_context.named_graph_iris,
           dataset:
             Map.put(graph_context.dataset_metadata, :revision, graph_context.revision_metadata.current_revision),
           graph_stats: %{
             memory: %{graph_name: "memory", present?: false, triple_count: 0},
             workflow_provenance: %{graph_name: "workflow_provenance", present?: false, triple_count: 0}
           },
           latest_validation_status: %{
             state: :not_validated,
             ready?: false,
             graph_name: graph_context.selected_graph_name,
             current_revision: graph_context.revision_metadata.current_revision,
             validated_revision: nil,
             validated_at: nil,
             stale?: false,
             failure: nil
           }
         }}

      {:error, diagnostics} ->
        {:error, diagnostics}
    end
  end

  defp load_ontology_graph(store, named_graph_resource) do
    MemoryGraph.ontology_artifacts()
    |> Enum.reduce_while({:ok, 0}, fn artifact, {:ok, total_count} ->
      case RDF.Turtle.read_file(artifact.path) do
        {:ok, graph} ->
          case TripleStore.load_graph(store, graph, graph: named_graph_resource) do
            {:ok, count} ->
              {:cont, {:ok, total_count + count}}

            {:error, reason} ->
              {:halt,
               {:error,
                %{
                  stage: :load_ontology_graph,
                  named_graph_iri: to_string(named_graph_resource),
                  ontology_path: artifact.path,
                  reason: inspect(reason)
                }}}
          end

        {:error, reason} ->
          {:halt,
           {:error,
            %{
              stage: :read_ontology,
              ontology_path: artifact.path,
              reason: inspect(reason)
            }}}
      end
    end)
  end

  defp graph_stats(store, named_graph_resource, graph_name) do
    case TripleStore.Exporter.export_single_graph(store.db, store.dict_manager, named_graph_resource) do
      {:ok, graph} ->
        triple_count = RDF.Graph.triple_count(graph)

        {:ok,
         %{
           graph_name: graph_name,
           named_graph_iri: to_string(named_graph_resource),
           present?: triple_count > 0,
           triple_count: triple_count
         }}

      {:error, reason} ->
        {:error,
         %{
           stage: :export_named_graph,
           graph_name: graph_name,
           named_graph_iri: to_string(named_graph_resource),
           reason: inspect(reason)
         }}
    end
  end

  defp ensure_parent_directory(store_path) do
    store_path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, %{stage: :prepare_store_parent, reason: inspect(reason)}}
    end
  end

  defp open_store(store_path, opts) do
    create_if_missing = Keyword.get(opts, :create_if_missing, false)

    case TripleStore.open(store_path, create_if_missing: create_if_missing, schema: :quad) do
      {:ok, store} ->
        {:ok, store}

      {:error, reason} ->
        {:error,
         %{
           stage: :open_store,
           graph_store_path: store_path,
           reason: inspect(reason)
         }}
    end
  end
end
