defmodule JidoCode.PhaseFiftyTwoIntegrationTest do
  # covers: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
  # covers: architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
  # covers: architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  test "explicit workflow intent overrides mixed free-text cues and routes to the requested specialist" do
    {project, managed_repo} = managed_repo_fixture!("explicit-intent")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase52-explicit-open"})
             )

    track_runtime!(conversation.id, managed_repo.id)

    assert {:ok, _snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{
                   instruction: "Review this and implement it.",
                   workflow: "review"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase52-explicit-submit"})
             )

    completed_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.active_turn == nil and snapshot.active_child_work == nil and
          accepted_result_matches?(snapshot, "review", "deterministic reviewer response") and
          routing_source_present?(snapshot, "explicit_payload")
      end)

    assert is_binary(completed_snapshot.work_item_id)
  end

  test "clarification resume preserves the established workflow instead of reclassifying from the response text" do
    {project, managed_repo} = managed_repo_fixture!("continuity")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase52-continuity-open"})
             )

    track_runtime!(conversation.id, managed_repo.id)

    assert {:ok, _snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Clarify which file needs input."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase52-continuity-submit"})
             )

    awaiting_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        (snapshot.active_turn &&
           snapshot.active_turn.state == :awaiting_input) and
          get_in(snapshot, [:shared_context, "pending_clarification", "prompt", "prompt"]) ==
            "Which file or module should I inspect first?"
      end)

    assert {:ok, _snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: awaiting_snapshot.active_turn_id,
                   response: "review lib/jido_code_web/live/project_detail_live.ex"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase52-continuity-resume"})
             )

    completed_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.active_turn == nil and snapshot.active_child_work == nil and
          accepted_result_matches?(snapshot, "explain", "deterministic explainer response") and
          routing_source_present?(snapshot, "routing_continuity")
      end)

    assert is_binary(completed_snapshot.work_item_id)
  end

  test "ambiguous workflow cues request clarification before governed execution continues" do
    {project, managed_repo} = managed_repo_fixture!("ambiguity")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase52-ambiguous-open"})
             )

    track_runtime!(conversation.id, managed_repo.id)

    assert {:ok, _snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Review this and implement it."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase52-ambiguous-submit"})
             )

    awaiting_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        match?(%{state: :awaiting_input}, snapshot.active_turn) and
          get_in(snapshot, [:shared_context, "pending_clarification", "prompt", "prompt"]) ==
            "Do you want me to plan, implement, refactor, review, or explain this request?" and
          snapshot.work_item_id == nil and
          get_in(snapshot.active_turn, [:payload, "conversation_runtime", "routing", "ambiguous"]) == true
      end)

    assert {:ok, _snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: awaiting_snapshot.active_turn_id,
                   response: "review"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase52-ambiguous-resume"})
             )

    completed_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.active_turn == nil and snapshot.active_child_work == nil and
          is_binary(snapshot.work_item_id) and
          accepted_result_matches?(snapshot, "review", "deterministic reviewer response")
      end)

    assert is_binary(completed_snapshot.work_item_id)
  end

  defp accepted_result_matches?(snapshot, workflow, summary_fragment) do
    Enum.any?(snapshot.shared_context["accepted_tool_results"], fn result ->
      summary = get_in(result, ["result", "summary"]) || ""

      get_in(result, ["result", "workflow"]) == workflow and
        String.contains?(summary, summary_fragment)
    end)
  end

  defp routing_source_present?(snapshot, source) do
    Enum.any?(snapshot.turns, fn turn ->
      get_in(turn, [:payload, "conversation_runtime", "routing", "source"]) == source
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
        name: "phase-fifty-two-#{suffix}",
        github_full_name: "owner/phase-fifty-two-#{suffix}",
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
        "jido-code-phase-fifty-two-#{suffix}-#{System.unique_integer([:positive])}"
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
