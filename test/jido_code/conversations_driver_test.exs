defmodule JidoCode.ConversationsDriverTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Projects.Project

  test "driver starts a conversation without exposing runtime topology" do
    managed_repo = managed_repo_fixture!("driver-start")

    assert {:ok, %{conversation: conversation, snapshot: snapshot}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Start a conversation through the driver."
             })

    assert snapshot.conversation_id == conversation.id
    assert snapshot.managed_repo_id == managed_repo.id
    assert Map.has_key?(snapshot, :active_turn_id)
    assert Map.has_key?(snapshot, :active_child_work_id)
    refute Map.has_key?(snapshot, :kernel_name)
    refute Map.has_key?(snapshot, :pod_id)

    assert :ok = Driver.stop(conversation.id)
  end

  test "driver admits work and control commands through distinct product-owned shapes" do
    managed_repo = managed_repo_fixture!("driver-commands")

    {:ok, %{conversation: conversation}} =
      Driver.start_conversation(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Admit commands."
      })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Plan the next step."}},
               actor: Actor.operator_actor()
             )

    assert running_snapshot.active_turn.command_type == "turn.submit"
    assert running_snapshot.active_turn.state == :running
    assert running_snapshot.active_child_work.turn_id == running_snapshot.active_turn.id
    assert running_snapshot.active_child_work.state == :running

    assert {:ok, paused_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "session.pause", payload: %{reason: "Operator paused the session."}},
               actor: Actor.operator_actor()
             )

    assert paused_snapshot.status == :paused
    assert paused_snapshot.admission_paused
    refute paused_snapshot.child_execution_paused
    assert Enum.any?(paused_snapshot.control_history, &(&1.type == "session.pause"))

    assert :ok = Driver.stop(conversation.id)
  end

  test "driver keeps baseline turn lifecycle transitions explicit and auditable" do
    managed_repo = managed_repo_fixture!("driver-lifecycle")

    {:ok, %{conversation: conversation}} =
      Driver.start_conversation(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Track lifecycle transitions."
      })

    {:ok, initial_snapshot} =
      Driver.handle_command(
        conversation.id,
        %{type: "turn.submit", payload: %{instruction: "Review the plan."}},
        actor: Actor.operator_actor()
      )

    turn_id = initial_snapshot.active_turn_id

    assert {:ok, awaiting_input_snapshot} =
             Driver.transition_turn(conversation.id, turn_id, :awaiting_input, actor: Actor.operator_actor())

    assert awaiting_input_snapshot.active_turn.state == :awaiting_input

    assert {:ok, completed_snapshot} =
             Driver.transition_turn(conversation.id, turn_id, :completed, actor: Actor.operator_actor())

    completed_turn = Enum.find(completed_snapshot.turns, &(&1.id == turn_id))

    assert completed_turn.state == :completed
    assert Enum.map(completed_turn.lifecycle, & &1["state"]) == ["queued", "running", "awaiting_input", "completed"]
    assert completed_snapshot.active_turn == nil

    assert :ok = Driver.stop(conversation.id)
  end

  test "driver exposes child work cancellation and explicit settlement" do
    managed_repo = managed_repo_fixture!("driver-child-work")

    {:ok, %{conversation: conversation}} =
      Driver.start_conversation(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Track child work ownership and cancellation."
      })

    {:ok, running_snapshot} =
      Driver.handle_command(
        conversation.id,
        %{
          type: "turn.submit",
          payload: %{instruction: "Inspect the workspace.", tool_call_id: "tool-driver-1"}
        },
        actor: Actor.operator_actor()
      )

    child_work_id = running_snapshot.active_child_work_id
    assert running_snapshot.active_child_work.tool_call_id == "tool-driver-1"

    assert {:ok, cancellation_snapshot} =
             Driver.cancel_child_work(conversation.id, child_work_id, actor: Actor.operator_actor())

    assert cancellation_snapshot.active_child_work.state == :cancel_acknowledged

    assert {:ok, settled_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               child_work_id,
               :cancelled,
               %{result: %{reason: "Operator cancelled from the driver."}},
               actor: Actor.operator_actor()
             )

    cancelled_child_work = Enum.find(settled_snapshot.child_works, &(&1.id == child_work_id))

    assert settled_snapshot.active_turn == nil
    assert settled_snapshot.active_child_work == nil
    assert cancelled_child_work.state == :cancelled
    assert cancelled_child_work.result["reason"] == "Operator cancelled from the driver."

    assert :ok = Driver.stop(conversation.id)
  end

  test "driver surfaces steer priority and supersession state cleanly" do
    managed_repo = managed_repo_fixture!("driver-steer")

    {:ok, %{conversation: conversation}} =
      Driver.start_conversation(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Exercise steer priority."
      })

    {:ok, first_snapshot} =
      Driver.handle_command(
        conversation.id,
        %{type: "turn.submit", payload: %{instruction: "Inspect the old objective."}},
        actor: Actor.operator_actor()
      )

    {:ok, second_snapshot} =
      Driver.handle_command(
        conversation.id,
        %{type: "turn.submit", payload: %{instruction: "Run the queued stale task."}},
        actor: Actor.operator_actor()
      )

    queued_turn_id = List.first(second_snapshot.queued_turn_ids)

    {:ok, steering_snapshot} =
      Driver.handle_command(
        conversation.id,
        %{type: "turn.steer", payload: %{instruction: "Replace the active turn with the narrowed objective."}},
        actor: Actor.operator_actor()
      )

    replacement_turn = List.last(steering_snapshot.turns)

    assert steering_snapshot.active_turn.id == first_snapshot.active_turn_id
    assert steering_snapshot.active_turn.state == :superseding
    assert steering_snapshot.queued_turn_ids == [replacement_turn.id, queued_turn_id]
    assert replacement_turn.supersedes_turn_id == first_snapshot.active_turn_id

    {:ok, superseded_snapshot} =
      Driver.settle_child_work(
        conversation.id,
        first_snapshot.active_child_work_id,
        :cancelled,
        %{result: %{reason: "Steering took precedence."}},
        actor: Actor.operator_actor()
      )

    superseded_turn = Enum.find(superseded_snapshot.turns, &(&1.id == first_snapshot.active_turn_id))

    assert superseded_turn.state == :superseded
    assert superseded_snapshot.active_turn.id == replacement_turn.id
    assert superseded_snapshot.queued_turn_ids == [queued_turn_id]

    assert :ok = Driver.stop(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "conversation-driver-#{suffix}",
        github_full_name: "owner/conversation-driver-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end
end
