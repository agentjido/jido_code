defmodule JidoCode.Runtime.PodsTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.InstanceManager
  alias Jido.Pod
  alias Jido.Pod.Runtime, as: PodRuntime
  alias JidoCode.Runtime

  setup do
    managed_repo_id = "runtime-pod-repo-#{System.unique_integer([:positive])}"
    workspace_path = workspace_path!(managed_repo_id)

    on_exit(fn ->
      Runtime.shutdown_repository(managed_repo_id)
      File.rm_rf(workspace_path)
    end)

    {:ok, managed_repo_id: managed_repo_id, workspace_path: workspace_path}
  end

  test "RepoPod starts eager repository nodes through Jido.Pod.get/3", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    key = {managed_repo_id, :repo}

    assert {:ok, pod_pid} =
             Pod.get(:jido_code_repo_pods, key,
               initial_state: %{managed_repo_id: managed_repo_id, workspace_path: workspace_path}
             )

    on_exit(fn -> cleanup_pod(:jido_code_repo_pods, key, pod_pid) end)

    assert {:ok, repo_monitor_pid} = Pod.lookup_node(pod_pid, :repo_monitor)
    assert {:ok, work_registry_pid} = Pod.lookup_node(pod_pid, :work_registry)
    assert repo_monitor_pid != work_registry_pid
  end

  test "CodingPod starts eager nodes and lazy-starts specialists", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    work_item_id = "work-item-one"
    key = {managed_repo_id, work_item_id, :coding}

    assert {:ok, pod_pid} =
             Pod.get(:jido_code_coding_pods, key,
               initial_state: %{
                 managed_repo_id: managed_repo_id,
                 work_item_id: work_item_id,
                 workspace_path: workspace_path
               }
             )

    on_exit(fn -> cleanup_pod(:jido_code_coding_pods, key, pod_pid) end)

    assert {:ok, _task_board_pid} = Pod.lookup_node(pod_pid, :task_board)
    assert {:ok, _project_context_pid} = Pod.lookup_node(pod_pid, :project_context)
    assert :error = Pod.lookup_node(pod_pid, :planner)
    assert {:ok, planner_pid} = Pod.ensure_node(pod_pid, :planner)
    assert {:ok, ^planner_pid} = Pod.lookup_node(pod_pid, :planner)
  end

  test "same work item id in different repositories gets isolated pod nodes", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    other_repo_id = "#{managed_repo_id}-other"
    other_workspace_path = workspace_path!(other_repo_id)
    work_item_id = "shared-work-item"
    first_key = {managed_repo_id, work_item_id, :coding}
    second_key = {other_repo_id, work_item_id, :coding}

    on_exit(fn -> File.rm_rf(other_workspace_path) end)

    assert {:ok, first_pod} =
             Pod.get(:jido_code_coding_pods, first_key,
               initial_state: %{
                 managed_repo_id: managed_repo_id,
                 work_item_id: work_item_id,
                 workspace_path: workspace_path
               }
             )

    assert {:ok, second_pod} =
             Pod.get(:jido_code_coding_pods, second_key,
               initial_state: %{
                 managed_repo_id: other_repo_id,
                 work_item_id: work_item_id,
                 workspace_path: other_workspace_path
               }
             )

    on_exit(fn ->
      cleanup_pod(:jido_code_coding_pods, first_key, first_pod)
      cleanup_pod(:jido_code_coding_pods, second_key, second_pod)
    end)

    assert first_pod != second_pod
    assert {:ok, first_task_board} = Pod.lookup_node(first_pod, :task_board)
    assert {:ok, second_task_board} = Pod.lookup_node(second_pod, :task_board)
    assert first_task_board != second_task_board
  end

  test "graph and context pods reconcile without legacy signal routes", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    assert {:ok, _status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, repo_pod} = Runtime.ensure_repo_pod(managed_repo_id)
    assert {:ok, source_graph_pod} = Runtime.ensure_source_code_graph_pod(managed_repo_id)
    assert {:ok, memory_graph_pod} = Runtime.ensure_memory_graph_pod(managed_repo_id)
    assert {:ok, coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, "work-with-context", workspace_path)

    assert {:ok, context_pod} =
             Runtime.ensure_context_management_pod(managed_repo_id, "work-with-context", workspace_path, %{})

    assert repo_pod.lifecycle == :running
    assert source_graph_pod.lifecycle == :running
    assert memory_graph_pod.lifecycle == :running
    assert coding_pod.lifecycle == :running
    assert context_pod.lifecycle == :running

    assert repo_pod.key == {managed_repo_id, :repo}
    assert source_graph_pod.key == {managed_repo_id, :source_code_graph}
    assert memory_graph_pod.key == {managed_repo_id, :memory_graph}
    assert coding_pod.key == {managed_repo_id, "work-with-context", :coding}
    assert context_pod.key == {managed_repo_id, "work-with-context", :context_management}
  end

  defp workspace_path!(name) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    Path.expand(path)
  end

  defp cleanup_pod(manager, key, pod_pid) do
    if is_pid(pod_pid) and Process.alive?(pod_pid) do
      _ = PodRuntime.teardown_runtime(pod_pid)
    end

    _ = InstanceManager.stop(manager, key)
    :ok
  end
end
