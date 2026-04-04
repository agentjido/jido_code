defmodule JidoCode.Orchestration.RunBridge do
  # covers: architecture.run_governance.run_launch_resolves_effective_execution_profile
  # covers: architecture.execution_pipeline.run_is_projection_of_workflow_state
  # covers: architecture.execution_pipeline.legacy_workflow_state_projects_forward_without_reexecution
  # covers: architecture.execution_pipeline.public_turn_materialization_preserves_execution_authority
  # covers: architecture.run_governance.run_projection_preserves_explicit_stage_catalog
  # covers: architecture.run_governance.legacy_workflow_history_backfills_into_governed_runs
  # covers: architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence
  @moduledoc """
  Projects legacy `WorkflowRun` records into governed `Run` and `ExecutionProfile` records.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RunGovernanceBridge
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.{ExecutionProfile, Run, WorkflowRun}

  @projection_actor Actor.factory_system_actor()
  @launch_actor Actor.managed_repo_orchestrator_actor()
  @default_runic_engine "jido_runic"
  @default_repo_prep_plan ExecutionProfile.default_repo_prep_plan()
  @default_validation_plan ExecutionProfile.default_validation_plan()
  @default_governed_stages ExecutionProfile.default_governed_stages()
  @default_checkpoint_strategy ExecutionProfile.default_checkpoint_strategy()

  @type launch_result :: {:ok, %{workflow_run: WorkflowRun.t(), run: Run.t()}} | {:error, term()}
  @type turn_materialization_result ::
          {:ok, %{workflow_run: WorkflowRun.t(), run: Run.t(), work_item: WorkItem.t() | nil}}
          | {:error, term()}

  @spec projected_run_for_workflow_run(WorkflowRun.t()) :: {:ok, Run.t()} | {:error, term()}
  def projected_run_for_workflow_run(%WorkflowRun{id: workflow_run_id} = workflow_run) do
    case Run.get_by_workflow_run_id(workflow_run_id, actor: @projection_actor) do
      {:ok, %Run{} = run} -> {:ok, run}
      {:ok, nil} -> sync_workflow_run(workflow_run)
      {:error, _reason} -> sync_workflow_run(workflow_run)
    end
  end

  def projected_run_for_workflow_run(_workflow_run), do: {:error, :invalid_workflow_run}

  @spec sync_workflow_run(WorkflowRun.t()) :: {:ok, Run.t()} | {:error, term()}
  def sync_workflow_run(%WorkflowRun{} = workflow_run) do
    with {:ok, managed_repo} <- managed_repo(workflow_run),
         {:ok, execution_profile} <- resolve_execution_profile(managed_repo, workflow_run),
         attrs <- projection_attrs(workflow_run, managed_repo, execution_profile),
         {:ok, run} <- Run.upsert_projection(attrs, actor: @projection_actor),
         {:ok, _governance_projection} <- RunGovernanceBridge.sync_run(run, workflow_run) do
      {:ok, run}
    end
  end

  def sync_workflow_run(_workflow_run), do: {:error, :invalid_workflow_run}

  @spec launch_work_item(WorkItem.t(), map() | nil) :: launch_result()
  def launch_work_item(work_item, attrs \\ %{})

  def launch_work_item(%WorkItem{} = work_item, attrs) do
    attrs = if is_map(attrs), do: attrs, else: %{}

    with {:ok, managed_repo} <- managed_repo_for_work_item(work_item),
         {:ok, workflow_attrs} <- build_workflow_run_attrs(work_item, managed_repo, attrs),
         {:ok, workflow_run} <- WorkflowRun.create(workflow_attrs, actor: @launch_actor),
         {:ok, run} <- Run.get_by_workflow_run_id(workflow_run.id, actor: @launch_actor) do
      {:ok, %{workflow_run: workflow_run, run: run}}
    end
  end

  def launch_work_item(_work_item, _attrs), do: {:error, :invalid_work_item}

  @spec materialize_turn(map()) :: turn_materialization_result()
  def materialize_turn(%{} = attrs) do
    with turn_id when is_binary(turn_id) <- nested_get(attrs, [:turn, :turn_id]) || :missing_turn_id,
         project_id when is_binary(project_id) <-
           normalize_optional_string(Map.get(attrs, :project_id)) || :missing_project_id,
         managed_repo_id when is_binary(managed_repo_id) <-
           normalize_optional_string(Map.get(attrs, :managed_repo_id)) || :missing_managed_repo_id,
         {:ok, work_item} <- maybe_attach_turn_to_work_item(attrs),
         {:ok, workflow_run} <- ensure_turn_workflow_run(attrs, turn_id, project_id, managed_repo_id),
         {:ok, terminal_workflow_run} <- ensure_turn_terminal_status(workflow_run, attrs),
         {:ok, run} <- Run.get_by_workflow_run_id(terminal_workflow_run.id, actor: @launch_actor) do
      {:ok, %{workflow_run: terminal_workflow_run, run: run, work_item: work_item}}
    else
      :missing_turn_id -> {:error, :missing_turn_id}
      :missing_project_id -> {:error, :missing_project_id}
      :missing_managed_repo_id -> {:error, :missing_managed_repo_id}
      {:error, _reason} = error -> error
    end
  end

  def materialize_turn(_attrs), do: {:error, :invalid_turn_materialization}

  defp projection_attrs(workflow_run, managed_repo, execution_profile) do
    work_item_id = referenced_work_item_id(workflow_run)
    governed_stages = effective_governed_stages(execution_profile)
    current_stage = infer_current_stage(workflow_run, governed_stages)
    public_turn = public_turn_metadata(workflow_run)

    %{
      workflow_run_id: workflow_run.id,
      managed_repo_id: managed_repo.id,
      execution_profile_id: execution_profile.id,
      legacy_project_id: workflow_run.project_id,
      run_id: workflow_run.run_id,
      workflow_name: workflow_run.workflow_name,
      workflow_version: workflow_run.workflow_version,
      status: workflow_run.status,
      current_step: workflow_run.current_step,
      current_stage: current_stage,
      governed_stages: governed_stages,
      stage_statuses: stage_statuses(governed_stages, current_stage, workflow_run.status),
      trigger: normalize_map(workflow_run.trigger),
      inputs: normalize_map(workflow_run.inputs),
      input_metadata: normalize_map(workflow_run.input_metadata),
      initiating_actor: normalize_map(workflow_run.initiating_actor),
      execution_engine: @default_runic_engine,
      workflow_state_ref: %{
        "engine" => @default_runic_engine,
        "workflow_run_id" => workflow_run.id,
        "runic_workflow_name" => workflow_run.workflow_name
      },
      run_metadata: %{
        "legacy_workflow_run_id" => workflow_run.id,
        "legacy_project_id" => workflow_run.project_id,
        "status_transitions" => workflow_run.status_transitions || [],
        "workflow_audit" => %{
          "status_transitions" => workflow_run.status_transitions || [],
          "step_results" => normalize_map(workflow_run.step_results),
          "error" => normalize_map(workflow_run.error),
          "step_retry_contract" => projected_step_retry_contract(workflow_run)
        },
        "execution_profile_name" => execution_profile.name,
        "repo_prep_plan" => execution_profile.repo_prep_plan,
        "validation_plan" => execution_profile.validation_plan,
        "governed_stages" => governed_stages,
        "projection_source" => "workflow_run"
      },
      retry_of_run_id: workflow_run.retry_of_run_id,
      retry_attempt: workflow_run.retry_attempt,
      retry_lineage: workflow_run.retry_lineage,
      started_at: workflow_run.started_at,
      completed_at: workflow_run.completed_at
    }
    |> maybe_put(:work_item_id, work_item_id)
    |> update_in([:workflow_state_ref], fn workflow_state_ref ->
      workflow_state_ref
      |> maybe_put("turn_id", Map.get(public_turn, "turn_id"))
      |> maybe_put("conversation_id", Map.get(public_turn, "conversation_id"))
    end)
    |> update_in([:run_metadata], fn run_metadata ->
      maybe_put(run_metadata, "public_turn", if(public_turn == %{}, do: nil, else: public_turn))
    end)
  end

  defp build_workflow_run_attrs(work_item, managed_repo, attrs) do
    workflow_name = workflow_name_for_launch(work_item, attrs)

    workflow_version =
      attrs
      |> Map.get(:workflow_version, attrs |> Map.get("workflow_version"))
      |> normalize_positive_integer(1)

    run_id = generated_run_id()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    execution_profile_hint = execution_profile_name_for_launch(managed_repo, workflow_name)

    {:ok,
     %{
       run_id: run_id,
       project_id: managed_repo.legacy_project_id,
       managed_repo_id: managed_repo.id,
       workflow_name: workflow_name,
       workflow_version: workflow_version,
       trigger: %{
         "source" => "work_item",
         "mode" => "governed",
         "work_item_id" => work_item.id,
         "execution_profile_name" => execution_profile_hint
       },
       inputs:
         attrs
         |> Map.get(:inputs, attrs |> Map.get("inputs", %{}))
         |> normalize_map()
         |> Map.put("work_item_id", work_item.id)
         |> Map.put_new("work_summary", work_item.summary),
       input_metadata: %{
         "work_item_id" => %{"required" => true, "source" => "work_item"},
         "work_summary" => %{"required" => true, "source" => "work_item"}
       },
       initiating_actor:
         attrs
         |> Map.get(:initiating_actor, attrs |> Map.get("initiating_actor", work_item.initiating_actor))
         |> normalize_map(),
       current_step: "queued",
       started_at: now
     }}
  end

  defp workflow_name_for_launch(work_item, attrs) do
    explicit_name =
      attrs
      |> Map.get(:workflow_name, attrs |> Map.get("workflow_name"))
      |> normalize_optional_string()

    explicit_name || workflow_name_from_recommended_action(work_item.recommended_action)
  end

  defp workflow_name_from_recommended_action("launch_fix_workflow"), do: "fix_failing_tests"
  defp workflow_name_from_recommended_action("triage_issue"), do: "issue_triage"
  defp workflow_name_from_recommended_action(_recommended_action), do: "implement_task"

  defp execution_profile_name_for_launch(managed_repo, workflow_name) do
    execution_settings = managed_repo.execution_settings |> normalize_map()

    workflow_settings =
      execution_settings
      |> Map.get("workflow", %{})
      |> normalize_map()
      |> Map.get(workflow_name, %{})
      |> normalize_map()

    if workflow_settings == %{}, do: "default", else: "workflow:#{workflow_name}"
  end

  defp maybe_attach_turn_to_work_item(attrs) do
    case normalize_optional_string(Map.get(attrs, :work_item_id)) do
      nil ->
        {:ok, nil}

      work_item_id ->
        with {:ok, work_item} <- fetch_work_item(work_item_id),
             updated_work_item <- update_work_item_turn_context(work_item, attrs),
             {:ok, persisted_work_item} <- WorkItem.update(work_item, updated_work_item, actor: @projection_actor) do
          {:ok, persisted_work_item}
        end
    end
  end

  defp fetch_work_item(work_item_id) when is_binary(work_item_id) do
    case WorkItem.read(query: [filter: [id: work_item_id]], actor: @projection_actor) do
      {:ok, [%WorkItem{} = work_item]} -> {:ok, work_item}
      {:ok, []} -> {:error, :work_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_work_item_turn_context(%WorkItem{} = work_item, attrs) do
    turn_context = build_public_turn_context(attrs)

    work_metadata =
      work_item.work_metadata
      |> normalize_map()
      |> Map.put("public_turn", turn_context)

    audit_entry =
      %{
        "entry_type" => "public_turn_materialized",
        "turn_id" => Map.get(turn_context, "turn_id"),
        "conversation_id" => Map.get(turn_context, "conversation_id"),
        "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }
      |> normalize_map()

    %{
      work_metadata: work_metadata,
      audit_log: (work_item.audit_log || []) ++ [audit_entry]
    }
  end

  defp ensure_turn_workflow_run(attrs, turn_id, project_id, managed_repo_id) do
    run_id = turn_run_id(turn_id)

    case WorkflowRun.get_by_project_and_run_id(%{project_id: project_id, run_id: run_id}, actor: @launch_actor) do
      {:ok, %WorkflowRun{} = workflow_run} ->
        {:ok, workflow_run}

      {:ok, nil} ->
        WorkflowRun.create(turn_workflow_run_attrs(attrs, project_id, managed_repo_id, run_id), actor: @launch_actor)

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _rest]}} ->
        WorkflowRun.create(turn_workflow_run_attrs(attrs, project_id, managed_repo_id, run_id), actor: @launch_actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp turn_workflow_run_attrs(attrs, project_id, managed_repo_id, run_id) do
    turn = normalize_map(Map.get(attrs, :turn))
    work_item_id = normalize_optional_string(Map.get(attrs, :work_item_id))

    conversation_id =
      normalize_optional_string(Map.get(attrs, :conversation_id)) ||
        normalize_optional_string(Map.get(turn, "conversation_id"))

    operation = normalize_optional_string(Map.get(turn, "operation")) || "plan"
    objective = normalize_optional_string(Map.get(turn, "objective"))
    started_at = turn_started_at(turn)

    %{
      run_id: run_id,
      project_id: project_id,
      managed_repo_id: managed_repo_id,
      workflow_name: turn_workflow_name(operation),
      workflow_version: 1,
      trigger:
        %{
          "source" => "public_turn_runtime",
          "mode" => "conversation_runtime",
          "conversation_id" => conversation_id,
          "turn_id" => Map.get(turn, "turn_id")
        }
        |> maybe_put("work_item_id", work_item_id),
      inputs:
        %{
          "turn_id" => Map.get(turn, "turn_id"),
          "conversation_id" => conversation_id,
          "operation" => operation
        }
        |> maybe_put("work_item_id", work_item_id)
        |> maybe_put("objective", objective),
      input_metadata:
        %{
          "turn_id" => %{"required" => true, "source" => "public_turn_runtime"},
          "conversation_id" => %{"required" => true, "source" => "public_turn_runtime"},
          "operation" => %{"required" => true, "source" => "public_turn_runtime"}
        }
        |> maybe_put(
          "objective",
          if(is_binary(objective), do: %{"required" => true, "source" => "public_turn_runtime"}, else: nil)
        ),
      initiating_actor:
        %{
          "id" => normalize_optional_string(Map.get(attrs, :actor_id)),
          "email" => normalize_optional_string(Map.get(attrs, :actor_email))
        }
        |> normalize_map(),
      current_step: "public_turn_materialized",
      step_results: turn_step_results(attrs),
      started_at: started_at
    }
  end

  defp ensure_turn_terminal_status(%WorkflowRun{} = workflow_run, attrs) do
    terminal_status = workflow_terminal_status(attrs)
    terminal_step = workflow_terminal_step(attrs)
    terminal_at = turn_terminal_at(normalize_map(Map.get(attrs, :turn)))

    cond do
      workflow_run.status == terminal_status ->
        {:ok, workflow_run}

      terminal_status == :cancelled and workflow_run.status == :pending ->
        WorkflowRun.transition_status(
          workflow_run,
          %{
            to_status: :cancelled,
            current_step: terminal_step,
            transitioned_at: terminal_at,
            transition_metadata: %{"source" => "public_turn_runtime"}
          },
          actor: @launch_actor
        )

      workflow_run.status == :pending ->
        with {:ok, running_workflow_run} <-
               WorkflowRun.transition_status(
                 workflow_run,
                 %{
                   to_status: :running,
                   current_step: "public_turn_in_progress",
                   transitioned_at: turn_started_at(normalize_map(Map.get(attrs, :turn))),
                   transition_metadata: %{"source" => "public_turn_runtime"}
                 },
                 actor: @launch_actor
               ) do
          ensure_turn_terminal_status(running_workflow_run, attrs)
        end

      workflow_run.status == :running ->
        WorkflowRun.transition_status(
          workflow_run,
          %{
            to_status: terminal_status,
            current_step: terminal_step,
            transitioned_at: terminal_at,
            transition_metadata: %{"source" => "public_turn_runtime"}
          },
          actor: @launch_actor
        )

      true ->
        {:ok, workflow_run}
    end
  end

  defp workflow_terminal_status(attrs) do
    case attrs |> Map.get(:turn) |> normalize_map() |> Map.get("state") |> normalize_optional_string() do
      "completed" -> :completed
      "cancelled" -> :cancelled
      "interrupted" -> :failed
      "failed" -> :failed
      _other -> :completed
    end
  end

  defp workflow_terminal_step(attrs) do
    case workflow_terminal_status(attrs) do
      :completed -> "public_turn_completed"
      :cancelled -> "public_turn_cancelled"
      :failed -> "public_turn_failed"
    end
  end

  defp turn_step_results(attrs) do
    turn_context = build_public_turn_context(attrs)
    review = normalize_map(Map.get(attrs, :review))
    artifacts = normalize_map_list(Map.get(attrs, :artifacts))
    events = normalize_map_list(Map.get(attrs, :events))

    %{}
    |> maybe_put("coding_turn_summary", turn_context)
    |> maybe_put("coding_turn_review", if(review == %{}, do: nil, else: review))
    |> maybe_put("coding_turn_artifacts", if(artifacts == [], do: nil, else: artifacts))
    |> maybe_put("coding_turn_replay", if(events == [], do: nil, else: events))
    |> maybe_put(
      "runtime_service_delivery",
      attrs |> Map.get(:runtime_delivery) |> normalize_map() |> nil_if_empty_map()
    )
  end

  defp build_public_turn_context(attrs) do
    turn = normalize_map(Map.get(attrs, :turn))
    review = normalize_map(Map.get(attrs, :review))

    %{
      "turn_id" => Map.get(turn, "turn_id"),
      "conversation_id" =>
        normalize_optional_string(Map.get(attrs, :conversation_id)) ||
          normalize_optional_string(Map.get(turn, "conversation_id")) ||
          normalize_optional_string(Map.get(turn, "session_id")),
      "session_id" => normalize_optional_string(Map.get(turn, "session_id")),
      "work_item_id" => normalize_optional_string(Map.get(attrs, :work_item_id)),
      "operation" => normalize_optional_string(Map.get(turn, "operation")),
      "objective" => normalize_optional_string(Map.get(turn, "objective")),
      "state" => normalize_optional_string(Map.get(turn, "state")),
      "summary_status" => normalize_map(Map.get(turn, "summary_status")),
      "assistant_output" => normalize_map(Map.get(turn, "assistant_output")),
      "review" => if(review == %{}, do: nil, else: review)
    }
    |> normalize_map()
  end

  defp public_turn_metadata(%WorkflowRun{} = workflow_run) do
    step_results = normalize_map(workflow_run.step_results)
    trigger = normalize_map(workflow_run.trigger)
    inputs = normalize_map(workflow_run.inputs)

    summary =
      step_results
      |> Map.get("coding_turn_summary", %{})
      |> normalize_map()

    %{}
    |> maybe_put(
      "turn_id",
      normalize_optional_string(Map.get(summary, "turn_id")) || normalize_optional_string(Map.get(trigger, "turn_id"))
    )
    |> maybe_put(
      "conversation_id",
      normalize_optional_string(Map.get(summary, "conversation_id")) ||
        normalize_optional_string(Map.get(trigger, "conversation_id")) ||
        normalize_optional_string(Map.get(inputs, "conversation_id"))
    )
    |> maybe_put("work_item_id", normalize_optional_string(Map.get(inputs, "work_item_id")))
    |> maybe_put("state", normalize_optional_string(Map.get(summary, "state")))
  end

  defp turn_run_id(turn_id), do: "turn:#{turn_id}"

  defp turn_workflow_name(operation), do: "coding_turn_#{operation}"

  defp projected_step_retry_contract(%WorkflowRun{} = workflow_run) do
    case WorkflowRun.step_retry_contract(workflow_run) do
      {:ok, contract} when is_map(contract) -> normalize_map(contract)
      {:error, typed_failure} when is_map(typed_failure) -> %{"typed_failure" => normalize_map(typed_failure)}
      _other -> %{}
    end
  end

  defp managed_repo(%WorkflowRun{managed_repo_id: managed_repo_id}) when is_binary(managed_repo_id) do
    case ManagedRepo.read(query: [filter: [id: managed_repo_id]], actor: @projection_actor) do
      {:ok, [%ManagedRepo{} = managed_repo]} -> {:ok, managed_repo}
      {:ok, []} -> {:error, :managed_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_repo(%WorkflowRun{} = workflow_run) do
    case ManagedRepo.get_by_legacy_project_id(workflow_run.project_id, actor: @projection_actor) do
      {:ok, managed_repo} -> {:ok, managed_repo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_repo(_workflow_run), do: {:error, :managed_repo_not_found}

  defp managed_repo_for_work_item(%WorkItem{managed_repo_id: managed_repo_id}) do
    case ManagedRepo.read(query: [filter: [id: managed_repo_id]], actor: @projection_actor) do
      {:ok, [%ManagedRepo{} = managed_repo]} -> {:ok, managed_repo}
      {:ok, []} -> {:error, :managed_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_execution_profile(managed_repo, workflow_run) do
    execution_settings = managed_repo.execution_settings |> normalize_map()

    repo_defaults =
      execution_settings
      |> Map.get("execution", %{})
      |> normalize_map()

    workflow_defaults =
      execution_settings
      |> Map.get("workflow", %{})
      |> normalize_map()
      |> Map.get(workflow_run.workflow_name, %{})
      |> normalize_map()

    effective_settings = deep_merge(repo_defaults, workflow_defaults)
    profile_name = if workflow_defaults == %{}, do: "default", else: "workflow:#{workflow_run.workflow_name}"

    ExecutionProfile.upsert_for_managed_repo(
      %{
        managed_repo_id: managed_repo.id,
        name: profile_name,
        sandbox_profile:
          effective_settings
          |> Map.get("sandbox_profile", %{})
          |> normalize_map()
          |> Map.put_new("engine", @default_runic_engine),
        repo_prep_plan:
          effective_settings
          |> Map.get("repo_prep_plan")
          |> normalize_string_list(@default_repo_prep_plan),
        validation_plan:
          effective_settings
          |> Map.get("validation_plan")
          |> normalize_string_list(@default_validation_plan),
        governed_stages:
          effective_settings
          |> Map.get("governed_stages")
          |> normalize_string_list(@default_governed_stages),
        checkpoint_strategy:
          effective_settings
          |> Map.get("checkpoint_strategy")
          |> normalize_string(@default_checkpoint_strategy),
        resume_strategy:
          effective_settings
          |> Map.get("resume_strategy")
          |> normalize_string(
            effective_settings
            |> Map.get("checkpoint_strategy")
            |> normalize_string(@default_checkpoint_strategy)
          ),
        profile_metadata: %{
          "workflow_name" => workflow_run.workflow_name,
          "legacy_project_id" => workflow_run.project_id,
          "repo_defaults" => repo_defaults,
          "workflow_defaults" => workflow_defaults
        },
        source: if(workflow_defaults == %{}, do: "managed_repo.execution", else: "managed_repo.workflow")
      },
      actor: @projection_actor
    )
  end

  defp referenced_work_item_id(%WorkflowRun{} = workflow_run) do
    workflow_run.inputs
    |> normalize_map()
    |> Map.get("work_item_id")
    |> normalize_optional_string()
  end

  defp effective_governed_stages(%ExecutionProfile{} = profile) do
    profile.governed_stages |> normalize_string_list(@default_governed_stages)
  end

  defp infer_current_stage(%WorkflowRun{} = workflow_run, governed_stages) do
    current_step =
      workflow_run.current_step
      |> normalize_optional_string()
      |> case do
        nil -> ""
        normalized -> String.downcase(normalized)
      end

    status = workflow_run.status

    cond do
      status in [:completed, :cancelled] ->
        stage_if_present("cleanup", governed_stages)

      status == :awaiting_approval ->
        stage_if_present("approval", governed_stages)

      current_step =~ "approval" ->
        stage_if_present("approval", governed_stages)

      current_step =~ "lint" or current_step =~ "test" or current_step =~ "spec" ->
        stage_if_present("validation", governed_stages)

      current_step =~ "sync" ->
        stage_if_present("repo_sync", governed_stages)

      current_step =~ "attach" or current_step =~ "checkout" ->
        stage_if_present("repo_attach", governed_stages)

      current_step =~ "prep" or current_step =~ "deps" or current_step =~ "bootstrap" ->
        stage_if_present("repo_prep", governed_stages)

      true ->
        stage_if_present("repo_prep", governed_stages)
    end
  end

  defp stage_statuses(governed_stages, current_stage, status) do
    stage_index = Enum.find_index(governed_stages, &(&1 == current_stage)) || 0

    governed_stages
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {stage, index}, acc ->
      stage_status =
        cond do
          index < stage_index -> "completed"
          index > stage_index -> "pending"
          status == :awaiting_approval and stage == "approval" -> "awaiting_decision"
          status in [:completed, :cancelled] and stage == current_stage -> "completed"
          status == :failed and stage == current_stage -> "failed"
          true -> "active"
        end

      Map.put(acc, stage, stage_status)
    end)
  end

  defp stage_if_present(stage, governed_stages) do
    if stage in governed_stages, do: stage, else: List.first(governed_stages) || stage
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp deep_merge(left, right) when is_map(left), do: Map.merge(left, normalize_map(right))
  defp deep_merge(_left, right), do: normalize_map(right)

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

  defp normalize_string_list(value, default) when is_list(value) do
    normalized =
      value
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized == [], do: default, else: normalized
  end

  defp normalize_string_list(_value, default), do: default

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

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_map_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_map/1)
  end

  defp normalize_map_list(_value), do: []

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

  defp nil_if_empty_map(%{} = value) when map_size(value) == 0, do: nil
  defp nil_if_empty_map(value), do: value

  defp turn_started_at(turn) when is_map(turn) do
    turn
    |> Map.get("started_at")
    |> parse_datetime()
    |> Kernel.||(DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp turn_terminal_at(turn) when is_map(turn) do
    turn
    |> Map.get("terminal_at")
    |> parse_datetime()
    |> Kernel.||(DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = value), do: DateTime.truncate(value, :second)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _other -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp nested_get(value, keys) when is_list(keys) do
    Enum.reduce_while(keys, value, fn key, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) and is_atom(key) and Map.has_key?(acc, Atom.to_string(key)) ->
          {:cont, Map.get(acc, Atom.to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> default
    end
  end

  defp normalize_positive_integer(_value, default), do: default

  defp generated_run_id do
    "run-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
