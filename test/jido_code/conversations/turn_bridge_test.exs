defmodule JidoCode.Conversations.TurnBridgeTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
  # covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates
  # covers: architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
  # covers: architecture.execution_pipeline.public_turn_projection_is_non_blocking_for_conversation_delivery
  # covers: architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress
  use ExUnit.Case, async: false

  alias JidoCode.Conversations.TurnBridge
  alias JidoCode.TestSupport.Conversations.TurnBridgeCodingAssistanceFake
  alias JidoCode.TestSupport.Conversations.TurnBridgeRunBridgeFake
  alias JidoCode.TestSupport.Conversations.TurnBridgeRuntimeFake

  setup do
    original_coding_assistance_module =
      Application.get_env(:jido_code, :conversation_turn_bridge_coding_assistance_module, :__missing__)

    original_runtime_module = Application.get_env(:jido_code, :code_server_runtime_module, :__missing__)

    original_poll_interval_ms =
      Application.get_env(:jido_code, :conversation_turn_bridge_poll_interval_ms, :__missing__)

    original_max_idle_polls = Application.get_env(:jido_code, :conversation_turn_bridge_max_idle_polls, :__missing__)

    original_live_receive_timeout_ms =
      Application.get_env(:jido_code, :conversation_turn_bridge_live_receive_timeout_ms, :__missing__)

    original_supervisor = Application.get_env(:jido_code, :conversation_turn_bridge_supervisor, :__missing__)

    original_run_bridge_module =
      Application.get_env(:jido_code, :conversation_turn_bridge_run_bridge_module, :__missing__)

    supervisor_name = :"turn-bridge-supervisor-#{System.unique_integer([:positive, :monotonic])}"
    start_supervised!({Task.Supervisor, name: supervisor_name})

    Application.put_env(
      :jido_code,
      :conversation_turn_bridge_coding_assistance_module,
      TurnBridgeCodingAssistanceFake
    )

    Application.put_env(:jido_code, :code_server_runtime_module, TurnBridgeRuntimeFake)
    Application.put_env(:jido_code, :conversation_turn_bridge_poll_interval_ms, 1)
    Application.put_env(:jido_code, :conversation_turn_bridge_max_idle_polls, 2)
    Application.put_env(:jido_code, :conversation_turn_bridge_live_receive_timeout_ms, 5)
    Application.put_env(:jido_code, :conversation_turn_bridge_supervisor, supervisor_name)
    Application.put_env(:jido_code, :conversation_turn_bridge_run_bridge_module, TurnBridgeRunBridgeFake)

    TurnBridgeCodingAssistanceFake.clear()
    TurnBridgeRunBridgeFake.clear()
    TurnBridgeRuntimeFake.clear()
    TurnBridgeRuntimeFake.set_owner(self())

    on_exit(fn ->
      restore_env(:conversation_turn_bridge_coding_assistance_module, original_coding_assistance_module)
      restore_env(:code_server_runtime_module, original_runtime_module)
      restore_env(:conversation_turn_bridge_poll_interval_ms, original_poll_interval_ms)
      restore_env(:conversation_turn_bridge_max_idle_polls, original_max_idle_polls)
      restore_env(:conversation_turn_bridge_live_receive_timeout_ms, original_live_receive_timeout_ms)
      restore_env(:conversation_turn_bridge_supervisor, original_supervisor)
      restore_env(:conversation_turn_bridge_run_bridge_module, original_run_bridge_module)
      TurnBridgeCodingAssistanceFake.clear()
      TurnBridgeRunBridgeFake.clear()
      TurnBridgeRuntimeFake.clear()
    end)

    :ok
  end

  test "prefers live delivery and uses terminal handoff plus replay verification to finish" do
    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-live-1",
        session_id: "conversation-live-1",
        state: "completed",
        assistant_output: %{message: "Live bridge ready."}
      },
      [
        %{
          event_id: "event-1",
          turn_id: "turn-live-1",
          session_id: "conversation-live-1",
          family: "admitted",
          content: "Accepted coding turn turn-live-1."
        },
        %{
          event_id: "event-2",
          turn_id: "turn-live-1",
          session_id: "conversation-live-1",
          family: "progress",
          content: "Preparing coding turn for live bridging"
        },
        %{
          event_id: "event-3",
          turn_id: "turn-live-1",
          session_id: "conversation-live-1",
          family: "completed",
          content: "Live bridge ready."
        }
      ],
      %{
        turn_id: "turn-live-1",
        assistant_output: %{message: "Live bridge ready."}
      },
      [
        %{
          artifact_id: "artifact-1",
          kind: "patch",
          title: "Patch summary",
          summary: "Live bridge patch summary"
        }
      ],
      subscribe_result: {:ok, %{delivery_status: "subscribed", subscription_id: "sub-live-1"}},
      live_envelopes: [
        %{
          kind: "turn_event",
          event: %{
            event_id: "event-1",
            turn_id: "turn-live-1",
            session_id: "conversation-live-1",
            family: "admitted",
            content: "Accepted coding turn turn-live-1."
          }
        },
        %{
          kind: "turn_event",
          event: %{
            event_id: "event-2",
            turn_id: "turn-live-1",
            session_id: "conversation-live-1",
            family: "progress",
            content: "Preparing coding turn for live bridging"
          }
        },
        %{
          kind: "terminal_handoff",
          terminal_state: "completed",
          terminal_event_id: "event-3",
          latest_event_id: "event-3"
        }
      ]
    )

    assert {:ok, pid} =
             TurnBridge.start(%{
               project_id: "project-live",
               conversation_id: "conversation-live-1",
               actor_id: "operator-live",
               context: %{
                 session_id: "conversation-live-1",
                 project_id: "managed-repo-live",
                 request_id: "req-live-1",
                 correlation_id: "corr-live-1"
               },
               ingress: %{work_item: %{id: "work-item-live-1"}},
               turn: %{turn_id: "turn-live-1"}
             })

    ref = Process.monitor(pid)

    assert_receive {:conversation_event, "conversation-live-1", admitted_event}
    assert admitted_event["type"] == "assistant.delta"

    assert_receive {:conversation_event, "conversation-live-1", progress_event}
    assert progress_event["type"] == "assistant.delta"

    assert_receive {:conversation_event, "conversation-live-1", final_event}
    assert final_event["type"] == "assistant.message"
    assert get_in(final_event, ["data", "content"]) == "Live bridge ready."

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert [%{resume_after_event_id: nil}] =
             Enum.map(TurnBridgeCodingAssistanceFake.calls(:subscribe_turn_events), fn payload ->
               %{resume_after_event_id: payload[:resume_after_event_id] || payload["resume_after_event_id"]}
             end)

    assert [%{subscription_id: "sub-live-1"}] =
             Enum.map(TurnBridgeCodingAssistanceFake.calls(:unsubscribe_turn_events), fn payload ->
               %{subscription_id: payload[:subscription_id] || payload["subscription_id"]}
             end)

    assert [
             %{
               turn: %{turn_id: "turn-live-1"},
               review: %{turn_id: "turn-live-1"},
               artifacts: [%{artifact_id: "artifact-1"}]
             }
           ] =
             Enum.map(TurnBridgeRunBridgeFake.calls(), fn attrs ->
               %{
                 turn: Map.take(attrs.turn, [:turn_id]),
                 review: Map.take(attrs.review, [:turn_id]),
                 artifacts: Enum.map(attrs.artifacts, &Map.take(&1, [:artifact_id]))
               }
             end)
  end

  test "falls back to replay when live delivery is withheld and still preserves subscriber contract" do
    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-fallback-1",
        session_id: "conversation-fallback-1",
        state: "completed",
        assistant_output: %{message: "Replay fallback ready."}
      },
      [
        %{
          event_id: "event-a",
          turn_id: "turn-fallback-1",
          session_id: "conversation-fallback-1",
          family: "admitted",
          content: "Accepted coding turn turn-fallback-1."
        },
        %{
          event_id: "event-b",
          turn_id: "turn-fallback-1",
          session_id: "conversation-fallback-1",
          family: "progress",
          content: "Repairing gap through replay fallback"
        },
        %{
          event_id: "event-c",
          turn_id: "turn-fallback-1",
          session_id: "conversation-fallback-1",
          family: "completed",
          content: "Replay fallback ready."
        }
      ],
      %{
        turn_id: "turn-fallback-1",
        assistant_output: %{message: "Replay fallback ready."}
      },
      [],
      subscribe_result: {:ok, %{delivery_status: "withheld", reason_code: "rollout_withheld"}}
    )

    assert {:ok, pid} =
             TurnBridge.start(%{
               project_id: "project-fallback",
               conversation_id: "conversation-fallback-1",
               actor_id: "operator-fallback",
               context: %{
                 session_id: "conversation-fallback-1",
                 project_id: "managed-repo-fallback",
                 request_id: "req-fallback-1",
                 correlation_id: "corr-fallback-1"
               },
               ingress: %{work_item: %{id: "work-item-fallback-1"}},
               turn: %{turn_id: "turn-fallback-1"}
             })

    ref = Process.monitor(pid)

    assert_receive {:conversation_event, "conversation-fallback-1", admitted_event}
    assert admitted_event["type"] == "assistant.delta"

    assert_receive {:conversation_event, "conversation-fallback-1", progress_event}
    assert progress_event["type"] == "assistant.delta"

    assert_receive {:conversation_event, "conversation-fallback-1", final_event}
    assert final_event["type"] == "assistant.message"
    assert get_in(final_event, ["data", "content"]) == "Replay fallback ready."

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert [%{}] = TurnBridgeCodingAssistanceFake.calls(:subscribe_turn_events)
    assert [] = TurnBridgeCodingAssistanceFake.calls(:unsubscribe_turn_events)
  end

  test "governed projection failures remain non-blocking for live subscriber progress" do
    TurnBridgeRunBridgeFake.put_result({:error, :governed_projection_failed})

    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-nonblocking-1",
        session_id: "conversation-nonblocking-1",
        state: "completed",
        assistant_output: %{message: "Non-blocking projection ready."}
      },
      [
        %{
          event_id: "event-x",
          turn_id: "turn-nonblocking-1",
          session_id: "conversation-nonblocking-1",
          family: "completed",
          content: "Non-blocking projection ready."
        }
      ],
      %{
        turn_id: "turn-nonblocking-1",
        assistant_output: %{message: "Non-blocking projection ready."}
      },
      [],
      subscribe_result: {:ok, %{delivery_status: "subscribed", subscription_id: "sub-nonblocking-1"}},
      live_envelopes: [
        %{
          kind: "terminal_handoff",
          terminal_state: "completed",
          terminal_event_id: "event-x",
          latest_event_id: "event-x"
        }
      ]
    )

    assert {:ok, pid} =
             TurnBridge.start(%{
               project_id: "project-nonblocking",
               conversation_id: "conversation-nonblocking-1",
               actor_id: "operator-nonblocking",
               context: %{
                 session_id: "conversation-nonblocking-1",
                 project_id: "managed-repo-nonblocking",
                 request_id: "req-nonblocking-1",
                 correlation_id: "corr-nonblocking-1"
               },
               ingress: %{work_item: %{id: "work-item-nonblocking-1"}},
               turn: %{turn_id: "turn-nonblocking-1"}
             })

    ref = Process.monitor(pid)

    assert_receive {:conversation_event, "conversation-nonblocking-1", final_event}
    assert final_event["type"] == "assistant.message"
    assert get_in(final_event, ["data", "content"]) == "Non-blocking projection ready."

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert [%{}] = TurnBridgeRunBridgeFake.calls()
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
