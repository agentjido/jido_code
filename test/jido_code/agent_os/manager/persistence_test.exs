defmodule JidoCode.AgentOS.Manager.PersistenceTest do
  use ExUnit.Case, async: false

  alias JidoCode.AgentOS.Manager.{KernelState, Persistence}
  alias JidoCode.ControlPlane.StoreServer

  setup do
    store_name = :"agent_os_persistence_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_agent_os_persistence/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  test "saves restores and tombstones kernel snapshots through the embedded runtime store" do
    kernel_name = :"kernel_#{System.unique_integer([:positive])}"

    state = %KernelState{
      managed_repo_id: Ecto.UUID.generate(),
      pid: self(),
      created_at: ~U[2026-02-15 12:00:00Z],
      pods: %{
        "planner" => %{
          metadata: %{
            runtime_pid: self(),
            output: "planned change"
          }
        }
      }
    }

    assert :ok = Persistence.save(kernel_name, state)

    assert {:ok, restored} = Persistence.load(kernel_name)
    assert restored.managed_repo_id == state.managed_repo_id
    assert restored.pid == nil
    assert restored.pods["planner"].metadata.runtime_status == :persisted
    refute Map.has_key?(restored.pods["planner"].metadata, :runtime_pid)

    assert :ok = Persistence.delete(kernel_name)
    assert :error = Persistence.load(kernel_name)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
