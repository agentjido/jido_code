defmodule JidoCode.PhaseThirtyNineIntegrationTest do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  # covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Operations.{Ingress, WorkItem}
  alias JidoCode.Projects.Project

  test "repo-scoped conversations preserve managed-repo scope and operator attribution through the driver" do
    managed_repo = managed_repo_fixture!("repo-scoped")

    assert {:ok, %{conversation: conversation, snapshot: snapshot, work_item: nil}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               title: "Investigate conversation entrypoint behavior",
               objective: "Validate repo-scoped conversation setup.",
               actor: %{id: "operator-phase39", email: "phase39@example.com"},
               source_metadata: %{entry_surface: "chat"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.scope == :repo_scoped
    assert conversation.attachment_mode == :pre_work
    assert conversation.initiating_actor["id"] == "operator-phase39"
    assert conversation.source_metadata["entry_surface"] == "chat"

    assert snapshot.conversation_id == conversation.id
    assert snapshot.managed_repo_id == managed_repo.id
    refute Map.has_key?(snapshot, :kernel_name)
    refute Map.has_key?(snapshot, :pod_id)

    assert :ok = Driver.stop(conversation.id)
  end

  test "work-item scoped conversations can attach to an existing governed work item without spawning a duplicate" do
    managed_repo = managed_repo_fixture!("existing-work")
    work_item = work_item_fixture!(managed_repo, "operator-existing")

    assert {:ok, %{conversation: conversation, work_item: attached_work_item, snapshot: snapshot}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               source: "conversation",
               objective: "Continue the existing governed work item.",
               actor: %{id: "operator-existing", email: "existing@example.com"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :existing_work_item
    assert attached_work_item.id == work_item.id
    assert snapshot.work_item_id == work_item.id

    assert {:ok, work_items} =
             WorkItem.read(
               query: [filter: [managed_repo_id: managed_repo.id]],
               actor: Actor.operator_actor()
             )

    assert Enum.map(work_items, & &1.id) == [work_item.id]

    assert :ok = Driver.stop(conversation.id)
  end

  test "actionable conversations can synthesize new governed work when asked to do so" do
    managed_repo = managed_repo_fixture!("synthesized-work")

    assert {:ok, %{conversation: conversation, work_item: work_item, snapshot: snapshot}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               attach_mode: :synthesized_work_item,
               objective: "Review the operator request before execution.",
               actor: %{id: "operator-synthesized", email: "synthesized@example.com"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :synthesized_work_item
    assert snapshot.work_item_id == work_item.id
    assert work_item.managed_repo_id == managed_repo.id
    assert work_item.recommended_action == "review_operator_request"

    assert :ok = Driver.stop(conversation.id)
  end

  test "workspace conversation helpers keep repo-scoped command admission topology-free" do
    managed_repo = managed_repo_fixture!("workspace-boundary")

    assert {:ok, %{conversation: conversation, snapshot: initial_snapshot}} =
             AgentWorkspace.open_repo_conversation(
               managed_repo.id,
               %{
                 source: "phase_thirty_nine_integration_test",
                 objective: "Exercise the workspace conversation boundary."
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase39-workspace"})
             )

    assert initial_snapshot.conversation_id == conversation.id
    assert initial_snapshot.managed_repo_id == managed_repo.id
    refute Map.has_key?(initial_snapshot, :kernel_name)
    refute Map.has_key?(initial_snapshot, :pod_id)

    assert {:ok, running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the workspace-owned conversation entrypoint."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase39-workspace"})
             )

    assert running_snapshot.managed_repo_id == managed_repo.id
    assert running_snapshot.work_item_id == nil
    assert running_snapshot.active_turn.command_type == "turn.submit"
    assert running_snapshot.active_turn.state == :running
    assert running_snapshot.active_child_work.turn_id == running_snapshot.active_turn.id
    refute Map.has_key?(running_snapshot, :kernel_name)
    refute Map.has_key?(running_snapshot, :pod_id)

    assert {:ok, persisted_snapshot} = AgentWorkspace.conversation_snapshot(conversation.id)

    assert persisted_snapshot.conversation_id == conversation.id
    refute Map.has_key?(persisted_snapshot, :kernel_name)
    refute Map.has_key?(persisted_snapshot, :pod_id)

    assert :ok = AgentWorkspace.stop_conversation(conversation.id)
  end

  test "driver keeps work and control commands explicit through auditable lifecycle transitions" do
    managed_repo = managed_repo_fixture!("command-lifecycle")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise explicit command and lifecycle shaping."
             })

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the driver lifecycle."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase39-driver"})
             )

    turn_id = running_snapshot.active_turn_id
    child_work_id = running_snapshot.active_child_work_id

    assert {:ok, paused_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "session.pause", payload: %{reason: "Pause before issuing a control command."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase39-driver"})
             )

    assert paused_snapshot.status == :paused
    assert paused_snapshot.admission_paused
    assert Enum.any?(paused_snapshot.control_history, &(&1.type == "session.pause"))

    assert {:ok, resumed_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "session.resume", payload: %{}},
               actor: Actor.operator_actor(%{"id" => "operator-phase39-driver"})
             )

    assert resumed_snapshot.status == :active
    refute resumed_snapshot.admission_paused

    assert {:ok, cancellation_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{type: "tool.cancel", payload: %{}},
               actor: Actor.operator_actor(%{"id" => "operator-phase39-driver"})
             )

    assert cancellation_snapshot.active_turn.id == turn_id
    assert cancellation_snapshot.active_turn.state == :cancelling
    assert cancellation_snapshot.active_child_work.id == child_work_id
    assert cancellation_snapshot.active_child_work.state == :cancel_acknowledged
    assert Enum.any?(cancellation_snapshot.control_history, &(&1.type == "tool.cancel"))

    assert {:ok, settled_snapshot} =
             Driver.settle_child_work(
               conversation.id,
               child_work_id,
               :cancelled,
               %{result: %{reason: "Driver lifecycle cancellation completed."}},
               actor: Actor.operator_actor(%{"id" => "operator-phase39-driver"})
             )

    cancelled_turn = Enum.find(settled_snapshot.turns, &(&1.id == turn_id))

    assert settled_snapshot.active_turn == nil
    assert settled_snapshot.active_child_work == nil
    assert cancelled_turn.state == :cancelled

    assert Enum.map(cancelled_turn.lifecycle, & &1["state"]) == [
             "queued",
             "running",
             "cancelling",
             "cancelled"
           ]

    assert :ok = Driver.stop(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-thirty-nine-#{suffix}",
        github_full_name: "owner/phase-thirty-nine-#{suffix}",
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
