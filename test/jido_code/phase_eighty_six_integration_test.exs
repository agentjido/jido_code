defmodule JidoCode.PhaseEightySixIntegrationTest do
  # covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_context
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentWorkspace.PromptProjection
  alias JidoCode.LLMSelection

  defmodule CapturingRunner do
    @behaviour JidoCode.AgentWorkspace.SpecialistRunner

    @impl true
    def run(agent_module, _pid, instruction, opts) do
      if capture_pid = Application.get_env(:jido_code, :phase_86_capture_pid) do
        send(capture_pid, {:phase_86_specialist_run, agent_module, instruction, opts})
      end

      role =
        agent_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      {:ok,
       %{
         role: role,
         instruction: instruction,
         tool_context: Keyword.get(opts, :tool_context, %{}),
         summary: "phase 86 #{role} response for #{instruction}",
         llm_selection: LLMSelection.summary(Keyword.get(opts, :llm_selection))
       }}
    end
  end

  setup do
    previous_runner = Application.get_env(:jido_code, :agent_workspace_specialist_runner)
    previous_capture_pid = Application.get_env(:jido_code, :phase_86_capture_pid, :__missing__)

    Application.put_env(:jido_code, :agent_workspace_specialist_runner, CapturingRunner)
    Application.put_env(:jido_code, :phase_86_capture_pid, self())

    on_exit(fn ->
      Application.put_env(:jido_code, :agent_workspace_specialist_runner, previous_runner)

      case previous_capture_pid do
        :__missing__ -> Application.delete_env(:jido_code, :phase_86_capture_pid)
        pid -> Application.put_env(:jido_code, :phase_86_capture_pid, pid)
      end
    end)

    :ok
  end

  test "AgentWorkspace trims prompt-facing memory context while preserving tool_context" do
    managed_repo_id = "phase-86-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-86-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()
    memory_graph = oversized_memory_graph(work_item_id)

    on_exit(fn ->
      _ = AgentWorkspace.shutdown_kernel(managed_repo_id)
      File.rm_rf!(workspace_path)
    end)

    assert {:ok, result} =
             AgentWorkspace.execute_work(
               managed_repo_id,
               work_item_id,
               "Implement from bounded memory projection.",
               workspace_path: workspace_path,
               memory_graph: memory_graph,
               context_budget: [input_token_budget: 260]
             )

    memory_budget = context_budget_section(result.context_budget, "memory_context")
    assert memory_budget["metadata"]["state"] in [:trimmed, "trimmed"]

    assert_receive {:phase_86_specialist_run, JidoCode.Agents.Coder, instruction, opts}

    assert instruction =~ "Current request:"
    assert instruction =~ "Implement from bounded memory projection."
    assert instruction =~ "Memory context:"
    refute instruction =~ "END-MEMORY-SENTINEL-10"

    tool_context = Keyword.fetch!(opts, :tool_context)

    tool_context_budget = context_budget_section(tool_context.context_budget, "memory_context")
    assert tool_context_budget["metadata"]["state"] in [:trimmed, "trimmed"]
    assert get_in(tool_context, [:memory_graph, :selection, "selected_items", "memories"]) |> length() == 10

    assert Enum.any?(
             get_in(tool_context, [:memory_graph, :selection, "selected_items", "memories"]),
             &(Map.get(&1, "content") =~ "END-MEMORY-SENTINEL-10")
           )
  end

  test "semantic prompt projection is compact before packing" do
    semantic_context = %{
      workflow: :review,
      graph_status: %{ready?: true, stale?: true, current_revision: "rev-86-semantic"},
      results:
        Map.new(1..10, fn index ->
          {"result_#{index}", %{finding: String.duplicate("semantic-result-#{index} ", 40)}}
        end)
    }

    projection = PromptProjection.semantic(semantic_context, max_items: 3, max_item_bytes: 100)

    assert projection.state == :trimmed
    assert "graph_ready?: true" in projection.lines
    assert "graph_stale?: true" in projection.lines
    assert projection.diagnostics.original_items == 10
    assert projection.diagnostics.packed_items == 3
    assert projection.diagnostics.dropped_items == 7
    refute Enum.join(projection.lines, "\n") =~ "semantic-result-9"
  end

  defp oversized_memory_graph(work_item_id) do
    %{
      workflow: :execute,
      graph: %{
        ready?: true,
        stale?: false,
        state: :ready,
        current_revision: "rev-86-memory"
      },
      freshness: %{state: :ready, label: "Memory graph ready"},
      policy: %{
        intent: :implementation_constraints,
        follow_up_intent: :work_item,
        memory_kinds: [:decision, :invariant],
        provenance_kinds: [:plan, :patch]
      },
      selection: %{
        governed_references: [%{kind: :work_item, id: work_item_id, label: "Current work item"}],
        selected_items: %{
          memories:
            Enum.map(1..10, fn index ->
              %{
                memory_kind: "Decision",
                content:
                  "Memory #{index}: " <>
                    String.duplicate("preserve bounded behavior ", 50) <> "END-MEMORY-SENTINEL-#{index}"
              }
            end),
          provenance: []
        }
      }
    }
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(System.tmp_dir!(), "jido-code-phase-eighty-six-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Example do\nend\n")
    workspace_path
  end

  defp context_budget_section(context_budget, kind) do
    Enum.find(context_budget["diagnostics"], &(to_string(&1["kind"]) == kind))
  end
end
