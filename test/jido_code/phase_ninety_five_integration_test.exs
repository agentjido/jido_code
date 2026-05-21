defmodule JidoCode.PhaseNinetyFiveIntegrationTest do
  # covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics
  # covers: architecture.context_management_pod.context_compactor_is_bounded_specialist
  # covers: architecture.context_management_pod.request_time_budgeting_remains_hard_guard
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project

  test "conversation coordinator compacts at a terminal turn boundary before continuing" do
    {managed_repo, work_item} = managed_repo_and_work_item_fixture!("terminal-boundary")
    workspace_path = create_workspace_path!("terminal-boundary")

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} = AgentWorkspace.ensure_coding_pod(managed_repo.id, work_item.id, workspace_path)

    assert {:ok, %{conversation: conversation}} =
             AgentWorkspace.open_work_item_conversation(work_item.id, %{
               source: "work_item_detail",
               objective: "Exercise automatic context compaction."
             })

    first_done =
      conversation.id
      |> submit_turn!("older implementation context")
      |> complete_active_child_work!("older implementation result")

    refute Enum.any?(first_done.events, &(&1.name == "conversation.context_compacted"))

    second_running = submit_turn!(conversation.id, "active implementation follow-up")

    assert {:ok, context_management} =
             AgentWorkspace.record_context_observation(managed_repo.id, work_item.id, %{
               workflow: :execute,
               specialist_role: :coder,
               conversation_id: conversation.id,
               turn_id: second_running.active_turn_id,
               context_budget: high_water_budget()
             })

    completed =
      complete_active_child_work!(second_running, "active implementation result", %{
        "context_management" => context_management
      })

    assert Enum.any?(completed.events, &(&1.name == "conversation.context_compacted"))
    assert completed.shared_context["latest_context_reset"]["summary_id"]
    assert completed.shared_context["accepted_tool_results"] |> Enum.map(& &1["child_work_id"]) |> length() == 1

    assert [%{"summary_text" => summary_text}] =
             AgentWorkspace.context_compaction_summaries(managed_repo.id, work_item.id)

    assert summary_text =~ "Compacted 1 older execute/coder context span"

    assert :ok = AgentWorkspace.stop_conversation(conversation.id)
  end

  defp submit_turn!(conversation_id, instruction) do
    assert {:ok, snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation_id,
               %{type: "turn.submit", payload: %{instruction: instruction}},
               actor: Actor.operator_actor(%{"id" => "operator-phase-95"})
             )

    snapshot
  end

  defp complete_active_child_work!(snapshot, summary, extra_payload \\ %{}) do
    assert {:ok, completed} =
             AgentWorkspace.handle_conversation_command(
               snapshot.conversation_id,
               %{
                 type: "tool_result.submit",
                 payload:
                   %{
                     child_work_id: snapshot.active_child_work_id,
                     kind: "completed",
                     result: %{summary: summary}
                   }
                   |> Map.merge(extra_payload)
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase-95"})
             )

    completed
  end

  defp managed_repo_and_work_item_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-ninety-five-#{suffix}",
        github_full_name: "owner/phase-ninety-five-#{suffix}",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => create_workspace_path!("repo-#{suffix}"),
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "implement_auto_compaction",
        actor: %{id: "phase-95-#{suffix}", email: "phase-95-#{suffix}@example.com"},
        payload: %{"summary" => "Implement automatic compaction for #{suffix}."}
      })

    {managed_repo, work_item}
  end

  defp high_water_budget do
    %{
      "policy_id" => "context-budget:v1",
      "state" => "packed",
      "model_budget" => 1_000,
      "estimated_input_tokens" => 900,
      "diagnostics" => []
    }
  end

  defp create_workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_95_context_management_#{suffix}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Phase95.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Phase95.Example do\nend\n")

    workspace_path
  end
end
