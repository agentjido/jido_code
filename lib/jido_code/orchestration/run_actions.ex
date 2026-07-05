defmodule JidoCode.Orchestration.RunActions do
  @moduledoc """
  Store-backed commands for governed run operator actions.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.GitHub.IssueCommentClient
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

    cond do
      status(run) != :awaiting_approval ->
        {:error,
         action_failure(
           @approval_action_error_type,
           "approve_run",
           "run_not_awaiting_approval",
           "Governed run is not awaiting approval.",
           "Reload run detail and retry once the run is awaiting approval."
         )}

      approval_context_blocked?(run) ->
        {:error,
         action_failure(
           @approval_action_error_type,
           "approve_run",
           "approval_context_blocked",
           "Run approval context generation failed and the run cannot be approved safely.",
           "Regenerate the approval payload with a diff summary, test summary, and risk notes before approving."
         )}

      issue_triage_run?(run) ->
        approve_issue_triage_run(run, params)

      true ->
        approved_at = params |> map_get(:approved_at) |> normalize_datetime()
        actor = params |> map_get(:actor, %{}) |> normalize_actor_map()

        current_step =
          params |> map_get(:current_step, @approval_resume_step) |> normalize_string(@approval_resume_step)

        transition_run(
          run,
          :running,
          current_step,
          approved_at,
          %{"approval_decision" => approval_decision(actor, approved_at)}
        )
    end
  end

  def approve(_run, _params), do: invalid_run(@approval_action_error_type, "approved")

  @spec reject(Run.t(), map() | nil) :: {:ok, Run.t()} | {:error, map()}
  def reject(run, params \\ nil)

  def reject(%Run{} = run, params) do
    params = normalize_map(params)

    if status(run) == :awaiting_approval do
      rejected_at = params |> map_get(:rejected_at) |> normalize_datetime()
      actor = params |> map_get(:actor, %{}) |> normalize_actor_map()
      rationale = params |> map_get(:rationale) |> normalize_optional_string()
      current_step = run.current_step |> normalize_string("approval_gate")

      case rejection_route(run) do
        {:retry_route, retry_step} ->
          transition_run(
            run,
            :running,
            retry_step,
            rejected_at,
            %{
              "approval_decision" =>
                %{
                  "decision" => "rejected",
                  "actor" => actor,
                  "rationale" => rationale,
                  "timestamp" => DateTime.to_iso8601(rejected_at),
                  "outcome" => "retry_route",
                  "retry_step" => retry_step
                }
                |> reject_nil_values()
            }
          )

        {:error, :invalid_retry_route} ->
          {:error,
           action_failure(
             @approval_action_error_type,
             "reject_run",
             "policy_invalid",
             "Approval rejection retry route is invalid because it does not name a retry step.",
             "Fix the retry rejection policy before rejecting this run."
           )}

        :cancel ->
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
                  "timestamp" => DateTime.to_iso8601(rejected_at),
                  "outcome" => "cancelled"
                }
                |> reject_nil_values()
            }
          )
      end
    else
      {:error,
       action_failure(
         @approval_action_error_type,
         "reject_run",
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

    cond do
      status(run) not in @retryable_terminal_statuses ->
        {:error,
         action_failure(
           @retry_action_error_type,
           "retry_run",
           "run_not_retryable",
           "Governed run is not in a retryable terminal state.",
           "Reload run detail and retry once the run has failed or been cancelled."
         )}

      full_run_retry_disallowed?(run) ->
        policy = run |> retry_policy() |> normalize_map()

        {:error,
         action_failure(
           @retry_action_error_type,
           "retry_run",
           "policy_violation",
           "Full-run retry is disallowed by this workflow retry policy.",
           "Use a step-level retry or update the workflow retry policy.",
           nil,
           %{policy: policy}
         )}

      true ->
        retry_started_at = params |> map_get(:retry_started_at) |> normalize_datetime()
        create_retry_run(run, @retry_initial_step, retry_started_at, "full_run", params)
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
      create_retry_run(run, retry_step, retry_started_at, "step_level", params)
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
      |> merge_retry_policy_contract(run.trigger)

    case contract |> map_get(:retry_step) |> normalize_optional_string() do
      nil ->
        {:error,
         action_failure(
           @retry_action_error_type,
           "retry_step",
           "policy_violation",
           "This workflow does not declare step retry capability.",
           "Enable step-level retry in the workflow contract or use full-run retry.",
           nil,
           %{policy: retry_policy(run)}
         )}

      _retry_step ->
        {:ok, contract}
    end
  end

  def step_retry_contract(_run), do: invalid_run(@retry_action_error_type, "retried")

  defp transition_run(%Run{} = run, to_status, current_step, transitioned_at, transition_metadata) do
    with {:ok, %WorkflowRun{} = workflow_run} <- workflow_run_for_run(run),
         {:ok, %WorkflowRun{} = transitioned} <-
           WorkflowRun.transition_status(
             workflow_run,
             %{
               to_status: to_status,
               current_step: current_step,
               transitioned_at: transitioned_at,
               transition_metadata: transition_metadata
             },
             actor: Actor.operator_actor()
           ),
         {:ok, %Run{} = projected_run} <- RunBridge.projected_run_for_workflow_run(transitioned) do
      {:ok, projected_run}
    end
  end

  defp create_retry_run(%Run{} = run, retry_step, retry_started_at, retry_policy, params) do
    retry_attempt = normalize_positive_integer(run.retry_attempt, 1) + 1
    run_id = "#{run.run_id}-retry-#{retry_attempt}"
    retry_actor = params |> map_get(:actor, %{}) |> normalize_actor_map()

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
        initiating_actor: retry_actor,
        retry_of_run_id: run.run_id,
        retry_attempt: retry_attempt,
        retry_lineage: retry_lineage(run, retry_policy, retry_step, retry_actor),
        step_results: retry_step_results(run, retry_policy, retry_step, retry_attempt)
      })

    with {:ok, %WorkflowRun{} = workflow_run} <- WorkflowRun.create(workflow_attrs),
         {:ok, %Run{} = retried_run} <- RunBridge.projected_run_for_workflow_run(workflow_run) do
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
         "retry_step",
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

  defp workflow_run_for_run(%Run{} = run) do
    case RecordStore.get_run_by_workflow_run_id(run.workflow_run_id) do
      {:ok, %Run{} = persisted_run} ->
        persisted_run
        |> workflow_run_attrs()
        |> RecordStore.upsert_workflow_run_compatibility()

      {:ok, nil} ->
        run
        |> workflow_run_attrs()
        |> RecordStore.upsert_workflow_run_compatibility()

      {:error, _reason} ->
        run
        |> workflow_run_attrs()
        |> RecordStore.upsert_workflow_run_compatibility()
    end
  end

  defp approval_context_blocked?(%Run{} = run) do
    audit = workflow_audit(run)
    step_results = audit |> map_get(:step_results, %{}) |> normalize_map()
    error = audit |> map_get(:error, %{}) |> normalize_map()

    diagnostics =
      error
      |> map_get(:approval_context_diagnostics, [])
      |> normalize_list()

    diagnostics != [] or present?(step_results |> map_get(:approval_context_generation_error))
  end

  defp issue_triage_run?(%Run{} = run), do: normalize_optional_string(run.workflow_name) == "issue_triage"

  defp approve_issue_triage_run(%Run{} = run, params) do
    approved_at = params |> map_get(:approved_at) |> normalize_datetime()
    actor = params |> map_get(:actor, %{}) |> normalize_actor_map()
    decision = approval_decision(actor, approved_at)

    with {:ok, %Run{} = running_run} <-
           transition_run(
             run,
             :running,
             "post_github_comment",
             approved_at,
             %{"approval_decision" => decision}
           ),
         {:ok, %WorkflowRun{} = workflow_run} <- workflow_run_for_run(running_run) do
      case issue_triage_post_request(workflow_run) do
        {:ok, post_request} ->
          post_issue_triage_response(running_run, workflow_run, post_request, decision, approved_at)

        {:error, typed_failure} ->
          fail_issue_triage_post(running_run, workflow_run, typed_failure, decision, approved_at)
      end
    end
  end

  defp post_issue_triage_response(run, workflow_run, post_request, decision, approved_at) do
    case safe_invoke_issue_triage_response_poster(post_request) do
      {:ok, post_result} ->
        artifact = issue_triage_post_artifact_success(post_result, workflow_run, decision, approved_at)

        transition_run(
          run,
          :completed,
          "post_github_comment",
          approved_at,
          %{"post_issue_response" => artifact}
        )

      {:error, reason} ->
        typed_failure = normalize_issue_triage_post_failure(reason, workflow_run)
        fail_issue_triage_post(run, workflow_run, typed_failure, decision, approved_at)
    end
  end

  defp fail_issue_triage_post(run, workflow_run, typed_failure, decision, approved_at) do
    typed_failure = normalize_issue_triage_post_failure(typed_failure, workflow_run)
    artifact = issue_triage_post_artifact_failure(typed_failure, workflow_run, decision, approved_at)

    transition_run(
      run,
      :failed,
      "post_github_comment",
      approved_at,
      %{"post_issue_response" => artifact, "failure_context" => typed_failure}
    )
  end

  defp issue_triage_post_request(%WorkflowRun{} = workflow_run) do
    step_results = normalize_map(workflow_run.step_results)

    proposed_response =
      step_results
      |> map_get(:compose_issue_response, %{})
      |> normalize_map()
      |> map_get(:proposed_response)
      |> normalize_optional_string()

    issue_number =
      workflow_run
      |> issue_triage_source_issue()
      |> map_get(:number)
      |> normalize_optional_positive_integer() ||
        workflow_run
        |> issue_triage_issue_reference()
        |> parse_issue_reference_issue_number()

    repo_full_name = resolve_issue_triage_repo_full_name(workflow_run)

    cond do
      is_nil(repo_full_name) ->
        {:error, issue_triage_post_failure("GitHub repository reference is missing from run metadata.", workflow_run)}

      is_nil(issue_number) ->
        {:error, issue_triage_post_failure("Issue number is missing from run metadata.", workflow_run)}

      is_nil(proposed_response) ->
        {:error, issue_triage_post_failure("Proposed response artifact is missing and cannot be posted.", workflow_run)}

      true ->
        {:ok,
         %{
           repo_full_name: repo_full_name,
           issue_number: issue_number,
           body: proposed_response
         }}
    end
  end

  defp safe_invoke_issue_triage_response_poster(post_request) when is_map(post_request) do
    poster =
      Application.get_env(
        :jido_code,
        :issue_triage_response_poster,
        &IssueCommentClient.post_issue_comment/1
      )

    try do
      case poster.(post_request) do
        {:ok, post_result} when is_map(post_result) ->
          {:ok, post_result}

        {:error, typed_failure} when is_map(typed_failure) ->
          {:error, typed_failure}

        other ->
          {:error,
           issue_triage_post_failure(
             "Issue Bot response poster returned invalid result #{inspect(other)}.",
             nil
           )}
      end
    rescue
      exception ->
        {:error,
         issue_triage_post_failure(
           "Issue Bot response poster crashed (#{Exception.message(exception)}).",
           nil
         )}
    catch
      kind, reason ->
        {:error,
         issue_triage_post_failure(
           "Issue Bot response poster threw #{inspect({kind, reason})}.",
           nil
         )}
    end
  end

  defp issue_triage_post_artifact_success(post_result, workflow_run, decision, approved_at) do
    %{
      "status" => "posted",
      "provider" => "github",
      "posted" => true,
      "approval_mode" => issue_triage_post_mode_label(workflow_run),
      "approval_decision" => decision |> map_get(:decision) |> normalize_optional_string(),
      "comment_url" =>
        post_result
        |> map_get(:comment_url, map_get(post_result, :html_url))
        |> normalize_optional_string(),
      "comment_api_url" =>
        post_result
        |> map_get(:comment_api_url, map_get(post_result, :url))
        |> normalize_optional_string(),
      "comment_id" =>
        post_result
        |> map_get(:comment_id, map_get(post_result, :id))
        |> normalize_optional_positive_integer(),
      "posted_at" =>
        post_result
        |> map_get(:posted_at, map_get(post_result, :created_at))
        |> normalize_optional_string() || DateTime.to_iso8601(approved_at),
      "issue_reference" => issue_triage_issue_reference(workflow_run),
      "source_issue" => issue_triage_source_issue(workflow_run),
      "repo_full_name" => resolve_issue_triage_repo_full_name(workflow_run)
    }
    |> reject_nil_values()
  end

  defp issue_triage_post_artifact_failure(typed_failure, workflow_run, decision, approved_at) do
    %{
      "status" => "failed",
      "provider" => "github",
      "posted" => false,
      "approval_mode" => issue_triage_post_mode_label(workflow_run),
      "approval_decision" => decision |> map_get(:decision) |> normalize_optional_string(),
      "attempted_at" => DateTime.to_iso8601(approved_at),
      "issue_reference" => issue_triage_issue_reference(workflow_run),
      "source_issue" => issue_triage_source_issue(workflow_run),
      "repo_full_name" => resolve_issue_triage_repo_full_name(workflow_run),
      "typed_failure" => string_key_map(typed_failure)
    }
    |> reject_nil_values()
  end

  defp issue_triage_post_failure(detail, %WorkflowRun{} = workflow_run) do
    %{
      "error_type" => "issue_triage_response_post_failed",
      "reason_type" => "provider_error",
      "operation" => "post_issue_triage_response",
      "detail" => detail,
      "remediation" => "Inspect GitHub issue posting credentials and retry posting the approved response.",
      "failed_step" => "post_github_comment",
      "last_successful_step" => "compose_issue_response",
      "run_id" => workflow_run.run_id,
      "issue_reference" => issue_triage_issue_reference(workflow_run),
      "source_issue" => issue_triage_source_issue(workflow_run),
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    |> reject_nil_values()
  end

  defp issue_triage_post_failure(detail, _workflow_run) do
    %{
      "error_type" => "issue_triage_response_post_failed",
      "reason_type" => "provider_error",
      "operation" => "post_issue_triage_response",
      "detail" => detail,
      "remediation" => "Inspect GitHub issue posting credentials and retry posting the approved response.",
      "failed_step" => "post_github_comment",
      "last_successful_step" => "compose_issue_response",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp normalize_issue_triage_post_failure(failure_reason, workflow_run) when is_map(failure_reason) do
    %{
      "error_type" =>
        failure_reason
        |> map_get(:error_type, "issue_triage_response_post_failed")
        |> normalize_optional_string() || "issue_triage_response_post_failed",
      "reason_type" =>
        failure_reason
        |> map_get(:reason_type, "provider_error")
        |> normalize_issue_triage_reason_type(),
      "operation" => "post_issue_triage_response",
      "detail" =>
        failure_reason
        |> map_get(:detail, "Issue Bot could not post the approved response to GitHub.")
        |> normalize_optional_string() || "Issue Bot could not post the approved response to GitHub.",
      "remediation" =>
        failure_reason
        |> map_get(:remediation, "Inspect GitHub issue posting credentials and retry posting the approved response.")
        |> normalize_optional_string() ||
          "Inspect GitHub issue posting credentials and retry posting the approved response.",
      "failed_step" => "post_github_comment",
      "last_successful_step" => "compose_issue_response",
      "run_id" => workflow_run && workflow_run.run_id,
      "issue_reference" => workflow_run && issue_triage_issue_reference(workflow_run),
      "source_issue" => workflow_run && issue_triage_source_issue(workflow_run),
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    |> reject_nil_values()
  end

  defp normalize_issue_triage_post_failure(_failure_reason, workflow_run),
    do: issue_triage_post_failure("Issue Bot could not post the approved response to GitHub.", workflow_run)

  defp normalize_issue_triage_reason_type(reason_type) do
    case normalize_optional_string(reason_type) do
      "authentication" -> "auth_error"
      "auth" -> "auth_error"
      "authorization" -> "auth_error"
      nil -> "provider_error"
      other -> other
    end
  end

  defp issue_triage_post_mode_label(%WorkflowRun{} = workflow_run) do
    policy =
      workflow_run.trigger
      |> normalize_map()
      |> map_get(:approval_policy, %{})
      |> normalize_map()

    cond do
      map_get(policy, :auto_post) == true ->
        "auto_post"

      normalize_optional_string(map_get(policy, :mode)) in ["auto_post", "auto-post"] ->
        "auto_post"

      true ->
        "approval_required"
    end
  end

  defp issue_triage_issue_reference(%WorkflowRun{} = workflow_run) do
    workflow_run.inputs
    |> normalize_map()
    |> map_get(:issue_reference)
    |> normalize_optional_string()
  end

  defp issue_triage_source_issue(%WorkflowRun{} = workflow_run) do
    workflow_run.trigger
    |> normalize_map()
    |> map_get(:source_issue, %{})
    |> normalize_map()
  end

  defp resolve_issue_triage_repo_full_name(%WorkflowRun{} = workflow_run) do
    source_row_repo =
      workflow_run.trigger
      |> normalize_map()
      |> map_get(:source_row, %{})
      |> normalize_map()
      |> map_get(:project_github_full_name)
      |> normalize_optional_string()

    source_row_repo || workflow_run |> issue_triage_issue_reference() |> parse_issue_reference_repo_full_name()
  end

  defp parse_issue_reference_repo_full_name(issue_reference) when is_binary(issue_reference) do
    case String.split(issue_reference, "#", parts: 2) do
      [repo_full_name, _number] -> normalize_optional_string(repo_full_name)
      _other -> nil
    end
  end

  defp parse_issue_reference_repo_full_name(_issue_reference), do: nil

  defp parse_issue_reference_issue_number(issue_reference) when is_binary(issue_reference) do
    case String.split(issue_reference, "#", parts: 2) do
      [_repo, number] -> normalize_optional_positive_integer(number)
      _other -> nil
    end
  end

  defp parse_issue_reference_issue_number(_issue_reference), do: nil

  defp rejection_route(%Run{} = run) do
    on_reject =
      run.trigger
      |> normalize_map()
      |> map_get(:approval_policy, %{})
      |> normalize_map()
      |> map_get(:on_reject, %{})
      |> normalize_map()

    case on_reject |> map_get(:action) |> normalize_optional_string() do
      "retry_route" ->
        case on_reject |> map_get(:retry_step) |> normalize_optional_string() do
          nil -> {:error, :invalid_retry_route}
          retry_step -> {:retry_route, retry_step}
        end

      _other ->
        :cancel
    end
  end

  defp approval_decision(actor, approved_at) do
    %{
      "decision" => "approved",
      "actor" => actor,
      "timestamp" => DateTime.to_iso8601(approved_at)
    }
  end

  defp retry_policy(%Run{} = run) do
    run.trigger
    |> normalize_map()
    |> map_get(:retry_policy, %{})
    |> normalize_map()
  end

  defp full_run_retry_disallowed?(%Run{} = run), do: retry_policy(run) |> map_get(:full_run) == false

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

  defp retry_step_results(%Run{} = run, retry_policy, retry_step, retry_attempt) do
    run
    |> workflow_audit()
    |> map_get(:step_results, %{})
    |> normalize_map()
    |> Map.put("retry_context", %{
      "policy" => retry_policy,
      "retry_of_run_id" => run.run_id,
      "retry_attempt" => retry_attempt,
      "retry_step" => retry_step
    })
  end

  defp retry_lineage(%Run{} = run, retry_policy, retry_step, retry_actor) do
    audit = workflow_audit(run)
    step_results = audit |> map_get(:step_results, %{}) |> normalize_map()
    error = audit |> map_get(:error, %{}) |> normalize_map()

    run.retry_lineage
    |> normalize_list()
    |> Kernel.++([
      %{
        "run_id" => run.run_id,
        "retry_policy" => retry_policy,
        "retry_step" => retry_step,
        "status" => run.status |> normalize_optional_string(),
        "failure_artifacts" => step_results,
        "typed_failure" => error,
        "retry_actor" => retry_actor
      }
      |> reject_nil_values()
    ])
  end

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
       "invalid_run",
       "Governed run reference is invalid and cannot be #{verb}.",
       "Reload run detail and retry."
     )}
  end

  defp action_failure(error_type, operation, reason_type, detail, remediation, reason \\ nil, extra \\ %{}) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    string_payload =
      %{
        "error_type" => error_type,
        "operation" => operation,
        "reason_type" => reason_type,
        "detail" => detail,
        "remediation" => remediation,
        "reason" => reason && inspect(reason),
        "timestamp" => timestamp
      }
      |> Map.merge(extra |> normalize_map() |> string_key_map())
      |> reject_nil_values()

    atom_payload =
      Enum.reduce(string_payload, %{}, fn {key, value}, acc ->
        case existing_atom_key(key) do
          nil -> acc
          atom_key -> Map.put(acc, atom_key, value)
        end
      end)

    Map.merge(string_payload, atom_payload)
  end

  defp existing_atom_key(key) do
    key
    |> normalize_optional_string()
    |> case do
      nil -> nil
      string_key -> String.to_existing_atom(string_key)
    end
  rescue
    ArgumentError -> nil
  end

  defp reject_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      if is_nil(value), do: acc, else: Map.put(acc, key, value)
    end)
  end

  defp string_key_map(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_optional_string(key) || inspect(key), value)
    end)
  end

  defp string_key_map(_value), do: %{}

  defp normalize_actor_map(value) do
    actor = value |> normalize_map() |> string_key_map()

    case Actor.class(actor) do
      nil -> actor
      actor_class -> Map.put(actor, "actor_class", Atom.to_string(actor_class))
    end
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

  defp normalize_optional_string(value) when value in [nil, nil], do: nil

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_optional_positive_integer(value) when is_binary(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp normalize_optional_positive_integer(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp normalize_datetime(_value), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default

  defp present?(value) when value in [nil, ""], do: false
  defp present?(_value), do: true
end
