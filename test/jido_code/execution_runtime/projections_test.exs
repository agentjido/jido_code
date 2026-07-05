defmodule JidoCode.ExecutionRuntime.ProjectionsTest do
  # covers: architecture.execution_runtime.exec_session_projection_excludes_unbounded_output
  use JidoCode.DataCase, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.ExecutionRuntime.{Projections, RecordStore}

  setup do
    setup_product_store()
  end

  test "projects filtered sandbox sessions latest checkpoint execution history and bounded events" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    repo_id = "repo-runtime-projections"

    {:ok, running} =
      RecordStore.upsert_sandbox_session(%{
        sandbox_session_id: "sandbox-running-projection",
        managed_repo_id: repo_id,
        name: "running projection",
        phase: :running,
        runner_type: :shell,
        spec: %{"workflow" => "workflow:repair"},
        execution_count: 2,
        last_activity_at: now
      })

    assert {:ok, _old_ready} =
             RecordStore.upsert_sandbox_session(%{
               sandbox_session_id: "sandbox-ready-old-projection",
               managed_repo_id: repo_id,
               name: "old ready projection",
               phase: :ready,
               runner_type: :shell,
               spec: %{"workflow" => "workflow:repair"},
               last_activity_at: DateTime.add(now, -300, :second)
             })

    assert {:ok, _other_workflow} =
             RecordStore.upsert_sandbox_session(%{
               sandbox_session_id: "sandbox-other-workflow-projection",
               managed_repo_id: repo_id,
               name: "other workflow projection",
               phase: :running,
               runner_type: :shell,
               spec: %{"workflow" => "workflow:review"},
               last_activity_at: now
             })

    assert {:ok, _first_exec} =
             RecordStore.create_exec_session(%{
               session_id: running.id,
               sequence: 1,
               status: :completed,
               command: "mix test",
               output: "first output",
               duration_ms: 100
             })

    assert {:ok, _second_exec} =
             RecordStore.create_exec_session(%{
               session_id: running.id,
               sequence: 2,
               status: :completed,
               command: "mix test --failed",
               output: "second output",
               duration_ms: 120
             })

    assert {:ok, _old_checkpoint} =
             RecordStore.create_checkpoint(%{
               session_id: running.id,
               sprites_checkpoint_id: "checkpoint-old",
               name: "old checkpoint",
               exec_session_sequence: 1,
               created_at: DateTime.add(now, -90, :second)
             })

    assert {:ok, _latest_checkpoint} =
             RecordStore.create_checkpoint(%{
               session_id: running.id,
               sprites_checkpoint_id: "checkpoint-latest",
               name: "latest checkpoint",
               exec_session_sequence: 2,
               created_at: now
             })

    for {event_type, offset} <- [{"session.started", -30}, {"exec_session.output", -20}, {"session.completed", -10}] do
      assert {:ok, _event} =
               RecordStore.create_runtime_event(%{
                 session_id: running.id,
                 event_type: event_type,
                 payload: %{"event_type" => event_type},
                 occurred_at: DateTime.add(now, offset, :second)
               })
    end

    assert {:ok, sessions_projection} =
             Projections.sandbox_sessions(
               %{
                 managed_repo_id: repo_id,
                 status: [:ready, :running],
                 workflow: "workflow:repair",
                 updated_after: DateTime.add(now, -60, :second)
               },
               limit: 10
             )

    assert sessions_projection.status == :ready
    assert Enum.map(sessions_projection.sessions, & &1.id) == [running.id]
    assert hd(sessions_projection.sessions).workflow == "workflow:repair"

    assert {:ok, exec_projection} = Projections.execution_history(running.id, limit: 1)
    assert [%{sequence: 2, output_summary: "second output"}] = exec_projection.exec_sessions

    assert {:ok, event_projection} = Projections.event_history(running.id, limit: 2)
    assert Enum.map(event_projection.events, & &1.event_type) == ["session.completed", "exec_session.output"]
    assert event_projection.result_group.limit == 2

    assert {:ok, detail_projection} = Projections.session_detail(running.id, exec_limit: 2, event_limit: 2)
    assert detail_projection.session.id == running.id
    assert detail_projection.latest_checkpoint.name == "latest checkpoint"
    assert detail_projection.latest_exec_session.sequence == 2
    assert detail_projection.execution_history.result_group.count == 2
    assert detail_projection.event_history.result_group.count == 2
  end

  defp setup_product_store do
    store_name = :"execution_runtime_projections_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_execution_runtime_projections_store/#{store_name}")

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
