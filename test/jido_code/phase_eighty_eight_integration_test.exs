defmodule JidoCode.PhaseEightyEightIntegrationTest do
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.ContextBudget
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.{ChildWork, Conversation, Event, Runtime, Snapshot}
  alias JidoCode.MemoryGraph.CaptureEnvelope
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

  test "runtime progress and snapshots expose metadata-only budget summaries" do
    {managed_repo, work_item} = managed_repo_and_work_item_fixture!("runtime-observability")
    instruction = "Review lib/example.ex and preserve the request text."

    accepted_tool_results =
      Enum.map(1..8, fn index ->
        %{
          "child_work_id" => "child-88-#{index}",
          "workflow" => "review",
          "result" => %{
            "summary" =>
              "oversized accepted result #{index} " <>
                String.duplicate("phase-88-observability ", 80) <> "END-PHASE-88-SENTINEL-#{index}"
          }
        }
      end)

    {outcome, events} =
      run_runtime(%{
        conversation_id: "conversation-88-runtime-budget",
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        turn_id: "turn-88-runtime-budget",
        instruction: instruction,
        objective: "Exercise context budget observability.",
        source: "phase_88_test",
        turn_payload: %{
          "workflow" => "review",
          "instruction" => instruction
        },
        shared_context: %{
          "referenced_files" => ["lib/example.ex"],
          "accepted_tool_results" => accepted_tool_results,
          "context_budget" => %{"input_token_budget" => 180}
        }
      })

    assert {:completed, %{"result" => %{"summary" => summary, "context_budget" => result_budget}}} =
             outcome

    assert summary =~ instruction
    refute summary =~ "END-PHASE-88-SENTINEL-8"

    progress = Enum.find(events, &(&1["kind"] == "progress" and &1["workflow"] == "review"))
    assert progress["context_budget"]["state"] in ["trimmed", "degraded"]

    accepted_tool_diagnostics =
      Enum.find(
        progress["context_budget"]["diagnostics"],
        &(to_string(&1["kind"]) == "accepted_tool_results")
      )

    assert accepted_tool_diagnostics["state"] in ["trimmed", "dropped", :trimmed, :dropped]
    assert accepted_tool_diagnostics["dropped_entries"] > 0

    budget_dump = inspect(progress["context_budget"], limit: :infinity)
    refute budget_dump =~ instruction
    refute budget_dump =~ "END-PHASE-88-SENTINEL"

    result_budget_dump = inspect(result_budget, limit: :infinity)
    refute result_budget_dump =~ instruction
    refute result_budget_dump =~ "END-PHASE-88-SENTINEL"

    snapshot =
      snapshot_from_state(
        conversation_id: "conversation-88-runtime-budget",
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        events: [
          Event.new("conversation-88-runtime-budget", 1, "tool.progress", %{
            payload: progress
          })
        ]
      )

    assert snapshot.shared_context["latest_context_budget"] == progress["context_budget"]
  end

  test "snapshots fall back to child-work budget diagnostics when event metadata is absent" do
    child_budget = %{
      "policy_id" => "context-budget:v1",
      "state" => "trimmed",
      "model_budget" => 180,
      "estimated_input_tokens" => 170,
      "trimmed_section_count" => 1,
      "diagnostics" => [
        %{
          "kind" => "semantic_context",
          "state" => "trimmed",
          "original_entries" => 8,
          "packed_entries" => 2,
          "dropped_entries" => 6
        }
      ]
    }

    child_work = %ChildWork{
      id: "child-88-budget",
      conversation_id: "conversation-88-child-budget",
      managed_repo_id: "repo-88-child-budget",
      work_item_id: "work-88-child-budget",
      turn_id: "turn-88-child-budget",
      tool_call_id: "tool-88-child-budget",
      kind: "workflow",
      state: :completed,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      result: %{"latest_progress" => %{"context_budget" => child_budget}}
    }

    snapshot =
      snapshot_from_state(
        conversation_id: "conversation-88-child-budget",
        managed_repo_id: "repo-88-child-budget",
        work_item_id: "work-88-child-budget",
        child_works: %{"child-88-budget" => child_work},
        child_work_order: ["child-88-budget"]
      )

    assert snapshot.shared_context["latest_context_budget"] == child_budget
  end

  test "workflow provenance envelopes keep budget diagnostics without raw prompt dumps" do
    prompt_sentinel = "END-PHASE-88-PROVENANCE-SENTINEL"

    packed =
      ContextBudget.pack(
        [
          ContextBudget.section(:current_request, "Instruction: preserve #{prompt_sentinel}", retention: :required),
          ContextBudget.section(
            :semantic_context,
            Enum.map(1..8, &"semantic projection #{&1} #{String.duplicate("context ", 80)} #{prompt_sentinel}"),
            retention: :useful
          )
        ],
        input_token_budget: 180
      )

    capture =
      CaptureEnvelope.agent_run(
        session_id: "phase-88-provenance-session",
        id: "phase-88-provenance-run",
        actor_id: "system:phase-88",
        workflow: :execute,
        work_item_id: "work-88-provenance",
        agent_name: "Coder",
        content: "Outcome: success",
        started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        ended_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        revision: "rev-phase-88",
        metadata: %{context_budget: ContextBudget.summary(packed)}
      )

    assert {:ok, envelope} = CaptureEnvelope.normalize(capture, graph_context())

    budget_metadata = get_in(envelope, [:metadata, "context_budget"])
    assert budget_metadata["state"] in ["trimmed", "degraded"]
    assert Enum.any?(budget_metadata["diagnostics"], &(to_string(&1["kind"]) == "semantic_context"))

    metadata_dump = inspect(envelope.metadata, limit: :infinity)
    refute metadata_dump =~ prompt_sentinel
    refute metadata_dump =~ "Instruction: preserve"
  end

  test "budget summaries distinguish optional trimming from required context overflow" do
    trimmed =
      ContextBudget.pack(
        [
          ContextBudget.section(:current_request, "Keep this request intact.", retention: :required),
          ContextBudget.section(:semantic_context, Enum.map(1..8, &String.duplicate("optional-#{&1} ", 80)),
            retention: :useful
          )
        ],
        input_token_budget: 160
      )

    degraded =
      ContextBudget.pack(
        [
          ContextBudget.section(:current_request, String.duplicate("required-overflow ", 2_000), retention: :required),
          ContextBudget.section(:semantic_context, ["optional context"], retention: :useful)
        ],
        input_token_budget: 160
      )

    assert trimmed.summary.state == "trimmed"
    refute trimmed.summary.degraded?
    assert trimmed.summary.remediation =~ "Optional context was trimmed"

    assert degraded.summary.state == "degraded"
    assert degraded.summary.degraded?
    assert degraded.summary.remediation =~ "Required context exceeded"
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
      source: "phase_88_test",
      title: "Phase 88 test conversation",
      objective: "Verify context budget observability.",
      initiating_actor: %{"id" => "phase-88"},
      source_metadata: %{},
      conversation_metadata: %{},
      started_at: now,
      last_activity_at: now
    }
  end

  defp graph_context do
    %{
      managed_repo_id: "repo-88-provenance",
      workspace_path: "/tmp/repo-88-provenance",
      revision_metadata: %{current_revision: "rev-phase-88"}
    }
  end

  defp managed_repo_and_work_item_fixture!(suffix) do
    {_project, managed_repo} = managed_repo_fixture!(suffix)
    work_item = work_item_fixture!(managed_repo, "phase88-#{suffix}")

    on_exit(fn ->
      _ = AgentWorkspace.shutdown_kernel(managed_repo.id)
    end)

    {managed_repo, work_item}
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-eighty-eight-#{suffix}",
        github_full_name: "owner/phase-eighty-eight-#{suffix}",
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
        "jido-code-phase-eighty-eight-#{suffix}-#{System.unique_integer([:positive])}"
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
