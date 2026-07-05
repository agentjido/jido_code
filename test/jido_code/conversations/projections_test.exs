defmodule JidoCode.Conversations.ProjectionsTest do
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  use JidoCode.DataCase, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Conversations.{Projections, RecordStore}

  setup do
    setup_product_store()
  end

  test "projects active historical clarification event-window and reset-aware snapshot views" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    repo_id = "repo-conversation-projections"
    work_item_id = "work-conversation-projections"

    {:ok, active} =
      RecordStore.create_conversation(%{
        conversation_id: "conversation-active-projection",
        managed_repo_id: repo_id,
        work_item_id: work_item_id,
        status: :active,
        scope: :work_item_scoped,
        attachment_mode: :existing_work_item,
        title: "Active projection",
        last_activity_at: DateTime.add(now, -60, :second)
      })

    {:ok, paused} =
      RecordStore.create_conversation(%{
        conversation_id: "conversation-paused-projection",
        managed_repo_id: repo_id,
        work_item_id: "work-paused-projection",
        status: :paused,
        scope: :work_item_scoped,
        attachment_mode: :existing_work_item,
        title: "Paused projection",
        last_activity_at: now
      })

    {:ok, completed} =
      RecordStore.create_conversation(%{
        conversation_id: "conversation-completed-projection",
        managed_repo_id: repo_id,
        work_item_id: work_item_id,
        status: :completed,
        scope: :work_item_scoped,
        attachment_mode: :existing_work_item,
        title: "Completed projection",
        last_activity_at: DateTime.add(now, -120, :second)
      })

    for sequence <- 1..4 do
      assert {:ok, _event} =
               RecordStore.append_event(%{
                 conversation_id: active.id,
                 sequence: sequence,
                 name: "conversation.event.#{sequence}",
                 payload: %{"sequence" => sequence}
               })
    end

    assert {:ok, _snapshot} =
             RecordStore.upsert_snapshot(%{
               conversation_id: active.id,
               managed_repo_id: repo_id,
               work_item_id: work_item_id,
               status: :active,
               last_event_sequence: 4,
               event_count: 4,
               shared_context: %{
                 "latest_context_reset" => %{
                   "summary_id" => "summary-projection",
                   "reset_sequence" => 3
                 }
               },
               captured_at: now
             })

    assert {:ok, _paused_snapshot} =
             RecordStore.upsert_snapshot(%{
               conversation_id: paused.id,
               managed_repo_id: repo_id,
               work_item_id: paused.work_item_id,
               status: :paused,
               admission_paused: true,
               active_turn_id: "turn-needs-clarification",
               captured_at: now
             })

    assert {:ok, active_projection} = Projections.active_for_managed_repo(repo_id, limit: 10)
    assert active_projection.status == :ready
    assert Enum.map(active_projection.conversations, & &1.id) == [paused.id, active.id]

    assert {:ok, work_projection} = Projections.active_for_work_item(work_item_id)
    assert work_projection.conversation.id == active.id

    assert {:ok, historical_projection} = Projections.historical_for_work_item(work_item_id)
    assert Enum.map(historical_projection.conversations, & &1.id) == [completed.id]

    assert {:ok, clarification_projection} = Projections.clarification_for_managed_repo(repo_id)
    assert [%{conversation_id: paused_id}] = clarification_projection.snapshots
    assert paused_id == paused.id

    assert {:ok, event_window} = Projections.event_window(active.id, after_sequence: 1, limit: 2)
    assert Enum.map(event_window.events, & &1.sequence) == [2, 3]
    assert event_window.has_more?
    assert event_window.next_after_sequence == 3

    assert {:ok, snapshot_projection} = Projections.latest_snapshot_prompt(active.id)
    assert snapshot_projection.prompt_projection.reset_aware?
    assert snapshot_projection.prompt_projection.history_start_sequence == 3
    assert snapshot_projection.prompt_projection.latest_context_reset["summary_id"] == "summary-projection"
  end

  defp setup_product_store do
    store_name = :"conversation_projections_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_conversation_projections_store/#{store_name}")

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
