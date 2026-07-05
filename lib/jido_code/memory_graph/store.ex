defmodule JidoCode.MemoryGraph.Store do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  @moduledoc false

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.Config
  alias JidoCode.MemoryGraph.GovernedReference
  alias JidoCode.MemoryGraph.Retry

  @legacy_governed_artifact_segments [
    "managed_repo_id/",
    "event_id/",
    "observation_id/",
    "assessment_id/",
    "work_item_id/",
    "run_id/",
    "evidence_id/",
    "change_request_id/",
    "decision_id/"
  ]

  @typed_governed_predicates [
    "aboutManagedRepo",
    "aboutEvent",
    "aboutObservation",
    "aboutAssessment",
    "aboutWorkItem",
    "aboutRun",
    "aboutEvidence",
    "aboutChangeRequest",
    "aboutDecision"
  ]

  @type graph_context :: map()

  @spec refresh(graph_context()) :: {:ok, map()} | {:error, map()}
  def refresh(graph_context) when is_map(graph_context) do
    with :ok <- maybe_reset_store(graph_context),
         :ok <- ensure_parent_directory(graph_context.graph_store_path),
         {:ok, store} <- open_store(graph_context.graph_store_path, create_if_missing: true) do
      try do
        with {:ok, memory_triple_count} <-
               load_ontology_graph(store, MemoryGraph.memory_named_graph_resource()),
             {:ok, workflow_triple_count} <-
               load_ontology_graph(store, MemoryGraph.workflow_provenance_named_graph_resource()),
             {:ok, semantic_model} <- semantic_model_status(store, graph_context.managed_repo_id) do
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
            failure: nil,
            semantic_model: semantic_model
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
               load_strategy: :shared_named_graph_bootstrap,
               reset_store?: Map.get(graph_context, :reset_store?, false)
             },
             load_counts: %{
               memory: memory_triple_count,
               workflow_provenance: workflow_triple_count
             },
             latest_validation_status: latest_validation_status,
             semantic_model: semantic_model,
             latest_failure: nil
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
                 graph_stats(store, MemoryGraph.workflow_provenance_named_graph_resource(), :workflow_provenance),
               {:ok, semantic_model} <- semantic_model_status(store, graph_context.managed_repo_id) do
            current_revision = graph_context.revision_metadata.current_revision
            ready? = memory_stats.present? and workflow_stats.present? and not semantic_model.rebuild_required?
            validated_at = DateTime.utc_now()
            latest_failure = semantic_failure(semantic_model)
            validation_state = validation_state(ready?, semantic_model, latest_failure)

            latest_validation_status = %{
              state: validation_state,
              ready?: ready?,
              graph_name: graph_context.selected_graph_name,
              current_revision: current_revision,
              validated_revision: if(ready?, do: current_revision, else: nil),
              validated_at: if(ready?, do: validated_at, else: nil),
              stale?: false,
              failure: latest_failure,
              semantic_model: semantic_model
            }

            {:ok,
             %{
               status: validation_result_status(ready?, semantic_model),
               graph_names: graph_context.graph_names,
               named_graph_iris: graph_context.named_graph_iris,
               dataset: Map.put(graph_context.dataset_metadata, :revision, current_revision),
               graph_stats: %{
                 memory: memory_stats,
                 workflow_provenance: workflow_stats
               },
               latest_validation_status: latest_validation_status,
               semantic_model: semantic_model,
               latest_failure: latest_failure
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
           semantic_model: default_semantic_model(),
           latest_failure: nil,
           latest_validation_status: %{
             state: :not_validated,
             ready?: false,
             graph_name: graph_context.selected_graph_name,
             current_revision: graph_context.revision_metadata.current_revision,
             validated_revision: nil,
             validated_at: nil,
             stale?: false,
             failure: nil,
             semantic_model: default_semantic_model()
           }
         }}

      {:error, diagnostics} ->
        {:error, diagnostics}
    end
  end

  defp load_ontology_graph(store, named_graph_resource, opts \\ []) do
    timeout = Config.validation_timeout(opts)

    load_task =
      Task.async(fn ->
        load_ontology_graph_with_retry(store, named_graph_resource)
      end)

    case Task.yield(load_task, timeout) || Task.shutdown(load_task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        {:error,
         %{
           stage: :load_ontology_graph,
           named_graph_iri: to_string(named_graph_resource),
           reason: :timeout,
           timeout_ms: timeout
         }}
    end
  end

  defp load_ontology_graph_with_retry(store, named_graph_resource) do
    Retry.with_retry(
      fn -> do_load_ontology_graph(store, named_graph_resource) end,
      attempt_context: %{named_graph_iri: to_string(named_graph_resource)}
    )
  end

  defp do_load_ontology_graph(store, named_graph_resource) do
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
    timeout = Config.store_timeout(opts)

    open_task =
      Task.async(fn ->
        open_store_with_retry(store_path, create_if_missing)
      end)

    case Task.yield(open_task, timeout) || Task.shutdown(open_task, :brutal_kill) do
      {:ok, {:ok, store}} ->
        {:ok, store}

      {:ok, {:error, reason}} ->
        {:error, %{stage: :open_store, reason: inspect(reason)}}

      {:ok, other} ->
        {:error, %{stage: :open_store, reason: inspect(other)}}

      nil ->
        {:error, %{stage: :open_store, reason: :timeout, timeout_ms: timeout}}
    end
  end

  defp open_store_with_retry(store_path, create_if_missing) do
    Retry.with_retry(
      fn ->
        case TripleStore.open(store_path, create_if_missing: create_if_missing, schema: :quad) do
          {:ok, store} -> {:ok, store}
          {:error, reason} -> {:error, reason}
        end
      end,
      attempt_context: %{graph_store_path: store_path}
    )
  end

  defp maybe_reset_store(%{graph_store_path: store_path, reset_store?: true}) do
    case File.rm_rf(store_path) do
      {:ok, _paths} -> :ok
      {:error, reason, _path} -> {:error, %{stage: :reset_store, graph_store_path: store_path, reason: inspect(reason)}}
    end
  end

  defp maybe_reset_store(_graph_context), do: :ok

  defp semantic_model_status(store, managed_repo_id) do
    with {:ok, memory_graph} <- export_graph(store, MemoryGraph.memory_named_graph_resource(), :memory),
         {:ok, workflow_graph} <-
           export_graph(store, MemoryGraph.workflow_provenance_named_graph_resource(), :workflow_provenance) do
      ontology_pair = ontology_pair_status(memory_graph, workflow_graph)

      typed_governed_link_count =
        count_typed_governed_links(memory_graph, managed_repo_id) +
          count_typed_governed_links(workflow_graph, managed_repo_id)

      legacy_governed_artifact_count =
        count_legacy_governed_artifacts(memory_graph, managed_repo_id) +
          count_legacy_governed_artifacts(workflow_graph, managed_repo_id)

      {:ok,
       %{
         state: semantic_model_state(ontology_pair, legacy_governed_artifact_count),
         ontology_pair: ontology_pair,
         typed_governed_link_count: typed_governed_link_count,
         legacy_governed_artifact_count: legacy_governed_artifact_count,
         rebuild_required?: legacy_governed_artifact_count > 0 or not ontology_pair.complete?,
         explainable?: true
       }}
    end
  end

  defp export_graph(store, named_graph_resource, graph_name) do
    case TripleStore.Exporter.export_single_graph(store.db, store.dict_manager, named_graph_resource) do
      {:ok, graph} ->
        {:ok, graph}

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

  defp count_typed_governed_links(graph, managed_repo_id) do
    governed_prefix = GovernedReference.base_iri(managed_repo_id)

    graph
    |> RDF.Graph.triples()
    |> Enum.count(fn
      {_subject, predicate, %RDF.IRI{} = object} ->
        predicate_name =
          predicate
          |> to_string()
          |> String.split("#")
          |> List.last()

        predicate_name in @typed_governed_predicates and String.starts_with?(to_string(object), governed_prefix)

      _other ->
        false
    end)
  end

  defp count_legacy_governed_artifacts(graph, managed_repo_id) do
    legacy_prefix = "#{MemoryGraph.base_iri(managed_repo_id)}artifact/"

    graph
    |> RDF.Graph.triples()
    |> Enum.count(fn
      {_subject, predicate, %RDF.IRI{} = object} ->
        predicate_name =
          predicate
          |> to_string()
          |> String.split("#")
          |> List.last()

        predicate_name in ["supportedBy", "evidenceArtifact"] and
          String.starts_with?(to_string(object), legacy_prefix) and
          Enum.any?(@legacy_governed_artifact_segments, &String.contains?(to_string(object), "/#{&1}"))

      _other ->
        false
    end)
  end

  defp ontology_pair_status(memory_graph, workflow_graph) do
    memory_status = graph_ontology_status(memory_graph, :memory)
    workflow_status = graph_ontology_status(workflow_graph, :workflow_provenance)

    %{
      complete?: memory_status.complete? and workflow_status.complete?,
      memory: memory_status,
      workflow_provenance: workflow_status
    }
  end

  defp graph_ontology_status(graph, graph_name) do
    ontology_iris = MemoryGraph.ontology_iris()

    memory_ontology_loaded? = graph_contains_iri?(graph, ontology_iris.memory)
    control_plane_ontology_loaded? = graph_contains_iri?(graph, ontology_iris.control_plane)

    %{
      graph_name: graph_name,
      memory_ontology_loaded?: memory_ontology_loaded?,
      control_plane_ontology_loaded?: control_plane_ontology_loaded?,
      complete?: memory_ontology_loaded? and control_plane_ontology_loaded?
    }
  end

  defp graph_contains_iri?(graph, iri) when is_binary(iri) do
    graph
    |> RDF.Graph.triples()
    |> Enum.any?(fn
      {%RDF.IRI{} = subject, _predicate, _object} -> to_string(subject) == iri
      {_subject, %RDF.IRI{} = predicate, _object} -> to_string(predicate) == iri
      {_subject, _predicate, %RDF.IRI{} = object} -> to_string(object) == iri
      _other -> false
    end)
  end

  defp semantic_model_state(%{complete?: false}, _legacy_governed_artifact_count),
    do: :ontology_pair_incomplete

  defp semantic_model_state(_ontology_pair, legacy_governed_artifact_count)
       when legacy_governed_artifact_count > 0,
       do: :legacy_governed_artifacts

  defp semantic_model_state(_ontology_pair, _legacy_governed_artifact_count),
    do: :typed_governed_references

  defp semantic_failure(%{state: :ontology_pair_incomplete} = semantic_model) do
    %{
      kind: :memory_graph_ontology_pair_incomplete,
      operation: :validate,
      stage: :ontology_pair,
      message:
        "Repository memory graph is missing the companion ontology pair and must be recovered before typed governed semantics are trusted.",
      semantic_model: semantic_model
    }
  end

  defp semantic_failure(%{rebuild_required?: true} = semantic_model) do
    %{
      kind: :memory_graph_semantic_cutover_required,
      operation: :validate,
      stage: :legacy_governed_artifacts,
      message:
        "Repository memory graph still contains legacy governed artifact links and must be recovered before typed governed semantics are trusted.",
      semantic_model: semantic_model
    }
  end

  defp semantic_failure(_semantic_model), do: nil

  defp validation_state(true, _semantic_model, _latest_failure), do: :validated
  defp validation_state(false, %{rebuild_required?: true}, _latest_failure), do: :semantic_cutover_required
  defp validation_state(false, _semantic_model, _latest_failure), do: :not_ready

  defp validation_result_status(true, _semantic_model), do: :memory_graph_validated
  defp validation_result_status(false, %{rebuild_required?: true}), do: :memory_graph_recovery_required
  defp validation_result_status(false, _semantic_model), do: :memory_graph_not_ready

  defp default_semantic_model do
    %{
      state: :not_loaded,
      ontology_pair: %{
        complete?: false,
        memory: %{
          graph_name: :memory,
          memory_ontology_loaded?: false,
          control_plane_ontology_loaded?: false,
          complete?: false
        },
        workflow_provenance: %{
          graph_name: :workflow_provenance,
          memory_ontology_loaded?: false,
          control_plane_ontology_loaded?: false,
          complete?: false
        }
      },
      typed_governed_link_count: 0,
      legacy_governed_artifact_count: 0,
      rebuild_required?: false,
      explainable?: true
    }
  end
end
