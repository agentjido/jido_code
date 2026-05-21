defmodule JidoCode.PhaseEightyNineIntegrationTest do
  # covers: architecture.context_management_pod.coding_pod_owns_context_management
  # covers: architecture.context_management_pod.compaction_store_is_product_owned
  # covers: architecture.context_management_pod.request_time_budgeting_remains_hard_guard
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentOS.Manager
  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentWorkspace.SpecialistRunner
  alias JidoCode.Pods.ContextManagementPod

  defmodule CapturingRunner do
    @behaviour SpecialistRunner

    @impl true
    def run(agent_module, _pid, instruction, opts) do
      if capture_pid = Application.get_env(:jido_code, :phase_89_capture_pid) do
        send(capture_pid, {:phase_89_specialist_run, agent_module, instruction, opts})
      end

      role =
        agent_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      {:ok, %{summary: "phase 89 #{role} response", role: role}}
    end
  end

  setup do
    previous_runner = Application.get_env(:jido_code, :agent_workspace_specialist_runner)
    previous_capture_pid = Application.get_env(:jido_code, :phase_89_capture_pid, :__missing__)

    Application.put_env(:jido_code, :agent_workspace_specialist_runner, CapturingRunner)
    Application.put_env(:jido_code, :phase_89_capture_pid, self())

    on_exit(fn ->
      Application.put_env(:jido_code, :agent_workspace_specialist_runner, previous_runner)

      case previous_capture_pid do
        :__missing__ -> Application.delete_env(:jido_code, :phase_89_capture_pid)
        pid -> Application.put_env(:jido_code, :phase_89_capture_pid, pid)
      end
    end)

    :ok
  end

  test "each CodingPod owns one context-management pod for the same work item" do
    managed_repo_id = "phase-89-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-89-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    pod_id = AgentWorkspace.context_management_pod_id(work_item_id)
    assert %{module: ContextManagementPod, metadata: metadata} = Manager.pod_status(managed_repo_id, pod_id)
    assert metadata.parent_pod_id == "coding-pod-#{work_item_id}"
    assert metadata.work_item_id == work_item_id
    assert metadata.context_management_status == :healthy
    assert AgentWorkspace.context_management_status(managed_repo_id, work_item_id)["state"] == "healthy"
  end

  test "different work items do not share compaction summaries" do
    managed_repo_id = "phase-89-repo-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()
    work_item_1 = "phase-89-work-a-#{System.unique_integer([:positive])}"
    work_item_2 = "phase-89-work-b-#{System.unique_integer([:positive])}"

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_1, workspace_path)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_2, workspace_path)

    assert {:ok, status} =
             AgentWorkspace.store_context_compaction_summary(managed_repo_id, work_item_1, %{
               workflow: :execute,
               specialist_role: :coder,
               summary_text: "Work item one summary.",
               source_span_ids: ["turn-1"]
             })

    assert status["summary_count"] == 1
    assert [%{"summary_text" => "Work item one summary."}] =
             AgentWorkspace.context_compaction_summaries(managed_repo_id, work_item_1)

    assert [] = AgentWorkspace.context_compaction_summaries(managed_repo_id, work_item_2)
  end

  test "disabled context management leaves specialist context-budget packing active" do
    managed_repo_id = "phase-89-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-89-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, result} =
             AgentWorkspace.execute_work(
               managed_repo_id,
               work_item_id,
               "Implement with disabled proactive context management.",
               workspace_path: workspace_path,
               context_management: [enabled?: false],
               context_budget: [input_token_budget: 240]
             )

    assert result.context_budget["policy_id"] == "context-budget:v1"
    assert result.context_budget["state"] in ["packed", "trimmed", "degraded"]
    assert_receive {:phase_89_specialist_run, JidoCode.Agents.Coder, _instruction, opts}

    tool_context = Keyword.fetch!(opts, :tool_context)
    assert tool_context.context_budget["policy_id"] == "context-budget:v1"
    assert Manager.pod_status(managed_repo_id, AgentWorkspace.context_management_pod_id(work_item_id)) == nil
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_89_context_management_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Phase89.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Phase89.Example do\nend\n")

    workspace_path
  end
end
