defmodule JidoCode.AgentWorkspaceTest do
  # covers: architecture.agent_os_integration.workspace_context
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
end
