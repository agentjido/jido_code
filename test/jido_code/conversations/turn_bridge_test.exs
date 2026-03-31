defmodule JidoCode.Conversations.TurnBridgeTest do
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
      restore_env(:conversation_turn_bridge_supervisor, original_supervisor)
      restore_env(:conversation_turn_bridge_run_bridge_module, original_run_bridge_module)
      TurnBridgeCodingAssistanceFake.clear()
      TurnBridgeRunBridgeFake.clear()
      TurnBridgeRuntimeFake.clear()
    end)

    :ok
  end

  test "replays public turn events into the existing subscriber event contract" do
    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-1",
        session_id: "conversation-bridge-1",
        state: "completed"
      },
      [
        %{
          event_id: "event-1",
          turn_id: "turn-1",
          session_id: "conversation-bridge-1",
          family: "admitted",
          content: "Accepted coding turn turn-1."
        },
        %{
          event_id: "event-2",
          turn_id: "turn-1",
          session_id: "conversation-bridge-1",
          family: "progress",
          content: "Preparing coding turn for replay bridging"
        },
        %{
          event_id: "event-3",
          turn_id: "turn-1",
          session_id: "conversation-bridge-1",
          family: "completed",
          content: "Replay bridge ready."
        }
      ],
      %{
        turn_id: "turn-1",
        assistant_output: %{message: "Replay bridge ready."}
      },
      [
        %{
          artifact_id: "artifact-1",
          kind: "patch",
          title: "Patch summary",
          summary: "Replay bridge patch summary"
        }
      ]
    )

    assert {:ok, pid} =
             TurnBridge.start(%{
               project_id: "project-bridge",
               conversation_id: "conversation-bridge-1",
               actor_id: "operator-bridge",
               context: %{
                 session_id: "conversation-bridge-1",
                 project_id: "managed-repo-1",
                 request_id: "req-bridge-1",
                 correlation_id: "corr-bridge-1"
               },
               ingress: %{work_item: %{id: "work-item-1"}},
               turn: %{turn_id: "turn-1"}
             })

    ref = Process.monitor(pid)

    assert_receive {:conversation_event, "conversation-bridge-1", admitted_event}
    assert admitted_event["type"] == "assistant.delta"
    assert get_in(admitted_event, ["data", "content"]) =~ "Accepted coding turn"

    assert_receive {:conversation_delta, "conversation-bridge-1", admitted_delta}
    assert admitted_delta["type"] == "assistant.delta"

    assert_receive {:conversation_event, "conversation-bridge-1", progress_event}
    assert progress_event["type"] == "assistant.delta"
    assert get_in(progress_event, ["data", "content"]) =~ "Preparing coding turn"

    assert_receive {:conversation_delta, "conversation-bridge-1", progress_delta}
    assert progress_delta["type"] == "assistant.delta"

    assert_receive {:conversation_event, "conversation-bridge-1", final_event}
    assert final_event["type"] == "assistant.message"
    assert get_in(final_event, ["data", "content"]) == "Replay bridge ready."
    assert get_in(final_event, ["meta", "turn_event_family"]) == "completed"

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert [%{turn: %{turn_id: "turn-1"}, review: %{turn_id: "turn-1"}, artifacts: [%{artifact_id: "artifact-1"}]}] =
             Enum.map(TurnBridgeRunBridgeFake.calls(), fn attrs ->
               %{
                 turn: Map.take(attrs.turn, [:turn_id]),
                 review: Map.take(attrs.review, [:turn_id]),
                 artifacts: Enum.map(attrs.artifacts, &Map.take(&1, [:artifact_id]))
               }
             end)

    assert [
             {"project-bridge", "conversation-bridge-1", %{"type" => "assistant.delta"}},
             {"project-bridge", "conversation-bridge-1", %{"type" => "assistant.delta"}},
             {"project-bridge", "conversation-bridge-1", %{"type" => "assistant.message"}}
           ] =
             Enum.map(TurnBridgeRuntimeFake.calls(:send_event), fn {project_id, conversation_id, event} ->
               {project_id, conversation_id, %{"type" => event["type"]}}
             end)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
