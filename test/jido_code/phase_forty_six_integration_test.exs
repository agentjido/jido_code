defmodule JidoCode.PhaseFortySixIntegrationTest do
  # covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  test "project detail conversations route through the real runtime and preserve clarification resume state" do
    {project, _managed_repo} = managed_repo_fixture!("real-runtime")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, snapshot: initial_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase46-open"})
             )

    on_exit(fn ->
      case AgentWorkspace.stop_conversation(conversation.id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)

    assert initial_snapshot.conversation_id == conversation.id

    assert {:ok, running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase46-first-turn"})
             )

    assert is_binary(running_snapshot.active_child_work_id)

    completed_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.active_turn == nil and snapshot.active_child_work == nil and
          Enum.any?(snapshot.shared_context["accepted_tool_results"], fn result ->
            get_in(result, ["result", "workflow"]) == "explain" and
              String.contains?(get_in(result, ["result", "summary"]) || "", "deterministic explainer response")
          end)
      end)

    clarification_checkpoint = completed_snapshot.last_event_sequence

    assert {:ok, _clarification_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Clarify which file needs input."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase46-clarify"})
             )

    awaiting_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        (snapshot.active_turn &&
           snapshot.active_turn.state == :awaiting_input) and
          get_in(snapshot, [:shared_context, "pending_clarification", "prompt", "prompt"]) ==
            "Which file or module should I inspect first?"
      end)

    assert {:ok, clarification_events} =
             AgentWorkspace.conversation_events_since(
               conversation.id,
               clarification_checkpoint,
               actor: Actor.operator_actor()
             )

    assert Enum.any?(clarification_events, &(&1.name == "tool.progress"))
    assert Enum.any?(clarification_events, &(&1.name == "tool.needs_input"))
    assert Enum.any?(clarification_events, &(&1.name == "turn.awaiting_input"))

    turn_id = awaiting_snapshot.active_turn_id

    assert {:ok, resumed_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: turn_id,
                   response: "lib/jido_code_web/live/project_detail_live.ex"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase46-resume"})
             )

    assert resumed_snapshot.active_turn.state == :running

    resumed_checkpoint = awaiting_snapshot.last_event_sequence

    resumed_completion_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.active_turn == nil and snapshot.active_child_work == nil and
          Enum.any?(snapshot.shared_context["accepted_tool_results"], fn result ->
            summary = get_in(result, ["result", "summary"]) || ""

            get_in(result, ["result", "workflow"]) == "explain" and
              String.contains?(summary, "deterministic explainer response") and
              String.contains?(summary, "lib/jido_code_web/live/project_detail_live.ex")
          end)
      end)

    assert {:ok, resumed_events} =
             AgentWorkspace.conversation_events_since(
               conversation.id,
               resumed_checkpoint,
               actor: Actor.operator_actor()
             )

    assert Enum.any?(resumed_events, &(&1.name == "turn.started"))
    assert Enum.any?(resumed_events, &(&1.name == "turn.delta"))
    assert Enum.any?(resumed_events, &(&1.name == "tool.completed"))
    assert resumed_completion_snapshot.conversation_id == conversation.id
    assert :ok = AgentWorkspace.stop_conversation(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-six-#{suffix}",
        github_full_name: "owner/phase-forty-six-#{suffix}",
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
        "jido-code-phase-forty-six-#{suffix}-#{System.unique_integer([:positive])}"
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
