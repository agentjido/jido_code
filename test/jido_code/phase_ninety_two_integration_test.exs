defmodule JidoCode.PhaseNinetyTwoIntegrationTest do
  # covers: architecture.context_management_pod.context_lifecycle_is_observable
  # covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata
  # covers: architecture.context_compaction_policy.compaction_degrades_to_request_time_packing
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentWorkspace.SpecialistRunner
  alias JidoCode.ContextManagement

  defmodule CapturingRunner do
    @behaviour SpecialistRunner

    @impl true
    def run(agent_module, _pid, instruction, _opts) do
      if capture_pid = Application.get_env(:jido_code, :phase_92_capture_pid) do
        send(capture_pid, {:phase_92_specialist_run, agent_module, instruction})
      end

      role =
        agent_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      {:ok, %{summary: "phase 92 #{role} response"}}
    end
  end

  setup do
    previous_runner = Application.get_env(:jido_code, :agent_workspace_specialist_runner)
    previous_capture_pid = Application.get_env(:jido_code, :phase_92_capture_pid, :__missing__)

    Application.put_env(:jido_code, :agent_workspace_specialist_runner, CapturingRunner)
    Application.put_env(:jido_code, :phase_92_capture_pid, self())

    on_exit(fn ->
      Application.put_env(:jido_code, :agent_workspace_specialist_runner, previous_runner)

      case previous_capture_pid do
        :__missing__ -> Application.delete_env(:jido_code, :phase_92_capture_pid)
        pid -> Application.put_env(:jido_code, :phase_92_capture_pid, pid)
      end
    end)

    :ok
  end

  test "repeated trims can lead to a summary that appears as bounded prompt context" do
    managed_repo_id = "phase-92-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-92-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()
    raw_sentinel = "PHASE-92-RAW-COMPACTION-SENTINEL"

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path,
               context_management: [repeated_trim_threshold: 2]
             )

    trimmed_observation = %{
      workflow: :execute,
      specialist_role: :coder,
      context_budget: trimmed_budget(),
      diagnostics: %{source_span_ids: ["turn-a", "tool-a"]}
    }

    assert {:ok, _status} =
             AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, trimmed_observation)

    assert {:ok, status} = AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, trimmed_observation)
    assert status["state"] == "recommend_compaction"

    assert {:ok, candidate} =
             ContextManagement.compaction_candidate(
               [
                 %{id: "turn-a", role: "user", content: "older context #{raw_sentinel}"},
                 %{id: "tool-a", role: "tool", content: "older tool output #{raw_sentinel}"},
                 %{id: "turn-b", role: "user", content: "active request"}
               ],
               %{
                 managed_repo_id: managed_repo_id,
                 work_item_id: work_item_id,
                 workflow: :execute,
                 specialist_role: :coder
               }
             )

    assert {:ok, compacted_status} = AgentWorkspace.compact_context(managed_repo_id, work_item_id, candidate)
    assert compacted_status["active_summary_source_span_count"] == 2
    assert compacted_status["active_summary_ids"] != []

    assert {:ok, result} =
             AgentWorkspace.execute_work(
               managed_repo_id,
               work_item_id,
               "Continue with compacted context.",
               workspace_path: workspace_path
             )

    assert result.context_budget["policy_id"] == "context-budget:v1"
    assert_receive {:phase_92_specialist_run, JidoCode.Agents.Coder, instruction}
    assert instruction =~ "Compaction summary:"
    refute instruction =~ raw_sentinel

    metadata_dump = inspect(AgentWorkspace.context_management_status(managed_repo_id, work_item_id), limit: :infinity)
    refute metadata_dump =~ raw_sentinel
  end

  test "failed compaction falls back to request-time packing" do
    managed_repo_id = "phase-92-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-92-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:error, {:ineligible_compaction_candidate, %{reason: :no_eligible_history}}} =
             AgentWorkspace.compact_context(managed_repo_id, work_item_id, %{
               eligible?: false,
               source_span_ids: [],
               diagnostics: %{reason: :no_eligible_history}
             })

    degraded_status = AgentWorkspace.context_management_status(managed_repo_id, work_item_id)
    assert degraded_status["state"] == "degraded"
    assert get_in(degraded_status, ["latest_compaction", "retryable?"])

    assert {:ok, result} =
             AgentWorkspace.execute_work(
               managed_repo_id,
               work_item_id,
               "Continue after failed compaction.",
               workspace_path: workspace_path,
               context_budget: [input_token_budget: 240]
             )

    assert result.context_budget["policy_id"] == "context-budget:v1"
    assert result.context_budget["state"] in ["packed", "trimmed", "degraded"]
  end

  defp trimmed_budget do
    %{
      "policy_id" => "context-budget:v1",
      "state" => "trimmed",
      "model_budget" => 1_000,
      "estimated_input_tokens" => 400,
      "diagnostics" => [
        %{"kind" => "conversation_history", "state" => "trimmed", "dropped_entries" => 2}
      ]
    }
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_92_context_management_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Phase92.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Phase92.Example do\nend\n")

    workspace_path
  end
end
