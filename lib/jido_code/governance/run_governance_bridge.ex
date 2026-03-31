defmodule JidoCode.Governance.RunGovernanceBridge do
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  # covers: architecture.run_governance.decision_records_capture_governance_outcomes
  # covers: architecture.run_governance.review_policy_controls_change_request_creation
  # covers: architecture.run_governance.blocked_review_context_preserves_typed_remediation
  # covers: architecture.repo_posture.governed_turn_evidence_can_inform_posture
  @moduledoc """
  Projects governed run review artifacts from workflow-run audit data.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Governance.{ChangeRequest, Decision, Evidence, PolicyBridge, PostureBridge}
  alias JidoCode.Orchestration.{Run, WorkflowRun}

  @projection_actor Actor.factory_system_actor()

  @spec sync_run(Run.t(), WorkflowRun.t()) :: {:ok, map()} | {:error, term()}
  def sync_run(%Run{} = run, %WorkflowRun{} = workflow_run) do
    with {:ok, evidence_records} <- sync_evidence(run, workflow_run),
         {:ok, change_request} <- sync_change_request(run, workflow_run, evidence_records),
         {:ok, decision} <- sync_decision(run, workflow_run, change_request, evidence_records),
         :ok <- sync_repo_posture(run.managed_repo_id) do
      {:ok,
       %{
         evidence: evidence_records,
         change_request: change_request,
         decision: decision
       }}
    end
  end

  def sync_run(_run, _workflow_run), do: {:error, :invalid_run_projection}

  defp sync_evidence(run, workflow_run) do
    evidence_entries(workflow_run)
    |> Enum.reduce_while({:ok, []}, fn evidence_entry, {:ok, acc} ->
      case Evidence.upsert_for_run(evidence_attrs(run, evidence_entry), actor: @projection_actor) do
        {:ok, evidence} -> {:cont, {:ok, [evidence | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, evidence_records} -> {:ok, Enum.reverse(evidence_records)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_change_request(run, workflow_run, evidence_records) do
    with true <- should_track_change_request?(run, workflow_run),
         latest_decision <- latest_decision_payload(workflow_run),
         attrs <- change_request_attrs(run, workflow_run, evidence_records, latest_decision),
         {:ok, change_request} <- ChangeRequest.upsert_for_run(attrs, actor: @projection_actor) do
      {:ok, change_request}
    else
      false -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_decision(run, workflow_run, change_request, evidence_records) do
    case latest_decision_payload(workflow_run) do
      nil ->
        {:ok, nil}

      decision_payload ->
        attrs =
          decision_attrs(
            run,
            workflow_run,
            decision_payload,
            change_request,
            Enum.map(evidence_records, & &1.id)
          )

        Decision.upsert_for_run(attrs, actor: @projection_actor)
    end
  end

  defp evidence_entries(workflow_run) do
    step_results = normalize_map(workflow_run.step_results)
    error = normalize_map(workflow_run.error)

    []
    |> maybe_add_summary_entry(
      "diff_summary",
      "diff_summary",
      Map.get(step_results, "diff_summary"),
      "workflow_run.step_results"
    )
    |> maybe_add_summary_entry(
      "test_summary",
      "test_summary",
      Map.get(step_results, "test_summary"),
      "workflow_run.step_results"
    )
    |> maybe_add_list_entry(
      "risk_notes",
      "risk_notes",
      Map.get(step_results, "risk_notes"),
      "workflow_run.step_results"
    )
    |> maybe_add_map_entry(
      "coding_turn_summary",
      "coding_turn_summary",
      Map.get(step_results, "coding_turn_summary"),
      "workflow_run.step_results"
    )
    |> maybe_add_map_entry(
      "coding_turn_review",
      "coding_turn_review",
      Map.get(step_results, "coding_turn_review"),
      "workflow_run.step_results"
    )
    |> maybe_add_list_entry(
      "coding_turn_artifacts",
      "coding_turn_artifacts",
      Map.get(step_results, "coding_turn_artifacts"),
      "workflow_run.step_results"
    )
    |> maybe_add_map_entry(
      "approval_context",
      "approval_context",
      Map.get(step_results, "approval_context"),
      "workflow_run.step_results"
    )
    |> maybe_add_map_entry(
      "issue_response_post",
      "issue_response_post",
      Map.get(step_results, "post_issue_response"),
      "workflow_run.step_results"
    )
    |> maybe_add_map_entry(
      "failure_context",
      "failure_context",
      error,
      "workflow_run.error"
    )
    |> maybe_add_list_entry(
      "event_channel_diagnostics",
      "diagnostics",
      Map.get(error, "event_channel_diagnostics"),
      "workflow_run.error"
    )
    |> maybe_add_list_entry(
      "approval_context_diagnostics",
      "diagnostics",
      Map.get(error, "approval_context_diagnostics"),
      "workflow_run.error"
    )
  end

  defp evidence_attrs(run, evidence_entry) do
    %{
      run_id: run.id,
      managed_repo_id: run.managed_repo_id,
      key: Map.fetch!(evidence_entry, :key),
      evidence_type: Map.fetch!(evidence_entry, :evidence_type),
      summary: Map.fetch!(evidence_entry, :summary),
      evidence_details: Map.fetch!(evidence_entry, :evidence_details),
      source: Map.fetch!(evidence_entry, :source),
      recorded_at: Map.fetch!(evidence_entry, :recorded_at)
    }
    |> maybe_put(:work_item_id, run.work_item_id)
  end

  defp should_track_change_request?(run, workflow_run) do
    review_policy = review_policy_for_run(run)

    review_policy_requires_change_request?(review_policy) and
      (run.status == :awaiting_approval or not is_nil(latest_decision_payload(workflow_run)))
  end

  defp change_request_attrs(run, workflow_run, evidence_records, latest_decision) do
    evidence_ids = Enum.map(evidence_records, & &1.id)
    requested_at = awaiting_approval_timestamp(workflow_run) || run.started_at
    review_policy = review_policy_for_run(run)
    blocking_diagnostic = review_blocking_diagnostic(workflow_run, review_policy)

    {status, resolved_at} =
      case normalize_decision(latest_decision) do
        :approve -> {:approved, decision_timestamp(latest_decision)}
        :reject -> {:rejected, decision_timestamp(latest_decision)}
        :defer -> {:deferred, decision_timestamp(latest_decision)}
        nil -> {:open, nil}
      end

    %{
      run_id: run.id,
      managed_repo_id: run.managed_repo_id,
      status: status,
      summary: "Review #{run.workflow_name} run #{run.run_id}",
      review_context: %{
        "workflow_name" => run.workflow_name,
        "current_step" => run.current_step,
        "approval_context" => workflow_run.step_results |> normalize_map() |> Map.get("approval_context", %{}),
        "coding_turn_review" => coding_turn_review(workflow_run),
        "evidence_keys" => Enum.map(evidence_records, & &1.key)
      },
      request_metadata: %{
        "trigger" => normalize_map(run.trigger),
        "run_status" => Atom.to_string(run.status),
        "review_policy" => review_policy,
        "review_blocked" => not is_nil(blocking_diagnostic),
        "public_turn" => public_turn_summary(workflow_run)
      },
      evidence_ids: evidence_ids,
      requested_at: requested_at,
      resolved_at: resolved_at
    }
    |> maybe_put(:work_item_id, run.work_item_id)
    |> put_in_review_context_if_present("blocking_diagnostic", blocking_diagnostic)
  end

  defp decision_attrs(run, workflow_run, decision_payload, change_request, evidence_ids) do
    decision_timestamp = decision_timestamp(decision_payload) || run.completed_at || run.started_at
    normalized_decision = normalize_decision(decision_payload)

    %{
      decision_key: "#{run.id}:#{normalized_decision}:#{DateTime.to_iso8601(decision_timestamp)}",
      run_id: run.id,
      managed_repo_id: run.managed_repo_id,
      decision: normalized_decision,
      actor:
        decision_payload
        |> normalize_map()
        |> Map.get("actor", %{})
        |> normalize_map(),
      rationale:
        decision_payload
        |> normalize_map()
        |> Map.get("rationale")
        |> normalize_optional_string(),
      evidence_ids: evidence_ids,
      decision_metadata:
        normalize_map(decision_payload)
        |> Map.put("coding_turn_summary", public_turn_summary(workflow_run))
        |> Map.put("coding_turn_review", coding_turn_review(workflow_run)),
      decided_at: decision_timestamp
    }
    |> maybe_put(:work_item_id, run.work_item_id)
    |> maybe_put(:change_request_id, change_request && change_request.id)
  end

  defp latest_decision_payload(workflow_run) do
    step_results = normalize_map(workflow_run.step_results)

    decision_history =
      step_results
      |> Map.get("approval_decisions", [])
      |> normalize_map_list()

    case List.last(decision_history) || normalize_map(Map.get(step_results, "approval_decision")) do
      map when map_size(map) == 0 -> nil
      map -> map
    end
  end

  defp awaiting_approval_timestamp(workflow_run) do
    workflow_run.status_transitions
    |> normalize_map_list()
    |> Enum.reverse()
    |> Enum.find_value(fn transition ->
      if Map.get(transition, "to_status") == "awaiting_approval" do
        transition
        |> Map.get("transitioned_at")
        |> parse_iso8601()
      end
    end)
  end

  defp decision_timestamp(nil), do: nil

  defp decision_timestamp(decision_payload) do
    decision_payload
    |> normalize_map()
    |> Map.get("timestamp")
    |> parse_iso8601()
  end

  defp normalize_decision(nil), do: nil

  defp normalize_decision(decision_payload) do
    case decision_payload |> normalize_map() |> Map.get("decision") |> normalize_optional_string() do
      "approved" -> :approve
      "auto_approved" -> :approve
      "rejected" -> :reject
      "deferred" -> :defer
      _other -> nil
    end
  end

  defp maybe_add_summary_entry(entries, _key, _type, value, _source)
       when not is_binary(value) or value == "" do
    entries
  end

  defp maybe_add_summary_entry(entries, key, evidence_type, value, source) do
    [
      %{
        key: key,
        evidence_type: evidence_type,
        summary: value,
        evidence_details: %{"value" => value},
        source: source,
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      | entries
    ]
  end

  defp maybe_add_list_entry(entries, _key, _type, value, _source) when not is_list(value) or value == [] do
    entries
  end

  defp maybe_add_list_entry(entries, key, evidence_type, value, source) do
    [
      %{
        key: key,
        evidence_type: evidence_type,
        summary: "#{length(value)} #{String.replace(evidence_type, "_", " ")} item(s) captured.",
        evidence_details: %{"items" => value},
        source: source,
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      | entries
    ]
  end

  defp maybe_add_map_entry(entries, _key, _type, value, _source) when not is_map(value) or value == %{} do
    entries
  end

  defp maybe_add_map_entry(entries, key, evidence_type, value, source) do
    summary =
      value
      |> normalize_map()
      |> Map.get("detail")
      |> normalize_optional_string() ||
        "#{String.capitalize(String.replace(key, "_", " "))} captured."

    [
      %{
        key: key,
        evidence_type: evidence_type,
        summary: summary,
        evidence_details: normalize_map(value),
        source: source,
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      | entries
    ]
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp put_in_review_context_if_present(attrs, _key, nil), do: attrs

  defp put_in_review_context_if_present(attrs, key, value) do
    review_context =
      attrs
      |> Map.get(:review_context, %{})
      |> Map.put(key, value)

    Map.put(attrs, :review_context, review_context)
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_map_list(value) when is_list(value) do
    Enum.map(value, &normalize_map/1)
  end

  defp normalize_map_list(_value), do: []

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp public_turn_summary(workflow_run) do
    workflow_run
    |> step_results_map()
    |> Map.get("coding_turn_summary", %{})
    |> normalize_map()
  end

  defp coding_turn_review(workflow_run) do
    workflow_run
    |> step_results_map()
    |> Map.get("coding_turn_review", %{})
    |> normalize_map()
  end

  defp step_results_map(workflow_run) do
    workflow_run
    |> Map.get(:step_results, %{})
    |> normalize_map()
  end

  defp parse_iso8601(nil), do: nil

  defp parse_iso8601(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> timestamp
      _other -> nil
    end
  end

  defp parse_iso8601(_value), do: nil

  defp sync_repo_posture(managed_repo_id) when is_binary(managed_repo_id) do
    case PostureBridge.sync_managed_repo_id(managed_repo_id) do
      {:ok, _result} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp sync_repo_posture(_managed_repo_id), do: :ok

  defp review_policy_for_run(run) do
    case PolicyBridge.review_policy_for_managed_repo(run.managed_repo_id) do
      {:ok, review_policy} -> review_policy
      _other -> PolicyBridge.default_review_policy()
    end
  end

  defp review_policy_requires_change_request?(review_policy) do
    review_policy
    |> normalize_map()
    |> Map.get("change_request_required", true)
  end

  defp review_blocking_diagnostic(workflow_run, review_policy) do
    normalized_review_policy = normalize_map(review_policy)
    step_results = normalize_map(workflow_run.step_results)
    error = normalize_map(workflow_run.error)

    cond do
      not review_policy_requires_change_request?(normalized_review_policy) ->
        nil

      is_map(Map.get(step_results, "approval_context")) and map_size(Map.get(step_results, "approval_context")) > 0 ->
        nil

      true ->
        error
        |> Map.get("approval_context_diagnostics", [])
        |> List.first()
        |> normalize_map()
        |> case do
          diagnostic when map_size(diagnostic) > 0 ->
            diagnostic

          _other ->
            %{
              "error_type" => "approval_context_missing",
              "detail" => "Approval context is required before human review can proceed.",
              "remediation" => "Generate diff summary, test summary, and risk notes before awaiting approval.",
              "required_stage" => Map.get(normalized_review_policy, "required_stage", "approval")
            }
        end
    end
  end
end
