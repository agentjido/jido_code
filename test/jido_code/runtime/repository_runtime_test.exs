defmodule JidoCode.Runtime.RepositoryRuntimeTest do
  use ExUnit.Case, async: false

  alias JidoCode.ContextManagement
  alias JidoCode.Runtime

  setup do
    managed_repo_id = "runtime-repo-#{System.unique_integer([:positive])}"
    workspace_path = workspace_path!(managed_repo_id)

    on_exit(fn ->
      Runtime.shutdown_repository(managed_repo_id)
      File.rm_rf(workspace_path)
    end)

    {:ok, managed_repo_id: managed_repo_id, workspace_path: workspace_path}
  end

  test "ensure_repository starts one runtime per ManagedRepo and reuses it", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    assert {:ok, first_status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, second_status} = Runtime.ensure_repository(managed_repo_id, workspace_path)

    assert first_status.managed_repo_id == managed_repo_id
    assert first_status.workspace_path == workspace_path
    assert first_status.started_at == second_status.started_at
    assert Runtime.repository_status(managed_repo_id).managed_repo_id == managed_repo_id
  end

  test "two ManagedRepos get isolated runtime state", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    other_repo_id = "#{managed_repo_id}-other"
    other_workspace_path = workspace_path!(other_repo_id)

    on_exit(fn ->
      Runtime.shutdown_repository(other_repo_id)
      File.rm_rf(other_workspace_path)
    end)

    assert {:ok, _status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, _status} = Runtime.ensure_repository(other_repo_id, other_workspace_path)

    assert :ok = Runtime.admit_work_item(managed_repo_id, "work-one", %{workspace_path: workspace_path})
    assert :ok = Runtime.admit_work_item(other_repo_id, "work-two", %{workspace_path: other_workspace_path})

    assert Runtime.active_work_items(managed_repo_id) == ["work-one"]
    assert Runtime.active_work_items(other_repo_id) == ["work-two"]
  end

  test "shutdown_repository is idempotent and removes registry entries", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    assert {:ok, _status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, _status} = Runtime.fetch_repository(managed_repo_id)

    assert :ok = Runtime.shutdown_repository(managed_repo_id)
    assert :ok = Runtime.shutdown_repository(managed_repo_id)
    assert Runtime.fetch_repository(managed_repo_id) == :error
    assert Runtime.repository_status(managed_repo_id) == nil
  end

  test "invalid workspace input fails closed without leaking runtime processes", %{
    managed_repo_id: managed_repo_id
  } do
    missing_path =
      System.tmp_dir!()
      |> Path.join("missing-runtime-workspace-#{System.unique_integer([:positive])}")

    assert {:error, %{type: :workspace_unavailable, workspace_path: ^missing_path}} =
             Runtime.ensure_repository(managed_repo_id, missing_path)

    assert Runtime.fetch_repository(managed_repo_id) == :error
  end

  test "work admission enforces repository capacity and releases completed work", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    previous_limit = Application.get_env(:jido_code, :agent_workspace_max_concurrent_work_items)
    Application.put_env(:jido_code, :agent_workspace_max_concurrent_work_items, 1)

    on_exit(fn ->
      case previous_limit do
        nil -> Application.delete_env(:jido_code, :agent_workspace_max_concurrent_work_items)
        limit -> Application.put_env(:jido_code, :agent_workspace_max_concurrent_work_items, limit)
      end
    end)

    assert {:ok, _status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert :ok = Runtime.admit_work_item(managed_repo_id, "work-one", %{workspace_path: workspace_path})

    assert {:error,
            %{
              type: :capacity_exceeded,
              managed_repo_id: ^managed_repo_id,
              limit: 1,
              active_work_items: ["work-one"]
            }} = Runtime.admit_work_item(managed_repo_id, "work-two", %{workspace_path: workspace_path})

    assert Runtime.active_work_items(managed_repo_id) == ["work-one"]
    assert :ok = Runtime.complete_work_item(managed_repo_id, "work-one")
    assert Runtime.active_work_items(managed_repo_id) == []
    assert :ok = Runtime.admit_work_item(managed_repo_id, "work-two", %{workspace_path: workspace_path})
  end

  test "ensure_work_item_node locates specialists through the runtime coding pod", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    assert {:error, %{type: :coding_pod_unavailable, managed_repo_id: ^managed_repo_id}} =
             Runtime.ensure_work_item_node(managed_repo_id, "work-one", :planner)

    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, "work-one", workspace_path)
    assert {:ok, planner_pid} = Runtime.ensure_work_item_node(managed_repo_id, "work-one", :planner)
    assert Process.alive?(planner_pid)

    assert {:ok, ^planner_pid} = Runtime.ensure_work_item_node(managed_repo_id, "work-one", :planner)
  end

  test "shutdown_context_management_pod releases only the context pod", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    work_item_id = "work-with-context"

    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, _context_pod} =
             Runtime.ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, %{})

    assert Runtime.coding_pod_status(managed_repo_id, work_item_id)
    assert Runtime.pod_status(managed_repo_id, ContextManagement.pod_id(work_item_id))
    assert Runtime.active_work_items(managed_repo_id) == [work_item_id]

    assert :ok = Runtime.shutdown_context_management_pod(managed_repo_id, work_item_id)

    assert Runtime.coding_pod_status(managed_repo_id, work_item_id)
    refute Runtime.pod_status(managed_repo_id, ContextManagement.pod_id(work_item_id))
    assert Runtime.active_work_items(managed_repo_id) == [work_item_id]
  end

  defp workspace_path!(name) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    Path.expand(path)
  end
end
