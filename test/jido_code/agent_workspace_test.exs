defmodule JidoCode.AgentWorkspaceTest do
  # covers: architecture.agent_os_integration.workspace_context
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  use ExUnit.Case, async: false

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
  end

  describe "pod lifecycle" do
    test "ensure_coding_pod returns ok with pod name" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, pod_name} = AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, "/tmp")
      assert is_atom(pod_name)
    end

    test "complete_work returns ok" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert :ok = AgentWorkspace.complete_work(managed_repo_id, work_item_id)
    end

    test "active_work_items returns list" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"

      items = AgentWorkspace.active_work_items(managed_repo_id)
      assert is_list(items)
    end
  end

  describe "work execution" do
    test "plan_work returns ok with plan map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} = AgentWorkspace.plan_work(managed_repo_id, work_item_id, "Implement feature")
      assert is_map(result)
      assert Map.has_key?(result, :plan)
    end

    test "execute_work returns ok with changes map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} = AgentWorkspace.execute_work(managed_repo_id, work_item_id, "Implement function")
      assert is_map(result)
      assert Map.has_key?(result, :changes)
    end

    test "review_work returns ok with feedback map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} = AgentWorkspace.review_work(managed_repo_id, work_item_id, "Review code")
      assert is_map(result)
      assert Map.has_key?(result, :feedback)
    end

    test "full_workflow returns ok with plan, changes, and feedback" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} = AgentWorkspace.full_workflow(managed_repo_id, work_item_id, "Full workflow")
      assert Map.has_key?(result, :plan)
      assert Map.has_key?(result, :changes)
      assert Map.has_key?(result, :feedback)
    end
  end

  describe "parallel execution" do
    test "parallel_plan returns ok with results map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_ids = ["work-1", "work-2"]

      assert {:ok, results} = AgentWorkspace.parallel_plan(managed_repo_id, work_item_ids)
      assert is_map(results)
      assert Map.has_key?(results, "work-1")
      assert Map.has_key?(results, "work-2")
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
