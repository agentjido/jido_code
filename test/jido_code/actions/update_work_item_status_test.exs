defmodule JidoCode.Actions.UpdateWorkItemStatusTest do
  # covers: architecture.agent_os_integration.actions
  use JidoCode.DataCase, async: false

  alias JidoCode.Actions.UpdateWorkItemStatus
  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Operations.RecordStore

  setup do
    setup_product_store()
  end

  test "updates work item status through the product store" do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "update-work-item-status-store",
        full_name: "owner/update-work-item-status-store",
        default_branch: "main"
      })

    {:ok, work_item} =
      RecordStore.create(:work_item, %{
        managed_repo_id: managed_repo.id,
        category: "agent_os",
        status: :open,
        priority: :medium,
        recommended_action: "Move status update action to product store.",
        summary: "Cut over UpdateWorkItemStatus action",
        dedup_key: "update-work-item-status:#{managed_repo.id}",
        initiating_actor: %{"id" => "operator-update-work-item-status"},
        work_metadata: %{"source" => "update_work_item_status_test"},
        audit_log: []
      })

    assert {:ok, result} =
             UpdateWorkItemStatus.run(
               %{
                 work_item_id: work_item.id,
                 status: "in_progress",
                 message: "agent started"
               },
               %{}
             )

    assert result.work_item_id == work_item.id
    assert result.status == :in_progress
    assert result.updated

    assert {:ok, updated_work_item} = RecordStore.get(:work_item, work_item.id)
    assert updated_work_item.status == :in_progress

    assert [%{"event" => "status_updated", "message" => "agent started", "status" => "in_progress"}] =
             updated_work_item.audit_log
  end

  test "rejects unsupported statuses before store mutation" do
    assert {:error, :invalid_status, "Invalid status: waiting"} =
             UpdateWorkItemStatus.run(
               %{
                 work_item_id: JidoCode.UUID.generate(),
                 status: "waiting",
                 message: nil
               },
               %{}
             )
  end

  defp setup_product_store do
    store_name = :"update_work_item_status_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_update_work_item_status_store/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
