defmodule JidoCode.PhaseEightyThreeIntegrationTest do
  # covers: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
  # covers: architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
  # covers: architecture.repository_runtime_integration.product_work_entrypoints_route_to_workspace
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.WorkflowRouter
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  test "workflow router selects refactor only for explicit behavior-preserving intent" do
    assert :refactor in WorkflowRouter.workflows()

    explicit =
      WorkflowRouter.resolve(%{
        payload: %{
          "instruction" => "Review the code and implement the cleanup.",
          "workflow" => "refactor"
        }
      })

    assert explicit.workflow == :refactor
    assert explicit.source == :explicit_payload

    refactor =
      WorkflowRouter.resolve(%{
        payload: %{
          "instruction" => "Refactor the parser helpers to extract duplicate behavior while preserving behavior."
        }
      })

    assert refactor.workflow == :refactor
    assert refactor.source == :heuristic
    assert refactor.scores.refactor > refactor.scores.execute

    execute =
      WorkflowRouter.resolve(%{
        payload: %{
          "instruction" => "Fix failing tests and update the implementation."
        }
      })

    assert execute.workflow == :execute
    assert execute.ambiguous? == false

    ambiguous =
      WorkflowRouter.resolve(%{
        payload: %{
          "instruction" => "Refactor this module and review the diff."
        }
      })

    assert ambiguous.workflow == nil
    assert ambiguous.ambiguous? == true
    assert ambiguous.candidate_workflow in [:refactor, :review]
  end

  test "conversation refactor intent routes through refactorer and preserves work-item identity" do
    {project, managed_repo} = managed_repo_fixture!("conversation-refactor")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase83-open"})
             )

    track_runtime!(conversation.id, managed_repo.id)

    assert {:ok, _snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{
                   instruction: "Refactor lib/example/parser.ex to extract duplicate helpers while preserving behavior."
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase83-submit"})
             )

    completed_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.active_turn == nil and snapshot.active_child_work == nil and
          accepted_result_matches?(snapshot, "refactor", "deterministic refactorer response") and
          routing_workflow_present?(snapshot, "refactor")
      end)

    assert is_binary(completed_snapshot.work_item_id)

    assert {:ok, %{conversation: resumed_conversation, resumed?: true}} =
             AgentWorkspace.open_work_item_conversation(
               completed_snapshot.work_item_id,
               %{},
               actor: Actor.operator_actor(%{"id" => "operator-phase83-resume"})
             )

    assert resumed_conversation.id == conversation.id

    assert {:ok, active_conversations} =
             AgentWorkspace.active_work_item_conversations(managed_repo.id,
               actor: Actor.operator_actor(%{"id" => "operator-phase83-active"})
             )

    assert Enum.count(active_conversations, &(&1.work_item_id == completed_snapshot.work_item_id)) == 1
  end

  defp accepted_result_matches?(snapshot, workflow, summary_fragment) do
    Enum.any?(snapshot.shared_context["accepted_tool_results"], fn result ->
      summary = get_in(result, ["result", "summary"]) || ""

      get_in(result, ["result", "workflow"]) == workflow and
        String.contains?(summary, summary_fragment)
    end)
  end

  defp routing_workflow_present?(snapshot, workflow) do
    Enum.any?(snapshot.turns, fn turn ->
      get_in(turn, [:payload, "conversation_runtime", "routing", "workflow"]) == workflow
    end)
  end

  defp track_runtime!(conversation_id, managed_repo_id) do
    on_exit(fn ->
      case AgentWorkspace.stop_conversation(conversation_id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end

      case AgentWorkspace.shutdown_kernel(managed_repo_id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-eighty-three-#{suffix}",
        github_full_name: "owner/phase-eighty-three-#{suffix}",
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
        "jido-code-phase-eighty-three-#{suffix}-#{System.unique_integer([:positive])}"
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
