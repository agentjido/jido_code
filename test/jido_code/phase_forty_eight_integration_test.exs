defmodule JidoCode.PhaseFortyEightIntegrationTest do
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{Inventory, ProjectConversation, ProjectDetail}

  test "repo detail, workbench, and governed run projections share one conversation lineage" do
    {project, managed_repo} = managed_repo_fixture!("operator-surfaces")
    tracked_conversations = tracked_conversations!(managed_repo.id)

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase48-open"})
             )

    track_conversation!(tracked_conversations, conversation.id)

    assert {:ok, _running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase48-turn"})
             )

    attached_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and
          snapshot.active_turn == nil and snapshot.active_child_work == nil and
          snapshot.work_resolution["action"] == "created"
      end)

    work_item_id = attached_snapshot.work_item_id

    repo_detail_projection =
      ProjectConversation.load_repo_detail(project_detail, actor: Actor.operator_actor())

    assert repo_detail_projection.conversation.id == conversation.id
    assert repo_detail_projection.conversation.work_item_id == work_item_id
    assert repo_detail_projection.conversation.work_resolution["action"] == "created"
    assert repo_detail_projection.work_item.id == work_item_id
    assert repo_detail_projection.action_label == "Open repo conversation"

    assert {:ok, rows, _warning} = Inventory.load()
    row = Enum.find(rows, &(&1.managed_repo_id == managed_repo.id))
    refute is_nil(row)

    assert row.repo_conversation.conversation.id == conversation.id
    assert row.repo_conversation.conversation.work_item_id == work_item_id
    assert row.repo_conversation.conversation.work_resolution["action"] == "created"
    assert row.repo_conversation.work_item.id == work_item_id
    assert row.repo_conversation.action_label == "Open repo conversation"

    run_id = "phase-forty-eight-run-#{System.unique_integer([:positive])}"

    assert {:ok, workflow_run} =
             WorkflowRun.create(%{
               project_id: project.id,
               managed_repo_id: managed_repo.id,
               run_id: run_id,
               workflow_name: "implement_task",
               workflow_version: 2,
               trigger: %{source: "workflows", mode: "manual"},
               inputs: %{
                 "task_summary" => "Project conversation lineage across operator surfaces",
                 "work_item_id" => work_item_id
               },
               input_metadata: %{
                 "task_summary" => %{required: true, source: "manual_workflows_ui"},
                 "work_item_id" => %{required: true, source: "conversation"}
               },
               initiating_actor: %{id: "owner-1", email: "phase48@example.com"},
               current_step: "queued",
               started_at: ~U[2026-04-14 12:00:00Z]
             })

    assert {:ok, _workflow_run} =
             WorkflowRun.transition_status(workflow_run, %{
               to_status: :running,
               current_step: "plan_changes",
               transitioned_at: ~U[2026-04-14 12:01:00Z]
             })

    assert {:ok, governed_run} =
             Run.get_by_managed_repo_and_run_id(managed_repo.id, run_id, actor: Actor.operator_actor())

    assert governed_run.work_item_id == work_item_id

    run_detail_linkage =
      ProjectConversation.load_work_item_linkage(governed_run.work_item_id,
        actor: Actor.operator_actor()
      )

    assert run_detail_linkage.managed_repo_id == managed_repo.id
    assert run_detail_linkage.work_item.id == work_item_id
    assert run_detail_linkage.conversation.id == conversation.id
    assert run_detail_linkage.conversation.work_item_id == work_item_id
    assert run_detail_linkage.conversation.work_resolution["action"] == "created"
    assert run_detail_linkage.origin["conversation_id"] == conversation.id
    assert run_detail_linkage.origin["turn_id"] == attached_snapshot.work_resolution["turn_id"]
    assert run_detail_linkage.action_label == "Resume governed conversation"
  end

  defp tracked_conversations!(managed_repo_id) do
    {:ok, tracker} = Agent.start(fn -> [] end)

    on_exit(fn ->
      tracker
      |> Agent.get(&Enum.uniq(&1))
      |> Enum.each(fn conversation_id ->
        case AgentWorkspace.stop_conversation(conversation_id) do
          :ok -> :ok
          {:error, _reason} -> :ok
        end
      end)

      case AgentWorkspace.shutdown_kernel(managed_repo_id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end

      Agent.stop(tracker)
    end)

    tracker
  end

  defp track_conversation!(tracker, conversation_id) do
    Agent.update(tracker, &[conversation_id | &1])
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-eight-#{suffix}",
        github_full_name: "owner/phase-forty-eight-#{suffix}",
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

    {project, managed_repo}
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-forty-eight-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp eventually_snapshot!(conversation_id, predicate, attempts \\ 40)

  defp eventually_snapshot!(conversation_id, predicate, attempts)
       when is_binary(conversation_id) and is_function(predicate, 1) and attempts > 1 do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)

    if predicate.(snapshot) do
      snapshot
    else
      receive do
      after
        25 -> eventually_snapshot!(conversation_id, predicate, attempts - 1)
      end
    end
  end

  defp eventually_snapshot!(conversation_id, predicate, _attempts) do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)
    assert predicate.(snapshot)
    snapshot
  end
end
