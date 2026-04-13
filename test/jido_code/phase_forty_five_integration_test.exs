defmodule JidoCode.PhaseFortyFiveIntegrationTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.{Assessment, Event, WorkItem}
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.RunConversation

  test "run detail conversation boundaries reuse the active work-item conversation and expose snapshots through agent workspace" do
    {_project, managed_repo, work_item, run_scope} = governed_run_fixture!("run-detail-conversation")

    initial_projection =
      RunConversation.load_run_detail(run_scope, actor: Actor.operator_actor())

    assert initial_projection.snapshot == nil
    assert initial_projection.conversation == nil
    assert initial_projection.action_label == "Open work conversation"

    assert {:ok, %{conversation: conversation, snapshot: snapshot, resumed?: false}} =
             RunConversation.open_run_detail(
               run_scope,
               actor: Actor.operator_actor(%{"id" => "operator-phase45-open"})
             )

    on_exit(fn ->
      :ok = AgentWorkspace.stop_conversation(conversation.id)
    end)

    assert snapshot.conversation_id == conversation.id
    assert snapshot.managed_repo_id == managed_repo.id
    assert snapshot.work_item_id == work_item.id

    assert {:ok, latest_conversation} =
             AgentWorkspace.latest_work_item_conversation(work_item.id, actor: Actor.operator_actor())

    assert latest_conversation.id == conversation.id

    assert {:ok, updated_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the run detail conversation boundary."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase45-turn"})
             )

    assert updated_snapshot.conversation_id == conversation.id
    assert updated_snapshot.work_item_id == work_item.id
    assert is_binary(updated_snapshot.active_turn_id)

    projection_after_turn =
      RunConversation.load_run_detail(run_scope, actor: Actor.operator_actor())

    assert projection_after_turn.conversation.id == conversation.id
    assert projection_after_turn.snapshot.conversation_id == conversation.id

    assert Enum.any?(
             projection_after_turn.recent_events,
             &(&1.name == "conversation.message_added")
           )

    assert {:ok, %{conversation: reopened_conversation, snapshot: reopened_snapshot, resumed?: true}} =
             RunConversation.open_run_detail(
               run_scope,
               actor: Actor.operator_actor(%{"id" => "operator-phase45-reopen"})
             )

    assert reopened_conversation.id == conversation.id
    assert reopened_snapshot.conversation_id == conversation.id
    assert reopened_snapshot.work_item_id == work_item.id
  end

  defp governed_run_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-five-#{suffix}",
        github_full_name: "owner/phase-forty-five-#{suffix}",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path!(suffix),
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, event} =
      Event.create(
        %{
          managed_repo_id: managed_repo.id,
          category: "operator_request",
          summary: "Create governed work for run detail conversation coverage.",
          correlation_key: "phase45-run-conversation-#{System.unique_integer([:positive])}",
          payload: %{},
          source_metadata: %{"source" => "phase_forty_five_integration_test"},
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: Actor.operator_actor()
      )

    {:ok, assessment} =
      Assessment.create(
        %{
          managed_repo_id: managed_repo.id,
          event_id: event.id,
          category: "operator_work_request",
          summary: "Assess governed work for run detail conversation coverage.",
          priority: :high,
          urgency: :medium,
          recommended_action: "review_operator_request",
          rationale: "Phase 45 needs a canonical work item for run detail conversation adoption.",
          inputs: %{},
          assessment_metadata: %{},
          assessed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: Actor.operator_actor()
      )

    {:ok, work_item} =
      WorkItem.create(
        %{
          managed_repo_id: managed_repo.id,
          assessment_id: assessment.id,
          event_id: event.id,
          category: "operator_work_request",
          status: :open,
          priority: :high,
          recommended_action: "review_operator_request",
          summary: "Continue governed run detail work.",
          dedup_key: "phase45-work-item-#{System.unique_integer([:positive])}",
          initiating_actor: %{"id" => "operator-phase45"},
          work_metadata: %{},
          audit_log: [],
          opened_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
          last_assessed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: Actor.operator_actor()
      )

    run_id = "phase45-run-detail-#{System.unique_integer([:positive])}"

    {:ok, _workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{
          "task_summary" => "Continue governed work from run detail.",
          "work_item_id" => work_item.id
        },
        input_metadata: %{
          "task_summary" => %{required: true, source: "manual_workflows_ui"},
          "work_item_id" => %{"required" => true, "source" => "work_item"}
        },
        initiating_actor: %{id: "owner-1", email: "phase45@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-13 16:00:00Z]
      })

    {project, managed_repo, work_item,
     %{managed_repo_id: managed_repo.id, work_item_id: work_item.id, run_id: run_id}}
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-forty-five-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
