defmodule JidoCode.Orchestration.RecordStore do
  @moduledoc """
  Store-backed orchestration records for governed runs and execution profiles.
  """

  alias JidoCode.ControlPlane.RecordStore, as: Store
  alias JidoCode.Orchestration.{ExecutionProfile, Run, WorkflowRun}

  @run_statuses %{
    "pending" => :pending,
    "running" => :running,
    "awaiting_approval" => :awaiting_approval,
    "completed" => :completed,
    "failed" => :failed,
    "cancelled" => :cancelled
  }

  @default_runic_engine "jido_runic"

  @atom_key_aliases %{
    id: :id,
    project_id: :legacy_project_id
  }

  @top_level_key_aliases %{
    "id" => :id,
    "workflow_run_id" => :workflow_run_id,
    "workflowRunId" => :workflow_run_id,
    "run_record_id" => :run_record_id,
    "runId" => :run_record_id,
    "source_run_id" => :run_id,
    "sourceRunId" => :run_id,
    "run_id" => :run_id,
    "managed_repo_id" => :managed_repo_id,
    "managedRepoId" => :managed_repo_id,
    "work_item_id" => :work_item_id,
    "workItemId" => :work_item_id,
    "execution_profile_id" => :execution_profile_id,
    "executionProfileId" => :execution_profile_id,
    "legacy_project_id" => :legacy_project_id,
    "project_id" => :legacy_project_id,
    "legacyProjectId" => :legacy_project_id,
    "workflow_name" => :workflow_name,
    "workflowName" => :workflow_name,
    "workflow_version" => :workflow_version,
    "workflowVersion" => :workflow_version,
    "status" => :status,
    "recordStatus" => :status,
    "current_step" => :current_step,
    "currentStep" => :current_step,
    "current_stage" => :current_stage,
    "currentStage" => :current_stage,
    "governed_stages" => :governed_stages,
    "governedStagesJson" => :governed_stages,
    "stage_statuses" => :stage_statuses,
    "stageStatusesJson" => :stage_statuses,
    "trigger" => :trigger,
    "triggerJson" => :trigger,
    "inputs" => :inputs,
    "inputsJson" => :inputs,
    "input_metadata" => :input_metadata,
    "inputMetadataJson" => :input_metadata,
    "initiating_actor" => :initiating_actor,
    "initiatingActorJson" => :initiating_actor,
    "execution_engine" => :execution_engine,
    "executionEngine" => :execution_engine,
    "workflow_state_ref" => :workflow_state_ref,
    "workflowStateRefJson" => :workflow_state_ref,
    "run_metadata" => :run_metadata,
    "runMetadataJson" => :run_metadata,
    "retry_of_run_id" => :retry_of_run_id,
    "retryOfRunId" => :retry_of_run_id,
    "retry_attempt" => :retry_attempt,
    "retryAttempt" => :retry_attempt,
    "retry_lineage" => :retry_lineage,
    "retryLineageJson" => :retry_lineage,
    "source_key" => :source_key,
    "sourceKey" => :source_key,
    "runSourceKey" => :source_key,
    "executionProfileSourceKey" => :source_key,
    "started_at" => :started_at,
    "startedAt" => :started_at,
    "completed_at" => :completed_at,
    "completedAt" => :completed_at,
    "inserted_at" => :inserted_at,
    "insertedAt" => :inserted_at,
    "updated_at" => :updated_at,
    "updatedAt" => :updated_at,
    "name" => :name,
    "sandbox_profile" => :sandbox_profile,
    "sandboxProfileJson" => :sandbox_profile,
    "repo_prep_plan" => :repo_prep_plan,
    "repoPrepPlanJson" => :repo_prep_plan,
    "validation_plan" => :validation_plan,
    "validationPlanJson" => :validation_plan,
    "checkpoint_strategy" => :checkpoint_strategy,
    "checkpointStrategy" => :checkpoint_strategy,
    "resume_strategy" => :resume_strategy,
    "resumeStrategy" => :resume_strategy,
    "profile_metadata" => :profile_metadata,
    "profileMetadataJson" => :profile_metadata,
    "source" => :source,
    "step_results" => :step_results,
    "stepResultsJson" => :step_results,
    "error" => :error,
    "errorJson" => :error,
    "status_transitions" => :status_transitions,
    "statusTransitionsJson" => :status_transitions,
    "metadata" => :metadata,
    "metadataJson" => :metadata
  }

  @map_fields [
    :sandbox_profile,
    :stage_statuses,
    :trigger,
    :inputs,
    :input_metadata,
    :initiating_actor,
    :workflow_state_ref,
    :run_metadata,
    :profile_metadata,
    :step_results,
    :error,
    :metadata
  ]

  @list_fields [
    :repo_prep_plan,
    :validation_plan,
    :governed_stages,
    :retry_lineage,
    :status_transitions
  ]

  @spec upsert_execution_profile(map(), keyword()) :: {:ok, ExecutionProfile.t()} | {:error, term()}
  def upsert_execution_profile(attrs, opts \\ [])

  def upsert_execution_profile(attrs, opts) when is_map(attrs) do
    attrs = normalize_record_map(attrs)
    source_key = execution_profile_source_key(attrs)

    with {:ok, existing} <-
           Store.get_by_identity(
             :execution_profile,
             :unique_managed_repo_name,
             "executionProfileSourceKey",
             source_key,
             opts
           ),
         record <- execution_profile_record(attrs, existing),
         {:ok, saved_record} <- Store.upsert(:execution_profile, record, opts) do
      {:ok, to_execution_profile(saved_record)}
    end
  end

  def upsert_execution_profile(_attrs, _opts), do: {:error, :invalid_execution_profile_attrs}

  @spec get_execution_profile_by_managed_repo_name(String.t(), String.t(), keyword()) ::
          {:ok, ExecutionProfile.t() | nil} | {:error, term()}
  def get_execution_profile_by_managed_repo_name(managed_repo_id, name, opts \\ []) do
    source_key =
      %{managed_repo_id: managed_repo_id, name: name}
      |> execution_profile_source_key()

    with {:ok, record} <-
           Store.get_by_identity(
             :execution_profile,
             :unique_managed_repo_name,
             "executionProfileSourceKey",
             source_key,
             opts
           ) do
      {:ok, record && to_execution_profile(record)}
    end
  end

  @spec upsert_workflow_run_compatibility(WorkflowRun.t() | map(), keyword()) ::
          {:ok, WorkflowRun.t()} | {:error, term()}
  def upsert_workflow_run_compatibility(attrs, opts \\ [])

  def upsert_workflow_run_compatibility(attrs, opts) when is_map(attrs) do
    attrs = attrs |> map_from_struct() |> normalize_record_map()
    workflow_run_id = normalize_optional_string(map_get(attrs, :workflow_run_id) || map_get(attrs, :id))

    with {:ok, existing} <-
           Store.get_by_identity(:workflow_run, :unique_workflow_run, "workflowRunId", workflow_run_id, opts),
         record <- workflow_run_record(attrs, existing),
         {:ok, saved_record} <- Store.upsert(:workflow_run, record, opts) do
      {:ok, to_workflow_run(saved_record)}
    end
  end

  def upsert_workflow_run_compatibility(_attrs, _opts), do: {:error, :invalid_workflow_run_attrs}

  @spec upsert_run(map(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def upsert_run(attrs, opts \\ [])

  def upsert_run(attrs, opts) when is_map(attrs) do
    attrs = normalize_record_map(attrs)

    with {:ok, existing} <- existing_run(attrs, opts),
         record <- run_record(attrs, existing),
         {:ok, saved_record} <- Store.upsert(:run, record, opts) do
      {:ok, to_run(saved_record)}
    end
  end

  def upsert_run(_attrs, _opts), do: {:error, :invalid_run_attrs}

  @spec get_run_by_workflow_run_id(String.t(), keyword()) :: {:ok, Run.t() | nil} | {:error, term()}
  def get_run_by_workflow_run_id(workflow_run_id, opts \\ []) do
    with {:ok, record} <- Store.get_by_identity(:run, :unique_workflow_run, "runWorkflowRunId", workflow_run_id, opts) do
      {:ok, record && to_run(record)}
    end
  end

  @spec get_run_by_managed_repo_and_run_id(String.t(), String.t(), keyword()) :: {:ok, Run.t() | nil} | {:error, term()}
  def get_run_by_managed_repo_and_run_id(managed_repo_id, run_id, opts \\ []) do
    source_key = run_source_key(%{managed_repo_id: managed_repo_id, run_id: run_id})

    with {:ok, record} <- Store.get_by_identity(:run, :unique_managed_repo_run_id, "runSourceKey", source_key, opts) do
      {:ok, record && to_run(record)}
    end
  end

  @spec list_runs(map(), keyword()) :: {:ok, [Run.t()]} | {:error, term()}
  def list_runs(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:run, filters, opts, &to_run/1)
  end

  def to_execution_profile(record) when is_map(record) do
    record = normalize_record_map(record)

    %ExecutionProfile{
      id: map_get(record, :execution_profile_id) || map_get(record, :id),
      managed_repo_id: map_get(record, :managed_repo_id),
      name: normalize_string(map_get(record, :name), "default"),
      sandbox_profile: decode_json_map(map_get(record, :sandbox_profile, %{})),
      repo_prep_plan: decode_json_list(map_get(record, :repo_prep_plan, []), ExecutionProfile.default_repo_prep_plan()),
      validation_plan:
        decode_json_list(map_get(record, :validation_plan, []), ExecutionProfile.default_validation_plan()),
      governed_stages:
        decode_json_list(map_get(record, :governed_stages, []), ExecutionProfile.default_governed_stages()),
      checkpoint_strategy:
        normalize_string(map_get(record, :checkpoint_strategy), ExecutionProfile.default_checkpoint_strategy()),
      resume_strategy:
        normalize_string(map_get(record, :resume_strategy), ExecutionProfile.default_checkpoint_strategy()),
      profile_metadata: decode_json_map(map_get(record, :profile_metadata, %{})),
      source: normalize_string(map_get(record, :source), "managed_repo.execution_settings"),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  def to_run(record) when is_map(record) do
    record = normalize_record_map(record)

    %Run{
      id: map_get(record, :run_record_id) || map_get(record, :id),
      workflow_run_id: map_get(record, :workflow_run_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      work_item_id: map_get(record, :work_item_id),
      execution_profile_id: map_get(record, :execution_profile_id),
      legacy_project_id: map_get(record, :legacy_project_id),
      run_id: map_get(record, :run_id),
      workflow_name: normalize_string(map_get(record, :workflow_name), "unknown_workflow"),
      workflow_version: normalize_positive_integer(map_get(record, :workflow_version), 1),
      status: normalize_atom(map_get(record, :status), @run_statuses, :pending),
      current_step: normalize_string(map_get(record, :current_step), "unknown"),
      current_stage: normalize_string(map_get(record, :current_stage), "repo_attach"),
      governed_stages:
        decode_json_list(map_get(record, :governed_stages, []), ExecutionProfile.default_governed_stages()),
      stage_statuses: decode_json_map(map_get(record, :stage_statuses, %{})),
      trigger: decode_json_map(map_get(record, :trigger, %{})),
      inputs: decode_json_map(map_get(record, :inputs, %{})),
      input_metadata: decode_json_map(map_get(record, :input_metadata, %{})),
      initiating_actor: decode_json_map(map_get(record, :initiating_actor, %{})),
      execution_engine: normalize_string(map_get(record, :execution_engine), @default_runic_engine),
      workflow_state_ref: decode_json_map(map_get(record, :workflow_state_ref, %{})),
      run_metadata: decode_json_map(map_get(record, :run_metadata, %{})),
      retry_of_run_id: normalize_optional_string(map_get(record, :retry_of_run_id)),
      retry_attempt: normalize_positive_integer(map_get(record, :retry_attempt), 1),
      retry_lineage: decode_json_list(map_get(record, :retry_lineage, []), []),
      started_at: normalize_datetime(map_get(record, :started_at)),
      completed_at: normalize_datetime(map_get(record, :completed_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  def to_workflow_run(record) when is_map(record) do
    record = normalize_record_map(record)

    %WorkflowRun{
      id: map_get(record, :workflow_run_id) || map_get(record, :id),
      managed_repo_id: map_get(record, :managed_repo_id),
      project_id: map_get(record, :legacy_project_id),
      run_id: map_get(record, :run_id),
      workflow_name: normalize_string(map_get(record, :workflow_name), "unknown_workflow"),
      workflow_version: normalize_positive_integer(map_get(record, :workflow_version), 1),
      status: normalize_atom(map_get(record, :status), @run_statuses, :pending),
      trigger: decode_json_map(map_get(record, :trigger, %{})),
      inputs: decode_json_map(map_get(record, :inputs, %{})),
      input_metadata: decode_json_map(map_get(record, :input_metadata, %{})),
      initiating_actor: decode_json_map(map_get(record, :initiating_actor, %{})),
      current_step: normalize_string(map_get(record, :current_step), "unknown"),
      status_transitions: decode_json_list(map_get(record, :status_transitions, []), []),
      step_results: decode_json_map(map_get(record, :step_results, %{})),
      error: decode_json_map(map_get(record, :error, %{})),
      retry_of_run_id: normalize_optional_string(map_get(record, :retry_of_run_id)),
      retry_attempt: normalize_positive_integer(map_get(record, :retry_attempt), 1),
      retry_lineage: decode_json_list(map_get(record, :retry_lineage, []), []),
      started_at: normalize_datetime(map_get(record, :started_at)),
      completed_at: normalize_datetime(map_get(record, :completed_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp existing_run(attrs, opts) do
    case normalize_optional_string(map_get(attrs, :workflow_run_id)) do
      nil ->
        Store.get_by_identity(:run, :unique_managed_repo_run_id, "runSourceKey", run_source_key(attrs), opts)

      workflow_run_id ->
        case Store.get_by_identity(:run, :unique_workflow_run, "runWorkflowRunId", workflow_run_id, opts) do
          {:ok, nil} ->
            Store.get_by_identity(:run, :unique_managed_repo_run_id, "runSourceKey", run_source_key(attrs), opts)

          other ->
            other
        end
    end
  end

  defp execution_profile_record(attrs, existing) do
    now = now()

    repo_prep_plan = decode_json_list(map_get(attrs, :repo_prep_plan, []), ExecutionProfile.default_repo_prep_plan())
    validation_plan = decode_json_list(map_get(attrs, :validation_plan, []), ExecutionProfile.default_validation_plan())
    governed_stages = decode_json_list(map_get(attrs, :governed_stages, []), ExecutionProfile.default_governed_stages())

    checkpoint_strategy =
      normalize_string(map_get(attrs, :checkpoint_strategy), ExecutionProfile.default_checkpoint_strategy())

    %{
      execution_profile_id:
        existing_id(existing, :execution_profile_id) ||
          normalize_optional_string(map_get(attrs, :execution_profile_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      name: normalize_string(map_get(attrs, :name), "default"),
      source_key: execution_profile_source_key(attrs),
      sandbox_profile: decode_json_map(map_get(attrs, :sandbox_profile, %{})),
      repo_prep_plan: repo_prep_plan,
      validation_plan: validation_plan,
      governed_stages: governed_stages,
      checkpoint_strategy: checkpoint_strategy,
      resume_strategy: normalize_string(map_get(attrs, :resume_strategy), checkpoint_strategy),
      profile_metadata: decode_json_map(map_get(attrs, :profile_metadata, %{})),
      source: normalize_string(map_get(attrs, :source), "managed_repo.execution_settings"),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp workflow_run_record(attrs, existing) do
    now = now()

    %{
      workflow_run_id:
        existing_id(existing, :workflow_run_id) ||
          normalize_optional_string(map_get(attrs, :workflow_run_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      legacy_project_id: normalize_optional_string(map_get(attrs, :legacy_project_id)),
      run_id: normalize_string(map_get(attrs, :run_id), generated_run_id()),
      workflow_name: normalize_string(map_get(attrs, :workflow_name), "unknown_workflow"),
      workflow_version: normalize_positive_integer(map_get(attrs, :workflow_version), 1),
      status: normalize_atom(map_get(attrs, :status), @run_statuses, :pending),
      current_step: normalize_string(map_get(attrs, :current_step), "unknown"),
      trigger: decode_json_map(map_get(attrs, :trigger, %{})),
      inputs: decode_json_map(map_get(attrs, :inputs, %{})),
      input_metadata: decode_json_map(map_get(attrs, :input_metadata, %{})),
      initiating_actor: decode_json_map(map_get(attrs, :initiating_actor, %{})),
      step_results: decode_json_map(map_get(attrs, :step_results, %{})),
      error: decode_json_map(map_get(attrs, :error, %{})),
      status_transitions: decode_json_list(map_get(attrs, :status_transitions, []), []),
      retry_of_run_id: normalize_optional_string(map_get(attrs, :retry_of_run_id)),
      retry_attempt: normalize_positive_integer(map_get(attrs, :retry_attempt), 1),
      retry_lineage: decode_json_list(map_get(attrs, :retry_lineage, []), []),
      started_at: normalize_datetime(map_get(attrs, :started_at)) || now,
      completed_at: normalize_datetime(map_get(attrs, :completed_at)),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp run_record(attrs, existing) do
    now = now()
    governed_stages = decode_json_list(map_get(attrs, :governed_stages, []), ExecutionProfile.default_governed_stages())
    current_stage = normalize_string(map_get(attrs, :current_stage), List.first(governed_stages) || "repo_attach")

    %{
      run_record_id:
        existing_id(existing, :run_record_id) ||
          normalize_optional_string(map_get(attrs, :run_record_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      workflow_run_id: normalize_optional_string(map_get(attrs, :workflow_run_id)),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      execution_profile_id: normalize_optional_string(map_get(attrs, :execution_profile_id)),
      legacy_project_id: normalize_optional_string(map_get(attrs, :legacy_project_id)),
      run_id: normalize_string(map_get(attrs, :run_id), generated_run_id()),
      source_key: run_source_key(attrs),
      workflow_name: normalize_string(map_get(attrs, :workflow_name), "unknown_workflow"),
      workflow_version: normalize_positive_integer(map_get(attrs, :workflow_version), 1),
      status: normalize_atom(map_get(attrs, :status), @run_statuses, :pending),
      current_step: normalize_string(map_get(attrs, :current_step), "unknown"),
      current_stage: current_stage,
      governed_stages: governed_stages,
      stage_statuses: decode_json_map(map_get(attrs, :stage_statuses, %{})),
      trigger: decode_json_map(map_get(attrs, :trigger, %{})),
      inputs: decode_json_map(map_get(attrs, :inputs, %{})),
      input_metadata: decode_json_map(map_get(attrs, :input_metadata, %{})),
      initiating_actor: decode_json_map(map_get(attrs, :initiating_actor, %{})),
      execution_engine: normalize_string(map_get(attrs, :execution_engine), @default_runic_engine),
      workflow_state_ref: decode_json_map(map_get(attrs, :workflow_state_ref, %{})),
      run_metadata: decode_json_map(map_get(attrs, :run_metadata, %{})),
      error: decode_json_map(map_get(attrs, :error, %{})),
      retry_of_run_id: normalize_optional_string(map_get(attrs, :retry_of_run_id)),
      retry_attempt: normalize_positive_integer(map_get(attrs, :retry_attempt), 1),
      retry_lineage: decode_json_list(map_get(attrs, :retry_lineage, []), []),
      started_at: normalize_datetime(map_get(attrs, :started_at)) || now,
      completed_at: normalize_datetime(map_get(attrs, :completed_at)),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp list(record_type, filters, opts, mapper) do
    query = Keyword.get(opts, :query)
    merged_filters = Map.merge(query_filter(query), normalize_filter_map(filters))
    store_opts = opts |> Keyword.delete(:query) |> Keyword.put(:query, %{limit: 500, offset: 0})

    with {:ok, records} <- Store.list(record_type, %{}, store_opts) do
      results =
        records
        |> Enum.map(mapper)
        |> Enum.filter(&matches_filters?(&1, merged_filters))
        |> sort_records(query_sort(query))
        |> limit_records(query_limit(query))

      {:ok, results}
    end
  end

  defp execution_profile_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      compact_join([map_get(record, :managed_repo_id), normalize_string(map_get(record, :name), "default")])
  end

  defp run_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      compact_join([map_get(record, :managed_repo_id), map_get(record, :run_id)])
  end

  defp compact_join(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp existing_id(nil, _field), do: nil
  defp existing_id(existing, field), do: normalize_optional_string(map_get(existing, field) || map_get(existing, :id))

  defp existing_datetime(nil, _field), do: nil
  defp existing_datetime(existing, field), do: normalize_datetime(map_get(existing, field))

  defp query_filter(query) when is_list(query), do: query |> Keyword.get(:filter, %{}) |> normalize_filter_map()
  defp query_filter(query) when is_map(query), do: query |> map_get(:filter, %{}) |> normalize_filter_map()
  defp query_filter(_query), do: %{}

  defp query_sort(query) when is_list(query), do: Keyword.get(query, :sort, [])
  defp query_sort(query) when is_map(query), do: map_get(query, :sort, [])
  defp query_sort(_query), do: []

  defp query_limit(query) when is_list(query), do: Keyword.get(query, :limit)
  defp query_limit(query) when is_map(query), do: map_get(query, :limit)
  defp query_limit(_query), do: nil

  defp normalize_filter_map(filters) when is_list(filters), do: Map.new(filters)
  defp normalize_filter_map(filters) when is_map(filters), do: filters
  defp normalize_filter_map(_filters), do: %{}

  defp sort_records(records, [{field, direction} | _rest]) do
    sorted = Enum.sort_by(records, &sort_value(Map.get(&1, field)), DateTime)
    if direction == :desc or direction == "desc", do: Enum.reverse(sorted), else: sorted
  rescue
    _error -> records
  end

  defp sort_records(records, _sort), do: records

  defp sort_value(%DateTime{} = value), do: value
  defp sort_value(nil), do: ~U[0000-01-01 00:00:00Z]
  defp sort_value(value), do: value

  defp limit_records(records, limit) when is_integer(limit) and limit >= 0, do: Enum.take(records, limit)
  defp limit_records(records, _limit), do: records

  defp matches_filters?(record, filters) do
    Enum.all?(filters, fn {key, expected} ->
      actual = Map.get(record, key) || Map.get(record, to_string(key))
      values_equal?(actual, expected)
    end)
  end

  defp values_equal?(actual, expected) when is_list(expected), do: Enum.any?(expected, &values_equal?(actual, &1))
  defp values_equal?(actual, expected), do: normalize_comparable(actual) == normalize_comparable(expected)

  defp normalize_comparable(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_comparable(value), do: value

  defp normalize_record_map(%Ash.NotLoaded{}), do: %{}

  defp normalize_record_map(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__])
    |> normalize_record_map()
  end

  defp normalize_record_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_key(key)
      normalized_value = normalize_record_value(normalized_key, nested_value)
      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: Map.get(@atom_key_aliases, key, key)

  defp normalize_key(key) when is_binary(key) do
    Map.get(@top_level_key_aliases, key) ||
      Map.get(@top_level_key_aliases, Macro.underscore(key)) ||
      key
  end

  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp normalize_record_value(key, value) when key in @map_fields, do: decode_json_map(value)
  defp normalize_record_value(key, value) when key in @list_fields, do: decode_json_list(value, [])
  defp normalize_record_value(_key, %Ash.NotLoaded{}), do: nil
  defp normalize_record_value(_key, %Ecto.Schema.Metadata{}), do: nil
  defp normalize_record_value(_key, %DateTime{} = value), do: DateTime.truncate(value, :microsecond)
  defp normalize_record_value(_key, %NaiveDateTime{} = value), do: value
  defp normalize_record_value(_key, value) when is_map(value), do: normalize_map(value)
  defp normalize_record_value(_key, value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_record_value(_key, value), do: value

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> normalize_map(decoded)
      _other -> %{}
    end
  end

  defp decode_json_map(%Ash.NotLoaded{}), do: %{}
  defp decode_json_map(%Ecto.Schema.Metadata{}), do: %{}
  defp decode_json_map(%_{} = value), do: value |> Map.from_struct() |> normalize_map()
  defp decode_json_map(value) when is_map(value), do: normalize_map(value)
  defp decode_json_map(_value), do: %{}

  defp decode_json_list(value, default) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> Enum.map(decoded, &normalize_nested_value/1)
      _other -> default
    end
  end

  defp decode_json_list(value, _default) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp decode_json_list(_value, default), do: default

  defp normalize_map(%Ash.NotLoaded{}), do: %{}
  defp normalize_map(%Ecto.Schema.Metadata{}), do: %{}

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      Map.put(acc, to_string(key), normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(%Ash.NotLoaded{}), do: nil
  defp normalize_nested_value(%Ecto.Schema.Metadata{}), do: nil

  defp normalize_nested_value(%DateTime{} = value),
    do: value |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp normalize_nested_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_nested_value(%_{} = value), do: value |> Map.from_struct() |> normalize_map()
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> normalize_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_datetime(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

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

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> default
    end
  end

  defp normalize_positive_integer(_value, default), do: default

  defp normalize_atom(value, known_atoms, default) when is_atom(value) do
    if value in Map.values(known_atoms), do: value, else: default
  end

  defp normalize_atom(value, known_atoms, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> default
      normalized -> Map.get(known_atoms, normalized, default)
    end
  end

  defp normalize_atom(_value, _known_atoms, default), do: default

  defp map_from_struct(%_{} = value), do: Map.from_struct(value)
  defp map_from_struct(value), do: value

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
  defp generated_run_id, do: "run-" <> Integer.to_string(System.unique_integer([:positive]))
end
