defmodule JidoCode.ExecutionRuntime.RecordStoreTest do
  # covers: architecture.execution_runtime.exec_session_projection_excludes_unbounded_output
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.ExecutionRuntime.RecordStore
  alias JidoCode.Forge.{EventLogger, Operations, Persistence}

  setup do
    setup_product_store()
  end

  test "runtime records persist sessions events exec summaries and checkpoints through the product store" do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "runtime-store",
        full_name: "owner/runtime-store",
        default_branch: "main",
        settings: %{}
      })

    assert {:ok, workflow} =
             RecordStore.upsert_execution_workflow(%{
               name: "runtime-test-workflow",
               description: "Exercise runtime store records",
               steps: [%{"name" => "run"}],
               tags: ["runtime"]
             })

    assert workflow.name == "runtime-test-workflow"

    assert {:ok, sprite_spec} =
             RecordStore.upsert_sprite_spec(%{
               name: "runtime-test-sprite",
               runner: :shell,
               base_image: "ubuntu-22.04",
               env: %{"SAFE" => "true"}
             })

    assert sprite_spec.name == "runtime-test-sprite"

    session_id = "runtime-store-session"

    assert {:ok, session} =
             Persistence.record_session_started(session_id, %{
               managed_repo_id: managed_repo.id,
               runner: :shell,
               runner_config: %{shell: "bash"}
             })

    assert session.name == session_id
    assert Map.get(session, :managed_repo_id) == managed_repo.id

    assert {:ok, provisioned} = Persistence.record_provision_complete(session_id, "sprite-runtime", "runtime")
    assert provisioned.phase == :bootstrapping

    assert {:ok, ready} = Persistence.record_bootstrap_complete(session_id)
    assert ready.phase == :ready

    assert {:ok, exec_session} =
             Persistence.record_execution_start(session_id, 1,
               command: "echo safe",
               sprites_session_id: "sprites-session-runtime"
             )

    assert exec_session.sequence == 1
    assert exec_session.session_id == ready.id

    secret = "sk-test-0123456789abcdef"

    assert {:ok, completed} =
             Persistence.record_execution_complete(session_id, %{
               status: :done,
               output: "Authorization: Bearer #{secret}",
               runner_state: %{api_token: secret}
             })

    assert completed.phase == :completed
    refute completed.output_buffer =~ secret
    assert completed.output_buffer =~ "Bearer [REDACTED"

    assert :ok =
             EventLogger.log_event(session.id, "exec_session.output", %{
               chunk: "Authorization: Bearer #{secret}",
               size: 99
             })

    assert {:ok, [event]} =
             RecordStore.list_runtime_events(%{
               sandbox_session_id: session.id,
               event_type: "exec_session.output"
             })

    assert event.event_type == "exec_session.output"
    refute inspect(event.data) =~ secret

    assert {:ok, checkpoint_ready} =
             RecordStore.update_sandbox_session(completed, %{
               phase: :ready,
               sprite_id: "sprite-runtime",
               runner_state: %{"step" => "ready"}
             })

    assert {:ok, checkpoint} = Operations.create_checkpoint(checkpoint_ready.id, name: "after-first-exec")
    assert checkpoint.name == "after-first-exec"
    assert checkpoint.sprites_checkpoint_id =~ "chk_sprite-runtime_"

    assert {:ok, reloaded} = RecordStore.get_sandbox_session(checkpoint_ready.id)
    assert reloaded.last_checkpoint_id == checkpoint.sprites_checkpoint_id

    assert {:ok, [persisted_exec]} = RecordStore.list_exec_sessions(%{sandbox_session_id: session.id})
    assert persisted_exec.output_size_bytes > 0
    refute to_string(persisted_exec.output) =~ secret
  end

  defp setup_product_store do
    store_name = :"execution_runtime_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_execution_runtime_store/#{store_name}")

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
