defmodule JidoCode.ContextManagementTest do
  # covers: architecture.context_management_pod.compaction_store_is_product_owned
  # covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata
  use ExUnit.Case, async: true

  alias JidoCode.ContextManagement

  test "compaction summaries require scoped metadata and bounded source span ids" do
    assert {:ok, summary} =
             ContextManagement.compaction_summary(%{
               managed_repo_id: "repo-89",
               work_item_id: "work-89",
               workflow: :execute,
               specialist_role: :coder,
               summary_text: "Implemented the parser through a bounded helper.",
               source_span_ids: ["turn-1", "tool-group-2"]
             })

    assert summary.managed_repo_id == "repo-89"
    assert summary.work_item_id == "work-89"
    assert summary.workflow == "execute"
    assert summary.specialist_role == "coder"
    assert summary.retention == :important
    assert summary.source_span_ids == ["turn-1", "tool-group-2"]
    assert summary.summary_estimate.approximate_tokens > 0
  end

  test "compaction summaries reject raw prompt or tool output metadata" do
    assert {:error, :raw_context_metadata_rejected} =
             ContextManagement.compaction_summary(%{
               managed_repo_id: "repo-89",
               work_item_id: "work-89",
               workflow: :review,
               specialist_role: :reviewer,
               summary_text: "Reviewed the bounded change.",
               source_span_ids: ["turn-1"],
               diagnostics: %{raw_prompt: "do not store this"}
             })
  end

  test "summary store supersedes older summaries for the same source span" do
    base_metadata =
      ContextManagement.initial_metadata(
        "repo-89",
        "work-89",
        "/tmp/workspace",
        "coding-pod-work-89"
      )

    assert {:ok, first_metadata} =
             ContextManagement.add_summary(base_metadata, %{
               managed_repo_id: "repo-89",
               work_item_id: "work-89",
               workflow: :execute,
               specialist_role: :coder,
               summary_text: "First compact summary.",
               source_span_ids: ["turn-1", "tool-group-2"]
             })

    assert {:ok, second_metadata} =
             ContextManagement.add_summary(first_metadata, %{
               managed_repo_id: "repo-89",
               work_item_id: "work-89",
               workflow: :execute,
               specialist_role: :coder,
               summary_text: "Replacement compact summary.",
               source_span_ids: ["tool-group-2", "turn-1"]
             })

    active = ContextManagement.active_summaries(second_metadata)
    assert length(active) == 1
    assert hd(active)["summary_text"] == "Replacement compact summary."

    [first, second] = second_metadata.summaries
    assert first["superseded_at"]
    refute second["superseded_at"]
    assert second_metadata.latest_compaction.source_span_count == 2
  end

  test "disabled status is explicit and independent from context budget policy" do
    status =
      "Context management disabled for this request."
      |> ContextManagement.disabled_metadata()
      |> ContextManagement.status_summary()

    assert status["enabled?"] == false
    assert status["state"] == "disabled"
    assert get_in(status, ["latest_monitor_decision", "state"]) == "skipped"
  end

  test "invalid context-management tuning is reported as degraded diagnostics" do
    policy = ContextManagement.policy(high_water_mark: "not-a-number", repeated_trim_threshold: -1)

    assert policy.enabled?
    assert Enum.count(policy.diagnostics, &(&1.kind == :invalid_context_management_config)) == 2
  end

  test "budget monitor recommends compaction at the high-water mark" do
    metadata =
      ContextManagement.initial_metadata(
        "repo-90",
        "work-90",
        "/tmp/workspace",
        "coding-pod-work-90",
        high_water_mark: 0.75
      )

    assert {:ok, updated} =
             ContextManagement.add_observation(metadata, %{
               managed_repo_id: "repo-90",
               work_item_id: "work-90",
               workflow: :execute,
               specialist_role: :coder,
               context_budget: %{
                 "policy_id" => "context-budget:v1",
                 "state" => "packed",
                 "model_budget" => 1_000,
                 "estimated_input_tokens" => 800,
                 "diagnostics" => []
               }
             })

    assert updated.context_management_status == :recommend_compaction
    assert updated.latest_monitor_decision["state"] == "recommend"
    assert updated.latest_monitor_decision["reason"] == "history_high_water_mark"
    assert length(updated.recommendations) == 1
  end

  test "budget monitor debounces repeated trim recommendations for unchanged spans" do
    metadata =
      ContextManagement.initial_metadata(
        "repo-90",
        "work-90",
        "/tmp/workspace",
        "coding-pod-work-90",
        repeated_trim_threshold: 2
      )

    observation = %{
      managed_repo_id: "repo-90",
      work_item_id: "work-90",
      workflow: :review,
      specialist_role: :reviewer,
      context_budget: trimmed_budget(),
      diagnostics: %{source_span_ids: ["span-a", "span-b"]}
    }

    assert {:ok, first} = ContextManagement.add_observation(metadata, observation)
    assert {:ok, second} = ContextManagement.add_observation(first, observation)
    assert {:ok, third} = ContextManagement.add_observation(second, observation)

    assert third.latest_monitor_decision["state"] == "recommend"
    assert third.latest_monitor_decision["debounced?"]
    assert length(third.recommendations) == 1
  end

  test "budget monitor blocks compaction for required overflow and unresolved tool groups" do
    metadata =
      ContextManagement.initial_metadata(
        "repo-90",
        "work-90",
        "/tmp/workspace",
        "coding-pod-work-90"
      )

    assert {:ok, required_overflow} =
             ContextManagement.add_observation(metadata, %{
               managed_repo_id: "repo-90",
               work_item_id: "work-90",
               workflow: :plan,
               specialist_role: :planner,
               context_budget: %{
                 "policy_id" => "context-budget:v1",
                 "state" => "degraded",
                 "degraded?" => true,
                 "model_budget" => 100,
                 "estimated_input_tokens" => 250,
                 "diagnostics" => [
                   %{"kind" => "current_request", "retention" => "required", "state" => "degraded"}
                 ]
               }
             })

    assert required_overflow.context_management_status == :blocked
    assert required_overflow.latest_monitor_decision["reason"] == "required_context_overflow"

    assert {:ok, unresolved_tool_group} =
             ContextManagement.add_observation(metadata, %{
               managed_repo_id: "repo-90",
               work_item_id: "work-90",
               workflow: :execute,
               specialist_role: :coder,
               context_budget: trimmed_budget(),
               diagnostics: %{"unresolved_tool_call_group?" => true}
             })

    assert unresolved_tool_group.context_management_status == :blocked
    assert unresolved_tool_group.latest_monitor_decision["reason"] == "unresolved_tool_call_group"
  end

  test "compaction candidate selection preserves assistant tool-result groups and excludes active tail" do
    messages = [
      %{id: "system-1", role: "system", content: "system prompt"},
      %{id: "user-1", role: "user", content: "older request"},
      %{id: "assistant-1", role: "assistant", content: "calling tool", tool_calls: [%{id: "tool-1"}]},
      %{id: "tool-1", role: "tool", content: "bounded tool result"},
      %{id: "user-2", role: "user", content: "active request"}
    ]

    assert {:ok, candidate} =
             ContextManagement.compaction_candidate(messages, %{
               managed_repo_id: "repo-91",
               work_item_id: "work-91",
               workflow: :execute,
               specialist_role: :coder
             })

    assert candidate.eligible?
    assert candidate.source_span_ids == ["user-1", "assistant-1..tool-1"]
    assert candidate.source_text =~ "user: older request"
    assert candidate.source_text =~ "assistant: calling tool"
    assert candidate.source_text =~ "tool: bounded tool result"
    refute candidate.source_text =~ "active request"
  end

  test "compaction candidate selection blocks unresolved tool groups" do
    messages = [
      %{id: "user-1", role: "user", content: "older request"},
      %{id: "assistant-1", role: "assistant", content: "calling tool", tool_calls: [%{id: "tool-1"}]},
      %{id: "user-2", role: "user", content: "active request"}
    ]

    assert {:ok, candidate} =
             ContextManagement.compaction_candidate(messages, %{
               managed_repo_id: "repo-91",
               work_item_id: "work-91",
               workflow: :execute,
               specialist_role: :coder
             })

    refute candidate.eligible?
    assert candidate.diagnostics.reason == :unresolved_tool_call_group
  end

  defp trimmed_budget do
    %{
      "policy_id" => "context-budget:v1",
      "state" => "trimmed",
      "model_budget" => 1_000,
      "estimated_input_tokens" => 500,
      "diagnostics" => [
        %{"kind" => "conversation_history", "state" => "trimmed", "dropped_entries" => 2}
      ]
    }
  end
end
