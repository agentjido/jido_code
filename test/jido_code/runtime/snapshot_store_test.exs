defmodule JidoCode.Runtime.SnapshotStoreTest do
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Runtime.{Snapshot, SnapshotStore}

  setup do
    store_name = :"runtime_snapshot_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_runtime_snapshot_store/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  test "saves loads and tombstones snapshots through product checkpoint storage" do
    managed_repo_id = "snapshot-store-repo-#{System.unique_integer([:positive])}"
    snapshot = snapshot(managed_repo_id)

    assert :ok = SnapshotStore.save(snapshot, backend: :record_store)

    assert {:ok, restored} = SnapshotStore.load(managed_repo_id, backend: :record_store)
    assert restored.managed_repo_id == managed_repo_id
    assert restored.workspace_path == snapshot.workspace_path
    assert restored.pods == snapshot.pods
    assert restored.graph_summaries == snapshot.graph_summaries

    assert :ok = SnapshotStore.delete(managed_repo_id, backend: :record_store)
    assert :error = SnapshotStore.load(managed_repo_id, backend: :record_store)
  end

  test "supports an ETS-only backend for tests and failure injection" do
    managed_repo_id = "snapshot-ets-repo-#{System.unique_integer([:positive])}"
    snapshot = snapshot(managed_repo_id)

    assert :ok = SnapshotStore.save(snapshot, backend: :ets)
    assert {:ok, restored} = SnapshotStore.load(managed_repo_id, backend: :ets)
    assert restored.managed_repo_id == managed_repo_id

    assert :ok = SnapshotStore.delete(managed_repo_id, backend: :ets)
    assert :error = SnapshotStore.load(managed_repo_id, backend: :ets)
  end

  test "unsupported storage backends fail closed with bounded diagnostics" do
    snapshot = snapshot("snapshot-unsupported-repo-#{System.unique_integer([:positive])}")

    assert {:error,
            %{
              type: :runtime_snapshot_store_unavailable,
              backend: :unsupported,
              operation: :save,
              reason: :unsupported_backend
            }} = SnapshotStore.save(snapshot, backend: :unsupported)
  end

  defp snapshot(managed_repo_id) do
    %Snapshot{
      managed_repo_id: managed_repo_id,
      workspace_path: "/tmp/#{managed_repo_id}",
      lifecycle: "ready",
      capacity: %{"max_active_work_items" => "infinity"},
      active_work_items: [
        %{
          "work_item_id" => "work-one",
          "workspace_path" => "/tmp/#{managed_repo_id}",
          "lifecycle" => "admitted"
        }
      ],
      pods: [
        %{
          "pod_id" => "repo-pod",
          "kind" => "repo",
          "key" => [managed_repo_id, "repo"],
          "scope" => "repository",
          "module" => "Elixir.JidoCode.Pods.RepoPod",
          "metadata" => %{"managed_repo_id" => managed_repo_id, "runtime_status" => "running"},
          "lifecycle" => "running"
        }
      ],
      diagnostics: [],
      graph_summaries: %{"source_code_graph" => %{"ready?" => false}},
      context_summaries: %{},
      captured_at: "2026-07-06T10:00:00Z"
    }
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
