defmodule JidoCode.PhaseFortyThreeIntegrationTest do
  # covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Projects.Project

  test "pending clarification survives persisted recovery and resumes through canonical commands" do
    managed_repo = managed_repo_fixture!("phase-forty-three-recovery")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise persisted clarification recovery."
             })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Clarify the active repo scope."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    child_work_id = running_snapshot.active_child_work_id
    turn_id = running_snapshot.active_turn_id

    assert {:ok, _progress_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "progress",
                   summary: "Inspecting the active repo scope.",
                   percent: 20
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    assert {:ok, _stdout_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "stdout",
                   text: "rg --context 2 Clarify the active repo scope."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    assert {:ok, awaiting_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "needs_input",
                   prompt: "Which file should I inspect first?"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    assert awaiting_snapshot.active_turn.state == :awaiting_input
    assert awaiting_snapshot.active_child_work.result["latest_progress"]["percent"] == 20

    assert awaiting_snapshot.shared_context["pending_clarification"]["prompt"]["prompt"] ==
             "Which file should I inspect first?"

    assert :ok = Driver.stop(conversation.id)

    assert {:ok, persisted_snapshot} = Driver.snapshot(conversation.id)

    assert persisted_snapshot.active_turn.state == :awaiting_input

    assert persisted_snapshot.shared_context["pending_clarification"]["prompt"]["prompt"] ==
             "Which file should I inspect first?"

    assert persisted_snapshot.active_child_work.result["stdout"] == [
             "rg --context 2 Clarify the active repo scope."
           ]

    assert {:ok, resumed_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: turn_id,
                   response: "Start with lib/jido_code/conversations/snapshot.ex."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    assert resumed_snapshot.active_turn.id == turn_id
    assert resumed_snapshot.active_turn.state == :running
    assert resumed_snapshot.shared_context["pending_clarification"] == nil

    assert {:ok, _delta_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "delta",
                   text: "Continuing with lib/jido_code/conversations/snapshot.ex."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    assert {:ok, completed_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "completed",
                   result: %{summary: "Recovered clarification flow completed cleanly."}
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43"})
             )

    assert completed_snapshot.active_turn == nil
    assert completed_snapshot.active_child_work == nil

    assert Enum.any?(
             completed_snapshot.shared_context["accepted_tool_results"],
             &(&1["child_work_id"] == child_work_id)
           )
  end

  test "runtime delta replay stays sequenced after the last accepted event" do
    managed_repo = managed_repo_fixture!("phase-forty-three-replay")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise runtime delta replay."
             })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Replay the runtime delta flow."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    child_work_id = running_snapshot.active_child_work_id
    turn_id = running_snapshot.active_turn_id

    assert {:ok, _progress_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "progress",
                   summary: "Tracing the runtime event flow."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    assert {:ok, _stdout_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "stdout",
                   text: "rg runtime delta flow"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    assert {:ok, _awaiting_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "needs_input",
                   prompt: "Which test should I replay?"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    checkpoint_sequence = running_snapshot.last_event_sequence

    assert {:ok, _resumed_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: turn_id,
                   response: "Replay the conversation integration tests."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    assert {:ok, _delta_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "delta",
                   text: "Replaying the conversation integration tests."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    assert {:ok, _completed_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "completed",
                   result: %{summary: "Runtime replay completed."}
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase43-replay"})
             )

    assert {:ok, replayed_events} =
             Driver.events_since(
               conversation.id,
               checkpoint_sequence,
               actor: Actor.operator_actor()
             )

    assert Enum.map(replayed_events, & &1.name) == [
             "tool.progress",
             "tool.stdout",
             "tool.needs_input",
             "turn.awaiting_input",
             "conversation.message_added",
             "turn.started",
             "turn.delta",
             "tool.completed",
             "turn.completed"
           ]

    assert Enum.map(replayed_events, & &1.sequence) ==
             Enum.to_list(
               (checkpoint_sequence + 1)..(checkpoint_sequence + length(replayed_events))
             )

    assert :ok = Driver.stop(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-three-#{suffix}",
        github_full_name: "owner/phase-forty-three-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end
end
