defmodule JidoCode.PhaseFortyTwoIntegrationTest do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Operations.{Ingress, WorkItem}
  alias JidoCode.Projects.Project

  test "persisted snapshots and sequenced history support degraded recovery after coordinator shutdown" do
    managed_repo = managed_repo_fixture!("persisted-recovery")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise persisted conversation recovery."
             })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{
                   instruction: "Inspect the persisted recovery path.",
                   referenced_files: ["lib/jido_code/conversations/coordinator.ex"]
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase42-recovery"})
             )

    assert :ok = Driver.stop(conversation.id)

    assert {:ok, persisted_snapshot} = Driver.snapshot(conversation.id)

    assert persisted_snapshot.conversation_id == conversation.id
    assert persisted_snapshot.last_event_sequence == running_snapshot.last_event_sequence
    assert persisted_snapshot.active_turn_id == running_snapshot.active_turn_id
    assert persisted_snapshot.active_child_work_id == running_snapshot.active_child_work_id
    assert persisted_snapshot.shared_context["referenced_files"] == ["lib/jido_code/conversations/coordinator.ex"]

    assert {:ok, replayed_events} =
             Driver.events_since(conversation.id, 0, actor: Actor.operator_actor())

    assert Enum.map(replayed_events, & &1.sequence) == Enum.to_list(1..length(replayed_events))

    assert Enum.map(replayed_events, & &1.name) == [
             "conversation.message_added",
             "turn.queued",
             "turn.intent_announced",
             "turn.started",
             "tool.started"
           ]
  end

  test "steering attaches canonical work and preserves bounded shared context" do
    managed_repo = managed_repo_fixture!("steering-convergence")
    work_item = work_item_fixture!(managed_repo, "operator-phase42-existing-work")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise conversation work steering."
             })

    on_exit(fn ->
      :ok = Driver.stop(conversation.id)
    end)

    assert {:ok, first_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{
                   instruction: "Inspect the repo before steering.",
                   referenced_files: ["lib/jido_code/conversations.ex"],
                   tool_call_id: "phase42-tool-1"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase42-initial"})
             )

    assert {:ok, completed_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               first_snapshot.active_child_work_id,
               :completed,
               %{
                 result: %{
                   summary: "Repo inspection completed before steering.",
                   referenced_files: ["lib/jido_code/conversations.ex"]
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase42-initial"})
             )

    assert completed_snapshot.shared_context["accepted_tool_results"] != []

    assert {:ok, _running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Continue the stale pre-work objective."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase42-initial"})
             )

    assert {:ok, steering_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.steer",
                 payload: %{
                   work_item_id: work_item.id,
                   instruction: "Redirect this conversation to the governed work item."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase42-steer"})
             )

    assert steering_snapshot.work_item_id == work_item.id
    assert steering_snapshot.shared_context["work_item_id"] == work_item.id
    assert steering_snapshot.shared_context["referenced_files"] == ["lib/jido_code/conversations.ex"]
    assert length(steering_snapshot.shared_context["accepted_tool_results"]) == 1
    assert Enum.any?(steering_snapshot.control_history, &(&1.type == "turn.steer" and &1.work_action == "steered"))

    assert {:ok, [updated_work_item]} =
             WorkItem.read(query: [filter: [id: work_item.id], limit: 1], actor: Actor.operator_actor())

    assert updated_work_item.initiating_actor["id"] == "operator-phase42-steer"
    assert List.last(updated_work_item.audit_log)["action"] == "steered"

    assert :ok = Driver.stop(conversation.id)
    assert {:ok, persisted_snapshot} = Driver.snapshot(conversation.id)
    assert persisted_snapshot.work_item_id == work_item.id
    assert persisted_snapshot.shared_context["work_item_id"] == work_item.id
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-two-#{suffix}",
        github_full_name: "owner/phase-forty-two-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp work_item_fixture!(managed_repo, actor_id) do
    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "fix_workflow_kickoff",
        actor: %{id: actor_id, email: "#{actor_id}@example.com"},
        payload: %{
          "workflow_name" => "fix_failing_tests",
          "context_item" => %{"type" => "issue"}
        },
        source_metadata: %{
          "trigger" => %{"source" => "workbench", "mode" => "manual"}
        }
      })

    work_item
  end
end
