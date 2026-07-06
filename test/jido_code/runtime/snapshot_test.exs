defmodule JidoCode.Runtime.SnapshotTest do
  use ExUnit.Case, async: false

  alias JidoCode.ContextManagement
  alias JidoCode.Runtime
  alias JidoCode.Runtime.Snapshot
  alias JidoCode.SourceCodeGraph

  setup do
    managed_repo_id = "snapshot-repo-#{System.unique_integer([:positive])}"
    workspace_path = workspace_path!(managed_repo_id)

    on_exit(fn ->
      Runtime.shutdown_repository(managed_repo_id)
      File.rm_rf!(workspace_path)
    end)

    {:ok, managed_repo_id: managed_repo_id, workspace_path: workspace_path}
  end

  test "captures bounded runtime topology without pids or legacy runtime identity", %{
    managed_repo_id: managed_repo_id,
    workspace_path: workspace_path
  } do
    work_item_id = "work-#{System.unique_integer([:positive])}"

    assert {:ok, _status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, _repo_pod} = Runtime.ensure_repo_pod(managed_repo_id)
    assert {:ok, _source_pod} = Runtime.ensure_source_code_graph_pod(managed_repo_id)

    assert {:ok, _source_pod} =
             Runtime.update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), %{
               runtime_pid: self(),
               kernel_name: :legacy_kernel,
               prompt_payload: String.duplicate("x", 512),
               latest_import_status: %{
                 ready?: true,
                 imported_revision: "rev-one",
                 runtime_pid: self()
               },
               graph_store_path: Path.join(workspace_path, ".jido_code/source_graph")
             })

    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, _context_pod} =
             Runtime.ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, %{
               context_management_status: :healthy,
               latest_monitor_decision: %{state: :healthy, pid: self()}
             })

    assert {:ok, snapshot} =
             managed_repo_id
             |> Runtime.repository_status()
             |> Snapshot.from_status(captured_at: ~U[2026-07-06 10:00:00Z])

    record = Snapshot.to_record(snapshot)

    assert record["kind"] == Snapshot.kind()
    assert record["managed_repo_id"] == managed_repo_id
    assert record["workspace_path"] == workspace_path
    assert record["lifecycle"] == "ready"
    assert [%{"work_item_id" => ^work_item_id}] = record["active_work_items"]

    pod_ids = Enum.map(record["pods"], & &1["pod_id"])
    assert "repo-pod" in pod_ids
    assert SourceCodeGraph.pod_id() in pod_ids
    assert "coding-pod-#{work_item_id}" in pod_ids
    assert ContextManagement.pod_id(work_item_id) in pod_ids

    assert get_in(record, ["graph_summaries", "source_code_graph", "latest_import_status", "ready?"])

    assert get_in(record, ["graph_summaries", "source_code_graph", "latest_import_status", "imported_revision"]) ==
             "rev-one"

    assert get_in(record, ["context_summaries", work_item_id, "context_management_status"]) == "healthy"
    assert get_in(record, ["context_summaries", work_item_id, "latest_monitor_decision", "state"]) == "healthy"

    refute contains_key?(record, "runtime_pid")
    refute contains_key?(record, "pid")
    refute contains_key?(record, "kernel_name")
    refute contains_key?(record, "nodes")
    refute contains_key?(record, "prompt_payload")
  end

  defp workspace_path!(name) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    Path.expand(path)
  end

  defp contains_key?(map, target_key) when is_map(map) do
    Enum.any?(map, fn {key, value} ->
      to_string(key) == target_key or contains_key?(value, target_key)
    end)
  end

  defp contains_key?(list, target_key) when is_list(list) do
    Enum.any?(list, &contains_key?(&1, target_key))
  end

  defp contains_key?(_value, _target_key), do: false
end
