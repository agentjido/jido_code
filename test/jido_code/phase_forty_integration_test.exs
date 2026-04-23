defmodule JidoCode.PhaseFortyIntegrationTest do
  # covers: architecture.conversation_orchestration.active_turns_can_be_superseded
  # covers: architecture.conversation_orchestration.cancellation_lifecycle_is_evented
  # covers: architecture.conversation_orchestration.control_lane_preempts_work_lane
  # covers: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Projects.Project

  test "conversation cancellation keeps child-work ownership and explicit terminal outcomes aligned" do
    managed_repo = managed_repo_fixture!("cancel")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise cancellation through the driver.",
               actor: %{id: "operator-phase40-cancel", email: "phase40-cancel@example.com"}
             })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the current issue.", tool_call_id: "phase40-tool-1"}},
               actor: Actor.operator_actor()
             )

    assert running_snapshot.active_child_work.managed_repo_id == managed_repo.id
    assert running_snapshot.active_child_work.turn_id == running_snapshot.active_turn.id
    assert running_snapshot.active_child_work.tool_call_id == "phase40-tool-1"

    assert {:ok, stopping_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.stop", payload: %{reason: "Stop the active tool execution."}},
               actor: Actor.operator_actor()
             )

    assert stopping_snapshot.active_turn.state == :cancelling
    assert stopping_snapshot.active_child_work.state == :cancel_acknowledged
    assert Enum.any?(stopping_snapshot.control_history, &(&1.type == "turn.stop"))

    assert {:ok, cancelled_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               running_snapshot.active_child_work_id,
               :cancelled,
               %{result: %{reason: "Operator stop completed cleanly."}},
               actor: Actor.operator_actor()
             )

    cancelled_turn = Enum.find(cancelled_snapshot.turns, &(&1.id == running_snapshot.active_turn_id))
    cancelled_child_work = Enum.find(cancelled_snapshot.child_works, &(&1.id == running_snapshot.active_child_work_id))

    assert cancelled_snapshot.active_turn == nil
    assert cancelled_turn.state == :cancelled
    assert cancelled_child_work.state == :cancelled
    assert cancelled_child_work.result["reason"] == "Operator stop completed cleanly."

    assert :ok = Driver.stop(conversation.id)
  end

  test "completion before cancel remains explicit and leaves the settled turn intact" do
    managed_repo = managed_repo_fixture!("completion-race")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise completion-before-cancel race behavior."
             })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Run the fast analysis.", tool_call_id: "phase40-tool-2"}},
               actor: Actor.operator_actor()
             )

    assert {:ok, completed_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               running_snapshot.active_child_work_id,
               :completed,
               %{result: %{summary: "The active work completed before cancellation arrived."}},
               actor: Actor.operator_actor()
             )

    completed_turn = Enum.find(completed_snapshot.turns, &(&1.id == running_snapshot.active_turn_id))
    completed_child_work = Enum.find(completed_snapshot.child_works, &(&1.id == running_snapshot.active_child_work_id))

    assert completed_turn.state == :completed
    assert completed_child_work.state == :completed
    assert {:error, :child_work_already_settled} =
             Driver.cancel_child_work(conversation.id, running_snapshot.active_child_work_id, actor: Actor.operator_actor())

    assert :ok = Driver.stop(conversation.id)
  end

  test "steering overtakes queued work and preserves supersession audit links through the driver" do
    managed_repo = managed_repo_fixture!("steer")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise steer priority and supersession."
             })

    assert {:ok, first_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the broad objective."}},
               actor: Actor.operator_actor()
             )

    assert {:ok, second_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Run the stale queued task."}},
               actor: Actor.operator_actor()
             )

    queued_turn_id = List.first(second_snapshot.queued_turn_ids)

    assert {:ok, steering_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.steer", payload: %{instruction: "Replace the active turn with the narrowed objective."}},
               actor: Actor.operator_actor()
             )

    replacement_turn = List.last(steering_snapshot.turns)

    assert steering_snapshot.active_turn.id == first_snapshot.active_turn_id
    assert steering_snapshot.active_turn.state == :superseding
    assert steering_snapshot.active_child_work.state == :cancel_acknowledged
    assert steering_snapshot.queued_turn_ids == [replacement_turn.id, queued_turn_id]
    assert replacement_turn.supersedes_turn_id == first_snapshot.active_turn_id
    assert Enum.any?(steering_snapshot.control_history, &(&1.type == "turn.steer"))

    assert {:ok, superseded_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               first_snapshot.active_child_work_id,
               :cancelled,
               %{result: %{reason: "Steering overtook the stale active turn."}},
               actor: Actor.operator_actor()
             )

    superseded_turn = Enum.find(superseded_snapshot.turns, &(&1.id == first_snapshot.active_turn_id))
    replacement_turn = Enum.find(superseded_snapshot.turns, &(&1.id == replacement_turn.id))

    assert superseded_turn.state == :superseded
    assert superseded_turn.superseded_by_turn_id == replacement_turn.id
    assert replacement_turn.supersedes_turn_id == superseded_turn.id
    assert superseded_snapshot.active_turn.id == replacement_turn.id
    assert superseded_snapshot.active_turn.state == :running
    assert superseded_snapshot.queued_turn_ids == [queued_turn_id]

    assert :ok = Driver.stop(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-#{suffix}",
        github_full_name: "owner/phase-forty-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end
end
