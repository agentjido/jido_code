defmodule JidoCode.PhaseNinetySixIntegrationTest do
  # covers: architecture.context_management_pod.context_lifecycle_is_observable
  # covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory
  # covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata
  use ExUnit.Case, async: true

  alias JidoCode.ContextManagement
  alias JidoCode.Conversations.{Conversation, Event, Snapshot, Turn}

  @raw_sentinel "PHASE-96-RAW-CONTEXT-SENTINEL"

  test "context-management status exposes automatic compaction lifecycle metadata" do
    metadata = base_metadata()

    assert %{"state" => "healthy", "reason" => "within_budget"} =
             metadata
             |> ContextManagement.status_summary()
             |> Map.fetch!("auto_compaction_lifecycle")

    disabled_status =
      "repo-96"
      |> ContextManagement.initial_metadata("work-96", "/tmp/workspace", "coding-pod-work-96",
        auto_compaction_enabled?: false
      )
      |> ContextManagement.status_summary()

    assert get_in(disabled_status, ["auto_compaction_lifecycle", "state"]) == "skipped"
    assert get_in(disabled_status, ["auto_compaction_lifecycle", "reason"]) == "auto_compaction_disabled"
    assert get_in(disabled_status, ["auto_compaction_lifecycle", "remediation"])

    assert {:ok, recommended} = ContextManagement.add_observation(metadata, high_water_observation())

    recommendation_lifecycle =
      recommended
      |> ContextManagement.status_summary()
      |> Map.fetch!("auto_compaction_lifecycle")

    assert recommendation_lifecycle["state"] == "recommended"
    assert recommendation_lifecycle["recommendation_id"] == recommended.latest_monitor_decision["id"]
    assert recommendation_lifecycle["debounce_key"] == recommended.latest_monitor_decision["debounce_key"]
    assert recommendation_lifecycle["policy_id"] == "context-management:v1"

    assert {:ok, compacted} =
             ContextManagement.add_summary(recommended, %{
               managed_repo_id: "repo-96",
               work_item_id: "work-96",
               workflow: :execute,
               specialist_role: :coder,
               summary_text: "Bounded summary of older implementation context.",
               source_span_ids: ["turn:older", "tool:older"]
             })

    compacted_status = ContextManagement.status_summary(compacted)
    compacted_lifecycle = compacted_status["auto_compaction_lifecycle"]

    assert compacted_lifecycle["state"] == "compacted"
    assert compacted_lifecycle["summary_id"] == get_in(compacted_status, ["latest_compaction", "id"])
    assert compacted_lifecycle["active_summary_ids"] == [compacted_lifecycle["summary_id"]]
    assert compacted_lifecycle["source_span_count"] == 2

    failed =
      Map.merge(
        compacted,
        ContextManagement.compaction_failure_metadata(
          {:provider_failed, %{raw_tool_output: @raw_sentinel}},
          %{source_span_ids: ["turn:older"]}
        )
      )

    failed_status = ContextManagement.status_summary(failed)
    failed_lifecycle = failed_status["auto_compaction_lifecycle"]

    assert failed_lifecycle["state"] == "degraded"
    assert failed_lifecycle["source_span_count"] == 1
    assert failed_lifecycle["remediation"]
    refute inspect(failed_status, limit: :infinity) =~ @raw_sentinel
    refute inspect(failed_status, limit: :infinity) =~ "raw_tool_output"
  end

  test "conversation snapshots expose pending, deferred, compacted, and degraded lifecycle states" do
    pending_snapshot =
      state_with_turns(
        [
          turn("turn-older", :completed, "older context #{@raw_sentinel}"),
          turn("turn-active", :completed, "active request")
        ],
        pending_context_compaction: pending_compaction()
      )
      |> Snapshot.from_state()

    assert pending_snapshot.context_compaction_lifecycle["state"] == "pending"
    assert pending_snapshot.context_compaction_lifecycle["recommendation_id"] == "recommendation-96"
    refute inspect(pending_snapshot.context_compaction_lifecycle, limit: :infinity) =~ @raw_sentinel

    deferred_snapshot =
      state_with_turns(
        [
          turn("turn-older", :completed, "older context #{@raw_sentinel}"),
          turn("turn-active", :running, "active request")
        ],
        active_turn_id: "turn-active",
        pending_context_compaction: pending_compaction()
      )
      |> Snapshot.from_state()

    assert deferred_snapshot.context_compaction_lifecycle["state"] == "deferred"
    assert deferred_snapshot.context_compaction_lifecycle["child_work_id"] == "child-96"
    refute inspect(deferred_snapshot.context_compaction_lifecycle, limit: :infinity) =~ @raw_sentinel

    reset_event =
      Event.new("conversation-96", 1, "conversation.context_compacted", %{
        payload: %{
          "summary_id" => "summary-96",
          "recommendation_id" => "recommendation-96",
          "debounce_key" => "work-96:execute:coder:history_high_water_mark:turn-older",
          "source_span_ids" => ["turn:turn-older"],
          "policy_id" => "context-management:v1",
          "workflow" => "execute",
          "specialist_role" => "coder",
          "reset_sequence" => 1
        }
      })

    compacted_snapshot =
      state_with_turns(
        [
          turn("turn-older", :completed, "older context #{@raw_sentinel}"),
          turn("turn-active", :completed, "active request")
        ],
        events: [reset_event],
        event_sequence: 1
      )
      |> Snapshot.from_state()

    assert compacted_snapshot.context_compaction_lifecycle["state"] == "compacted"
    assert compacted_snapshot.context_compaction_lifecycle["summary_id"] == "summary-96"
    assert compacted_snapshot.context_compaction_lifecycle["reset_sequence"] == 1
    assert compacted_snapshot.context_compaction_lifecycle["source_span_count"] == 1
    assert compacted_snapshot.shared_context["latest_context_reset"]["summary_id"] == "summary-96"
    refute inspect(compacted_snapshot.context_compaction_lifecycle, limit: :infinity) =~ @raw_sentinel
    refute inspect(compacted_snapshot.shared_context, limit: :infinity) =~ @raw_sentinel

    failure_event =
      Event.new("conversation-96", 1, "conversation.context_compaction_failed", %{
        payload: %{
          "recommendation_id" => "recommendation-96",
          "debounce_key" => "work-96:execute:coder:history_high_water_mark:turn-older",
          "policy_id" => "context-management:v1",
          "workflow" => "execute",
          "specialist_role" => "coder",
          "turn_id" => "turn-active",
          "child_work_id" => "child-96",
          "reason" => ContextManagement.safe_failure_reason({:failed, %{raw_prompt: @raw_sentinel}}),
          "retryable?" => true
        }
      })

    degraded_snapshot =
      state_with_turns(
        [
          turn("turn-older", :completed, "older context #{@raw_sentinel}"),
          turn("turn-active", :completed, "active request")
        ],
        events: [failure_event],
        event_sequence: 1
      )
      |> Snapshot.from_state()

    assert degraded_snapshot.context_compaction_lifecycle["state"] == "degraded"
    assert degraded_snapshot.context_compaction_lifecycle["retryable?"]
    assert degraded_snapshot.context_compaction_lifecycle["event_sequence"] == 1

    assert degraded_snapshot.shared_context["latest_context_compaction_failure"]["recommendation_id"] ==
             "recommendation-96"

    refute inspect(degraded_snapshot.context_compaction_lifecycle, limit: :infinity) =~ @raw_sentinel
    refute inspect(degraded_snapshot.context_compaction_lifecycle, limit: :infinity) =~ "raw_prompt"
  end

  defp base_metadata do
    ContextManagement.initial_metadata(
      "repo-96",
      "work-96",
      "/tmp/workspace",
      "coding-pod-work-96"
    )
  end

  defp high_water_observation do
    %{
      managed_repo_id: "repo-96",
      work_item_id: "work-96",
      workflow: :execute,
      specialist_role: :coder,
      conversation_id: "conversation-96",
      turn_id: "turn-active",
      context_budget: %{
        "policy_id" => "context-budget:v1",
        "state" => "packed",
        "model_budget" => 1_000,
        "estimated_input_tokens" => 900,
        "diagnostics" => []
      }
    }
  end

  defp pending_compaction do
    %{
      "state" => "pending",
      "recommendation_id" => "recommendation-96",
      "debounce_key" => "work-96:execute:coder:history_high_water_mark:turn-older",
      "workflow" => "execute",
      "specialist_role" => "coder",
      "policy_id" => "context-management:v1",
      "reason" => "history_high_water_mark",
      "turn_id" => "turn-active",
      "child_work_id" => "child-96"
    }
  end

  defp state_with_turns(turns, opts) do
    events = Keyword.get(opts, :events, [])

    %{
      conversation: conversation_struct(),
      status: :active,
      admission_paused: false,
      child_execution_paused: false,
      active_turn_id: Keyword.get(opts, :active_turn_id),
      work_queue: [],
      turns: Map.new(turns, &{&1.id, &1}),
      turn_order: Enum.map(turns, & &1.id),
      control_history: [],
      child_works: %{},
      child_work_order: [],
      child_worker_pids: %{},
      pending_context_compaction: Keyword.get(opts, :pending_context_compaction),
      event_sequence: Keyword.get(opts, :event_sequence, length(events)),
      events: events
    }
  end

  defp conversation_struct do
    %Conversation{
      id: "conversation-96",
      managed_repo_id: "repo-96",
      work_item_id: "work-96",
      status: :active,
      scope: :work_item_scoped,
      attachment_mode: :existing_work_item,
      source: "phase_96_test",
      objective: "Keep automatic compaction observable.",
      conversation_metadata: %{},
      source_metadata: %{}
    }
  end

  defp turn(id, state, instruction) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Turn{
      id: id,
      conversation_id: "conversation-96",
      command_id: "command-#{id}",
      command_type: "turn.submit",
      state: state,
      payload: %{"instruction" => instruction},
      inserted_at: now,
      completed_at: if(state == :completed, do: now)
    }
  end
end
