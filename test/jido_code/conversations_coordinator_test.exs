defmodule JidoCode.ConversationsCoordinatorTest do
  use ExUnit.Case, async: true

  alias JidoCode.Conversations.{Command, Conversation, Coordinator, Turn}

  test "command normalization separates work and control commands" do
    actor = %{"id" => "operator-1", "actor_class" => "operator"}

    assert {:ok, work_command} =
             Command.normalize(%{type: "turn.submit", payload: %{instruction: "Plan the next step."}}, actor)

    assert work_command.class == :work
    assert work_command.type == :turn_submit
    assert work_command.payload["instruction"] == "Plan the next step."

    assert {:ok, control_command} =
             Command.normalize(%{type: "session.pause", payload: %{reason: "Operator paused."}}, actor)

    assert control_command.class == :control
    assert control_command.type == :session_pause
    assert control_command.payload["reason"] == "Operator paused."
  end

  test "coordinator admits work turns, pauses the session, and resumes queued work" do
    conversation = conversation_fixture()
    start_supervised!({Coordinator, conversation})

    actor = %{"id" => "operator-2", "actor_class" => "operator"}

    assert {:ok, first_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Review the current plan."}},
               actor
             )

    assert first_snapshot.status == :active
    assert first_snapshot.active_turn.command_type == "turn.submit"
    assert first_snapshot.active_turn.state == :running
    refute Map.has_key?(first_snapshot, :pod_id)
    refute Map.has_key?(first_snapshot, :kernel_name)

    assert {:ok, second_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Prepare the next step."}},
               actor
             )

    assert second_snapshot.active_turn.id == first_snapshot.active_turn.id
    assert length(second_snapshot.queued_turn_ids) == 1

    assert {:ok, paused_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "session.pause", payload: %{reason: "Operator pause"}},
               actor
             )

    assert paused_snapshot.status == :paused
    assert Enum.any?(paused_snapshot.control_history, &(&1.type == "session.pause"))

    assert {:ok, completed_snapshot} =
             Coordinator.transition_turn(conversation.id, first_snapshot.active_turn.id, :completed)

    assert completed_snapshot.active_turn == nil
    assert completed_snapshot.queued_turn_ids == [List.first(second_snapshot.queued_turn_ids)]

    assert {:ok, resumed_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "session.resume", payload: %{}},
               actor
             )

    assert resumed_snapshot.status == :active
    assert resumed_snapshot.active_turn.id == List.first(second_snapshot.queued_turn_ids)
    assert resumed_snapshot.active_turn.state == :running
    assert resumed_snapshot.queued_turn_ids == []
  end

  test "turn transition keeps lifecycle history explicit" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    turn =
      Turn.new("conversation-1", %{id: Ecto.UUID.generate(), raw_type: "turn.submit", payload: %{}, admitted_at: now})

    assert {:ok, running_turn} = Turn.transition(turn, :running)
    assert {:ok, awaiting_input_turn} = Turn.transition(running_turn, :awaiting_input)
    assert {:ok, completed_turn} = Turn.transition(awaiting_input_turn, :completed)

    assert Enum.map(completed_turn.lifecycle, & &1["state"]) == ["queued", "running", "awaiting_input", "completed"]
    assert completed_turn.completed_at != nil
  end

  defp conversation_fixture do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Conversation{
      id: Ecto.UUID.generate(),
      managed_repo_id: Ecto.UUID.generate(),
      work_item_id: nil,
      status: :active,
      scope: :repo_scoped,
      attachment_mode: :pre_work,
      source: "conversation",
      title: "Phase 39 Coordinator Test",
      objective: "Exercise coordinator behavior without database persistence.",
      initiating_actor: %{"id" => "operator-test", "actor_class" => "operator"},
      source_metadata: %{},
      conversation_metadata: %{},
      started_at: now,
      last_activity_at: now
    }
  end
end
