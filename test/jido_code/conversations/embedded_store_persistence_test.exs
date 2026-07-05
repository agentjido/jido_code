defmodule JidoCode.Conversations.EmbeddedStorePersistenceTest do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Conversations
  alias JidoCode.Conversations.{Conversation, Persistence, Snapshot}
  alias JidoCode.Conversations.RecordStore, as: ConversationStore
  alias JidoCode.Operations.{RecordStore, WorkItem}

  setup do
    setup_product_store()
  end

  test "conversation lifecycle records are queried from the embedded product store" do
    {:ok, managed_repo} = create_managed_repo("owner/conversation-store-lifecycle")
    {:ok, %WorkItem{} = work_item} = create_work_item(managed_repo.id, "Store-backed conversation lifecycle")

    assert {:ok, %{conversation: %Conversation{} = conversation, work_item: %WorkItem{} = attached_work_item}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               source: "test",
               objective: "Exercise store-backed conversation lifecycle",
               actor: %{"id" => "operator-conversation-store", "email" => "operator@example.com"}
             })

    assert attached_work_item.id == work_item.id
    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :existing_work_item

    assert {:ok, %Conversation{} = active_conversation} = Conversations.active_for_work_item(work_item.id)
    assert active_conversation.id == conversation.id

    assert {:ok, %Conversation{} = latest_conversation} = Conversations.latest_for_work_item(work_item.id)
    assert latest_conversation.id == conversation.id

    assert {:error, {:active_work_item_conversation_exists, details}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               source: "test",
               objective: "Attempt duplicate active conversation"
             })

    assert details.work_item_id == work_item.id
    assert details.active_conversation_id == conversation.id
  end

  test "conversation events are sequenced and snapshots are recovered from the embedded product store" do
    {:ok, managed_repo} = create_managed_repo("owner/conversation-store-persistence")
    {:ok, %WorkItem{} = work_item} = create_work_item(managed_repo.id, "Store-backed conversation persistence")

    assert {:ok, %{conversation: %Conversation{} = conversation}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               source: "test",
               objective: "Exercise store-backed conversation persistence"
             })

    assert {:ok, first_event} =
             ConversationStore.append_event(%{
               conversation_id: conversation.id,
               name: "conversation.message_added",
               payload: %{"content" => "first"}
             })

    assert {:ok, second_event} =
             ConversationStore.append_event(%{
               conversation_id: conversation.id,
               name: "turn.started",
               payload: %{"turn_id" => "turn-1"}
             })

    assert {:ok, compaction_event} =
             ConversationStore.append_event(%{
               conversation_id: conversation.id,
               name: "conversation.context_compacted",
               payload: %{"reset_id" => "reset-1", "covered_turn_ids" => ["turn-1"]}
             })

    assert first_event.sequence == 1
    assert second_event.sequence == 2
    assert compaction_event.sequence == 3

    assert {:ok, [first_summary, second_summary, compaction_summary]} = Persistence.events_since(conversation.id, 0)
    assert first_summary.sequence == 1
    assert first_summary.name == "conversation.message_added"
    assert second_summary.sequence == 2
    assert second_summary.name == "turn.started"
    assert compaction_summary.sequence == 3
    assert compaction_summary.name == "conversation.context_compacted"
    assert compaction_summary.payload["reset_id"] == "reset-1"

    assert {:ok, [after_second_summary]} = Persistence.events_since(conversation.id, 2)
    assert after_second_summary.sequence == compaction_summary.sequence
    assert after_second_summary.name == compaction_summary.name

    snapshot =
      conversation
      |> Snapshot.empty()
      |> Map.put(:last_event_sequence, 3)
      |> Map.put(:event_count, 3)
      |> Map.put(:events, [first_summary, second_summary, compaction_summary])

    assert :ok = Persistence.persist_snapshot(snapshot)

    assert {:ok, fetched_snapshot} = Persistence.fetch_snapshot(conversation.id)
    assert fetched_snapshot.conversation_id == conversation.id
    assert fetched_snapshot.last_event_sequence == 3
    assert fetched_snapshot.event_count == 3
    assert fetched_snapshot.shared_context["work_item_id"] == work_item.id

    assert {:ok, restored_state} = Persistence.restore_state(conversation)
    assert restored_state.event_sequence == 3
    assert Enum.map(restored_state.events, & &1.sequence) == [1, 2, 3]
    assert List.last(restored_state.events).name == "conversation.context_compacted"
  end

  defp create_managed_repo(full_name) do
    with {:ok, %{managed_repo: managed_repo}} <-
           RepoBridge.upsert_managed_repo(%{
             name: full_name,
             full_name: full_name,
             default_branch: "main",
             settings: %{}
           }) do
      {:ok, managed_repo}
    end
  end

  defp create_work_item(managed_repo_id, summary) do
    RecordStore.create(:work_item, %{
      managed_repo_id: managed_repo_id,
      category: "conversation",
      status: :open,
      priority: :medium,
      recommended_action: "continue",
      summary: summary,
      dedup_key: "conversation:#{managed_repo_id}:#{summary}",
      initiating_actor: %{"id" => "operator-conversation-store"},
      work_metadata: %{"source" => "embedded_store_persistence_test"},
      audit_log: []
    })
  end

  defp setup_product_store do
    store_name = :"conversation_embedded_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_conversation_embedded_store/#{store_name}")

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
