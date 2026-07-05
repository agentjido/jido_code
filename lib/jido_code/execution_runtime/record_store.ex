defmodule JidoCode.ExecutionRuntime.RecordStore do
  @moduledoc """
  Store-backed execution runtime records.

  This is the product-owned persistence boundary for the legacy Forge runtime
  implementation. The returned structs remain the existing Forge resource
  structs until the module namespace is renamed in a later removal pass.
  """

  alias JidoCode.ControlPlane.RecordStore, as: Store

  alias JidoCode.Forge.Resources.{
    Checkpoint,
    Event,
    ExecSession,
    Session,
    SpriteSpec,
    Workflow
  }

  @unscoped_repo_id "unscoped"
  @max_output_summary_bytes 10_000

  @phase_values ~w(created provisioning bootstrapping ready running needs_input completed failed cancelled resuming)a
  @runner_values ~w(shell claude_code workflow custom)a
  @exec_status_values ~w(started completed needs_continuation needs_input failed timeout)a

  @id_predicates %{
    execution_workflow_id: "executionWorkflowId",
    sandbox_session_id: "sandboxSessionId",
    runtime_event_id: "runtimeEventId",
    checkpoint_id: "checkpointId",
    exec_session_id: "execSessionId",
    sprite_spec_id: "spriteSpecId"
  }

  @top_level_key_aliases %{
    "id" => :id,
    "managed_repo_id" => :managed_repo_id,
    "managedRepoId" => :managed_repo_id,
    "execution_workflow_id" => :execution_workflow_id,
    "executionWorkflowId" => :execution_workflow_id,
    "sandbox_session_id" => :sandbox_session_id,
    "sandboxSessionId" => :sandbox_session_id,
    "runtime_event_id" => :runtime_event_id,
    "runtimeEventId" => :runtime_event_id,
    "checkpoint_id" => :checkpoint_id,
    "checkpointId" => :checkpoint_id,
    "exec_session_id" => :exec_session_id,
    "execSessionId" => :exec_session_id,
    "sprite_spec_id" => :sprite_spec_id,
    "spriteSpecId" => :sprite_spec_id,
    "session_id" => :sandbox_session_id,
    "name" => :name,
    "description" => :description,
    "version" => :version,
    "steps" => :steps,
    "stepsJson" => :steps,
    "timeout_ms" => :timeout_ms,
    "timeoutMs" => :timeout_ms,
    "on_error" => :on_error,
    "onError" => :on_error,
    "max_retries" => :max_retries,
    "maxRetries" => :max_retries,
    "tags" => :tags,
    "tagsJson" => :tags,
    "phase" => :phase,
    "recordStatus" => :phase,
    "runner_type" => :runner_type,
    "runnerType" => :runner_type,
    "runner" => :runner,
    "runner_config" => :runner_config,
    "runnerConfigJson" => :runner_config,
    "runner_state" => :runner_state,
    "runnerStateJson" => :runner_state,
    "runner_state_snapshot" => :runner_state_snapshot,
    "runnerStateSnapshotJson" => :runner_state_snapshot,
    "spec" => :spec,
    "specJson" => :spec,
    "sprite_id" => :sprite_id,
    "spriteId" => :sprite_id,
    "sprite_name" => :sprite_name,
    "spriteName" => :sprite_name,
    "last_checkpoint_id" => :last_checkpoint_id,
    "lastCheckpointId" => :last_checkpoint_id,
    "execution_count" => :execution_count,
    "executionCount" => :execution_count,
    "output_buffer" => :output_buffer,
    "outputSummary" => :output,
    "output" => :output,
    "last_error" => :last_error,
    "lastErrorJson" => :last_error,
    "sprites_checkpoint_id" => :sprites_checkpoint_id,
    "spritesCheckpointId" => :sprites_checkpoint_id,
    "exec_session_sequence" => :exec_session_sequence,
    "execSessionSequence" => :exec_session_sequence,
    "sequence" => :sequence,
    "status" => :status,
    "command" => :command,
    "exit_code" => :exit_code,
    "exitCode" => :exit_code,
    "output_size_bytes" => :output_size_bytes,
    "outputSizeBytes" => :output_size_bytes,
    "error" => :error,
    "errorJson" => :error,
    "cost_usd" => :cost_usd,
    "costUsd" => :cost_usd,
    "duration_ms" => :duration_ms,
    "durationMs" => :duration_ms,
    "sprites_session_id" => :sprites_session_id,
    "spritesSessionId" => :sprites_session_id,
    "event_type" => :event_type,
    "eventName" => :event_type,
    "data" => :payload,
    "payload" => :payload,
    "payloadJson" => :payload,
    "source_kind" => :source_kind,
    "sourceKind" => :source_kind,
    "base_image" => :base_image,
    "baseImage" => :base_image,
    "env" => :env,
    "envJson" => :env,
    "bootstrap_steps" => :bootstrap_steps,
    "bootstrapStepsJson" => :bootstrap_steps,
    "file_injection" => :file_injection,
    "fileInjectionJson" => :file_injection,
    "timeouts" => :timeouts,
    "timeoutsJson" => :timeouts,
    "resource_limits" => :resource_limits,
    "resourceLimitsJson" => :resource_limits,
    "started_at" => :started_at,
    "startedAt" => :started_at,
    "completed_at" => :completed_at,
    "completedAt" => :completed_at,
    "last_activity_at" => :last_activity_at,
    "lastActivityAt" => :last_activity_at,
    "created_at" => :created_at,
    "createdAt" => :created_at,
    "timestamp" => :occurred_at,
    "occurred_at" => :occurred_at,
    "occurredAt" => :occurred_at,
    "inserted_at" => :inserted_at,
    "insertedAt" => :inserted_at,
    "updated_at" => :updated_at,
    "updatedAt" => :updated_at,
    "metadata" => :metadata,
    "metadataJson" => :metadata
  }

  @top_level_atom_aliases %{
    data: :payload,
    session_id: :sandbox_session_id
  }

  @map_fields [
    :runner_config,
    :runner_state,
    :spec,
    :last_error,
    :runner_state_snapshot,
    :error,
    :payload,
    :env,
    :timeouts,
    :resource_limits,
    :metadata
  ]

  @list_fields [:steps, :tags, :bootstrap_steps, :file_injection]

  @spec upsert_execution_workflow(map(), keyword()) :: {:ok, Workflow.t()} | {:error, term()}
  def upsert_execution_workflow(attrs, opts \\ []) when is_map(attrs) do
    upsert(:execution_workflow, attrs, opts, &workflow_record/2, &to_workflow/1, &existing_workflow/2)
  end

  @spec upsert_sprite_spec(map(), keyword()) :: {:ok, SpriteSpec.t()} | {:error, term()}
  def upsert_sprite_spec(attrs, opts \\ []) when is_map(attrs) do
    upsert(:sprite_spec, attrs, opts, &sprite_spec_record/2, &to_sprite_spec/1, &existing_sprite_spec/2)
  end

  @spec upsert_sandbox_session(map(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def upsert_sandbox_session(attrs, opts \\ []) when is_map(attrs) do
    upsert(:sandbox_session, attrs, opts, &sandbox_session_record/2, &to_session/1, &existing_sandbox_session/2)
  end

  @spec update_sandbox_session(Session.t(), map(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def update_sandbox_session(%Session{} = session, attrs, opts \\ []) when is_map(attrs) do
    session
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__])
    |> Map.merge(attrs)
    |> Map.put(:sandbox_session_id, session.id)
    |> Map.put_new(:name, session.name)
    |> upsert_sandbox_session(opts)
  end

  @spec get_sandbox_session(String.t(), keyword()) :: {:ok, Session.t() | nil} | {:error, term()}
  def get_sandbox_session(identifier, opts \\ []) when is_binary(identifier) do
    with {:ok, record} <- existing_sandbox_session(%{sandbox_session_id: identifier, name: identifier}, opts) do
      {:ok, record && to_session(record)}
    end
  end

  @spec list_sandbox_sessions(map(), keyword()) :: {:ok, [Session.t()]} | {:error, term()}
  def list_sandbox_sessions(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:sandbox_session, filters, opts, &to_session/1)
  end

  @spec list_exec_sessions(map(), keyword()) :: {:ok, [ExecSession.t()]} | {:error, term()}
  def list_exec_sessions(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:exec_session, filters, opts, &to_exec_session/1)
  end

  @spec list_runtime_events(map(), keyword()) :: {:ok, [Event.t()]} | {:error, term()}
  def list_runtime_events(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:runtime_event, filters, opts, &to_event/1)
  end

  @spec list_checkpoints(map(), keyword()) :: {:ok, [Checkpoint.t()]} | {:error, term()}
  def list_checkpoints(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:checkpoint, filters, opts, &to_checkpoint/1)
  end

  @spec create_exec_session(map(), keyword()) :: {:ok, ExecSession.t()} | {:error, term()}
  def create_exec_session(attrs, opts \\ []) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_record_map()
      |> put_session_scope(opts)
      |> Map.put_new(:status, :started)
      |> Map.put_new(:exec_session_id, Ecto.UUID.generate())

    upsert(:exec_session, attrs, opts, &exec_session_record/2, &to_exec_session/1, &existing_exec_session/2)
  end

  @spec update_exec_session(String.t(), map(), keyword()) :: {:ok, ExecSession.t()} | {:error, term()}
  def update_exec_session(exec_session_id, attrs, opts \\ []) when is_binary(exec_session_id) and is_map(attrs) do
    with {:ok, existing} <- existing_exec_session(%{exec_session_id: exec_session_id}, opts),
         {:ok, %ExecSession{} = exec_session} <- ok_existing(existing, :exec_session_not_found) do
      attrs =
        exec_session
        |> Map.from_struct()
        |> Map.drop([:__meta__, :__metadata__])
        |> Map.merge(attrs)
        |> Map.put(:exec_session_id, exec_session.id)

      upsert(:exec_session, attrs, opts, &exec_session_record/2, &to_exec_session/1, &existing_exec_session/2)
    end
  end

  @spec create_runtime_event(map(), keyword()) :: {:ok, Event.t()} | {:error, term()}
  def create_runtime_event(attrs, opts \\ []) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_record_map()
      |> put_session_scope(opts)
      |> Map.put_new(:runtime_event_id, Ecto.UUID.generate())
      |> Map.put_new(:source_kind, "execution_runtime")

    upsert(:runtime_event, attrs, opts, &runtime_event_record/2, &to_event/1, &existing_runtime_event/2)
  end

  @spec create_checkpoint(map(), keyword()) :: {:ok, Checkpoint.t()} | {:error, term()}
  def create_checkpoint(attrs, opts \\ []) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_record_map()
      |> put_session_scope(opts)
      |> Map.put_new(:checkpoint_id, Ecto.UUID.generate())

    upsert(:checkpoint, attrs, opts, &checkpoint_record/2, &to_checkpoint/1, &existing_checkpoint/2)
  end

  @spec latest_checkpoint(String.t(), keyword()) :: {:ok, Checkpoint.t() | nil} | {:error, term()}
  def latest_checkpoint(session_id, opts \\ []) when is_binary(session_id) do
    with {:ok, checkpoints} <- list(:checkpoint, %{sandbox_session_id: session_id}, opts, &to_checkpoint/1) do
      checkpoint =
        checkpoints
        |> Enum.sort_by(&sort_datetime(&1.created_at), :desc)
        |> List.first()

      {:ok, checkpoint}
    end
  end

  defp upsert(record_type, attrs, opts, record_builder, mapper, existing_fun) do
    attrs = normalize_record_map(attrs)

    with {:ok, existing} <- existing_fun.(attrs, opts),
         record <- record_builder.(attrs, existing),
         {:ok, saved_record} <- Store.upsert(record_type, record, opts) do
      {:ok, mapper.(saved_record)}
    end
  end

  defp existing_workflow(attrs, opts), do: get_by_id_or_name(:execution_workflow, :execution_workflow_id, attrs, opts)
  defp existing_sprite_spec(attrs, opts), do: get_by_id_or_name(:sprite_spec, :sprite_spec_id, attrs, opts)
  defp existing_sandbox_session(attrs, opts), do: get_by_id_or_name(:sandbox_session, :sandbox_session_id, attrs, opts)
  defp existing_exec_session(attrs, opts), do: get_by_id(:exec_session, :exec_session_id, attrs, opts)
  defp existing_runtime_event(attrs, opts), do: get_by_id(:runtime_event, :runtime_event_id, attrs, opts)
  defp existing_checkpoint(attrs, opts), do: get_by_id(:checkpoint, :checkpoint_id, attrs, opts)

  defp get_by_id_or_name(record_type, id_field, attrs, opts) do
    name = normalize_optional_string(map_get(attrs, :name))

    with {:ok, by_id} <- get_by_id(record_type, id_field, attrs, opts) do
      case {by_id, name} do
        {nil, name} when is_binary(name) ->
          Store.get_by_identity(record_type, :unique_name, "name", name, opts)

        _other ->
          {:ok, by_id}
      end
    end
  end

  defp get_by_id(record_type, id_field, attrs, opts) do
    id = normalize_optional_string(map_get(attrs, id_field) || map_get(attrs, :id))
    predicate = Map.fetch!(@id_predicates, id_field)
    Store.get_by_identity(record_type, :"unique_#{id_field}", predicate, id, opts)
  end

  defp ok_existing(nil, reason), do: {:error, reason}
  defp ok_existing(record, _reason), do: {:ok, to_exec_session(record)}

  defp workflow_record(attrs, existing) do
    now = now()

    %{
      execution_workflow_id: existing_id(existing, :execution_workflow_id) || id_from(attrs, :execution_workflow_id),
      name: normalize_string(map_get(attrs, :name), "workflow"),
      description: normalize_optional_string(map_get(attrs, :description)),
      version: normalize_non_negative_integer(map_get(attrs, :version), 1),
      steps: decode_json_list(map_get(attrs, :steps, []), []),
      timeout_ms: normalize_non_negative_integer(map_get(attrs, :timeout_ms), 3_600_000),
      on_error: normalize_atom(map_get(attrs, :on_error), [:halt, :continue], :halt),
      max_retries: normalize_non_negative_integer(map_get(attrs, :max_retries), 0),
      tags: decode_json_list(map_get(attrs, :tags, []), []),
      inserted_at: existing_datetime(existing, :inserted_at) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp sprite_spec_record(attrs, existing) do
    now = now()

    %{
      sprite_spec_id: existing_id(existing, :sprite_spec_id) || id_from(attrs, :sprite_spec_id),
      name: normalize_string(map_get(attrs, :name), "sprite"),
      description: normalize_optional_string(map_get(attrs, :description)),
      runner: normalize_atom(map_get(attrs, :runner), @runner_values, :shell),
      runner_config: decode_json_map(map_get(attrs, :runner_config, %{})),
      base_image: normalize_string(map_get(attrs, :base_image), "ubuntu-22.04"),
      env: decode_json_map(map_get(attrs, :env, %{})),
      bootstrap_steps: decode_json_list(map_get(attrs, :bootstrap_steps, []), []),
      file_injection: decode_json_list(map_get(attrs, :file_injection, []), []),
      timeouts: decode_json_map(map_get(attrs, :timeouts, %{})),
      resource_limits: decode_json_map(map_get(attrs, :resource_limits, %{})),
      inserted_at: existing_datetime(existing, :inserted_at) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp sandbox_session_record(attrs, existing) do
    now = now()
    managed_repo_id = normalize_optional_string(map_get(attrs, :managed_repo_id)) || @unscoped_repo_id

    %{
      sandbox_session_id: existing_id(existing, :sandbox_session_id) || id_from(attrs, :sandbox_session_id),
      managed_repo_id: managed_repo_id,
      name: normalize_string(map_get(attrs, :name), "session"),
      phase: normalize_atom(map_get(attrs, :phase), @phase_values, :created),
      runner_type: normalize_atom(map_get(attrs, :runner_type), @runner_values, :shell),
      runner_config: decode_json_map(map_get(attrs, :runner_config, %{})),
      runner_state: decode_json_map(map_get(attrs, :runner_state, %{})),
      spec: decode_json_map(map_get(attrs, :spec, %{})),
      sprite_id: normalize_optional_string(map_get(attrs, :sprite_id)),
      sprite_name: normalize_optional_string(map_get(attrs, :sprite_name)),
      last_checkpoint_id: normalize_optional_string(map_get(attrs, :last_checkpoint_id)),
      execution_count:
        normalize_non_negative_integer(
          map_get(attrs, :execution_count),
          existing_integer(existing, :execution_count, 0)
        ),
      output_buffer: bounded_output(map_get(attrs, :output_buffer) || map_get(attrs, :output)),
      last_error: decode_json_map(map_get(attrs, :last_error, %{})),
      started_at: normalize_datetime(map_get(attrs, :started_at)),
      completed_at: normalize_datetime(map_get(attrs, :completed_at)),
      last_activity_at: normalize_datetime(map_get(attrs, :last_activity_at)) || now,
      inserted_at: existing_datetime(existing, :inserted_at) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp exec_session_record(attrs, existing) do
    now = now()

    %{
      exec_session_id: existing_id(existing, :exec_session_id) || id_from(attrs, :exec_session_id),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)) || @unscoped_repo_id,
      sandbox_session_id: normalize_optional_string(map_get(attrs, :sandbox_session_id)),
      sequence: normalize_positive_integer(map_get(attrs, :sequence)) || 1,
      status: normalize_atom(map_get(attrs, :status), @exec_status_values, :started),
      command: normalize_optional_string(map_get(attrs, :command)),
      exit_code: normalize_integer(map_get(attrs, :exit_code)),
      output: bounded_output(map_get(attrs, :output)),
      output_size_bytes: output_size(map_get(attrs, :output), map_get(attrs, :output_size_bytes)),
      error: decode_json_map(map_get(attrs, :error, %{})),
      cost_usd: normalize_optional_string(map_get(attrs, :cost_usd)),
      duration_ms: normalize_non_negative_integer(map_get(attrs, :duration_ms), 0),
      sprites_session_id: normalize_optional_string(map_get(attrs, :sprites_session_id)),
      started_at: normalize_datetime(map_get(attrs, :started_at)) || existing_datetime(existing, :started_at) || now,
      completed_at: normalize_datetime(map_get(attrs, :completed_at)),
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp runtime_event_record(attrs, existing) do
    now = now()
    event_type = normalize_string(map_get(attrs, :event_type), "runtime.event")

    %{
      runtime_event_id: existing_id(existing, :runtime_event_id) || id_from(attrs, :runtime_event_id),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)) || @unscoped_repo_id,
      sandbox_session_id: normalize_optional_string(map_get(attrs, :sandbox_session_id)),
      exec_session_sequence: normalize_integer(map_get(attrs, :exec_session_sequence)),
      event_type: event_type,
      source_kind: normalize_string(map_get(attrs, :source_kind), "execution_runtime"),
      title: normalize_optional_string(map_get(attrs, :title)) || event_type,
      occurred_at: normalize_datetime(map_get(attrs, :occurred_at)) || now,
      payload: decode_json_map(map_get(attrs, :payload, %{})),
      inserted_at: existing_datetime(existing, :inserted_at) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp checkpoint_record(attrs, existing) do
    now = now()

    %{
      checkpoint_id: existing_id(existing, :checkpoint_id) || id_from(attrs, :checkpoint_id),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)) || @unscoped_repo_id,
      sandbox_session_id: normalize_optional_string(map_get(attrs, :sandbox_session_id)),
      sprites_checkpoint_id: normalize_string(map_get(attrs, :sprites_checkpoint_id), "checkpoint"),
      name: normalize_optional_string(map_get(attrs, :name)),
      exec_session_sequence: normalize_integer(map_get(attrs, :exec_session_sequence)),
      runner_state_snapshot: decode_json_map(map_get(attrs, :runner_state_snapshot, %{})),
      created_at: normalize_datetime(map_get(attrs, :created_at)) || existing_datetime(existing, :created_at) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp list(record_type, filters, opts, mapper) do
    with {:ok, records} <- Store.list(record_type, %{}, Keyword.put(opts, :query, %{limit: 500, offset: 0})) do
      normalized_filters = normalize_record_map(filters)

      {:ok,
       records
       |> Enum.map(mapper)
       |> Enum.filter(&matches_filters?(&1, normalized_filters))}
    end
  end

  defp put_session_scope(attrs, opts) do
    session_id = normalize_optional_string(map_get(attrs, :sandbox_session_id))

    case get_sandbox_session(session_id || "", opts) do
      {:ok, %Session{} = session} ->
        attrs
        |> put_if_missing(:sandbox_session_id, session.id)
        |> put_if_missing(:managed_repo_id, Map.get(session, :managed_repo_id))

      _other ->
        Map.put_new(attrs, :managed_repo_id, @unscoped_repo_id)
    end
  end

  defp to_workflow(record) do
    record = normalize_record_map(record)

    struct!(Workflow, %{
      id: map_get(record, :execution_workflow_id),
      name: map_get(record, :name),
      description: map_get(record, :description),
      version: normalize_non_negative_integer(map_get(record, :version), 1),
      steps: decode_json_list(map_get(record, :steps, []), []),
      timeout_ms: normalize_non_negative_integer(map_get(record, :timeout_ms), 3_600_000),
      on_error: normalize_atom(map_get(record, :on_error), [:halt, :continue], :halt),
      max_retries: normalize_non_negative_integer(map_get(record, :max_retries), 0),
      tags: decode_json_list(map_get(record, :tags, []), []),
      metadata: decode_json_map(map_get(record, :metadata, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    })
  end

  defp to_sprite_spec(record) do
    record = normalize_record_map(record)

    struct!(SpriteSpec, %{
      id: map_get(record, :sprite_spec_id),
      name: map_get(record, :name),
      description: map_get(record, :description),
      runner: normalize_atom(map_get(record, :runner), @runner_values, :shell),
      runner_config: decode_json_map(map_get(record, :runner_config, %{})),
      base_image: normalize_string(map_get(record, :base_image), "ubuntu-22.04"),
      env: decode_json_map(map_get(record, :env, %{})),
      bootstrap_steps: decode_json_list(map_get(record, :bootstrap_steps, []), []),
      file_injection: decode_json_list(map_get(record, :file_injection, []), []),
      timeouts: decode_json_map(map_get(record, :timeouts, %{})),
      resource_limits: decode_json_map(map_get(record, :resource_limits, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    })
  end

  defp to_session(record) do
    record = normalize_record_map(record)

    Session
    |> struct!(%{
      id: map_get(record, :sandbox_session_id),
      name: map_get(record, :name),
      phase: normalize_atom(map_get(record, :phase), @phase_values, :created),
      runner_type: normalize_atom(map_get(record, :runner_type), @runner_values, :shell),
      runner_config: decode_json_map(map_get(record, :runner_config, %{})),
      runner_state: decode_json_map(map_get(record, :runner_state, %{})),
      spec: decode_json_map(map_get(record, :spec, %{})),
      sprite_id: map_get(record, :sprite_id),
      sprite_name: map_get(record, :sprite_name),
      last_checkpoint_id: map_get(record, :last_checkpoint_id),
      execution_count: normalize_non_negative_integer(map_get(record, :execution_count), 0),
      output_buffer: map_get(record, :output_buffer) || map_get(record, :output),
      last_error: decode_json_map(map_get(record, :last_error, %{})),
      started_at: normalize_datetime(map_get(record, :started_at)),
      completed_at: normalize_datetime(map_get(record, :completed_at)),
      last_activity_at: normalize_datetime(map_get(record, :last_activity_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at)),
      metadata: decode_json_map(map_get(record, :metadata, %{}))
    })
    |> Map.put(:managed_repo_id, map_get(record, :managed_repo_id))
  end

  defp to_exec_session(record) do
    record = normalize_record_map(record)

    ExecSession
    |> struct!(%{
      id: map_get(record, :exec_session_id),
      session_id: map_get(record, :sandbox_session_id),
      sequence: normalize_positive_integer(map_get(record, :sequence)) || 1,
      status: normalize_atom(map_get(record, :status), @exec_status_values, :started),
      command: map_get(record, :command),
      exit_code: normalize_integer(map_get(record, :exit_code)),
      output: map_get(record, :output),
      output_size_bytes: normalize_non_negative_integer(map_get(record, :output_size_bytes), 0),
      error: decode_json_map(map_get(record, :error, %{})),
      cost_usd: map_get(record, :cost_usd),
      duration_ms: normalize_non_negative_integer(map_get(record, :duration_ms), 0),
      sprites_session_id: map_get(record, :sprites_session_id),
      started_at: normalize_datetime(map_get(record, :started_at)),
      completed_at: normalize_datetime(map_get(record, :completed_at)),
      metadata: decode_json_map(map_get(record, :metadata, %{}))
    })
    |> Map.put(:managed_repo_id, map_get(record, :managed_repo_id))
  end

  defp to_event(record) do
    record = normalize_record_map(record)

    struct!(Event, %{
      id: map_get(record, :runtime_event_id),
      session_id: map_get(record, :sandbox_session_id),
      event_type: map_get(record, :event_type),
      data: decode_json_map(map_get(record, :payload, %{})),
      exec_session_sequence: normalize_integer(map_get(record, :exec_session_sequence)),
      timestamp: normalize_datetime(map_get(record, :occurred_at) || map_get(record, :inserted_at))
    })
  end

  defp to_checkpoint(record) do
    record = normalize_record_map(record)

    Checkpoint
    |> struct!(%{
      id: map_get(record, :checkpoint_id),
      session_id: map_get(record, :sandbox_session_id),
      sprites_checkpoint_id: map_get(record, :sprites_checkpoint_id),
      name: map_get(record, :name),
      exec_session_sequence: normalize_integer(map_get(record, :exec_session_sequence)),
      runner_state_snapshot: decode_json_map(map_get(record, :runner_state_snapshot, %{})),
      metadata: decode_json_map(map_get(record, :metadata, %{})),
      created_at: normalize_datetime(map_get(record, :created_at))
    })
    |> Map.put(:managed_repo_id, map_get(record, :managed_repo_id))
  end

  defp matches_filters?(record, filters) do
    Enum.all?(filters, fn {key, expected} ->
      actual = filter_value(record, key)

      case expected do
        expected_values when is_list(expected_values) ->
          normalize_comparable(actual) in Enum.map(expected_values, &normalize_comparable/1)

        expected_value ->
          normalize_comparable(actual) == normalize_comparable(expected_value)
      end
    end)
  end

  defp filter_value(record, :sandbox_session_id) do
    Map.get(record, :sandbox_session_id) || Map.get(record, :session_id) || Map.get(record, "sandbox_session_id") ||
      Map.get(record, "session_id")
  end

  defp filter_value(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))

  defp normalize_record_map(%_{} = value), do: value |> Map.from_struct() |> normalize_record_map()

  defp normalize_record_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_key(key)
      Map.put(acc, normalized_key, normalize_record_value(normalized_key, nested_value))
    end)
  end

  defp normalize_record_map(_value), do: %{}

  defp normalize_key(key) when is_atom(key), do: Map.get(@top_level_atom_aliases, key, key)

  defp normalize_key(key) when is_binary(key) do
    Map.get(@top_level_key_aliases, key) ||
      Map.get(@top_level_key_aliases, Macro.underscore(key)) ||
      key
  end

  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp normalize_record_value(key, value) when key in @map_fields, do: decode_json_map(value)
  defp normalize_record_value(key, value) when key in @list_fields, do: decode_json_list(value, [])
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

  defp normalize_map(%_{}), do: %{}

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      Map.put(acc, to_string(key), normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(%DateTime{} = value),
    do: value |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp normalize_nested_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_nested_value(%_{} = value), do: inspect(value)
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp id_from(attrs, id_field),
    do: normalize_optional_string(map_get(attrs, id_field) || map_get(attrs, :id)) || Ecto.UUID.generate()

  defp existing_id(nil, _field), do: nil
  defp existing_id(existing, field), do: normalize_optional_string(map_get(existing, field) || map_get(existing, :id))

  defp existing_datetime(nil, _field), do: nil
  defp existing_datetime(existing, field), do: normalize_datetime(map_get(existing, field))

  defp existing_integer(nil, _field, default), do: default
  defp existing_integer(existing, field, default), do: normalize_non_negative_integer(map_get(existing, field), default)

  defp normalize_datetime(%DateTime{} = value), do: DateTime.truncate(value, :microsecond)

  defp normalize_datetime(%NaiveDateTime{} = value) do
    case DateTime.from_naive(value, "Etc/UTC") do
      {:ok, datetime} -> normalize_datetime(datetime)
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
  defp normalize_optional_string(value) when is_float(value), do: Float.to_string(value)
  defp normalize_optional_string(%Decimal{} = value), do: Decimal.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_positive_integer(value) do
    case normalize_integer(value) do
      integer when is_integer(integer) and integer > 0 -> integer
      _other -> nil
    end
  end

  defp normalize_non_negative_integer(value, default) do
    case normalize_integer(value) do
      integer when is_integer(integer) and integer >= 0 -> integer
      _other -> default
    end
  end

  defp normalize_atom(value, known_atoms, default) when is_atom(value) do
    if value in known_atoms, do: value, else: default
  end

  defp normalize_atom(value, known_atoms, default) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    Enum.find(known_atoms, default, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_atom(_value, _known_atoms, default), do: default

  defp normalize_comparable(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_comparable(value), do: value

  defp bounded_output(nil), do: nil

  defp bounded_output(output) do
    output
    |> to_string()
    |> then(fn value ->
      if byte_size(value) > @max_output_summary_bytes do
        "...[truncated]...\n" <>
          binary_part(value, byte_size(value) - @max_output_summary_bytes, @max_output_summary_bytes)
      else
        value
      end
    end)
  end

  defp output_size(nil, explicit_size), do: normalize_non_negative_integer(explicit_size, 0)
  defp output_size(output, _explicit_size), do: output |> to_string() |> byte_size()

  defp sort_datetime(nil), do: 0
  defp sort_datetime(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp sort_datetime(_value), do: 0

  defp put_if_missing(attrs, _key, nil), do: attrs

  defp put_if_missing(attrs, key, value) do
    case normalize_optional_string(map_get(attrs, key)) do
      nil -> Map.put(attrs, key, value)
      _existing -> attrs
    end
  end

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
