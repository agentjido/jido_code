defmodule JidoCode.SourceCodeGraphTest do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  # covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  use ExUnit.Case, async: true

  alias JidoCode.SourceCodeGraph

  describe "graph boundary helpers" do
    test "defines canonical graph identity and ontology profile" do
      assert SourceCodeGraph.pod_id() == "source_code_graph"
      assert SourceCodeGraph.graph_name() == "source_code"
      assert SourceCodeGraph.ontology_profile() == "full"
    end

    test "builds repository-local graph store metadata" do
      assert {:ok, metadata} =
               SourceCodeGraph.dataset_metadata("repo-123", "/tmp/example-repo", revision: "abc123")

      assert metadata.graph_name == "source_code"
      assert metadata.ontology_profile == "full"
      assert metadata.triple_store_schema == :quad
      assert metadata.dataset_id == "repo-123:source_code"
      assert String.ends_with?(metadata.graph_store_path, ".jido_code/source_code_graph/triple_store")
    end

    test "rejects missing workspace paths" do
      assert {:error, :missing_workspace_path} = SourceCodeGraph.dataset_metadata("repo-123", "")
    end
  end
end
