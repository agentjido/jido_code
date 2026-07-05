defmodule JidoCode.Orchestration.RunActions do
  @moduledoc """
  Store-backed commands for governed run operator actions.
  """

  alias JidoCode.Orchestration.{RecordStore, Run, RunBridge, WorkflowRun}

  @approval_action_error_type "workflow_run_approval_action_failed"
  @retry_action_error_type "workflow_run_retry_action_failed"
  @approval_resume_step "resume_execution"
  @retry_initial_step "queued"
  @retryable_terminal_statuses [:failed, :cancelled]

  @spec approve(Run.t(), map() | nil) :: {:ok, Run.t()} | {:error, map()}
  def approve(run, params \\ nil)

  def approve(%Run{} = run, params) do
    params = normalize_map(params)

    if status(run) == :awaiting_approval do
      approved_at = params |> map_get(:approved_at) |> normalize_datetime()
      actor = params |> map_get(:actor, %{}) |> normalize_map()
      current_step = params |> map_get(:current_step, @approval_resume_step) |> normalize_string(@approval_resume_step)

      transition_run(
        run,
        :running,
        current_step,
        approved_at,
        %{"approval_decision" => approval_decision(actor, approved_at)}
      )
    else
      {:error,
       action_failure(
         @approval_action_error_type,
         "run_not_awaiting_approval",
         "Governed run is not awaiting approval.",
         "Reload run detail and retry once the run is awaiting approval."
       )}
    end
  end

  def approve(_run, _params), do: invalid_run(@approval_action_error_type, "approved")

  @spec reject(Run.t(), map() | nil) :: {:ok, Run.t()} | {:error, map()}
  def reject(run, params \\ nil)

  def reject(%Run{} = run, params) do
    params = normalize_map(params)

    if status(run) == :awaiting_approval do
      rejected_at = params |> map_get(:rejected_at) |> normalize_datetime()
      actor = params |> map_get(:actor, %{}) |> normalize_map()
      rationale = params |> map_get(:rationale) |> normalize_optional_string()
      current_step = run.current_step |> normalize_string("approval_gate")

      transition_run(
        run,
        :cancelled,
        current_step,
        rejected_at,
        %{
          "approval_decision" =>
            %{
              "decision" => "rejected",
              "actor" => actor,
              "rationale" => rationale,
              "timestamp" => DateTime.to_iso8601(rejected_at)
            }
            |> reject_nil_values()
        }
      )
    else
      {:error,
       action_failure(
         @approval_action_error_type,
         "run_not_awaiting_approval",
         "Governed run is not awaiting approval.",
         "Reload run detail and retry once the run is awaiting approval."
       )}
    end
  end

  def reject(_run, _params), do: invalid_run(@approval_action_error_type, "rejected")

  @spec retry(Run.t(), map() | nil) :: {:ok, Run.t()} | {:error, map()}
  def retry(run, params \\ nil)

  def retry(%Run{} = run, params) do
    params = normalize_map(params)

    if status(run) in @retryable_terminal_statuses do
      retry_started_at = params |> map_get(:retry_started_at) |> normalize_datetime()
      create_retry_run(run, @retry_initial_step, retry_started_at, "full_run")
    else
      {:error,
       action_failure(
         @retry_action_error_type,
         "run_not_retryable",
         "Governed run is not in a retryable terminal state.",
         "Reload run detail and retry once the run has failed or been cancelled."
       )}
    end
  end

  def retry(_run, _params), do: invalid_run(@retry_action_error_type, "retried")

  @spec retry_step(Run.t(), map() | nil) :: {:ok, Run.t()} | {:error, map()}
  def retry_step(run, params \\ nil)

  def retry_step(%Run{} = run, params) do
    params = normalize_map(params)

    with :ok <- retryable_status(run),
         {:ok, contract} <- step_retry_contract(run),
         retry_step <- contract |> map_get(:retry_step) |> normalize_string(@retry_initial_step),
         retry_started_at <- params |> map_get(:retry_started_at) |> normalize_datetime() do
      create_retry_run(run, retry_step, retry_started_at, "step_level")
    end
  end

  def retry_step(_run, _params), do: invalid_run(@retry_action_error_type, "retried")

  @spec step_retry_contract(Run.t()) :: {:ok, map()} | {:error, map()}
  def step_retry_contract(%Run{} = run) do
    contract =
      run
      |> workflow_audit()
      |> map_get(:step_retry_contract, %{})
      |> normalize_map()

    case contract |> map_get(:retry_step) |> normalize_optional_string() do
      nil ->
        {:error,
         action_failure(
           @retry_action_error_type,
           "step_retry_unavailable",
           "Step-level retry is not available for this governed run.",
           "Reload run detail and retry once failure context includes a retryable step."
         )}

      _retry_step ->
        {:ok, contract}
    end
  end

  def step_retry_contract(_run), do: invalid_run(@retry_action_error_type, "retried")

  defp transition_run(%Run{} = run, to_status, current_step, transitioned_at, transition_metadata) do
    audit = workflow_audit(run)

    status_transitions =
      audit
      |> map_get(:status_transitions, [])
      |> normalize_list()
      |> Kernel.++([
        %{
          "from_status" => run.status |> normalize_optional_string(),
          "to_status" => to_status |> normalize_optional_string(),
          "current_step" => current_step,
          "transitioned_at" => DateTime.to_iso8601(transitioned_at),
          "metadata" => transition_metadata
        }
        |> reject_nil_values()
      ])

    step_results =
      audit
      |> map_get(:step_results, %{})
      |> normalize_map()
      |> capture_approval_decision(to_status, transition_metadata)

    error =
      audit
      |> map_get(:error, %{})
      |> normalize_map()

    workflow_attrs =
      run
      |> workflow_run_attrs()
      |> Map.merge(%{
        status: to_status,
        current_step: current_step,
        status_transitions: status_transitions,
        step_results: step_results,
        error: error,
        completed_at: completed_at(to_status, transitioned_at)
      })

    run_metadata =
      run.run_metadata
      |> normalize_map()
      |> put_in(["workflow_audit"], %{
        "status_transitions" => status_transitions,
        "step_results" => step_results,
        "error" => error,
        "step_retry_contract" => audit |> map_get(:step_retry_contract, %{}) |> normalize_map()
      })

    run_attrs =
      run
      |> Map.from_struct()
      |> Map.merge(%{
        status: to_status,
        current_step: current_step,
        run_metadata: run_metadata,
        completed_at: completed_at(to_status, transitioned_at)
      })

    with {:ok, %WorkflowRun{} = workflow_run} <- RecordStore.upsert_workflow_run_compatibility(workflow_attrs),
         {:ok, %Run{}} <- RecordStore.upsert_run(run_attrs),
         {:ok, %Run{} = projected_run} <- RunBridge.sync_workflow_run(workflow_run) do
      {:ok, projected_run}
    end
  end

  defp create_retry_run(%Run{} = run, retry_step, retry_started_at, retry_policy) do
    retry_attempt = normalize_positive_integer(run.retry_attempt, 1) + 1
    run_id = generated_run_id()

    workflow_attrs =
      run
      |> workflow_run_attrs()
      |> Map.drop([:workflow_run_id, :id])
      |> Map.merge(%{
        run_id: run_id,
        status: :pending,
        current_step: retry_step,
        started_at: retry_started_at,
        completed_at: nil,
        retry_of_run_id: run.run_id,
        retry_attempt: retry_attempt,
        retry_lineage: retry_lineage(run, retry_policy, retry_step)
      })

    with {:ok, %WorkflowRun{} = workflow_run} <- RecordStore.upsert_workflow_run_compatibility(workflow_attrs),
         {:ok, %Run{} = retried_run} <- RunBridge.sync_workflow_run(workflow_run) do
      {:ok, retried_run}
    end
  end

  defp retryable_status(%Run{} = run) do
    if status(run) in @retryable_terminal_statuses do
      :ok
    else
      {:error,
       action_failure(
         @retry_action_error_type,
         "run_not_retryable",
         "Governed run is not in a retryable terminal state.",
         "Reload run detail and retry once the run has failed or been cancelled."
       )}
    end
  end

  defp workflow_run_attrs(%Run{} = run) do
    audit = workflow_audit(run)

    %{
      workflow_run_id: run.workflow_run_id,
      id: run.workflow_run_id,
      managed_repo_id: run.managed_repo_id,
      project_id: run.legacy_project_id,
      run_id: run.run_id,
      workflow_name: run.workflow_name,
      workflow_version: run.workflow_version,
      status: run.status,
      trigger: normalize_map(run.trigger),
      inputs: normalize_map(run.inputs),
      input_metadata: normalize_map(run.input_metadata),
      initiating_actor: normalize_map(run.initiating_actor),
      current_step: run.current_step,
      status_transitions: audit |> map_get(:status_transitions, []) |> normalize_list(),
      step_results: audit |> map_get(:step_results, %{}) |> normalize_map(),
      error: audit |> map_get(:error, %{}) |> normalize_map(),
      retry_of_run_id: run.retry_of_run_id,
      retry_attempt: run.retry_attempt,
      retry_lineage: normalize_list(run.retry_lineage),
      started_at: run.started_at,
      completed_at: run.completed_at
    }
  end

  defp workflow_audit(%Run{} = run) do
    run.run_metadata
    |> normalize_map()
    |> map_get(:workflow_audit, %{})
    |> normalize_map()
  end

  defp capture_approval_decision(step_results, :running, transition_metadata) do
    approval_decision =
      transition_metadata
      |> map_get(:approval_decision, %{})
      |> normalize_map()

    if map_size(approval_decision) == 0 do
      step_results
    else
      approval_decisions =
        step_results
        |> map_get(:approval_decisions, [])
        |> normalize_list()

      step_results
      |> Map.put("approval_decision", approval_decision)
      |> Map.put("approval_decisions", approval_decisions ++ [approval_decision])
    end
  end

  defp capture_approval_decision(step_results, _to_status, _transition_metadata), do: step_results

  defp approval_decision(actor, approved_at) do
    %{
      "decision" => "approved",
      "actor" => actor,
      "timestamp" => DateTime.to_iso8601(approved_at)
    }
  end

  defp retry_lineage(%Run{} = run, retry_policy, retry_step) do
    run.retry_lineage
    |> normalize_list()
    |> Kernel.++([
      %{
        "run_id" => run.run_id,
        "retry_policy" => retry_policy,
        "retry_step" => retry_step,
        "status" => run.status |> normalize_optional_string()
      }
      |> reject_nil_values()
    ])
  end

  defp completed_at(to_status, transitioned_at) when to_status in [:completed, :failed, :cancelled], do: transitioned_at
  defp completed_at(_to_status, _transitioned_at), do: nil

  defp status(%Run{status: status}) when is_atom(status), do: status
  defp status(%Run{status: "awaiting_approval"}), do: :awaiting_approval
  defp status(%Run{status: "failed"}), do: :failed
  defp status(%Run{status: "cancelled"}), do: :cancelled
  defp status(%Run{status: "completed"}), do: :completed
  defp status(%Run{status: "running"}), do: :running
  defp status(%Run{status: "pending"}), do: :pending
  defp status(_run), do: :unknown

  defp invalid_run(error_type, verb) do
    {:error,
     action_failure(
       error_type,
       "invalid_run",
       "Governed run reference is invalid and cannot be #{verb}.",
       "Reload run detail and retry."
     )}
  end

  defp action_failure(error_type, reason_type, detail, remediation, reason \\ nil) do
    %{
      "error_type" => error_type,
      "reason_type" => reason_type,
      "detail" => detail,
      "remediation" => remediation,
      "reason" => inspect(reason),
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    |> reject_nil_values()
  end

  defp reject_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      if is_nil(value), do: acc, else: Map.put(acc, key, value)
    end)
  end

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(_value), do: []

  defp map_get(map, key, default \\ nil)
  defp map_get(%{} = map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp normalize_string(value, default), do: normalize_optional_string(value) || default

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

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp normalize_datetime(_value), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default

  defp generated_run_id, do: "run-#{System.unique_integer([:positive, :monotonic])}"
end
