defmodule JidoCode.PhaseFortyOneIntegrationTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.{Driver, PubSub}
  alias JidoCode.Projects.Project

  test "sequenced conversation events stay coherent with PubSub delivery and materialized snapshots" do
    managed_repo = managed_repo_fixture!("phase-forty-one")

    assert {:ok, %{conversation: conversation, snapshot: initial_snapshot}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise sequenced event delivery."
             })

    assert initial_snapshot.last_event_sequence == 0
    assert :ok = PubSub.subscribe_conversation(conversation.id)

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the event stream."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase41"})
             )

    assert Enum.map(running_snapshot.events, & &1.sequence) == Enum.to_list(1..running_snapshot.event_count)
    assert Enum.map(running_snapshot.events, & &1.name) == [
             "conversation.message_added",
             "turn.queued",
             "turn.intent_announced",
             "turn.started",
             "tool.started"
           ]

    assert_receive {:conversation_event, %{name: "conversation.message_added", sequence: 1}}
    assert_receive {:conversation_event, %{name: "turn.queued", sequence: 2}}
    assert_receive {:conversation_event, %{name: "turn.intent_announced", sequence: 3}}
    assert_receive {:conversation_event, %{name: "turn.started", sequence: 4}}
    assert_receive {:conversation_event, %{name: "tool.started", sequence: 5}}

    assert {:ok, settled_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               running_snapshot.active_child_work_id,
               :completed,
               %{result: %{summary: "The evented demo work completed."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase41"})
             )

    assert settled_snapshot.active_turn == nil
    assert settled_snapshot.active_child_work == nil
    assert settled_snapshot.last_event_sequence == settled_snapshot.event_count
    assert Enum.map(settled_snapshot.events, & &1.sequence) == Enum.to_list(1..settled_snapshot.event_count)
    assert Enum.map(Enum.take(settled_snapshot.events, -2), & &1.name) == ["tool.completed", "turn.completed"]

    assert {:ok, replayed_events} =
             Driver.events_since(conversation.id, running_snapshot.last_event_sequence, actor: Actor.operator_actor())

    assert Enum.map(replayed_events, & &1.name) == ["tool.completed", "turn.completed"]

    assert :ok = Driver.stop(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-one-#{suffix}",
        github_full_name: "owner/phase-forty-one-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end
end
