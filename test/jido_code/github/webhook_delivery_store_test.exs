defmodule JidoCode.GitHub.WebhookDeliveryStoreTest do
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.GitHub.{RepoStore, WebhookDelivery, WebhookDeliveryStore}

  setup do
    store_name = :"github_webhook_delivery_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_github_webhook_delivery_store/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  test "creates lists and marks webhook deliveries through product store records" do
    {:ok, repo} = RepoStore.create(%{owner: "owner", name: "webhook-store"})

    assert {:ok, %WebhookDelivery{} = delivery} =
             WebhookDeliveryStore.create(%{
               github_delivery_id: "delivery-1",
               event_type: "issues",
               action: "opened",
               payload: %{"action" => "opened"},
               repo_id: repo.id
             })

    assert delivery.status == :pending
    assert {:ok, %WebhookDelivery{id: delivery_id}} = WebhookDeliveryStore.get_by_github_delivery_id("delivery-1")
    assert delivery_id == delivery.id
    assert {:error, :duplicate_github_delivery} = WebhookDeliveryStore.create(%{github_delivery_id: "delivery-1"})

    assert {:ok, [%WebhookDelivery{id: ^delivery_id} = pending]} = WebhookDeliveryStore.list_pending(10)
    assert pending.repo_id == repo.id

    assert {:ok, %WebhookDelivery{status: :processed}} = WebhookDeliveryStore.mark_processed(pending)
    assert {:ok, []} = WebhookDeliveryStore.list_pending(10)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
