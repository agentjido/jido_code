defmodule JidoCode.MemoryGraphTest do
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.source_code_graph_pod.code_entities_use_stable_iris_for_cross_graph_links
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: true

  alias JidoCode.{MemoryGraph, SourceCodeGraph}

  describe "graph boundary helpers" do
    test "reuses the repository-local quad store path used by the source code graph" do
      workspace_path = Path.join(System.tmp_dir!(), "memory_graph_workspace")

      assert MemoryGraph.graph_store_path(workspace_path) ==
               SourceCodeGraph.graph_store_path(workspace_path)
    end

    test "exposes canonical graph names, graph IRIs, and ontology artifacts" do
      assert MemoryGraph.graph_names() == ["memory", "workflow_provenance"]

      assert MemoryGraph.named_graph_iris() == %{
               memory: "https://jido.run/graphs/memory",
               workflow_provenance: "https://jido.run/graphs/workflow_provenance"
             }

      [artifact] = MemoryGraph.ontology_artifacts()
      assert artifact.kind == :ontology_schema
      assert artifact.filename == "jido-memory.ttl"
      assert artifact.format == :turtle
      assert String.ends_with?(artifact.path, "/priv/ontologies/jido-memory.ttl")
    end

    test "exposes stable repository-scoped base IRIs for memory and provenance" do
      assert MemoryGraph.base_iri("repo-123") ==
               "https://jido.run/managed_repos/repo-123/memory#"

      assert MemoryGraph.workflow_provenance_base_iri("repo-123") ==
               "https://jido.run/managed_repos/repo-123/workflow_provenance#"

      assert MemoryGraph.source_code_base_iri("repo-123") ==
               "https://jido.run/managed_repos/repo-123/source_code#"
    end

    test "builds graph context and pod metadata with explicit validation state" do
      workspace_path = create_workspace_path!()

      assert {:ok, graph_context} = MemoryGraph.graph_context("repo-123", workspace_path)

      assert graph_context.graph_names == ["memory", "workflow_provenance"]
      assert graph_context.dataset_metadata.graph_store_path == MemoryGraph.graph_store_path(workspace_path)
      assert graph_context.latest_record_status.state == :not_recorded
      assert graph_context.latest_query_status.state == :not_queried
      assert graph_context.latest_validation_status.state == :not_validated

      assert {:ok, pod_metadata} = MemoryGraph.pod_metadata("repo-123", workspace_path)
      assert pod_metadata.scope == :repository
      assert pod_metadata.graph_names == ["memory", "workflow_provenance"]
      assert Map.has_key?(pod_metadata, :latest_validation_status)
      assert pod_metadata.graph_store_path == MemoryGraph.graph_store_path(workspace_path)
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_memory_graph_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end
end
