defmodule JidoCode.SourceCodeGraphWorkspaceTest do
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.agent_os_integration.source_code_graph_stale_and_recovery_state_stays_workspace_bound
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_integration_gateways_preserve_actor_bound_policy
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
      workspace_path = create_workspace_path!()

      assert {:ok, result} =
               AgentWorkspace.ensure_source_code_graph_pod(managed_repo_id, workspace_path)

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
      workspace_path = create_workspace_path!()

      assert {:error, :source_code_graph_disabled} =
               AgentWorkspace.ensure_source_code_graph_pod(
                 managed_repo_id,
                 workspace_path,
                 enabled?: false
               )
    end
  end

  describe "load/refresh/query entrypoints" do
    test "persists analysis state in repository-scoped status" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, analysis_result} =
               AgentWorkspace.analyze_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert analysis_result.latest_analysis_status.state == :analyzed

      assert {:ok, status_result} =
               AgentWorkspace.source_code_graph_status(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert status_result.ready? == false
      assert status_result.stale? == false
      assert status_result.requested_revision == "abc123"
      assert status_result.latest_analysis_status.state == :analyzed
      assert status_result.latest_analysis_status.analyzed_revision == "abc123"
    end

    test "persists repository-scoped graph readiness after load" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert load_result.latest_import_status.ready? == true

      assert {:ok, status_result} =
               AgentWorkspace.source_code_graph_status(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert status_result.ready? == true
      assert status_result.stale? == false
      assert status_result.stale_reason == nil
      assert status_result.queryable_when_stale? == false
      assert status_result.imported_revision == "abc123"
      assert status_result.latest_import_status.state == :loaded
      assert status_result.latest_analysis_status.state == :analyzed
      assert status_result.latest_failure == nil
    end

    test "returns typed not-ready error for query before load" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:error, :source_code_graph_not_ready, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }"
               )
    end

    test "returns structured semantic query results after load" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, query_result} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?module
                 WHERE {
                   ?module a struct:Module .
                 }
                 """
               )

      assert query_result.engine == :sparql
      assert query_result.graph_name == "source_code"
      assert query_result.row_count >= 1
    end

    test "returns a typed stale outcome when the loaded revision is outdated" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert {:error, :source_code_graph_stale, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }",
                 revision: "def456"
               )
    end

    test "surfaces stale repository state after workspace changes and allows explicit stale queries" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      rewrite_workspace_module!(workspace_path, "ExampleWorkspaceRenamed")

      assert {:ok, status_result} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert status_result.ready? == true
      assert status_result.stale? == true
      assert status_result.stale_reason == :workspace_revision_changed
      assert status_result.queryable_when_stale? == true
      assert status_result.current_revision != load_result.latest_import_status.imported_revision

      assert {:ok, query_result} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o } LIMIT 5",
                 allow_stale?: true
               )

      assert query_result.degraded? == true
      assert query_result.stale_graph? == true
    end

    test "persists latest failure state and recovers after a failed load" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      blocker_path = Path.join(workspace_path, ".jido_code")

      File.write!(blocker_path, "block store directory")

      assert {:error, :source_code_graph_store_failed, diagnostics} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert diagnostics.stage == :prepare_store_parent

      assert {:ok, failed_status} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert failed_status.ready? == false
      assert failed_status.latest_failure.kind == :source_code_graph_store_failed
      assert failed_status.latest_failure.operation == :load
      assert failed_status.latest_failure.stage == :prepare_store_parent

      File.rm!(blocker_path)

      assert {:ok, recovery_result} =
               AgentWorkspace.recover_source_code_graph(managed_repo_id, workspace_path)

      assert recovery_result.recovery_action == :load
      assert recovery_result.graph_status.ready? == true

      assert {:ok, recovered_status} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert recovered_status.ready? == true
      assert recovered_status.latest_failure == nil
    end

    test "exposes bounded helper entrypoints for modules and functions" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, modules_result} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "ExampleWorkspace"
               )

      assert modules_result.helper == :modules
      assert modules_result.row_count >= 1

      assert {:ok, functions_result} =
               AgentWorkspace.find_source_code_graph_functions(
                 managed_repo_id,
                 workspace_path,
                 module_name: "ExampleWorkspace",
                 function_name: "greet"
               )

      assert functions_result.helper == :functions
      assert functions_result.row_count >= 1
    end

    test "exposes bounded helper entrypoints for runtime patterns and impact" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, runtime_result} =
               AgentWorkspace.find_source_code_graph_runtime_patterns(
                 managed_repo_id,
                 workspace_path
               )

      assert runtime_result.helper == :runtime_patterns

      assert {:ok, impact_result} =
               AgentWorkspace.trace_source_code_graph_impact(
                 managed_repo_id,
                 workspace_path,
                 module_name: "ExampleWorkspace"
               )

      assert impact_result.helper == :impact
      assert impact_result.row_count >= 1
    end

    test "keeps graph readiness repository-scoped" do
      repo_one = "repo-#{System.unique_integer()}"
      repo_two = "repo-#{System.unique_integer()}"
      workspace_one = create_workspace_path!()
      workspace_two = create_workspace_path!()

      assert {:ok, _result} = AgentWorkspace.load_source_code_graph(repo_one, workspace_one)

      assert {:ok, repo_one_status} =
               AgentWorkspace.source_code_graph_status(repo_one, workspace_one)

      assert {:ok, repo_two_status} =
               AgentWorkspace.source_code_graph_status(repo_two, workspace_two)

      assert repo_one_status.ready? == true
      assert repo_two_status.ready? == false
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_source_code_graph_workspace_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule ExampleWorkspace.MixProject do
        use Mix.Project

        def project do
          [app: :example_workspace, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule ExampleWorkspace do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end
end
