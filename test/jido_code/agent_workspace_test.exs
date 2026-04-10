defmodule JidoCode.AgentWorkspaceTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.agent_os_integration.workspace_context
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.pod_cleanup_on_completion
  # covers: architecture.agent_os_integration.multiple_pods_parallel_execution
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  # covers: architecture.agent_os_integration.missing_kernel_runtime_recovers_from_snapshot
  # covers: architecture.agent_os_integration.repository_work_queue_is_bounded
  # covers: architecture.agent_os_integration.eager_collaboration_state_is_seeded_before_specialist_work
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_capacity_limits_fail_closed
  # covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.source_code_graph_pod.workspace_binding_is_explicit_and_product_owned
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentOS.Manager
  alias JidoCode.AgentWorkspace

  describe "kernel lifecycle" do
    test "ensure_kernel creates or returns existing kernel" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"

      assert {:ok, kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
      assert is_atom(kernel_name)

      # Calling again should return the same kernel
      assert {:ok, ^kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
    end

    test "kernel_status returns nil for non-existent kernel" do
      refute AgentWorkspace.kernel_status("nonexistent-repo-#{System.unique_integer()}")
    end

    test "list_kernels returns list of kernel names" do
      kernels = AgentWorkspace.list_kernels()
      assert is_list(kernels)
    end

    test "shutdown_kernel is idempotent" do
      managed_repo_id = "temp-repo-#{System.unique_integer()}"

      # Should not error even if kernel doesn't exist
      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)
    end

    test "ensure_kernel restores persisted work pods after a restart" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, initial_result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Persist planning state",
                 workspace_path: workspace_path
               )

      assert initial_result.plan =~ "deterministic planner response"
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)

      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)
      refute Manager.kernel_exists?(managed_repo_id)

      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)

      pod_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(pod_status, [:metadata, :last_plan, :plan]) =~ "deterministic planner response"
    end

    test "ensure_kernel recovers after an unexpected kernel crash" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      old_pid =
        managed_repo_id
        |> Manager.kernel_status()
        |> Map.fetch!(:supervisor_pid)

      Process.exit(old_pid, :kill)
      Process.sleep(200)

      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      new_pid =
        managed_repo_id
        |> Manager.kernel_status()
        |> Map.fetch!(:supervisor_pid)

      assert is_pid(new_pid)
      refute new_pid == old_pid
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)
    end
  end

  describe "pod lifecycle" do
    test "ensure_coding_pod returns ok with pod name" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      assert is_atom(pod_name)
    end

    test "complete_work stops the work item and removes it from active work" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)

      assert :ok = AgentWorkspace.complete_work(managed_repo_id, work_item_id)
      refute work_item_id in AgentWorkspace.active_work_items(managed_repo_id)
    end

    test "active_work_items returns active coding work items" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      items = AgentWorkspace.active_work_items(managed_repo_id)
      assert work_item_id in items
    end

    test "enforces a bounded concurrent work queue for new work items" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      work_item_1 = "work-#{System.unique_integer()}"
      work_item_2 = "work-#{System.unique_integer()}"
      previous_limit = Application.get_env(:jido_code, :agent_workspace_max_concurrent_work_items)

      Application.put_env(:jido_code, :agent_workspace_max_concurrent_work_items, 1)

      on_exit(fn ->
        if is_nil(previous_limit) do
          Application.delete_env(:jido_code, :agent_workspace_max_concurrent_work_items)
        else
          Application.put_env(:jido_code, :agent_workspace_max_concurrent_work_items, previous_limit)
        end

        File.rm_rf!(workspace_path)
      end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_1, workspace_path)

      assert {:error, {:work_queue_full, %{limit: 1, active_work_items: [^work_item_1]}}} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_2, workspace_path)
    end
  end

  describe "work execution" do
    test "plan_work returns ok with plan map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Implement feature",
                 workspace_path: workspace_path
               )

      assert is_map(result)
      assert Map.has_key?(result, :plan)
      assert result.plan =~ "deterministic planner response"
    end

    test "execute_work returns ok with changes map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 work_item_id,
                 "Implement function",
                 workspace_path: workspace_path
               )

      assert is_map(result)
      assert Map.has_key?(result, :changes)
      assert result.changes =~ "deterministic coder response"
    end

    test "review_work returns ok with feedback map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 work_item_id,
                 "Review code",
                 workspace_path: workspace_path
               )

      assert is_map(result)
      assert Map.has_key?(result, :feedback)
      assert result.feedback =~ "deterministic reviewer response"
    end

    test "full_workflow returns ok with plan, changes, and feedback" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.full_workflow(
                 managed_repo_id,
                 work_item_id,
                 "Full workflow",
                 workspace_path: workspace_path
               )

      assert Map.has_key?(result, :plan)
      assert Map.has_key?(result, :changes)
      assert Map.has_key?(result, :feedback)
    end

    test "work entrypoints emit workflow provenance in the workflow_provenance graph" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      plan_work_item_id = "plan-#{System.unique_integer()}"
      coding_work_item_id = "code-#{System.unique_integer()}"
      review_work_item_id = "review-#{System.unique_integer()}"
      explain_work_item_id = "explain-#{System.unique_integer()}"
      previous = Application.get_env(:jido_code, :memory_graph_enabled, false)

      Application.put_env(:jido_code, :memory_graph_enabled, true)

      on_exit(fn ->
        Application.put_env(:jido_code, :memory_graph_enabled, previous)
        File.rm_rf!(workspace_path)
      end)

      assert {:ok, plan_result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 plan_work_item_id,
                 "Plan with provenance",
                 workspace_path: workspace_path
               )

      assert {:ok, code_result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 coding_work_item_id,
                 "Code with provenance",
                 workspace_path: workspace_path
               )

      assert {:ok, review_result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 review_work_item_id,
                 "Review with provenance",
                 workspace_path: workspace_path
               )

      assert {:ok, explain_result} =
               AgentWorkspace.explain_work(
                 managed_repo_id,
                 explain_work_item_id,
                 "Explain with provenance",
                 workspace_path: workspace_path
               )

      assert plan_result.workflow_provenance.workflow == :plan
      assert code_result.workflow_provenance.workflow == :execute
      assert review_result.workflow_provenance.workflow == :review
      assert explain_result.workflow_provenance.workflow == :explain

      assert {:ok, plan_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?run ?tool ?plan
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{plan_result.workflow_provenance.session_id}" ;
                     jido:hasAgentRun ?run ;
                     jido:hasToolInvocation ?tool ;
                     jido:hasPlan ?plan .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert plan_query.row_count == 1

      assert {:ok, code_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?patch
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{code_result.workflow_provenance.session_id}" ;
                     jido:hasPatch ?patch .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert code_query.row_count == 1

      assert {:ok, review_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?review
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{review_result.workflow_provenance.session_id}" ;
                     jido:hasReview ?review .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert review_query.row_count == 1

      assert {:ok, explain_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?run
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{explain_result.workflow_provenance.session_id}" ;
                     jido:hasAgentRun ?run .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert explain_query.row_count == 1
    end
  end

  describe "parallel execution" do
    test "parallel_plan returns ok with results map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_ids = ["work-1", "work-2"]
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      Enum.each(work_item_ids, fn work_item_id ->
        assert {:ok, _pod_name} =
                 AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)
      end)

      assert {:ok, results} = AgentWorkspace.parallel_plan(managed_repo_id, work_item_ids)
      assert is_map(results)
      assert Map.has_key?(results, "work-1")
      assert Map.has_key?(results, "work-2")
      assert results["work-1"].plan =~ "deterministic planner response"
    end
  end

  describe "source code graph workflow adoption" do
    setup do
      previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
      Application.put_env(:jido_code, :source_code_graph_enabled, true)

      workspace_path = create_workspace_path!()

      on_exit(fn ->
        Application.put_env(:jido_code, :source_code_graph_enabled, previous)
        File.rm_rf!(workspace_path)
      end)

      {:ok, workspace_path: workspace_path}
    end

    test "plan_work can gather explicit semantic graph inputs", %{workspace_path: workspace_path} do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan feature",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   modules: [module_name_contains: "Example"],
                   impact: [module_name: "Example"]
                 ]
               )

      assert result.semantic_context.workflow == :plan
      assert result.semantic_context.graph_status.ready? == true
      assert result.semantic_context.results.modules.helper == :modules
      assert result.semantic_context.results.impact.helper == :impact
    end

    test "review_work can gather explicit semantic review inputs", %{workspace_path: workspace_path} do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 work_item_id,
                 "Review feature",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   functions: [module_name: "Example", function_name: "greet"],
                   runtime_patterns: []
                 ]
               )

      assert result.semantic_context.workflow == :review
      assert result.semantic_context.graph_status.ready? == true
      assert result.semantic_context.results.functions.helper == :functions
      assert result.semantic_context.results.runtime_patterns.helper == :runtime_patterns
    end

    test "explain_work can query the graph through explicit workspace entrypoints", %{workspace_path: workspace_path} do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.explain_work(
                 managed_repo_id,
                 work_item_id,
                 "Explain feature",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   query: """
                   SELECT ?module
                   WHERE {
                     ?module a struct:Module .
                   }
                   ORDER BY ?module
                   """
                 ]
               )

      assert result.semantic_context.workflow == :explain
      assert result.semantic_context.results.query.engine == :sparql
      assert result.semantic_context.results.query.row_count >= 1
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_agent_workspace_source_graph_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule AgentWorkspaceExample.MixProject do
        use Mix.Project

        def project do
          [app: :agent_workspace_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule Example do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end
end
