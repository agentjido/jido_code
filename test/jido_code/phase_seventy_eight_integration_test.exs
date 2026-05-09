defmodule JidoCode.PhaseSeventyEightIntegrationTest do
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  # covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.{ContextMemory, Runtime}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project

  @store_table :jido_code_phase_78_prompt_memory_test
  @store {Jido.Memory.Store.ETS, [table: @store_table]}

  setup do
    previous_prompt_memory = Application.get_env(:jido_code, :conversation_context_memory, [])
    previous_memory_graph = Application.get_env(:jido_code, :memory_graph_enabled, false)
    previous_source_graph = Application.get_env(:jido_code, :source_code_graph_enabled, false)

    reset_prompt_memory_store!()

    Application.put_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, false)

    Application.put_env(:jido_code, :conversation_context_memory,
      enabled?: true,
      provider: :basic,
      store: @store,
      store_opts: [],
      retrieval_limit: 10,
      max_instruction_lines: 10,
      max_instruction_bytes: 2_000,
      ttl_ms: 60_000
    )

    on_exit(fn ->
      Application.put_env(:jido_code, :conversation_context_memory, previous_prompt_memory)
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory_graph)
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source_graph)
      reset_prompt_memory_store!()
    end)

    :ok
  end

  test "runtime retrieves prompt memory into bounded instruction assembly and progress diagnostics" do
    {managed_repo, work_item} = managed_repo_and_work_item_fixture!("retrieval")

    scope = prompt_memory_scope(managed_repo, work_item, "conversation-78-retrieval", "turn-seed", :review)

    assert {:ok, %{state: :ready}} =
             ContextMemory.remember(scope, %{
               kind: :active_constraint,
               text: "Prefer context-memory adapter coverage over transcript replay."
             })

    {outcome, events} =
      run_runtime(%{
        conversation_id: "conversation-78-retrieval",
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        turn_id: "turn-78-retrieval",
        instruction: "Review lib/example.ex for prompt-memory recall.",
        objective: "Review bounded prompt memory recall.",
        source: "phase_78_test",
        turn_payload: %{
          "workflow" => "review",
          "instruction" => "Review lib/example.ex for prompt-memory recall."
        },
        shared_context: %{
          referenced_files: ["lib/example.ex"]
        }
      })

    assert {:completed, %{"result" => %{"summary" => summary, "prompt_memory" => prompt_memory}}} = outcome
    assert summary =~ "Prompt memory:"
    assert summary =~ "active_constraint: Prefer context-memory adapter coverage over transcript replay."

    assert prompt_memory["state"] == "ready"
    assert prompt_memory["item_count"] >= 1

    progress = Enum.find(events, &(&1["kind"] == "progress" and &1["workflow"] == "review"))
    assert progress["prompt_memory"]["state"] == "ready"
    assert progress["prompt_memory"]["namespace"] == "repo:#{managed_repo.id}:work_item:#{work_item.id}"
  end

  test "runtime writes only bounded prompt-memory records at product-significant seams" do
    {managed_repo, work_item} = managed_repo_and_work_item_fixture!("capture")

    {outcome, _events} =
      run_runtime(%{
        conversation_id: "conversation-78-capture",
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        turn_id: "turn-78-capture",
        instruction: "Plan the fix for lib/example.ex.",
        objective: "Plan prompt-memory capture.",
        source: "phase_78_test",
        turn_payload: %{
          "workflow" => "plan",
          "instruction" => "Plan the fix for lib/example.ex.",
          "clarification_resume" => %{
            "prompt" => "Which file should I inspect?",
            "response" => "lib/example.ex"
          }
        },
        shared_context: %{
          referenced_files: ["lib/example.ex"],
          active_constraints: ["Keep prompt memory behind the runtime adapter."],
          accepted_tool_results: [
            %{
              "child_work_id" => "child-work-78",
              "workflow" => "execute",
              "result" => %{"summary" => "Accepted bounded tool result summary."}
            }
          ]
        }
      })

    assert {:completed, _payload} = outcome

    assert {:ok, %{state: :ready, items: items}} =
             ContextMemory.retrieve(
               prompt_memory_scope(managed_repo, work_item, "conversation-78-capture", "turn-78-capture", :plan)
             )

    kinds = Enum.map(items, & &1.kind)

    assert :clarification_answer in kinds
    assert :accepted_tool_result in kinds
    assert :active_constraint in kinds
    assert :plan_summary in kinds
    refute :raw_transcript in kinds

    accepted_tool_result = Enum.find(items, &(&1.kind == :accepted_tool_result))

    assert accepted_tool_result.text =~ "Accepted bounded tool result summary."
    assert accepted_tool_result.metadata["managed_repo_id"] == managed_repo.id
    assert accepted_tool_result.metadata["work_item_id"] == work_item.id
    assert accepted_tool_result.metadata["conversation_id"] == "conversation-78-capture"
    assert accepted_tool_result.metadata["turn_id"] == "turn-78-capture"
    assert accepted_tool_result.metadata["workflow"] == "plan"
    assert accepted_tool_result.metadata["source"] == "phase_78_test"
    assert accepted_tool_result.metadata["retention_policy"] == "short_term_prompt_context"
    assert accepted_tool_result.metadata["ttl_ms"] == 60_000
    assert accepted_tool_result.metadata["previous_prompt_memory_namespaces"] == ["repo:#{managed_repo.id}:intake"]
  end

  test "disabled prompt memory falls back to the existing runtime path" do
    Application.put_env(:jido_code, :conversation_context_memory, enabled?: false, store: @store)

    {managed_repo, work_item} = managed_repo_and_work_item_fixture!("disabled")

    {outcome, events} =
      run_runtime(%{
        conversation_id: "conversation-78-disabled",
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        turn_id: "turn-78-disabled",
        instruction: "Explain lib/example.ex.",
        objective: "Explain disabled prompt memory fallback.",
        source: "phase_78_test",
        turn_payload: %{
          "workflow" => "explain",
          "instruction" => "Explain lib/example.ex."
        },
        shared_context: %{
          referenced_files: ["lib/example.ex"]
        }
      })

    assert {:completed, %{"result" => %{"summary" => summary, "prompt_memory" => prompt_memory}}} = outcome
    refute summary =~ "Prompt memory:"
    assert prompt_memory["state"] == "disabled"

    progress = Enum.find(events, &(&1["kind"] == "progress" and &1["workflow"] == "explain"))
    assert progress["prompt_memory"]["state"] == "disabled"

    assert {:ok, %{state: :disabled, items: []}} =
             ContextMemory.retrieve(
               prompt_memory_scope(managed_repo, work_item, "conversation-78-disabled", "turn-78-disabled", :explain)
             )
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
    work_item = work_item_fixture!(managed_repo, "phase78-#{suffix}")

    on_exit(fn ->
      _ = AgentWorkspace.shutdown_kernel(managed_repo.id)
    end)

    {managed_repo, work_item}
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-seventy-eight-#{suffix}",
        github_full_name: "owner/phase-seventy-eight-#{suffix}",
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

  defp prompt_memory_scope(managed_repo, work_item, conversation_id, turn_id, workflow) do
    %{
      managed_repo_id: managed_repo.id,
      work_item_id: work_item.id,
      conversation_id: conversation_id,
      turn_id: turn_id,
      workflow: workflow,
      source: "phase_78_test"
    }
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-seventy-eight-#{suffix}-#{System.unique_integer([:positive])}"
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

  defp reset_prompt_memory_store! do
    for table <- [
          :jido_code_phase_78_prompt_memory_test_records,
          :jido_code_phase_78_prompt_memory_test_ns_time,
          :jido_code_phase_78_prompt_memory_test_ns_class_time,
          :jido_code_phase_78_prompt_memory_test_ns_tag
        ] do
      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end
  end
end
