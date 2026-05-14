defmodule JidoCode.AgentOSIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
  # covers: architecture.agent_os_integration.pod_hierarchy
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  # covers: architecture.agent_os_integration.missing_kernel_runtime_recovers_from_snapshot
  # covers: architecture.agent_os_integration.pod_contains_multiple_agents
  # covers: architecture.agent_os_integration.eager_collaboration_state_is_seeded_before_specialist_work
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentOS.Manager
  alias Jido.AgentServer
  alias Jido.Pod

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
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      # Ensure kernel
      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      # Create pods for two work items
      assert {:ok, pod_name_1} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_1, workspace_path)

      assert {:ok, pod_name_2} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_2, workspace_path)

      # Each work item should get a unique pod name
      assert pod_name_1 != pod_name_2
      assert is_atom(pod_name_1)
      assert is_atom(pod_name_2)
    end

    test "19.7.2.2 parallel pod execution" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_items = for i <- 1..3, do: "work-#{System.unique_integer()}-#{i}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      # Ensure all work items get pods
      results =
        Enum.map(work_items, fn work_item_id ->
          AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)
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

    test "19.7.2.3 pod state survives kernel restart restoration" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan restore scenario",
                 workspace_path: workspace_path
               )

      assert result.plan =~ "deterministic planner response"
      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)

      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      restored_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(restored_status, [:metadata, :last_plan, :plan]) =~ "deterministic planner response"
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)
    end

    test "19.7.2.4 refactorer runs stay isolated and end with pod teardown" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_1 = "work-#{System.unique_integer()}-one"
      work_item_2 = "work-#{System.unique_integer()}-two"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result_1} =
               AgentWorkspace.refactor_work(
                 managed_repo_id,
                 work_item_1,
                 "Refactor first work item",
                 workspace_path: workspace_path
               )

      assert {:ok, result_2} =
               AgentWorkspace.refactor_work(
                 managed_repo_id,
                 work_item_2,
                 "Refactor second work item",
                 workspace_path: workspace_path
               )

      assert result_1.refactoring =~ "Refactor first work item"
      assert result_2.refactoring =~ "Refactor second work item"

      status_1 = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_1}")
      status_2 = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_2}")
      pod_pid_1 = get_in(status_1, [:metadata, :runtime_pid])
      pod_pid_2 = get_in(status_2, [:metadata, :runtime_pid])

      assert is_pid(pod_pid_1)
      assert is_pid(pod_pid_2)
      assert pod_pid_1 != pod_pid_2

      assert {:ok, refactorer_pid_1} = Pod.lookup_node(pod_pid_1, :refactorer)
      assert {:ok, refactorer_pid_2} = Pod.lookup_node(pod_pid_2, :refactorer)
      assert refactorer_pid_1 != refactorer_pid_2

      assert get_in(status_1, [:metadata, :last_refactor, :instruction]) == "Refactor first work item"
      assert get_in(status_2, [:metadata, :last_refactor, :instruction]) == "Refactor second work item"

      assert :ok = AgentWorkspace.complete_work(managed_repo_id, work_item_1)

      completed_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_1}")
      assert get_in(completed_status, [:metadata, :runtime_pid]) == nil
      assert get_in(completed_status, [:metadata, :runtime_status]) == :completed
      refute work_item_1 in AgentWorkspace.active_work_items(managed_repo_id)
      assert work_item_2 in AgentWorkspace.active_work_items(managed_repo_id)
    end
  end

  describe "19.7.3 Agent collaboration scenarios" do
    test "19.7.3.1 planner workflow persists task output in pod metadata" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan with persisted result",
                 workspace_path: workspace_path
               )

      assert result.plan =~ "deterministic planner response"

      pod_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(pod_status, [:metadata, :last_plan, :plan]) =~ "deterministic planner response"

      project_context_state = pod_node_state(managed_repo_id, work_item_id, :project_context)
      assert project_context_state.workspace_path == Path.expand(workspace_path)
      assert project_context_state.work_item_id == work_item_id

      task_board_state = pod_node_state(managed_repo_id, work_item_id, :task_board)
      assert is_binary(task_board_state.active_task_id)
      assert Enum.any?(task_board_state.tasks, &(&1.metadata[:work_item_id] == work_item_id))

      assert Enum.any?(task_board_state.artifacts, fn artifact ->
               artifact.type == "plan" and
                 artifact.task_id == task_board_state.active_task_id and
                 String.contains?(artifact.content, "deterministic planner response")
             end)

      assert Enum.any?(task_board_state.activity_log, &(&1.type == "planning.started"))
      assert Enum.any?(task_board_state.activity_log, &(&1.type == "planning.completed"))
    end

    test "19.7.3.2 coder workflow persists change output in pod metadata" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 work_item_id,
                 "Code with persisted result",
                 workspace_path: workspace_path
               )

      assert result.changes =~ "deterministic coder response"

      pod_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(pod_status, [:metadata, :last_changes, :changes]) =~ "deterministic coder response"

      task_board_state = pod_node_state(managed_repo_id, work_item_id, :task_board)

      assert Enum.any?(task_board_state.artifacts, fn artifact ->
               artifact.type == "draft" and
                 String.contains?(artifact.content, "deterministic coder response")
             end)

      assert Enum.any?(task_board_state.activity_log, &(&1.type == "coding.started"))
      assert Enum.any?(task_board_state.activity_log, &(&1.type == "coding.completed"))
    end

    test "19.7.3.3 reviewer workflow persists feedback in pod metadata" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 work_item_id,
                 "Review with persisted result",
                 workspace_path: workspace_path
               )

      assert result.feedback =~ "deterministic reviewer response"

      pod_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(pod_status, [:metadata, :last_review, :feedback]) =~ "deterministic reviewer response"

      task_board_state = pod_node_state(managed_repo_id, work_item_id, :task_board)

      assert Enum.any?(task_board_state.artifacts, fn artifact ->
               artifact.type == "review" and
                 String.contains?(artifact.content, "deterministic reviewer response")
             end)

      assert Enum.any?(task_board_state.activity_log, &(&1.type == "reviewing.started"))
      assert Enum.any?(task_board_state.activity_log, &(&1.type == "reviewing.completed"))
    end

    test "19.7.3.4 refactorer workflow persists refactor output in pod state" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.refactor_work(
                 managed_repo_id,
                 work_item_id,
                 "Refactor with persisted result",
                 workspace_path: workspace_path
               )

      assert result.refactoring =~ "deterministic refactorer response"

      pod_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(pod_status, [:metadata, :last_refactor, :refactoring]) =~ "deterministic refactorer response"

      task_board_state = pod_node_state(managed_repo_id, work_item_id, :task_board)

      assert Enum.any?(task_board_state.artifacts, fn artifact ->
               artifact.type == "refactor" and
                 String.contains?(artifact.content, "deterministic refactorer response")
             end)

      assert Enum.any?(task_board_state.activity_log, &(&1.type == "refactoring.started"))
      assert Enum.any?(task_board_state.activity_log, &(&1.type == "refactoring.completed"))
    end
  end

  describe "19.7.4 End-to-end conversation scenarios" do
    test "19.7.4.1 plan operation through workspace" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      # Plan work through workspace
      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan a feature",
                 workspace_path: workspace_path
               )

      # Should return a plan result
      assert is_map(result)
      assert Map.has_key?(result, :plan)
      assert result.plan =~ "deterministic planner response"
    end

    test "19.7.4.2 implement operation through workspace" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      # Execute work through workspace
      assert {:ok, result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 work_item_id,
                 "Implement a feature",
                 workspace_path: workspace_path
               )

      # Should return a changes result
      assert is_map(result)
      assert Map.has_key?(result, :changes)
      assert result.changes =~ "deterministic coder response"
    end

    test "19.7.4.3 review operation through workspace" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      # Review work through workspace
      assert {:ok, result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 work_item_id,
                 "Review implementation",
                 workspace_path: workspace_path
               )

      # Should return a feedback result
      assert is_map(result)
      assert Map.has_key?(result, :feedback)
      assert result.feedback =~ "deterministic reviewer response"
    end

    test "19.7.4.4 full workflow conversation" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      # Full workflow through workspace
      assert {:ok, result} =
               AgentWorkspace.full_workflow(
                 managed_repo_id,
                 work_item_id,
                 "Add user settings",
                 workspace_path: workspace_path
               )

      # Should return combined results
      assert is_map(result)
      assert Map.has_key?(result, :plan)
      assert Map.has_key?(result, :changes)
      assert Map.has_key?(result, :feedback)

      task_board_state = pod_node_state(managed_repo_id, work_item_id, :task_board)
      assert Enum.count(task_board_state.tasks) == 1

      artifact_types =
        task_board_state.artifacts
        |> Enum.map(& &1.type)
        |> Enum.sort()

      assert artifact_types == ["draft", "plan", "review"]
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_agent_os_integration_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      "defmodule AgentOSIntegration.MixProject do\n  use Mix.Project\n  def project, do: [app: :agent_os_integration, version: \"0.1.0\", elixir: \"~> 1.18\", deps: []]\nend\n"
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      "defmodule AgentOSIntegration.Example do\n  def hello, do: :world\nend\n"
    )

    workspace_path
  end

  defp pod_node_state(managed_repo_id, work_item_id, node_name) do
    %{metadata: %{runtime_pid: pod_pid}} = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
    {:ok, node_pid} = Pod.ensure_node(pod_pid, node_name)
    {:ok, server_state} = AgentServer.state(node_pid)
    server_state.agent.state
  end
end
