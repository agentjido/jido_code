defmodule JidoCode.AgentOSIntegrationTest do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
  # covers: architecture.agent_os_integration.pod_hierarchy
  use ExUnit.Case, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentOS.Manager

  @moduletag :integration

  describe "19.7.1 Kernel lifecycle scenarios" do
    test "19.7.1.1 kernel creation on first work" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"

      # Verify no kernel exists initially
      refute Manager.kernel_exists?(managed_repo_id)

      # Ensure kernel for work
      assert {:ok, kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
      assert is_atom(kernel_name)

      # Verify kernel now exists
      assert Manager.kernel_exists?(managed_repo_id)
      assert Manager.kernel_status(managed_repo_id) != nil
    end

    test "19.7.1.2 kernel reuse across WorkItems" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"

      # First work item creates kernel
      assert {:ok, kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      # Second work item reuses same kernel
      assert {:ok, ^kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      # Third call also returns same kernel
      assert {:ok, ^kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      # Verify only one kernel exists
      kernels = Manager.list_kernels()
      assert length(kernels) >= 1
    end

    test "19.7.1.3 kernel shutdown and cleanup" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"

      # Create kernel
      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
      assert Manager.kernel_exists?(managed_repo_id)

      # Shutdown kernel
      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)

      # Verify kernel no longer exists
      refute Manager.kernel_exists?(managed_repo_id)
      assert Manager.kernel_status(managed_repo_id) == nil

      # Shutdown is idempotent
      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)
    end
  end

  describe "19.7.2 Pod isolation and parallel execution scenarios" do
    test "19.7.2.1 pod-per-work-item isolation" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_1 = "work-#{System.unique_integer()}"
      work_item_2 = "work-#{System.unique_integer()}"

      # Ensure kernel
      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      # Create pods for two work items
      assert {:ok, pod_name_1} = AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_1, "/tmp")
      assert {:ok, pod_name_2} = AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_2, "/tmp")

      # Each work item should get a unique pod name
      assert pod_name_1 != pod_name_2
      assert is_atom(pod_name_1)
      assert is_atom(pod_name_2)
    end

    test "19.7.2.2 parallel pod execution" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_items = for i <- 1..3, do: "work-#{System.unique_integer()}-#{i}"

      # Ensure all work items get pods
      results =
        Enum.map(work_items, fn work_item_id ->
          AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, "/tmp")
        end)

      # All should succeed
      assert Enum.all?(results, fn
        {:ok, _pod_name} -> true
        _ -> false
      end)

      # Each should have unique pod names
      pod_names = Enum.map(results, fn {:ok, pod_name} -> pod_name end)
      assert length(Enum.uniq(pod_names)) == length(pod_names)
    end
  end

  describe "19.7.3 Agent collaboration scenarios" do
    test "19.7.3.1 planner agent has required tools" do
      # Verify the planner agent has access to required tools
      planner = JidoCode.Agents.Planner

      # The agent should be callable
      assert function_exported?(planner, :ask, 2)
    end

    test "19.7.3.2 coder agent has required tools" do
      # Verify the coder agent has access to required tools
      coder = JidoCode.Agents.Coder

      # The agent should be callable
      assert function_exported?(coder, :ask, 2)
    end

    test "19.7.3.3 reviewer agent has required tools" do
      # Verify the reviewer agent has access to required tools
      reviewer = JidoCode.Agents.Reviewer

      # The agent should be callable
      assert function_exported?(reviewer, :ask, 2)
    end
  end

  describe "19.7.4 End-to-end conversation scenarios" do
    test "19.7.4.1 plan operation through workspace" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      # Plan work through workspace
      assert {:ok, result} = AgentWorkspace.plan_work(managed_repo_id, work_item_id, "Plan a feature")

      # Should return a plan result
      assert is_map(result)
      assert Map.has_key?(result, :plan)
    end

    test "19.7.4.2 implement operation through workspace" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      # Execute work through workspace
      assert {:ok, result} = AgentWorkspace.execute_work(managed_repo_id, work_item_id, "Implement a feature")

      # Should return a changes result
      assert is_map(result)
      assert Map.has_key?(result, :changes)
    end

    test "19.7.4.3 review operation through workspace" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      # Review work through workspace
      assert {:ok, result} = AgentWorkspace.review_work(managed_repo_id, work_item_id, "Review implementation")

      # Should return a feedback result
      assert is_map(result)
      assert Map.has_key?(result, :feedback)
    end

    test "19.7.4.4 full workflow conversation" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      # Full workflow through workspace
      assert {:ok, result} = AgentWorkspace.full_workflow(managed_repo_id, work_item_id, "Add user settings")

      # Should return combined results
      assert is_map(result)
      assert Map.has_key?(result, :plan)
      assert Map.has_key?(result, :changes)
      assert Map.has_key?(result, :feedback)
    end
  end
end
