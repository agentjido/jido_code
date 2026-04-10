defmodule JidoCode.MemoryGraphWorkspaceTest do
  # covers: architecture.agent_os_integration.memory_graph_read_write_and_query_stay_workspace_bound
  # covers: architecture.memory_graph.repo_scoped_memory_graph_pod
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
    end)

    :ok
  end

  describe "ensure_memory_graph_pod/3" do
    test "returns a product-owned summary without exposing pod internals" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, result} =
               AgentWorkspace.ensure_memory_graph_pod(managed_repo_id, workspace_path)

      assert result.managed_repo_id == managed_repo_id
      assert result.pod_id == "memory_graph"
      assert result.graph_names == ["memory", "workflow_provenance"]
      assert Map.has_key?(result, :graph_store_path)
      refute Map.has_key?(result, :module)
      refute Map.has_key?(result, :metadata)
    end

    test "returns a typed disabled error when the capability is not enabled" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:error, :memory_graph_disabled} =
               AgentWorkspace.ensure_memory_graph_pod(
                 managed_repo_id,
                 workspace_path,
                 enabled?: false
               )
    end
  end

  describe "refresh/validate/query entrypoints" do
    test "persists repository-scoped validation state after refresh and validate" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert refresh_result.latest_validation_status.ready? == true

      assert {:ok, validate_result} =
               AgentWorkspace.validate_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert validate_result.latest_validation_status.state == :validated

      assert {:ok, status_result} =
               AgentWorkspace.memory_graph_status(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      assert status_result.ready? == true
      assert status_result.stale? == false
      assert status_result.validated_revision == "abc123"
      assert status_result.latest_failure == nil
      assert status_result.feedback.state == :ready
      assert status_result.cross_graph.consistency.explainable? == true
    end

    test "returns typed not-ready error for query before refresh" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:error, :memory_graph_not_ready, diagnostics} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }"
               )

      assert diagnostics.feedback.recovery.action == :refresh
    end

    test "returns structured query results after refresh" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _refresh_result} =
               AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)

      assert {:ok, query_result} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?class
                 WHERE {
                   ?class a owl:Class .
                   FILTER(?class = jido:WorkSession)
                 }
                 """,
                 graph_name: "workflow_provenance"
               )

      assert query_result.engine == :sparql
      assert query_result.graph_name == "workflow_provenance"
      assert query_result.row_count == 1
      assert query_result.feedback.state == :ready
    end

    test "surfaces stale repository state after workspace changes and allows explicit stale queries" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "abc123"
               )

      rewrite_workspace_module!(workspace_path, "ExampleMemoryWorkspaceRenamed")

      assert {:ok, status_result} =
               AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path)

      assert status_result.ready? == true
      assert status_result.stale? == true
      assert status_result.stale_reason == :workspace_revision_changed
      assert status_result.queryable_when_stale? == true
      assert status_result.current_revision != refresh_result.latest_validation_status.validated_revision
      assert status_result.feedback.recovery.action == :validate

      assert {:ok, query_result} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o } LIMIT 5",
                 allow_stale?: true
               )

      assert query_result.degraded? == true
      assert query_result.stale_graph? == true
      assert query_result.feedback.recovery.action == :validate
    end

    test "persists latest failure state for blocked refresh" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      blocker_path = Path.join(workspace_path, ".jido_code")

      File.write!(blocker_path, "block store directory")

      assert {:error, :memory_graph_refresh_failed, diagnostics} =
               AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)

      assert diagnostics.stage == :prepare_store_parent

      assert {:ok, failed_status} =
               AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path)

      assert failed_status.ready? == false
      assert failed_status.latest_failure.kind == :memory_graph_refresh_failed
      assert failed_status.latest_failure.operation == :refresh
      assert failed_status.latest_failure.stage == :prepare_store_parent
      assert failed_status.feedback.recovery.action == :recover
    end

    test "routes record and invalidate through bounded workspace entrypoints" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _refresh_result} =
               AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)

      assert {:ok, record_result} =
               AgentWorkspace.record_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 JidoCode.MemoryGraph.CaptureEnvelope.work_session(
                   session_id: "workspace-session",
                   actor_id: "system:workspace-test",
                   workflow: :plan,
                   work_item_id: "work-1",
                   goal: "Test workspace provenance"
                 )
               )

      assert record_result.status == :workflow_provenance_recorded

      assert {:ok, query_result} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "workspace-session" .
                 }
                 """,
                 graph_name: "workflow_provenance"
               )

      assert query_result.row_count == 1

      assert {:ok, invalidate_result} =
               AgentWorkspace.invalidate_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 reason: :manual_invalidation
               )

      assert invalidate_result.status == :memory_graph_invalidated
      assert invalidate_result.feedback.recovery.action == :validate

      assert {:ok, invalidated_status} =
               AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path)

      assert invalidated_status.latest_validation_status.state == :invalidated
      assert invalidated_status.latest_validation_status.ready? == false
      assert invalidated_status.feedback.state == :invalidated
    end

    test "recovers invalidated graph state through a repository-scoped recovery action" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _refresh_result} =
               AgentWorkspace.refresh_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "recoverable-revision"
               )

      assert {:ok, _invalidate_result} =
               AgentWorkspace.invalidate_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 reason: :manual_invalidation,
                 revision: "recoverable-revision"
               )

      assert {:ok, recovery_result} =
               AgentWorkspace.recover_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "recoverable-revision"
               )

      assert recovery_result.status == :memory_graph_recovered
      assert recovery_result.recovery_action == :validate
      assert recovery_result.graph_status.ready? == true
      assert recovery_result.graph_status.stale? == false
    end

    test "explains cross-graph consistency when linked source graph is stale" do
      previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)
      Application.put_env(:jido_code, :source_code_graph_enabled, true)
      on_exit(fn -> Application.put_env(:jido_code, :source_code_graph_enabled, previous_source) end)

      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _source_graph} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "graph-aligned"
               )

      assert {:ok, _memory_graph} =
               AgentWorkspace.refresh_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "graph-aligned"
               )

      assert {:ok, status_result} =
               AgentWorkspace.memory_graph_status(
                 managed_repo_id,
                 workspace_path,
                 revision: "graph-stale"
               )

      assert status_result.cross_graph.source_code.state == :stale
      assert status_result.cross_graph.consistency.state == :source_code_stale
      assert status_result.feedback.cross_graph.consistency.state == :source_code_stale
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_memory_graph_workspace_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule MemoryGraphWorkspaceExample.MixProject do
        use Mix.Project

        def project do
          [app: :memory_graph_workspace_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule ExampleMemoryWorkspace do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end
end
