defmodule JidoCode.Conversations.PhaseNineIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
  # covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates
  # covers: architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
  # covers: architecture.conversation_driver.subscriber_event_contract_preserved
  # covers: architecture.factory_control_plane.runtime_turns_feed_governed_control_records
  # covers: architecture.execution_pipeline.public_turn_projection_is_non_blocking_for_conversation_delivery
  # covers: architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress
  use JidoCode.DataCase, async: false

  alias JidoCode.CodeServer
  alias JidoCode.Conversations.TurnBridge
  alias JidoCode.Conversations.Driver
  alias JidoCode.Projects.Project
  alias JidoCode.TestSupport.CodeServer.EngineFake

  alias JidoCode.TestSupport.Conversations.{
    TurnBridgeCodingAssistanceFake,
    TurnBridgeRunBridgeFake,
    TurnBridgeRuntimeFake
  }

  @managed_env_keys [
    :code_server_runtime_module,
    :code_server_engine_module,
    :code_server_conversation_driver_module,
    :code_server_conversation_turn_bridge_module,
    :conversation_driver_coding_assistance_module,
    :conversation_turn_bridge_coding_assistance_module,
    :conversation_turn_bridge_poll_interval_ms,
    :conversation_turn_bridge_max_idle_polls,
    :conversation_turn_bridge_live_receive_timeout_ms,
    :conversation_turn_bridge_supervisor,
    :conversation_turn_bridge_run_bridge_module
  ]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    supervisor_name = :"phase-nine-turn-bridge-#{System.unique_integer([:positive, :monotonic])}"
    start_supervised!({Task.Supervisor, name: supervisor_name})

    Application.put_env(:jido_code, :code_server_runtime_module, TurnBridgeRuntimeFake)
    Application.put_env(:jido_code, :code_server_engine_module, EngineFake)
    Application.put_env(:jido_code, :code_server_conversation_driver_module, Driver)
    Application.put_env(:jido_code, :code_server_conversation_turn_bridge_module, TurnBridge)
    Application.put_env(:jido_code, :conversation_driver_coding_assistance_module, TurnBridgeCodingAssistanceFake)
    Application.put_env(:jido_code, :conversation_turn_bridge_coding_assistance_module, TurnBridgeCodingAssistanceFake)
    Application.put_env(:jido_code, :conversation_turn_bridge_poll_interval_ms, 1)
    Application.put_env(:jido_code, :conversation_turn_bridge_max_idle_polls, 2)
    Application.put_env(:jido_code, :conversation_turn_bridge_live_receive_timeout_ms, 5)
    Application.put_env(:jido_code, :conversation_turn_bridge_supervisor, supervisor_name)
    Application.put_env(:jido_code, :conversation_turn_bridge_run_bridge_module, TurnBridgeRunBridgeFake)

    EngineFake.clear()
    TurnBridgeRuntimeFake.clear()
    TurnBridgeRuntimeFake.set_owner(self())
    TurnBridgeCodingAssistanceFake.clear()
    TurnBridgeRunBridgeFake.clear()
    EngineFake.put_default_whereis_response({:ok, self()})

    on_exit(fn ->
      EngineFake.clear()
      TurnBridgeRuntimeFake.clear()
      TurnBridgeCodingAssistanceFake.clear()
      TurnBridgeRunBridgeFake.clear()

      Enum.each(original_env, fn {key, value} ->
        restore_env(:jido_code, key, value)
      end)
    end)

    :ok
  end

  test "live delivery streams progress and terminal handoff keeps subscriber events stable" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-nine-live", workspace_path)

    configure_runtime_start(project.id)

    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-phase-nine-live",
        session_id: "conversation-phase-nine-live",
        state: "completed",
        assistant_output: %{message: "Live integration ready."}
      },
      [
        %{
          event_id: "event-live-1",
          turn_id: "turn-phase-nine-live",
          session_id: "conversation-phase-nine-live",
          family: "admitted",
          content: "Accepted live coding turn."
        },
        %{
          event_id: "event-live-2",
          turn_id: "turn-phase-nine-live",
          session_id: "conversation-phase-nine-live",
          family: "progress",
          content: "Streaming progress over live delivery."
        }
      ],
      %{turn_id: "turn-phase-nine-live"},
      [],
      subscribe_result: {:ok, %{delivery_status: "subscribed", subscription_id: "sub-phase-nine-live"}},
      live_envelopes: [
        %{
          kind: "turn_event",
          event: %{
            event_id: "event-live-1",
            turn_id: "turn-phase-nine-live",
            session_id: "conversation-phase-nine-live",
            family: "admitted",
            content: "Accepted live coding turn."
          }
        },
        %{
          kind: "turn_event",
          event: %{
            event_id: "event-live-2",
            turn_id: "turn-phase-nine-live",
            session_id: "conversation-phase-nine-live",
            family: "progress",
            content: "Streaming progress over live delivery."
          }
        },
        %{
          kind: "terminal_handoff",
          terminal_state: "completed",
          terminal_event_id: "event-live-3",
          latest_event_id: "event-live-3"
        }
      ]
    )

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-phase-nine", email: "phase-nine@example.com"}
             )

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Bridge live updates into the existing conversation event contract.",
               actor: %{id: "operator-phase-nine", email: "phase-nine@example.com"}
             )

    assert_receive {:conversation_event, ^conversation_id, %{"type" => "user.message"}}

    assert_receive {:conversation_event, ^conversation_id, admitted_event}
    assert admitted_event["type"] == "assistant.delta"
    assert get_in(admitted_event, ["data", "content"]) == "Accepted live coding turn."

    assert_receive {:conversation_delta, ^conversation_id, _admitted_delta}

    assert_receive {:conversation_event, ^conversation_id, progress_event}
    assert progress_event["type"] == "assistant.delta"
    assert get_in(progress_event, ["data", "content"]) == "Streaming progress over live delivery."

    assert_receive {:conversation_delta, ^conversation_id, _progress_delta}

    assert_receive {:conversation_event, ^conversation_id, final_event}
    assert final_event["type"] == "assistant.message"
    assert get_in(final_event, ["data", "content"]) == "Live integration ready."
    assert get_in(final_event, ["meta", "terminal_handoff_kind"]) == "terminal_handoff"
    assert get_in(final_event, ["meta", "terminal_event_id"]) == "event-live-3"

    assert [%{subscription_id: "sub-phase-nine-live"}] =
             wait_for_value(fn ->
               Enum.map(TurnBridgeCodingAssistanceFake.calls(:unsubscribe_turn_events), fn payload ->
                 %{subscription_id: payload[:subscription_id] || payload["subscription_id"]}
               end)
             end)

    assert [%{}] = wait_for_value(&TurnBridgeRunBridgeFake.calls/0)
  end

  test "detached live delivery repairs from replay cursor and emits terminal failure deterministically" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-nine-recovery", workspace_path)

    configure_runtime_start(project.id)

    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-phase-nine-recovery",
        session_id: "conversation-phase-nine-recovery",
        state: "failed",
        assistant_output: %{message: "Replay repair surfaced a failed turn."}
      },
      [
        %{
          event_id: "event-recovery-1",
          turn_id: "turn-phase-nine-recovery",
          session_id: "conversation-phase-nine-recovery",
          family: "admitted",
          content: "Accepted recoverable coding turn."
        },
        %{
          event_id: "event-recovery-2",
          turn_id: "turn-phase-nine-recovery",
          session_id: "conversation-phase-nine-recovery",
          family: "progress",
          content: "Recovered the missed progress update through replay."
        }
      ],
      %{turn_id: "turn-phase-nine-recovery"},
      [],
      subscribe_result: {:ok, %{delivery_status: "subscribed", subscription_id: "sub-phase-nine-recovery"}},
      live_envelopes: [
        %{
          kind: "turn_event",
          event: %{
            event_id: "event-recovery-1",
            turn_id: "turn-phase-nine-recovery",
            session_id: "conversation-phase-nine-recovery",
            family: "admitted",
            content: "Accepted recoverable coding turn."
          }
        },
        %{kind: "detached"}
      ]
    )

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-phase-nine", email: "phase-nine@example.com"}
             )

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Recover after live delivery disconnects.",
               actor: %{id: "operator-phase-nine", email: "phase-nine@example.com"}
             )

    assert_receive {:conversation_event, ^conversation_id, %{"type" => "user.message"}}

    assert_receive {:conversation_event, ^conversation_id, admitted_event}
    assert admitted_event["type"] == "assistant.delta"
    assert get_in(admitted_event, ["data", "content"]) == "Accepted recoverable coding turn."

    assert_receive {:conversation_event, ^conversation_id, repaired_progress_event}
    assert repaired_progress_event["type"] == "assistant.delta"

    assert get_in(repaired_progress_event, ["data", "content"]) ==
             "Recovered the missed progress update through replay."

    assert_receive {:conversation_event, ^conversation_id, failure_event}
    assert failure_event["type"] == "llm.failed"
    assert get_in(failure_event, ["data", "detail"]) == "Replay repair surfaced a failed turn."
    assert get_in(failure_event, ["meta", "terminal_handoff_kind"]) == "replay_terminal_lookup"
    assert get_in(failure_event, ["meta", "terminal_state"]) == "failed"

    assert Enum.any?(TurnBridgeCodingAssistanceFake.calls(:list_turn_events), fn payload ->
             (payload[:after_event_id] || payload["after_event_id"]) == "event-recovery-1"
           end)
  end

  test "rollout-withheld live delivery falls back to replay without blocking subscriber progress" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-nine-withheld", workspace_path)

    configure_runtime_start(project.id)
    TurnBridgeRunBridgeFake.put_result({:error, :governed_projection_failed})

    TurnBridgeCodingAssistanceFake.configure(
      %{
        turn_id: "turn-phase-nine-withheld",
        session_id: "conversation-phase-nine-withheld",
        state: "completed",
        assistant_output: %{message: "Withheld live delivery still completed through replay."}
      },
      [
        %{
          event_id: "event-withheld-1",
          turn_id: "turn-phase-nine-withheld",
          session_id: "conversation-phase-nine-withheld",
          family: "admitted",
          content: "Accepted coding turn while live rollout is withheld."
        },
        %{
          event_id: "event-withheld-2",
          turn_id: "turn-phase-nine-withheld",
          session_id: "conversation-phase-nine-withheld",
          family: "progress",
          content: "Replaying progress because live rollout is withheld."
        }
      ],
      %{turn_id: "turn-phase-nine-withheld"},
      [],
      subscribe_result: {:ok, %{delivery_status: "withheld", reason_code: "rollout_withheld"}}
    )

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-phase-nine", email: "phase-nine@example.com"}
             )

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Use replay when live delivery is rollout-withheld.",
               actor: %{id: "operator-phase-nine", email: "phase-nine@example.com"}
             )

    assert_receive {:conversation_event, ^conversation_id, %{"type" => "user.message"}}

    assert_receive {:conversation_event, ^conversation_id, admitted_event}
    assert admitted_event["type"] == "assistant.delta"

    assert get_in(admitted_event, ["data", "content"]) ==
             "Accepted coding turn while live rollout is withheld."

    assert_receive {:conversation_event, ^conversation_id, progress_event}
    assert progress_event["type"] == "assistant.delta"

    assert get_in(progress_event, ["data", "content"]) ==
             "Replaying progress because live rollout is withheld."

    assert_receive {:conversation_event, ^conversation_id, final_event}
    assert final_event["type"] == "assistant.message"

    assert get_in(final_event, ["data", "content"]) ==
             "Withheld live delivery still completed through replay."

    assert get_in(final_event, ["meta", "terminal_handoff_kind"]) == "replay_terminal_lookup"

    assert [%{}] = wait_for_value(&TurnBridgeRunBridgeFake.calls/0)
    assert [] = TurnBridgeCodingAssistanceFake.calls(:unsubscribe_turn_events)
  end

  defp configure_runtime_start(project_id) do
    EngineFake.clear()
    TurnBridgeRuntimeFake.clear()
    TurnBridgeRuntimeFake.set_owner(self())
    EngineFake.put_default_whereis_response({:ok, self()})

    EngineFake.put_whereis_responses(project_id, [
      {:error, {:project_not_found, project_id}},
      {:ok, self()}
    ])
  end

  defp create_ready_project(name, workspace_path) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: %{
        "workspace" => %{
          "workspace_environment" => "local",
          "workspace_path" => workspace_path,
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        }
      }
    })
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-nine-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp wait_for_value(fun, attempts_left \\ 20)

  defp wait_for_value(fun, 0), do: fun.()

  defp wait_for_value(fun, attempts_left) when is_function(fun, 0) do
    case fun.() do
      [] ->
        Process.sleep(25)
        wait_for_value(fun, attempts_left - 1)

      nil ->
        Process.sleep(25)
        wait_for_value(fun, attempts_left - 1)

      value ->
        value
    end
  end

  defp restore_env(app, key, :__missing__), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
