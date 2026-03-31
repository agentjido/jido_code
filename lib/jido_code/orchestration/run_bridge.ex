defmodule JidoCode.Orchestration.RunBridge do
  # covers: architecture.run_governance.run_launch_resolves_effective_execution_profile
  # covers: architecture.execution_pipeline.run_is_projection_of_workflow_state
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

  defp projection_attrs(workflow_run, managed_repo, execution_profile) do
    work_item_id = referenced_work_item_id(workflow_run)
    governed_stages = effective_governed_stages(execution_profile)
    current_stage = infer_current_stage(workflow_run, governed_stages)

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
        "execution_profile_name" => execution_profile.name,
        "projection_source" => "workflow_run"
      },
      retry_of_run_id: workflow_run.retry_of_run_id,
      retry_attempt: workflow_run.retry_attempt,
      retry_lineage: workflow_run.retry_lineage,
      started_at: workflow_run.started_at,
      completed_at: workflow_run.completed_at
    }
    |> maybe_put(:work_item_id, work_item_id)
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
