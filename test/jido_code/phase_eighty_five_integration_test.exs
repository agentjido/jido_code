defmodule JidoCode.PhaseEightyFiveIntegrationTest do
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Runtime
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project

  setup do
    previous_memory_graph = Application.get_env(:jido_code, :memory_graph_enabled, false)
    previous_source_graph = Application.get_env(:jido_code, :source_code_graph_enabled, false)

    Application.put_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, false)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory_graph)
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source_graph)
    end)

    :ok
  end

  test "runtime trims oversized optional context before invoking the specialist" do
    {managed_repo, work_item} = managed_repo_and_work_item_fixture!("runtime-budget")

    accepted_tool_results =
      Enum.map(1..8, fn index ->
        %{
          "child_work_id" => "child-85-#{index}",
          "workflow" => "execute",
          "result" => %{
            "summary" =>
              "oversized accepted result #{index} " <>
                String.duplicate("payload-#{index} ", 80) <> "END-SENTINEL-#{index}"
          }
        }
      end)

    {outcome, events} =
      run_runtime(%{
        conversation_id: "conversation-85-runtime-budget",
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        turn_id: "turn-85-runtime-budget",
        instruction: "Review lib/example.ex and keep the current request intact.",
        objective: "Exercise runtime context budget packing.",
        source: "phase_85_test",
        turn_payload: %{
          "workflow" => "review",
          "instruction" => "Review lib/example.ex and keep the current request intact."
        },
        shared_context: %{
          "referenced_files" => ["lib/example.ex"],
          "accepted_tool_results" => accepted_tool_results,
          "context_budget" => %{"input_token_budget" => 180}
        }
      })

    assert {:completed, %{"result" => %{"summary" => summary, "context_budget" => result_budget}}} =
             outcome

    assert summary =~ "Current request:"
    assert summary =~ "Review lib/example.ex and keep the current request intact."
    assert summary =~ "Repository scope:"
    assert summary =~ "- managed_repo_id: #{managed_repo.id}"
    refute summary =~ "END-SENTINEL-8"

    assert result_budget["state"] in ["trimmed", "degraded"]
    assert result_budget["trimmed_section_count"] >= 1

    progress = Enum.find(events, &(&1["kind"] == "progress" and &1["workflow"] == "review"))

    assert progress["context_budget"]["state"] in ["trimmed", "degraded"]

    accepted_tool_diagnostics =
      Enum.find(
        progress["context_budget"]["diagnostics"],
        &(to_string(&1["kind"]) == "accepted_tool_results")
      )

    assert accepted_tool_diagnostics["state"] in [:trimmed, :dropped, "trimmed", "dropped"]
    assert accepted_tool_diagnostics["dropped_entries"] > 0
  end

  defp run_runtime(spec) do
    outcome =
      Runtime.run(spec, fn event ->
        send(self(), {:runtime_event, event})
      end)

    {outcome, runtime_events()}
  end

  defp runtime_events(events \\ []) do
    receive do
      {:runtime_event, event} -> runtime_events([event | events])
    after
      0 -> Enum.reverse(events)
    end
  end

  defp managed_repo_and_work_item_fixture!(suffix) do
    {_project, managed_repo} = managed_repo_fixture!(suffix)
    work_item = work_item_fixture!(managed_repo, "phase85-#{suffix}")

    on_exit(fn ->
      _ = AgentWorkspace.shutdown_kernel(managed_repo.id)
    end)

    {managed_repo, work_item}
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-eighty-five-#{suffix}",
        github_full_name: "owner/phase-eighty-five-#{suffix}",
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

  defp work_item_fixture!(managed_repo, actor_id) do
    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "fix_workflow_kickoff",
        actor: %{id: actor_id, email: "#{actor_id}@example.com"},
        payload: %{
          "workflow_name" => "fix_failing_tests_#{actor_id}",
          "context_item" => %{"type" => "issue", "id" => actor_id}
        },
        source_metadata: %{
          "trigger" => %{"source" => "workbench", "mode" => "manual"}
        }
      })

    work_item
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-eighty-five-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule Example do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
