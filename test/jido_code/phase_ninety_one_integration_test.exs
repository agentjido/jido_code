defmodule JidoCode.PhaseNinetyOneIntegrationTest do
  # covers: architecture.context_management_pod.context_compactor_is_bounded_specialist
  # covers: architecture.context_compaction_policy.compaction_preserves_required_context
  # covers: architecture.context_compaction_policy.tool_protocol_boundaries_are_preserved
  # covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentWorkspace.SpecialistRunner

  defmodule CapturingRunner do
    @behaviour SpecialistRunner

    @impl true
    def run(agent_module, _pid, instruction, opts) do
      if capture_pid = Application.get_env(:jido_code, :phase_91_capture_pid) do
        send(capture_pid, {:phase_91_specialist_run, agent_module, instruction, opts})
      end

      role =
        agent_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      {:ok, %{summary: "phase 91 #{role} response"}}
    end
  end

  setup do
    previous_runner = Application.get_env(:jido_code, :agent_workspace_specialist_runner)
    previous_capture_pid = Application.get_env(:jido_code, :phase_91_capture_pid, :__missing__)

    Application.put_env(:jido_code, :agent_workspace_specialist_runner, CapturingRunner)
    Application.put_env(:jido_code, :phase_91_capture_pid, self())

    on_exit(fn ->
      Application.put_env(:jido_code, :agent_workspace_specialist_runner, previous_runner)

      case previous_capture_pid do
        :__missing__ -> Application.delete_env(:jido_code, :phase_91_capture_pid)
        pid -> Application.put_env(:jido_code, :phase_91_capture_pid, pid)
      end
    end)

    :ok
  end

  test "candidate to summary to prompt injection keeps raw old history out of the prompt" do
    managed_repo_id = "phase-91-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-91-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()
    old_sentinel = "PHASE-91-RAW-OLD-HISTORY-SENTINEL"

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, candidate} =
             JidoCode.ContextManagement.compaction_candidate(
               [
                 %{id: "turn-1", role: "user", content: "older implementation note #{old_sentinel}"},
                 %{id: "assistant-1", role: "assistant", content: "calling read", tool_calls: [%{id: "tool-1"}]},
                 %{id: "tool-1", role: "tool", content: "large older tool result #{old_sentinel}"},
                 %{id: "turn-2", role: "user", content: "active request should stay raw"}
               ],
               %{
                 managed_repo_id: managed_repo_id,
                 work_item_id: work_item_id,
                 workflow: :execute,
                 specialist_role: :coder
               }
             )

    assert {:ok, status} = AgentWorkspace.compact_context(managed_repo_id, work_item_id, candidate)
    assert status["summary_count"] == 1

    assert {:ok, result} =
             AgentWorkspace.execute_work(
               managed_repo_id,
               work_item_id,
               "Continue after compaction.",
               workspace_path: workspace_path,
               context_budget: [input_token_budget: 900]
             )

    assert result.context_budget["policy_id"] == "context-budget:v1"
    assert_receive {:phase_91_specialist_run, JidoCode.Agents.Coder, instruction, _opts}

    assert instruction =~ "Compaction summary:"
    assert instruction =~ "Compacted 2 older execute/coder context span"
    refute instruction =~ old_sentinel

    compaction_diagnostic =
      Enum.find(result.context_budget["diagnostics"], &(to_string(&1["kind"]) == "compaction_summary"))

    assert compaction_diagnostic["state"] in [:packed, "packed", :trimmed, "trimmed"]
  end

  test "unresolved assistant tool-call groups cannot be compacted" do
    assert {:ok, candidate} =
             JidoCode.ContextManagement.compaction_candidate(
               [
                 %{id: "turn-1", role: "user", content: "older request"},
                 %{id: "assistant-1", role: "assistant", content: "calling read", tool_calls: [%{id: "tool-1"}]},
                 %{id: "turn-2", role: "user", content: "active request"}
               ],
               %{
                 managed_repo_id: "repo-91",
                 work_item_id: "work-91",
                 workflow: :execute,
                 specialist_role: :coder
               }
             )

    assert {:error, {:ineligible_compaction_candidate, %{reason: :unresolved_tool_call_group}}} =
             JidoCode.ContextManagement.compact_candidate(candidate)
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_91_context_management_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Phase91.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Phase91.Example do\nend\n")

    workspace_path
  end
end
