defmodule JidoCode.ControlPlane.EmbeddedStorePhaseSixIntegrationTest do
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.context_compaction_policy.compaction_preserves_required_context
  # covers: architecture.execution_runtime.exec_session_projection_excludes_unbounded_output
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Conversations
  alias JidoCode.Conversations.{ChildWork, Event, Snapshot, Turn}
  alias JidoCode.Conversations.Persistence, as: ConversationPersistence
  alias JidoCode.Conversations.Projections, as: ConversationProjections
  alias JidoCode.ExecutionRuntime.Projections, as: RuntimeProjections
  alias JidoCode.ExecutionRuntime.RecordStore
  alias JidoCode.Forge.Persistence, as: RuntimePersistence
  alias JidoCode.Forge.{EventLogger, Operations}

  setup do
    setup_product_store()
  end

  test "conversation replay snapshots and reset-aware prompt projections survive embedded persistence" do
    {:ok, managed_repo} = create_managed_repo("owner/phase-six-conversation")

    assert {:ok, %{conversation: conversation, work_item: work_item}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               source: "phase_six_integration",
               attach_mode: :synthesized_work_item,
               title: "Phase six conversation",
               objective: "Persist and restore reset-aware conversation runtime state."
             })

    assert work_item.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id

    state = conversation_state_with_reset(conversation)
    previous_state = %{state | events: [], event_sequence: 0}

    assert :ok = ConversationPersistence.persist_transition(previous_state, state)

    assert {:ok, persisted_events} = ConversationPersistence.events_since(conversation.id, 0)
    assert Enum.map(persisted_events, & &1.sequence) == [1, 2]
    assert Enum.map(persisted_events, & &1.name) == ["conversation.message_added", "conversation.context_compacted"]

    assert {:ok, event_window} = ConversationProjections.event_window(conversation.id, after_sequence: 0, limit: 1)
    assert [%{sequence: 1}] = event_window.events
    assert event_window.has_more?

    assert {:ok, restored_state} = ConversationPersistence.restore_state(conversation)
    restored_snapshot = Snapshot.from_state(restored_state)

    assert Enum.map(restored_snapshot.events, & &1.name) == [
             "conversation.message_added",
             "conversation.context_compacted"
           ]

    assert restored_snapshot.shared_context["latest_context_reset"]["summary_id"] == "summary-phase-six"
    refute "lib/old_phase_six.ex" in restored_snapshot.shared_context["referenced_files"]
    assert "lib/current_phase_six.ex" in restored_snapshot.shared_context["referenced_files"]

    assert {:ok, prompt_projection} = ConversationProjections.latest_snapshot_prompt(conversation.id)
    assert prompt_projection.prompt_projection.reset_aware?
    assert prompt_projection.prompt_projection.history_start_sequence == 2
    assert prompt_projection.prompt_projection.latest_context_reset["summary_id"] == "summary-phase-six"
  end

  test "execution runtime lifecycle persists checkpoint resume metadata and redacted bounded output" do
    {:ok, managed_repo} = create_managed_repo("owner/phase-six-runtime")

    assert {:ok, workflow} =
             RecordStore.upsert_execution_workflow(%{
               name: "phase-six-runtime-workflow",
               description: "Phase six runtime integration workflow",
               steps: [%{"name" => "verify"}],
               tags: ["phase-six"]
             })

    assert {:ok, sprite_spec} =
             RecordStore.upsert_sprite_spec(%{
               name: "phase-six-runtime-sprite",
               runner: :shell,
               runner_config: %{"shell" => "bash"},
               base_image: "ubuntu-22.04"
             })

    assert workflow.name == "phase-six-runtime-workflow"
    assert sprite_spec.name == "phase-six-runtime-sprite"

    session_id = "phase-six-runtime-session"

    assert {:ok, session} =
             RuntimePersistence.record_session_started(session_id, %{
               managed_repo_id: managed_repo.id,
               runner: :shell,
               runner_config: %{shell: "bash"},
               workflow: workflow.name,
               sprite_spec_id: sprite_spec.id
             })

    assert {:ok, _provisioned} =
             RuntimePersistence.record_provision_complete(session_id, "sprite-phase-six", "phase-six")

    assert {:ok, _ready} = RuntimePersistence.record_bootstrap_complete(session_id)

    assert {:ok, exec_session} =
             RuntimePersistence.record_execution_start(session_id, 1,
               command: "mix test",
               sprites_session_id: "sprites-phase-six"
             )

    secret = "sk-test-0123456789abcdef"
    oversized_output = String.duplicate("x", 12_000) <> "\nAuthorization: Bearer #{secret}"

    assert {:ok, completed} =
             RuntimePersistence.record_execution_complete(session_id, %{
               status: :done,
               output: oversized_output,
               runner_state: %{
                 api_token: secret,
                 prompt: "Use Authorization: Bearer #{secret}"
               }
             })

    assert completed.phase == :completed
    refute completed.output_buffer =~ secret
    assert byte_size(completed.output_buffer) <= 10_000

    assert :ok =
             EventLogger.log_event(session.id, "exec_session.output", %{
               chunk: "Authorization: Bearer #{secret}",
               exec_session_id: exec_session.id
             })

    assert {:ok, checkpoint_ready} =
             RecordStore.update_sandbox_session(completed, %{
               phase: :ready,
               sprite_id: "sprite-phase-six",
               runner_state: %{"step" => "checkpoint-ready"}
             })

    assert {:ok, checkpoint} = Operations.create_checkpoint(checkpoint_ready.id, name: "phase-six-checkpoint")
    assert checkpoint.sprites_checkpoint_id =~ "chk_sprite-phase-six_"

    assert {:ok, failed} =
             Operations.mark_failed(checkpoint_ready.id, %{
               message: "Resume from latest checkpoint",
               api_token: secret
             })

    assert failed.phase == :failed
    refute inspect(failed.last_error) =~ secret

    assert {:ok, detail_projection} = RuntimeProjections.session_detail(failed.id, exec_limit: 5, event_limit: 10)
    assert detail_projection.session.phase == :failed
    assert detail_projection.latest_checkpoint.sprites_checkpoint_id == checkpoint.sprites_checkpoint_id
    assert detail_projection.latest_exec_session.sequence == 1
    assert detail_projection.latest_exec_session.output_size_bytes > 0
    assert byte_size(detail_projection.latest_exec_session.output_summary) <= 10_000
    refute inspect(detail_projection) =~ secret
  end

  defp conversation_state_with_reset(conversation) do
    conversation_id = conversation.id

    turn_1 = turn(conversation_id, "turn-old-phase-six", "older request", ["lib/old_phase_six.ex"])
    turn_2 = turn(conversation_id, "turn-current-phase-six", "current request", ["lib/current_phase_six.ex"])

    child_1 =
      child_work(conversation, "child-old-phase-six", "turn-old-phase-six", "older result", [
        "lib/old_result_phase_six.ex"
      ])

    child_2 =
      child_work(conversation, "child-current-phase-six", "turn-current-phase-six", "current result", [
        "lib/current_result_phase_six.ex"
      ])

    %{
      conversation: conversation,
      status: conversation.status,
      admission_paused: false,
      child_execution_paused: false,
      active_turn_id: nil,
      work_queue: [],
      turns: %{turn_1.id => turn_1, turn_2.id => turn_2},
      turn_order: [turn_1.id, turn_2.id],
      control_history: [],
      child_works: %{child_1.id => child_1, child_2.id => child_2},
      child_work_order: [child_1.id, child_2.id],
      child_worker_pids: %{},
      pending_context_compaction: nil,
      event_sequence: 2,
      events: [
        Event.new(conversation_id, 1, "conversation.message_added", %{
          payload: %{"instruction" => "older request"}
        }),
        Event.new(conversation_id, 2, "conversation.context_compacted", %{
          payload: %{
            "summary_id" => "summary-phase-six",
            "recommendation_id" => "recommendation-phase-six",
            "source_span_ids" => ["turn:#{turn_1.id}"],
            "policy_id" => "context-management:v1",
            "workflow" => "execute",
            "specialist_role" => "coder",
            "reset_sequence" => 2
          }
        })
      ]
    }
  end

  defp turn(conversation_id, id, instruction, referenced_files) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Turn{
      id: id,
      conversation_id: conversation_id,
      command_id: "command-#{id}",
      command_type: "turn.submit",
      state: :completed,
      payload: %{"instruction" => instruction, "referenced_files" => referenced_files},
      inserted_at: now,
      completed_at: now
    }
  end

  defp child_work(conversation, id, turn_id, summary, referenced_files) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %ChildWork{
      id: id,
      conversation_id: conversation.id,
      managed_repo_id: conversation.managed_repo_id,
      work_item_id: conversation.work_item_id,
      turn_id: turn_id,
      tool_call_id: "tool-#{id}",
      kind: "tool_call",
      state: :completed,
      inserted_at: now,
      completed_at: now,
      result: %{"summary" => summary, "referenced_files" => referenced_files}
    }
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

  defp setup_product_store do
    store_name = :"phase_six_embedded_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_phase_six_embedded_store/#{store_name}")

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
