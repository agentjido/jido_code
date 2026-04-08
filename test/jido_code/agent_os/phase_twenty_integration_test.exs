defmodule JidoCode.AgentOSPhaseTwentyIntegrationTest do
  # covers: architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.agent_os_integration.actions_use_jido_action
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: false

  alias JidoCode.AgentOS.Manager
  alias JidoCode.AgentWorkspace

  alias JidoCode.Actions.{
    AnalyzeSourceCodeGraph,
    LoadSourceCodeGraph,
    RefreshSourceCodeGraph,
    GetSourceCodeGraphStatus,
    QuerySourceCodeGraph,
    InspectSourceCodeGraphDataset
  }

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  describe "20.4.1 Repository-scoped pod contract scenarios" do
    test "20.4.1.1 one repository can host a source code graph pod without affecting another kernel" do
      repo_one = "repo-#{System.unique_integer()}"
      repo_two = "repo-#{System.unique_integer()}"

      assert {:ok, repo_one_summary} =
               AgentWorkspace.ensure_source_code_graph_pod(repo_one, "/tmp/repo-one")

      assert {:ok, repo_two_summary} =
               AgentWorkspace.ensure_source_code_graph_pod(repo_two, "/tmp/repo-two")

      assert repo_one_summary.pod_id == "source_code_graph"
      assert repo_two_summary.pod_id == "source_code_graph"
      assert repo_one_summary.graph_store_path != repo_two_summary.graph_store_path

      assert Manager.pod_status(repo_one, "source_code_graph").metadata.workspace_path == "/tmp/repo-one"
      assert Manager.pod_status(repo_two, "source_code_graph").metadata.workspace_path == "/tmp/repo-two"
    end

    test "20.4.1.2 the source code graph pod remains singleton per repository even when work items multiply" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:ok, _summary} =
               AgentWorkspace.ensure_source_code_graph_pod(managed_repo_id, "/tmp/example-repo")

      assert {:ok, _summary} =
               AgentWorkspace.ensure_source_code_graph_pod(managed_repo_id, "/tmp/example-repo")

      assert {:ok, _pod_name_one} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, "work-#{System.unique_integer()}", "/tmp")

      assert {:ok, _pod_name_two} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, "work-#{System.unique_integer()}", "/tmp")

      source_graph_pods =
        managed_repo_id
        |> Manager.list_pods()
        |> Enum.filter(&(&1.pod_id == "source_code_graph"))

      assert length(source_graph_pods) == 1
    end

    test "20.4.1.3 AgentWorkspace hides the pod topology from callers" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:ok, summary} =
               AgentWorkspace.ensure_source_code_graph_pod(managed_repo_id, "/tmp/example-repo")

      refute Map.has_key?(summary, :module)
      refute Map.has_key?(summary, :metadata)
      refute Map.has_key?(summary, :manager)
      refute Map.has_key?(summary, :topology)
    end
  end

  describe "20.4.2 Explicit action and boundary scenarios" do
    test "20.4.2.1 the action set for analyze, load, refresh, and query is explicit and schema-driven" do
      expected_actions = [
        {AnalyzeSourceCodeGraph, :workspace_path},
        {LoadSourceCodeGraph, :workspace_path},
        {RefreshSourceCodeGraph, :workspace_path},
        {GetSourceCodeGraphStatus, :workspace_path},
        {QuerySourceCodeGraph, :sparql},
        {InspectSourceCodeGraphDataset, :workspace_path}
      ]

      Enum.each(expected_actions, fn {action, expected_field} ->
        assert function_exported?(action, :run, 2)
        assert function_exported?(action, :schema, 0)
        assert Keyword.keyword?(action.schema())
        assert Keyword.has_key?(action.schema(), expected_field)
      end)
    end

    test "20.4.2.2 disabled or not-ready graph states surface as typed workspace outcomes" do
      managed_repo_id = "repo-#{System.unique_integer()}"

      assert {:error, :source_code_graph_disabled} =
               AgentWorkspace.ensure_source_code_graph_pod(
                 managed_repo_id,
                 "/tmp/example-repo",
                 enabled?: false
               )

      assert {:error, :source_code_graph_not_ready, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 "/tmp/example-repo",
                 "SELECT * WHERE { ?s ?p ?o }"
               )
    end
  end
end
