defmodule JidoCode.Orchestration.WorkflowRun do
  # covers: architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Control.Actor
  alias JidoCode.Orchestration.{RecordStore, Run, RunActions, RunBridge, RunPubSub}

  @retry_action_error_type "workflow_run_retry_action_failed"
  @allowed_actor_classes [:admin, :operator, :factory_system, :managed_repo_orchestrator, :run_worker]

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ [])

  def create(attrs, opts) when is_map(attrs) do
    with :ok <- authorize(opts),
         attrs <- normalize_create_attrs(attrs),
         {:ok, %__MODULE__{} = workflow_run} <- RecordStore.upsert_workflow_run_compatibility(attrs, opts),
         {:ok, %__MODULE__{} = workflow_run} <- publish_lifecycle_events(workflow_run, ["run_started"], opts),
         {:ok, _run} <- RunBridge.sync_workflow_run(workflow_run) do
      {:ok, workflow_run}
    end
  end

  def create(_attrs, _opts), do: {:error, :invalid_workflow_run_attrs}

  @spec transition_status(t(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def transition_status(workflow_run, attrs, opts \\ [])

  def transition_status(%__MODULE__{} = workflow_run, attrs, opts) when is_map(attrs) do
    with :ok <- authorize(opts),
         {:ok, transitioned} <- transition_workflow_run(workflow_run, attrs, opts),
         {:ok, transitioned} <-
           publish_lifecycle_events(transitioned, lifecycle_events(workflow_run, transitioned), opts),
         {:ok, _run} <- RunBridge.sync_workflow_run(transitioned) do
      {:ok, transitioned}
    end
  end

  def transition_status(_workflow_run, _attrs, _opts), do: {:error, :invalid_workflow_run}

  @spec get_by_project_and_run_id(map() | keyword(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_project_and_run_id(params, opts \\ []) do
    filters =
      params
      |> normalize_map()
      |> Map.take([:project_id, :run_id])
      |> normalize_workflow_filters()

    case read(Keyword.merge([query: [filter: filters, limit: 1]], opts)) do
      {:ok, [workflow_run | _rest]} -> {:ok, workflow_run}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec read(keyword()) :: {:ok, [t()]} | {:error, term()}
  def read(opts \\ []) when is_list(opts) do
    query = Keyword.get(opts, :query, [])
    filters = query |> query_filters() |> normalize_workflow_filters()
    query = put_query_filters(query, filters)

    case RecordStore.list_workflow_runs(filters, Keyword.put(opts, :query, query)) do
      {:ok, workflow_runs} -> {:ok, workflow_runs}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec approve(t(), map() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def approve(workflow_run, params \\ nil, opts \\ [])

  def approve(%__MODULE__{} = workflow_run, params, opts) do
    with {:ok, run} <- run_for_workflow_run(workflow_run),
         {:ok, %Run{} = approved_run} <- RunActions.approve(run, params),
         {:ok, approved_workflow_run} <-
           get_by_project_and_run_id(%{project_id: approved_run.legacy_project_id, run_id: approved_run.run_id}, opts) do
      {:ok, approved_workflow_run}
    end
  end

  def approve(_workflow_run, _params, _opts), do: {:error, :invalid_workflow_run}

  @spec reject(t(), map() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def reject(workflow_run, params \\ nil, opts \\ [])

  def reject(%__MODULE__{} = workflow_run, params, opts) do
    with {:ok, run} <- run_for_workflow_run(workflow_run),
         {:ok, %Run{} = rejected_run} <- RunActions.reject(run, params),
         {:ok, rejected_workflow_run} <-
           get_by_project_and_run_id(%{project_id: rejected_run.legacy_project_id, run_id: rejected_run.run_id}, opts) do
      {:ok, rejected_workflow_run}
    end
  end

  def reject(_workflow_run, _params, _opts), do: {:error, :invalid_workflow_run}

  @spec retry(t(), map() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def retry(workflow_run, params \\ nil, opts \\ [])

  def retry(%__MODULE__{} = workflow_run, params, opts) do
    with {:ok, run} <- run_for_workflow_run(workflow_run),
         {:ok, %Run{} = retry_run} <- RunActions.retry(run, params),
         {:ok, retried_workflow_run} <-
           get_by_project_and_run_id(%{project_id: retry_run.legacy_project_id, run_id: retry_run.run_id}, opts) do
      {:ok, retried_workflow_run}
    end
  end

  def retry(_workflow_run, _params, _opts), do: {:error, :invalid_workflow_run}

  @spec retry_step(t(), map() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def retry_step(workflow_run, params \\ nil, opts \\ [])

  def retry_step(%__MODULE__{} = workflow_run, params, opts) do
    with {:ok, run} <- run_for_workflow_run(workflow_run),
         {:ok, %Run{} = retry_run} <- RunActions.retry_step(run, params),
         {:ok, retried_workflow_run} <-
           get_by_project_and_run_id(%{project_id: retry_run.legacy_project_id, run_id: retry_run.run_id}, opts) do
      {:ok, retried_workflow_run}
    end
  end

  def retry_step(_workflow_run, _params, _opts), do: {:error, :invalid_workflow_run}

  @spec step_retry_contract(t()) :: {:ok, map()} | {:error, map()}
  def step_retry_contract(%__MODULE__{} = run) do
    contract =
      run.step_results
      |> normalize_map()
      |> map_get(:step_retry_contract, %{})
      |> normalize_map()
      |> merge_retry_policy_contract(run.trigger)

    case contract |> map_get(:retry_step) |> normalize_optional_string() do
      nil ->
        {:error,
         action_failure(
           "step_retry_unavailable",
           "Step-level retry is not available for this workflow run.",
           "Refresh run projections and retry once failure context includes a retryable step."
         )}

      _retry_step ->
        {:ok, contract}
    end
  end

  def step_retry_contract(_run) do
    {:error,
     action_failure(
       "invalid_run",
       "Run reference is invalid and step-level retry contract cannot be resolved.",
       "Reload run detail and retry once the failed run is available."
     )}
  end

  defp action_failure(reason_type, detail, remediation) do
    %{
      "error_type" => @retry_action_error_type,
      "reason_type" => reason_type,
      "detail" => detail,
      "remediation" => remediation,
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp authorize(opts) do
    if Actor.allowed?(Keyword.get(opts, :actor), @allowed_actor_classes) do
      :ok
    else
      {:error, forbidden_error()}
    end
  end

  defp normalize_create_attrs(attrs) do
    now = attrs |> map_get(:started_at) |> normalize_datetime()
    status = attrs |> map_get(:status, :pending) |> normalize_status()
    current_step = attrs |> map_get(:current_step, "queued") |> normalize_string("queued")

    attrs
    |> normalize_map()
    |> Map.put_new(:workflow_run_id, attrs |> map_get(:id) |> normalize_optional_string() || JidoCode.UUID.generate())
    |> Map.put_new(:status, status)
    |> Map.put_new(:current_step, current_step)
    |> Map.put_new(:started_at, now)
    |> Map.put_new(:status_transitions, [
      transition_entry(nil, status, current_step, now, %{})
    ])
  end

  defp transition_workflow_run(%__MODULE__{} = workflow_run, attrs, opts) do
    attrs = normalize_map(attrs)
    to_status = attrs |> map_get(:to_status, workflow_run.status) |> normalize_status()

    current_step =
      attrs |> map_get(:current_step, workflow_run.current_step) |> normalize_string(workflow_run.current_step)

    transitioned_at = attrs |> map_get(:transitioned_at) |> normalize_datetime()
    transition_metadata = attrs |> map_get(:transition_metadata, %{}) |> normalize_map()

    if allowed_transition?(workflow_run.status, to_status) do
      status_transitions =
        workflow_run.status_transitions
        |> normalize_list()
        |> Kernel.++([
          transition_entry(workflow_run.status, to_status, current_step, transitioned_at, transition_metadata)
        ])

      step_results =
        workflow_run.step_results
        |> normalize_map()
        |> capture_step_artifacts(to_status, transition_metadata)
        |> capture_approval_context(to_status)
        |> capture_approval_decision(transition_metadata)

      error =
        workflow_run.error
        |> normalize_map()
        |> capture_approval_context_diagnostics(step_results, to_status)
        |> capture_failure_context(to_status, workflow_run.current_step, current_step, transition_metadata)

      workflow_run
      |> Map.from_struct()
      |> Map.merge(%{
        status: to_status,
        current_step: current_step,
        status_transitions: status_transitions,
        step_results: step_results,
        error: error,
        completed_at: completed_at(to_status, transitioned_at)
      })
      |> RecordStore.upsert_workflow_run_compatibility(opts)
    else
      {:error,
       RuntimeError.exception(
         "invalid lifecycle transition from #{normalize_optional_string(workflow_run.status)} to #{normalize_optional_string(to_status)}"
       )}
    end
  end

  defp run_for_workflow_run(%__MODULE__{} = workflow_run) do
    case RecordStore.get_run_by_workflow_run_id(workflow_run.id) do
      {:ok, %Run{} = run} -> {:ok, run}
      {:ok, nil} -> RunBridge.projected_run_for_workflow_run(workflow_run)
      {:error, reason} -> {:error, reason}
    end
  end

  defp query_filters(query) when is_list(query), do: query |> Keyword.get(:filter, %{}) |> normalize_map()
  defp query_filters(query) when is_map(query), do: query |> map_get(:filter, %{}) |> normalize_map()
  defp query_filters(_query), do: %{}

  defp put_query_filters(query, filters) when is_list(query), do: Keyword.put(query, :filter, filters)
  defp put_query_filters(query, filters) when is_map(query), do: Map.put(query, :filter, filters)
  defp put_query_filters(_query, filters), do: [filter: filters]

  defp normalize_workflow_filters(filters) do
    filters
    |> normalize_map()
    |> Enum.reduce(%{}, fn
      {:project_id, value}, acc -> Map.put(acc, :legacy_project_id, value)
      {"project_id", value}, acc -> Map.put(acc, :legacy_project_id, value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp transition_entry(from_status, to_status, current_step, transitioned_at, metadata) do
    %{
      "from_status" => normalize_optional_string(from_status),
      "to_status" => normalize_optional_string(to_status),
      "current_step" => current_step,
      "transitioned_at" => transitioned_at |> normalize_datetime() |> DateTime.to_iso8601(),
      "metadata" => normalize_map(metadata)
    }
  end

  defp allowed_transition?(status, status), do: true
  defp allowed_transition?(:pending, next_status), do: next_status in [:running, :failed, :cancelled]

  defp allowed_transition?(:running, next_status),
    do: next_status in [:awaiting_approval, :completed, :failed, :cancelled]

  defp allowed_transition?(:awaiting_approval, next_status), do: next_status in [:running, :failed, :cancelled]
  defp allowed_transition?(status, _next_status) when status in [:completed, :failed, :cancelled], do: false
  defp allowed_transition?(_status, _next_status), do: false

  defp capture_step_artifacts(step_results, :completed, metadata) do
    metadata
    |> map_get(:issue_response_post, map_get(metadata, :post_issue_response))
    |> normalize_map()
    |> case do
      artifact when map_size(artifact) > 0 -> Map.put(step_results, "post_issue_response", artifact)
      _artifact -> step_results
    end
  end

  defp capture_step_artifacts(step_results, :failed, metadata) do
    metadata
    |> map_get(:issue_response_post, map_get(metadata, :post_issue_response))
    |> normalize_map()
    |> case do
      artifact when map_size(artifact) > 0 -> Map.put(step_results, "post_issue_response", artifact)
      _artifact -> step_results
    end
  end

  defp capture_step_artifacts(step_results, _status, _metadata), do: step_results

  defp capture_approval_context(step_results, :awaiting_approval) do
    generation_error =
      step_results
      |> map_get(:approval_context_generation_error)
      |> normalize_optional_string()

    cond do
      present?(generation_error) ->
        Map.delete(step_results, "approval_context")

      step_results |> map_get(:approval_context, %{}) |> normalize_map() |> map_size() > 0 ->
        step_results

      true ->
        approval_context =
          %{
            "diff_summary" => step_results |> map_get(:diff_summary) |> normalize_optional_string(),
            "test_summary" => step_results |> map_get(:test_summary) |> normalize_optional_string(),
            "risk_notes" => step_results |> map_get(:risk_notes, []) |> normalize_list()
          }
          |> reject_empty_values()

        if map_size(approval_context) == 0 do
          step_results
        else
          Map.put(step_results, "approval_context", approval_context)
        end
    end
  end

  defp capture_approval_context(step_results, _status), do: step_results

  defp capture_approval_context_diagnostics(error, step_results, :awaiting_approval) do
    generation_error =
      step_results
      |> map_get(:approval_context_generation_error)
      |> normalize_optional_string()

    if present?(generation_error) do
      diagnostic = approval_context_diagnostic(generation_error)

      error
      |> Map.put("approval_context_diagnostics", [diagnostic])
      |> Map.put_new("error_type", diagnostic["error_type"])
      |> Map.put_new("reason_type", diagnostic["reason_type"])
      |> Map.put_new("detail", diagnostic["detail"])
      |> Map.put_new("remediation", diagnostic["remediation"])
    else
      error
    end
  end

  defp capture_approval_context_diagnostics(error, _step_results, _status), do: error

  defp approval_context_diagnostic(detail) do
    %{
      "error_type" => "approval_context_generation_failed",
      "operation" => "build_approval_context",
      "reason_type" => "approval_payload_blocked",
      "detail" => detail,
      "remediation" =>
        "Regenerate the approval payload with a diff summary, test summary, and risk notes before approving.",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp capture_approval_decision(step_results, metadata) do
    metadata
    |> map_get(:approval_decision, %{})
    |> normalize_map()
    |> case do
      decision when map_size(decision) > 0 ->
        approval_decisions =
          step_results
          |> map_get(:approval_decisions, [])
          |> normalize_list()

        step_results
        |> Map.put("approval_decision", decision)
        |> Map.put("approval_decisions", approval_decisions ++ [decision])

      _decision ->
        step_results
    end
  end

  defp capture_failure_context(error, :failed, previous_step, current_step, metadata) do
    metadata_context =
      metadata
      |> map_get(:failure_context, map_get(metadata, :typed_failure, %{}))
      |> normalize_map()

    context =
      cond do
        map_size(metadata_context) > 0 -> metadata_context
        map_size(error) > 0 -> error
        true -> %{}
      end

    missing_fields = missing_failure_context_fields(context)

    context
    |> string_key_map()
    |> Map.put_new("error_type", "workflow_run_failed")
    |> Map.put_new("reason_type", map_get(context, :error_type, "workflow_run_failed"))
    |> Map.put_new("detail", "Workflow run failed at #{current_step || previous_step || "unknown"}.")
    |> Map.put_new("remediation", "Inspect the failure context, then retry from run detail when safe.")
    |> Map.put_new("last_successful_step", "unknown")
    |> Map.put_new("timestamp", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())
    |> Map.put("failed_step", current_step || previous_step)
    |> Map.put("failure_context_complete", missing_fields == [])
    |> Map.put("missing_failure_context_fields", missing_fields)
  end

  defp capture_failure_context(error, _status, _previous_step, _current_step, _metadata), do: error

  defp missing_failure_context_fields(context) do
    Enum.reject(~w(error_type reason_type detail remediation last_successful_step), fn field ->
      context |> map_get(field) |> present?()
    end)
  end

  defp merge_retry_policy_contract(contract, trigger) do
    retry_policy =
      trigger
      |> normalize_map()
      |> map_get(:retry_policy, %{})
      |> normalize_map()

    retry_step = retry_policy |> map_get(:retry_step) |> normalize_optional_string()

    if present?(retry_step) do
      contract
      |> Map.put_new("retry_step", retry_step)
      |> Map.put_new("retry_policy", retry_policy)
    else
      contract
    end
  end

  defp publish_lifecycle_events(%__MODULE__{} = workflow_run, events, opts) do
    diagnostics =
      events
      |> normalize_list()
      |> Enum.reduce([], fn event, acc ->
        case RunPubSub.broadcast_run_event(workflow_run.run_id, event_payload(workflow_run, event)) do
          :ok -> acc
          {:error, diagnostic} when is_map(diagnostic) -> acc ++ [diagnostic]
          {:error, reason} -> acc ++ [event_publication_diagnostic(workflow_run, event, reason)]
        end
      end)

    case diagnostics do
      [] ->
        {:ok, workflow_run}

      diagnostics ->
        error =
          workflow_run.error
          |> normalize_map()
          |> append_event_channel_diagnostics(diagnostics)

        workflow_run
        |> Map.from_struct()
        |> Map.put(:error, error)
        |> RecordStore.upsert_workflow_run_compatibility(opts)
    end
  end

  defp lifecycle_events(%__MODULE__{} = previous, %__MODULE__{} = current) do
    from_status = previous.status
    to_status = current.status
    decision = current.step_results |> normalize_map() |> map_get(:approval_decision, %{}) |> normalize_map()
    decision_name = decision |> map_get(:decision) |> normalize_optional_string()

    cond do
      from_status == :pending and to_status == :running ->
        ["step_started"]

      from_status == :running and to_status == :awaiting_approval ->
        ["approval_requested"]

      from_status == :awaiting_approval and to_status == :running and decision_name == "rejected" ->
        ["approval_rejected", "step_started"]

      from_status == :awaiting_approval and to_status == :running ->
        ["approval_granted", "step_started"]

      from_status == :running and to_status == :completed ->
        ["step_completed", "run_completed"]

      from_status == :running and to_status == :failed ->
        ["step_failed", "run_failed"]

      from_status == :awaiting_approval and to_status == :failed ->
        ["approval_granted", "step_failed", "run_failed"]

      from_status == :awaiting_approval and to_status == :cancelled ->
        ["approval_rejected", "run_cancelled"]

      to_status == :cancelled ->
        ["run_cancelled"]

      true ->
        []
    end
  end

  defp event_payload(%__MODULE__{} = workflow_run, event) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      "event" => event,
      "run_id" => workflow_run.run_id,
      "workflow_run_id" => workflow_run.id,
      "project_id" => workflow_run.project_id,
      "workflow_name" => workflow_run.workflow_name,
      "workflow_version" => workflow_run.workflow_version,
      "status" => normalize_optional_string(workflow_run.status),
      "current_step" => workflow_run.current_step,
      "correlation_id" => JidoCode.UUID.generate(),
      "timestamp" => DateTime.to_iso8601(now)
    }
    |> reject_empty_values()
  end

  defp event_publication_diagnostic(%__MODULE__{} = workflow_run, event, reason) do
    %{
      "error_type" => "workflow_run_event_publication_failed",
      "channel" => "run_topic",
      "operation" => "broadcast_run_event",
      "topic" => RunPubSub.run_topic(workflow_run.run_id),
      "event" => event,
      "reason_type" => normalize_optional_string(reason) || "unknown",
      "message" => "Run topic event publication failed.",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp append_event_channel_diagnostics(error, diagnostics) do
    existing =
      error
      |> map_get(:event_channel_diagnostics, [])
      |> normalize_list()

    Map.put(error, "event_channel_diagnostics", existing ++ diagnostics)
  end

  defp string_key_map(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_optional_string(key) || inspect(key), value)
    end)
  end

  defp reject_empty_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, value}, acc when value in [nil, ""] -> acc
      {_key, value}, acc when is_list(value) and value == [] -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp completed_at(status, transitioned_at) when status in [:completed, :failed, :cancelled], do: transitioned_at
  defp completed_at(_status, _transitioned_at), do: nil

  defp normalize_status(value) when value in [:pending, :running, :awaiting_approval, :completed, :failed, :cancelled],
    do: value

  defp normalize_status(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "pending" -> :pending
      "running" -> :running
      "awaiting_approval" -> :awaiting_approval
      "completed" -> :completed
      "failed" -> :failed
      "cancelled" -> :cancelled
      _other -> :pending
    end
  end

  defp normalize_status(_value), do: :pending

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp normalize_datetime(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp normalize_datetime(value) when is_binary(value),
    do: DateTime.from_iso8601(value) |> elem(1) |> normalize_datetime()

  defp normalize_datetime(_value), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(_value), do: []

  defp present?(value) when value in [nil, ""], do: false
  defp present?(_value), do: true

  defp forbidden_error do
    %{
      type: :forbidden,
      reason: :missing_allowed_actor,
      message: "workflow-run mutation requires an allowed actor"
    }
  end

  defp normalize_map(%{} = map), do: map
  defp normalize_map(list) when is_list(list), do: Map.new(list)
  defp normalize_map(_value), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(%{} = map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when value in [nil, nil], do: nil

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
