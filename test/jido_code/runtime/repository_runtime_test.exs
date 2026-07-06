defmodule JidoCode.Runtime.RepositoryRuntimeTest do
  use ExUnit.Case, async: false

  alias JidoCode.ContextManagement
  alias JidoCode.MemoryGraph
  alias JidoCode.Runtime
  alias JidoCode.Runtime.Snapshot
  alias JidoCode.SourceCodeGraph

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

  test "concurrent ensure_repository calls share one runtime", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    results =
      1..8
      |> Task.async_stream(fn _index -> Runtime.ensure_repository(managed_repo_id, workspace_path) end,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %{managed_repo_id: ^managed_repo_id}}, &1))

    started_at_values =
      results
      |> Enum.map(fn {:ok, status} -> status.started_at end)
      |> Enum.uniq()

    assert length(started_at_values) == 1
  end

  test "concurrent work admission respects capacity without double counting", %{
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

    results =
      ["work-race-one", "work-race-two"]
      |> Task.async_stream(
        fn work_item_id ->
          Runtime.admit_work_item(managed_repo_id, work_item_id, %{workspace_path: workspace_path})
        end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &match?({:error, %{type: :capacity_exceeded}}, &1)) == 1
    assert Runtime.active_work_items(managed_repo_id) |> length() == 1

    [active_work_item_id] = Runtime.active_work_items(managed_repo_id)
    assert :ok = Runtime.complete_work_item(managed_repo_id, active_work_item_id)
    assert Runtime.active_work_items(managed_repo_id) == []
    assert :ok = Runtime.admit_work_item(managed_repo_id, "replacement-work", %{workspace_path: workspace_path})
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

  test "repeated specialist lookup while lazy nodes start returns one live node", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    work_item_id = "work-lazy-specialist"

    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    results =
      1..6
      |> Task.async_stream(fn _index -> Runtime.ensure_work_item_node(managed_repo_id, work_item_id, :reviewer) end,
        max_concurrency: 6,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, pid} when is_pid(pid), &1))

    reviewer_pids =
      results
      |> Enum.map(fn {:ok, pid} -> pid end)
      |> Enum.uniq()

    assert length(reviewer_pids) == 1
    assert Process.alive?(hd(reviewer_pids))
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

  test "down coding pods degrade the runtime and release work capacity", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    work_item_id = "work-down-coding"

    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)
    assert %{runtime_pid: coding_pid} = Runtime.coding_pod_status(managed_repo_id, work_item_id)

    monitor_ref = Process.monitor(coding_pid)
    Process.exit(coding_pid, :kill)
    assert_receive {:DOWN, ^monitor_ref, :process, ^coding_pid, :killed}, 1_000

    status = Runtime.repository_status(managed_repo_id)
    assert status.lifecycle == :degraded
    assert Runtime.active_work_items(managed_repo_id) == []
    refute Runtime.coding_pod_status(managed_repo_id, work_item_id)

    assert Enum.any?(status.diagnostics, fn diagnostic ->
             diagnostic.type == :owned_process_down and
               diagnostic.kind == :coding and
               diagnostic.pod_id == "coding-pod-#{work_item_id}" and
               not Map.has_key?(diagnostic, :pid)
           end)

    assert :ok = Runtime.admit_work_item(managed_repo_id, "replacement-after-down", %{workspace_path: workspace_path})
    assert Runtime.active_work_items(managed_repo_id) == ["replacement-after-down"]
  end

  test "restore_repository restores repo pods and active work metadata from snapshots", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    work_item_id = "restored-work"

    assert {:ok, _runtime_status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, _repo_pod} = Runtime.ensure_repo_pod(managed_repo_id)
    assert {:ok, _source_pod} = Runtime.ensure_source_code_graph_pod(managed_repo_id)
    assert {:ok, _memory_pod} = Runtime.ensure_memory_graph_pod(managed_repo_id)
    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, _context_pod} =
             Runtime.ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, %{
               context_management_status: :healthy
             })

    assert {:ok, _source_pod} =
             Runtime.update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), %{
               latest_import_status: %{ready?: true, imported_revision: "rev-restore"}
             })

    assert {:ok, _snapshot} = Runtime.save_repository_snapshot(managed_repo_id, backend: :ets)
    assert :ok = Runtime.shutdown_repository(managed_repo_id)
    assert Runtime.fetch_repository(managed_repo_id) == :error

    resolver = fn ^managed_repo_id, ^work_item_id -> {:ok, %{managed_repo_id: managed_repo_id}} end

    assert {:ok, restored_status} =
             Runtime.restore_repository(managed_repo_id,
               backend: :ets,
               work_item_resolver: resolver
             )

    assert restored_status.workspace_path == workspace_path
    assert Runtime.active_work_items(managed_repo_id) == [work_item_id]
    assert Runtime.pod_status(managed_repo_id, "repo-pod")
    assert Runtime.pod_status(managed_repo_id, SourceCodeGraph.pod_id())
    assert Runtime.pod_status(managed_repo_id, MemoryGraph.pod_id())
    assert Runtime.coding_pod_status(managed_repo_id, work_item_id)
    assert Runtime.pod_status(managed_repo_id, ContextManagement.pod_id(work_item_id))

    assert get_in(Runtime.pod_status(managed_repo_id, SourceCodeGraph.pod_id()), [
             :metadata,
             :latest_import_status,
             :ready?
           ])
  end

  test "restore_repository drops stale work metadata and releases capacity", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    stale_work_item_id = "stale-work"

    snapshot = %Snapshot{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      lifecycle: "ready",
      capacity: %{"max_active_work_items" => 1},
      active_work_items: [
        %{
          "work_item_id" => stale_work_item_id,
          "workspace_path" => workspace_path,
          "coding_pod" => [managed_repo_id, stale_work_item_id, "coding"],
          "lifecycle" => "admitted"
        }
      ],
      pods: [
        %{
          "pod_id" => "coding-pod-#{stale_work_item_id}",
          "kind" => "coding",
          "key" => [managed_repo_id, stale_work_item_id, "coding"],
          "scope" => "work_item",
          "module" => "Elixir.JidoCode.Pods.CodingPod",
          "metadata" => %{
            "managed_repo_id" => managed_repo_id,
            "work_item_id" => stale_work_item_id,
            "workspace_path" => workspace_path,
            "runtime_status" => "running"
          },
          "lifecycle" => "running"
        }
      ],
      captured_at: "2026-07-06T10:00:00Z"
    }

    assert :ok = JidoCode.Runtime.SnapshotStore.save(snapshot, backend: :ets)

    resolver = fn ^managed_repo_id, ^stale_work_item_id -> {:ok, nil} end

    assert {:ok, restored_status} =
             Runtime.restore_repository(managed_repo_id,
               backend: :ets,
               work_item_resolver: resolver
             )

    assert restored_status.active_work_items == %{}
    assert Runtime.active_work_items(managed_repo_id) == []
    refute Runtime.coding_pod_status(managed_repo_id, stale_work_item_id)

    assert Enum.any?(restored_status.diagnostics, fn diagnostic ->
             diagnostic.type == :runtime_snapshot_stale_work and
               diagnostic.work_item_id == stale_work_item_id and
               diagnostic.reason == :work_item_not_found
           end)

    assert :ok = Runtime.admit_work_item(managed_repo_id, "replacement-work", %{workspace_path: workspace_path})
    assert Runtime.active_work_items(managed_repo_id) == ["replacement-work"]
  end

  test "restore_repository is idempotent when callers race", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    snapshot = %Snapshot{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      lifecycle: "ready",
      pods: [
        %{
          "pod_id" => "repo-pod",
          "kind" => "repo",
          "key" => [managed_repo_id, "repo"],
          "scope" => "repository",
          "module" => "Elixir.JidoCode.Pods.RepoPod",
          "metadata" => %{"managed_repo_id" => managed_repo_id, "workspace_path" => workspace_path},
          "lifecycle" => "running"
        }
      ],
      captured_at: "2026-07-06T10:00:00Z"
    }

    assert :ok = JidoCode.Runtime.SnapshotStore.save(snapshot, backend: :ets)

    results =
      1..5
      |> Task.async_stream(
        fn _index ->
          Runtime.restore_repository(managed_repo_id,
            backend: :ets,
            validate_work_items?: false
          )
        end,
        ordered: false,
        max_concurrency: 5
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %{managed_repo_id: ^managed_repo_id}}, &1))

    started_at_values =
      results
      |> Enum.map(fn {:ok, status} -> status.started_at end)
      |> Enum.uniq()

    assert length(started_at_values) == 1
    assert Runtime.repository_status(managed_repo_id).managed_repo_id == managed_repo_id
    assert Runtime.pod_status(managed_repo_id, "repo-pod")
  end

  defp workspace_path!(name) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    Path.expand(path)
  end
end
