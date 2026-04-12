defmodule JidoCode.MemoryGraph do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.source_code_graph_pod.code_entities_use_stable_iris_for_cross_graph_links
  # covers: architecture.source_code_graph_pod.stable_code_links_support_governed_memory_navigation
  @moduledoc """
  Product-owned boundary helpers for repository-scoped memory graph state.

  The boundary fixes the canonical graph identities, ontology asset location,
  repository-local store path, and repository-scoped revision metadata needed by
  the MemoryGraphPod runtime.
  """

  alias JidoCode.SourceCodeGraph

  @pod_id "memory_graph"
  @memory_graph_name "memory"
  @workflow_provenance_graph_name "workflow_provenance"
  @memory_named_graph_iri "https://jido.run/graphs/memory"
  @workflow_provenance_named_graph_iri "https://jido.run/graphs/workflow_provenance"
  @memory_ontology_iri "https://jido.run/ontology/memory#"
  @control_plane_ontology_iri "https://jido.run/ontology/control-plane#"
  @memory_ontology_filename "jido-memory.ttl"
  @control_plane_ontology_filename "jido-control-plane.ttl"

  @type managed_repo_id :: String.t()
  @type workspace_path :: String.t()
  @type revision_metadata :: map()
  @type graph_name :: String.t()

  @spec pod_id() :: String.t()
  def pod_id, do: @pod_id

  @spec memory_graph_name() :: String.t()
  def memory_graph_name, do: @memory_graph_name

  @spec workflow_provenance_graph_name() :: String.t()
  def workflow_provenance_graph_name, do: @workflow_provenance_graph_name

  @spec graph_names() :: [String.t()]
  def graph_names, do: [@memory_graph_name, @workflow_provenance_graph_name]

  @spec memory_named_graph_iri() :: String.t()
  def memory_named_graph_iri, do: @memory_named_graph_iri

  @spec workflow_provenance_named_graph_iri() :: String.t()
  def workflow_provenance_named_graph_iri, do: @workflow_provenance_named_graph_iri

  @spec memory_ontology_iri() :: String.t()
  def memory_ontology_iri, do: @memory_ontology_iri

  @spec control_plane_ontology_iri() :: String.t()
  def control_plane_ontology_iri, do: @control_plane_ontology_iri

  @spec named_graph_iris() :: %{memory: String.t(), workflow_provenance: String.t()}
  def named_graph_iris do
    %{
      memory: @memory_named_graph_iri,
      workflow_provenance: @workflow_provenance_named_graph_iri
    }
  end

  @spec ontology_iris() :: %{memory: String.t(), control_plane: String.t()}
  def ontology_iris do
    %{
      memory: @memory_ontology_iri,
      control_plane: @control_plane_ontology_iri
    }
  end

  @spec normalize_graph_name(graph_name() | atom() | nil) :: {:ok, graph_name()} | {:error, atom()}
  def normalize_graph_name(nil), do: {:ok, @memory_graph_name}
  def normalize_graph_name(:memory), do: {:ok, @memory_graph_name}
  def normalize_graph_name(:workflow_provenance), do: {:ok, @workflow_provenance_graph_name}
  def normalize_graph_name(@memory_graph_name), do: {:ok, @memory_graph_name}
  def normalize_graph_name(@workflow_provenance_graph_name), do: {:ok, @workflow_provenance_graph_name}
  def normalize_graph_name(_value), do: {:error, :invalid_memory_graph_name}

  @spec named_graph_iri(graph_name() | atom()) :: String.t()
  def named_graph_iri(graph_name) do
    case normalize_graph_name(graph_name) do
      {:ok, @memory_graph_name} -> @memory_named_graph_iri
      {:ok, @workflow_provenance_graph_name} -> @workflow_provenance_named_graph_iri
    end
  end

  @spec named_graph_resource(graph_name() | atom()) :: RDF.IRI.t()
  def named_graph_resource(graph_name), do: RDF.iri(named_graph_iri(graph_name))

  @spec memory_named_graph_resource() :: RDF.IRI.t()
  def memory_named_graph_resource, do: named_graph_resource(@memory_graph_name)

  @spec workflow_provenance_named_graph_resource() :: RDF.IRI.t()
  def workflow_provenance_named_graph_resource, do: named_graph_resource(@workflow_provenance_graph_name)

  @spec capability_enabled?(keyword()) :: boolean()
  def capability_enabled?(opts \\ []) do
    Keyword.get(opts, :enabled?, Application.get_env(:jido_code, :memory_graph_enabled, false))
  end

  @spec normalize_workspace_path(workspace_path() | nil) :: {:ok, workspace_path()} | {:error, atom()}
  def normalize_workspace_path(path), do: SourceCodeGraph.normalize_workspace_path(path)

  @spec graph_store_path(workspace_path()) :: String.t()
  def graph_store_path(workspace_path), do: SourceCodeGraph.graph_store_path(workspace_path)

  @spec base_iri(managed_repo_id()) :: String.t()
  def base_iri(managed_repo_id) when is_binary(managed_repo_id) do
    "https://jido.run/managed_repos/#{managed_repo_id}/memory#"
  end

  @spec workflow_provenance_base_iri(managed_repo_id()) :: String.t()
  def workflow_provenance_base_iri(managed_repo_id) when is_binary(managed_repo_id) do
    "https://jido.run/managed_repos/#{managed_repo_id}/workflow_provenance#"
  end

  @spec artifact_path(atom() | String.t(), String.t()) :: String.t() | nil
  def artifact_path(kind, id) when is_binary(id) do
    case normalize_artifact_kind(kind) do
      nil -> nil
      key -> "#{key}/#{id}"
    end
  end

  @spec artifact_iri(managed_repo_id(), String.t()) :: RDF.IRI.t()
  def artifact_iri(managed_repo_id, path) when is_binary(managed_repo_id) and is_binary(path) do
    RDF.iri("#{base_iri(managed_repo_id)}artifact/#{URI.encode(path)}")
  end

  @spec source_code_base_iri(managed_repo_id()) :: String.t()
  def source_code_base_iri(managed_repo_id), do: SourceCodeGraph.base_iri(managed_repo_id)

  @spec ontology_path() :: String.t()
  def ontology_path do
    Application.app_dir(:jido_code, Path.join("priv/ontologies", @memory_ontology_filename))
  end

  @spec control_plane_ontology_path() :: String.t()
  def control_plane_ontology_path do
    Application.app_dir(:jido_code, Path.join("priv/ontologies", @control_plane_ontology_filename))
  end

  @spec ontology_artifacts() :: [map()]
  def ontology_artifacts do
    [
      %{
        kind: :ontology_schema,
        filename: @memory_ontology_filename,
        format: :turtle,
        path: ontology_path()
      },
      %{
        kind: :ontology_schema,
        filename: @control_plane_ontology_filename,
        format: :turtle,
        path: control_plane_ontology_path()
      }
    ]
  end

  @spec current_revision_metadata(workspace_path(), keyword()) ::
          {:ok, revision_metadata()} | {:error, atom()}
  def current_revision_metadata(workspace_path, opts \\ []) when is_list(opts) do
    SourceCodeGraph.current_revision_metadata(workspace_path, opts)
  end

  @spec dataset_metadata(managed_repo_id(), workspace_path(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def dataset_metadata(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         dataset_id: "#{managed_repo_id}:memory_graph",
         graph_names: graph_names(),
         named_graph_iris: named_graph_iris(),
         memory_graph_name: @memory_graph_name,
         workflow_provenance_graph_name: @workflow_provenance_graph_name,
         base_iri: base_iri(managed_repo_id),
         workflow_provenance_base_iri: workflow_provenance_base_iri(managed_repo_id),
         source_code_base_iri: source_code_base_iri(managed_repo_id),
         workspace_path: normalized_workspace_path,
         graph_store_path: graph_store_path(normalized_workspace_path),
         revision: Keyword.get(opts, :revision),
         triple_store_schema: :quad
       }}
    end
  end

  @spec graph_context(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom()}
  def graph_context(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, metadata} <- dataset_metadata(managed_repo_id, workspace_path, opts),
         {:ok, revision_metadata} <- current_revision_metadata(workspace_path, opts) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         workspace_path: metadata.workspace_path,
         graph_store_path: metadata.graph_store_path,
         graph_names: metadata.graph_names,
         named_graph_iris: metadata.named_graph_iris,
         revision_metadata: revision_metadata,
         dataset_metadata: metadata,
         latest_record_status: %{
           state: :not_recorded,
           ready?: false,
           graph_name: @memory_graph_name,
           recorded_at: nil,
           failure: nil
         },
         latest_query_status: %{
           state: :not_queried,
           ready?: false,
           graph_name: @memory_graph_name,
           queried_at: nil,
           failure: nil
         },
         latest_validation_status: default_validation_status(revision_metadata),
         latest_failure: nil
       }}
    end
  end

  @spec pod_metadata(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom()}
  def pod_metadata(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, context} <- graph_context(managed_repo_id, workspace_path, opts) do
      {:ok,
       %{
         scope: :repository,
         graph_names: context.graph_names,
         named_graph_iris: context.named_graph_iris,
         workspace_path: context.workspace_path,
         graph_store_path: context.graph_store_path,
         revision_metadata: context.revision_metadata,
         latest_record_status: context.latest_record_status,
         latest_query_status: context.latest_query_status,
         latest_validation_status: context.latest_validation_status,
         latest_failure: context.latest_failure,
         dataset_metadata: context.dataset_metadata
       }}
    end
  end

  defp default_validation_status(revision_metadata) do
    %{
      state: :not_validated,
      ready?: false,
      graph_name: @memory_graph_name,
      current_revision: revision_metadata.current_revision,
      validated_revision: nil,
      validated_at: nil,
      stale?: false,
      failure: nil
    }
  end

  defp normalize_artifact_kind(:run), do: "run_id"
  defp normalize_artifact_kind(:run_id), do: "run_id"
  defp normalize_artifact_kind(:work_item), do: "work_item_id"
  defp normalize_artifact_kind(:work_item_id), do: "work_item_id"
  defp normalize_artifact_kind(:evidence), do: "evidence_id"
  defp normalize_artifact_kind(:evidence_id), do: "evidence_id"
  defp normalize_artifact_kind(:decision), do: "decision_id"
  defp normalize_artifact_kind(:decision_id), do: "decision_id"
  defp normalize_artifact_kind(:observation), do: "observation_id"
  defp normalize_artifact_kind(:observation_id), do: "observation_id"
  defp normalize_artifact_kind(:assessment), do: "assessment_id"
  defp normalize_artifact_kind(:assessment_id), do: "assessment_id"

  defp normalize_artifact_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "run" -> "run_id"
      "run_id" -> "run_id"
      "work_item" -> "work_item_id"
      "work_item_id" -> "work_item_id"
      "evidence" -> "evidence_id"
      "evidence_id" -> "evidence_id"
      "decision" -> "decision_id"
      "decision_id" -> "decision_id"
      "observation" -> "observation_id"
      "observation_id" -> "observation_id"
      "assessment" -> "assessment_id"
      "assessment_id" -> "assessment_id"
      _other -> nil
    end
  end

  defp normalize_artifact_kind(_kind), do: nil
end
