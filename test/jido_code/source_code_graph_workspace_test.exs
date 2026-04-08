defmodule JidoCode.SourceCodeGraphWorkspaceTest do
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: false

  alias JidoCode.AgentWorkspace

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  describe "ensure_source_code_graph_pod/3" do
    test "returns a product-owned summary without exposing pod internals" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.ensure_source_code_graph_pod(managed_repo_id, "/tmp/example-repo")

      assert result.managed_repo_id == managed_repo_id
      assert result.pod_id == "source_code_graph"
      assert result.graph_name == "source_code"
      assert result.ontology_profile == "full"
      assert Map.has_key?(result, :graph_store_path)
      refute Map.has_key?(result, :module)
      refute Map.has_key?(result, :metadata)
    end

    test "returns a typed disabled error when the capability is not enabled" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:error, :source_code_graph_disabled} =
               AgentWorkspace.ensure_source_code_graph_pod(
                 managed_repo_id,
                 "/tmp/example-repo",
                 enabled?: false
               )
    end
  end

  describe "load/refresh/query entrypoints" do
    test "persists repository-scoped graph readiness after load" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:ok, load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 "/tmp/example-repo",
                 revision: "abc123"
               )

      assert load_result.latest_import_status.ready? == true

      assert {:ok, status_result} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, "/tmp/example-repo")

      assert status_result.ready? == true
      assert status_result.latest_import_status.state == :loaded
    end

    test "returns typed not-ready error for query before load" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:error, :source_code_graph_not_ready, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 "/tmp/example-repo",
                 "SELECT * WHERE { ?s ?p ?o }"
               )
    end

    test "returns structured semantic query results after load" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, "/tmp/example-repo")

      assert {:ok, query_result} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 "/tmp/example-repo",
                 "SELECT * WHERE { GRAPH <source_code> { ?s ?p ?o } }"
               )

      assert query_result.engine == :sparql
      assert query_result.graph_name == "source_code"
      assert query_result.bindings == []
    end

    test "keeps graph readiness repository-scoped" do
      repo_one = "repo-#{System.unique_integer()}"
      repo_two = "repo-#{System.unique_integer()}"

      assert {:ok, _result} = AgentWorkspace.load_source_code_graph(repo_one, "/tmp/repo-one")

      assert {:ok, repo_one_status} =
               AgentWorkspace.source_code_graph_status(repo_one, "/tmp/repo-one")

      assert {:ok, repo_two_status} =
               AgentWorkspace.source_code_graph_status(repo_two, "/tmp/repo-two")

      assert repo_one_status.ready? == true
      assert repo_two_status.ready? == false
    end
  end
end
