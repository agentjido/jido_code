defmodule JidoCode.Actions.GetWorkItemTest do
  # covers: architecture.repository_runtime_integration.actions
  use JidoCode.DataCase, async: false

  alias JidoCode.Actions.GetWorkItem
  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Operations.RecordStore

  setup do
    setup_product_store()
  end

  test "reads work item and workspace path from product stores" do
    workspace_path = Path.join(System.tmp_dir!(), "get-work-item-store-cutover")

    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "get-work-item-store",
        full_name: "owner/get-work-item-store",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_path" => workspace_path
          }
        }
      })

    {:ok, work_item} =
      RecordStore.create(:work_item, %{
        managed_repo_id: managed_repo.id,
        category: "repository_runtime",
        status: :open,
        priority: :medium,
        recommended_action: "Implement product-store action lookup.",
        summary: "Cut over GetWorkItem action",
        dedup_key: "get-work-item:#{managed_repo.id}",
        initiating_actor: %{"id" => "operator-get-work-item"},
        work_metadata: %{"source" => "get_work_item_test"},
        audit_log: []
      })

    assert {:ok, result} = GetWorkItem.run(%{work_item_id: work_item.id}, %{})
    assert result.work_item_id == work_item.id
    assert result.title == "Cut over GetWorkItem action"
    assert result.description == "Implement product-store action lookup."
    assert result.status == :open
    assert result.managed_repo_id == managed_repo.id
    assert result.workspace_path == workspace_path
    assert result.metadata["source"] == "get_work_item_test"
  end

  defp setup_product_store do
    store_name = :"get_work_item_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_get_work_item_store/#{store_name}")

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
