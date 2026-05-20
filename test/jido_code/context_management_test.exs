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
end
