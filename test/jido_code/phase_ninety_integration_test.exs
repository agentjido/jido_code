defmodule JidoCode.PhaseNinetyIntegrationTest do
  # covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics
  # covers: architecture.context_compaction_policy.compaction_is_threshold_driven
  # covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.AgentWorkspace.SpecialistRunner
  alias JidoCode.Conversations.{ChildWork, Conversation, Event, Snapshot}

  defmodule CapturingRunner do
    @behaviour SpecialistRunner

    @impl true
    def run(agent_module, _pid, _instruction, _opts) do
      role =
        agent_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      {:ok, %{summary: "phase 90 #{role} response"}}
    end
  end

  setup do
    previous_runner = Application.get_env(:jido_code, :agent_workspace_specialist_runner)
    Application.put_env(:jido_code, :agent_workspace_specialist_runner, CapturingRunner)

    on_exit(fn ->
      Application.put_env(:jido_code, :agent_workspace_specialist_runner, previous_runner)
    end)

    :ok
  end

  test "specialist results expose monitor recommendations without prompt text" do
    managed_repo_id = "phase-90-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-90-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()
    sentinel = "PHASE-90-RAW-PROMPT-SENTINEL"

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, result} =
             AgentWorkspace.execute_work(
               managed_repo_id,
               work_item_id,
               "Implement bounded monitor flow #{sentinel}.",
               workspace_path: workspace_path,
               context_budget: [input_token_budget: 240],
               context_management: [high_water_mark: 0.001]
             )

    assert result.context_management["state"] in ["healthy", "recommend_compaction"]
    assert get_in(result.context_management, ["latest_monitor_decision", "state"]) in ["healthy", "recommend"]
    assert result.context_management["observation_count"] >= 1

    metadata_dump =
      managed_repo_id
      |> AgentWorkspace.context_management_status(work_item_id)
      |> inspect(limit: :infinity)

    refute metadata_dump =~ sentinel
    refute metadata_dump =~ "Implement bounded monitor flow"
  end

  test "workspace observation API debounces unchanged trim recommendations" do
    managed_repo_id = "phase-90-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-90-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path,
               context_management: [repeated_trim_threshold: 2]
             )

    observation = %{
      workflow: :review,
      specialist_role: :reviewer,
      context_budget: trimmed_budget(),
      diagnostics: %{source_span_ids: ["turn-1", "tool-group-1"]}
    }

    assert {:ok, _status} = AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, observation)
    assert {:ok, _status} = AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, observation)
    assert {:ok, status} = AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, observation)

    assert status["state"] == "recommend_compaction"
    assert status["latest_monitor_decision"]["debounced?"]
    assert status["recommendation_count"] == 1
  end

  test "conversation snapshots expose latest context-management metadata" do
    context_management = %{
      "state" => "recommend_compaction",
      "latest_monitor_decision" => %{
        "state" => "recommend",
        "reason" => "repeated_context_trimming"
      }
    }

    snapshot =
      snapshot_from_state(
        conversation_id: "conversation-90-context-management",
        managed_repo_id: "repo-90-snapshot",
        work_item_id: "work-90-snapshot",
        events: [
          Event.new("conversation-90-context-management", 1, "tool.progress", %{
            payload: %{"context_management" => context_management}
          })
        ]
      )

    assert snapshot.shared_context["latest_context_management"] == context_management

    child_work = %ChildWork{
      id: "child-90-context-management",
      conversation_id: "conversation-90-child",
      managed_repo_id: "repo-90-child",
      work_item_id: "work-90-child",
      turn_id: "turn-90-child",
      tool_call_id: "tool-90-child",
      kind: "workflow",
      state: :completed,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      result: %{"context_management" => context_management}
    }

    child_snapshot =
      snapshot_from_state(
        conversation_id: "conversation-90-child",
        managed_repo_id: "repo-90-child",
        work_item_id: "work-90-child",
        child_works: %{"child-90-context-management" => child_work},
        child_work_order: ["child-90-context-management"]
      )

    assert child_snapshot.shared_context["latest_context_management"] == context_management
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

  defp snapshot_from_state(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    managed_repo_id = Keyword.fetch!(opts, :managed_repo_id)
    work_item_id = Keyword.fetch!(opts, :work_item_id)
    events = Keyword.get(opts, :events, [])
    child_works = Keyword.get(opts, :child_works, %{})
    child_work_order = Keyword.get(opts, :child_work_order, [])

    Snapshot.from_state(%{
      conversation: conversation_struct(conversation_id, managed_repo_id, work_item_id),
      status: :active,
      admission_paused: false,
      child_execution_paused: false,
      active_turn_id: nil,
      turns: %{},
      turn_order: [],
      work_queue: [],
      child_works: child_works,
      child_work_order: child_work_order,
      control_history: [],
      event_sequence: length(events),
      events: events
    })
  end

  defp conversation_struct(conversation_id, managed_repo_id, work_item_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Conversation{
      id: conversation_id,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      status: :active,
      scope: :work_item_scoped,
      attachment_mode: :existing_work_item,
      source: "phase_90_test",
      title: "Phase 90 context management test",
      objective: "Verify monitor observability.",
      initiating_actor: %{"id" => "phase-90"},
      source_metadata: %{},
      conversation_metadata: %{},
      started_at: now,
      last_activity_at: now
    }
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_90_context_management_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Phase90.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Phase90.Example do\nend\n")

    workspace_path
  end
end
