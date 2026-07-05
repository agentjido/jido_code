defmodule JidoCode.ExecutionRuntime.Projections do
  @moduledoc """
  Product-shaped execution runtime read projections for operator surfaces.
  """

  alias JidoCode.ExecutionRuntime.RecordStore

  alias JidoCode.Forge.Resources.{
    Checkpoint,
    Event,
    ExecSession,
    Session
  }

  @default_limit 25
  @default_event_limit 50
  @default_exec_limit 25

  @spec sandbox_sessions(map(), keyword()) :: {:ok, map()}
  def sandbox_sessions(filters \\ %{}, opts \\ []) when is_map(filters) do
    limit = limit(opts, @default_limit)

    case RecordStore.list_sandbox_sessions(%{}, store_opts(opts)) do
      {:ok, sessions} ->
        projected_sessions =
          sessions
          |> Enum.filter(&session_matches?(&1, filters))
          |> Enum.sort_by(&sort_datetime(&1.last_activity_at || &1.updated_at), :desc)
          |> Enum.take(limit)

        {:ok,
         ready_projection(:sandbox_sessions, %{
           filters: normalize_filter_summary(filters),
           result_group: result_group(projected_sessions, limit),
           sessions: Enum.map(projected_sessions, &session_summary/1)
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:sandbox_sessions, %{filters: normalize_filter_summary(filters)}, reason)}
    end
  end

  @spec session_detail(String.t(), keyword()) :: {:ok, map()}
  def session_detail(session_id, opts \\ []) when is_binary(session_id) do
    record_opts = store_opts(opts)

    with {:ok, %Session{} = session} <- require_session(RecordStore.get_sandbox_session(session_id, record_opts)),
         {:ok, exec_projection} <- execution_history(session.id, Keyword.put(opts, :limit, exec_limit(opts))),
         {:ok, event_projection} <- event_history(session.id, Keyword.put(opts, :limit, event_limit(opts))),
         {:ok, latest_checkpoint} <- RecordStore.latest_checkpoint(session.id, record_opts) do
      {:ok,
       ready_projection(:sandbox_session_detail, %{
         session: session_summary(session),
         latest_checkpoint: checkpoint_summary(latest_checkpoint),
         latest_exec_session: latest_exec_summary(exec_projection.exec_sessions),
         execution_history: exec_projection,
         event_history: event_projection
       })}
    else
      {:ok, nil} ->
        {:ok, degraded_projection(:sandbox_session_detail, %{session_id: session_id}, :sandbox_session_not_found)}

      {:error, reason} ->
        {:ok, degraded_projection(:sandbox_session_detail, %{session_id: session_id}, reason)}
    end
  end

  @spec execution_history(String.t(), keyword()) :: {:ok, map()}
  def execution_history(session_id, opts \\ []) when is_binary(session_id) do
    limit = limit(opts, @default_exec_limit)

    case RecordStore.list_exec_sessions(%{sandbox_session_id: session_id}, store_opts(opts)) do
      {:ok, exec_sessions} ->
        ordered =
          exec_sessions
          |> Enum.sort_by(&(&1.sequence || 0), :desc)
          |> Enum.take(limit)

        {:ok,
         ready_projection(:exec_session_history, %{
           sandbox_session_id: session_id,
           result_group: result_group(ordered, limit),
           exec_sessions: Enum.map(ordered, &exec_summary/1)
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:exec_session_history, %{sandbox_session_id: session_id}, reason)}
    end
  end

  @spec event_history(String.t(), keyword()) :: {:ok, map()}
  def event_history(session_id, opts \\ []) when is_binary(session_id) do
    limit = limit(opts, @default_event_limit)

    case RecordStore.list_runtime_events(%{sandbox_session_id: session_id}, store_opts(opts)) do
      {:ok, events} ->
        ordered =
          events
          |> Enum.sort_by(&sort_datetime(&1.timestamp), :desc)
          |> Enum.take(limit)

        {:ok,
         ready_projection(:runtime_event_history, %{
           sandbox_session_id: session_id,
           result_group: result_group(ordered, limit),
           events: Enum.map(ordered, &event_summary/1)
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:runtime_event_history, %{sandbox_session_id: session_id}, reason)}
    end
  end

  defp require_session({:ok, nil}), do: {:ok, nil}
  defp require_session({:ok, %Session{} = session}), do: {:ok, session}
  defp require_session(other), do: other

  defp ready_projection(kind, fields) do
    Map.merge(
      %{
        kind: kind,
        status: :ready,
        degraded?: false,
        stale?: false
      },
      fields
    )
  end

  defp degraded_projection(kind, fields, reason) do
    Map.merge(
      %{
        kind: kind,
        status: :degraded,
        degraded?: true,
        stale?: true,
        result_group: result_group([], 0),
        error: %{type: :execution_runtime_projection_failed, detail: inspect(reason)}
      },
      fields
    )
  end

  defp result_group(items, limit) do
    %{
      count: length(items),
      limit: limit,
      empty?: items == []
    }
  end

  defp session_matches?(%Session{} = session, filters) do
    Enum.all?(filters, fn
      {:managed_repo_id, expected} -> comparable(Map.get(session, :managed_repo_id)) == comparable(expected)
      {"managed_repo_id", expected} -> comparable(Map.get(session, :managed_repo_id)) == comparable(expected)
      {:phase, expected} -> comparable(session.phase) in comparable_values(expected)
      {"phase", expected} -> comparable(session.phase) in comparable_values(expected)
      {:status, expected} -> comparable(session.phase) in comparable_values(expected)
      {"status", expected} -> comparable(session.phase) in comparable_values(expected)
      {:workflow, expected} -> comparable(session_workflow(session)) == comparable(expected)
      {"workflow", expected} -> comparable(session_workflow(session)) == comparable(expected)
      {:updated_after, expected} -> datetime_after?(session.last_activity_at || session.updated_at, expected)
      {"updated_after", expected} -> datetime_after?(session.last_activity_at || session.updated_at, expected)
      {:updated_since, expected} -> datetime_after?(session.last_activity_at || session.updated_at, expected)
      {"updated_since", expected} -> datetime_after?(session.last_activity_at || session.updated_at, expected)
      {_key, _expected} -> true
    end)
  end

  defp session_summary(%Session{} = session) do
    %{
      id: session.id,
      name: session.name,
      managed_repo_id: Map.get(session, :managed_repo_id),
      phase: session.phase,
      runner_type: session.runner_type,
      workflow: session_workflow(session),
      sprite_id: session.sprite_id,
      sprite_name: session.sprite_name,
      last_checkpoint_id: session.last_checkpoint_id,
      execution_count: session.execution_count || 0,
      output_summary: session.output_buffer,
      has_error?: normalize_map(session.last_error) != %{},
      started_at: session.started_at,
      completed_at: session.completed_at,
      last_activity_at: session.last_activity_at,
      updated_at: session.updated_at
    }
  end

  defp exec_summary(%ExecSession{} = exec_session) do
    %{
      id: exec_session.id,
      sandbox_session_id: exec_session.session_id,
      sequence: exec_session.sequence,
      status: exec_session.status,
      command: exec_session.command,
      exit_code: exec_session.exit_code,
      output_summary: exec_session.output,
      output_size_bytes: exec_session.output_size_bytes || 0,
      duration_ms: exec_session.duration_ms,
      sprites_session_id: exec_session.sprites_session_id,
      started_at: exec_session.started_at,
      completed_at: exec_session.completed_at
    }
  end

  defp event_summary(%Event{} = event) do
    %{
      id: event.id,
      sandbox_session_id: event.session_id,
      event_type: event.event_type,
      exec_session_sequence: event.exec_session_sequence,
      payload: event.data,
      occurred_at: event.timestamp
    }
  end

  defp checkpoint_summary(nil), do: nil

  defp checkpoint_summary(%Checkpoint{} = checkpoint) do
    %{
      id: checkpoint.id,
      sandbox_session_id: checkpoint.session_id,
      sprites_checkpoint_id: checkpoint.sprites_checkpoint_id,
      name: checkpoint.name,
      exec_session_sequence: checkpoint.exec_session_sequence,
      created_at: checkpoint.created_at
    }
  end

  defp latest_exec_summary([]), do: nil
  defp latest_exec_summary([latest | _rest]), do: latest

  defp session_workflow(%Session{} = session) do
    spec = normalize_map(session.spec)
    metadata = normalize_map(session.metadata)

    Map.get(spec, "workflow_id") ||
      Map.get(spec, "workflow") ||
      Map.get(spec, "workflow_name") ||
      Map.get(metadata, "workflow_id") ||
      Map.get(metadata, "workflow") ||
      Map.get(metadata, "workflow_name")
  end

  defp normalize_filter_summary(filters) when is_map(filters) do
    Map.new(filters, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_filter_summary(_filters), do: %{}

  defp normalize_map(value) when is_map(value),
    do: Map.new(value, fn {key, nested_value} -> {to_string(key), nested_value} end)

  defp normalize_map(_value), do: %{}

  defp comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp comparable(value) when is_binary(value), do: value
  defp comparable(value), do: to_string(value)

  defp comparable_values(values) when is_list(values), do: Enum.map(values, &comparable/1)
  defp comparable_values(value), do: [comparable(value)]

  defp datetime_after?(datetime, expected) do
    case {normalize_datetime(datetime), normalize_datetime(expected)} do
      {%DateTime{} = actual, %DateTime{} = threshold} -> DateTime.compare(actual, threshold) in [:gt, :eq]
      _other -> true
    end
  end

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_datetime(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp sort_datetime(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp sort_datetime(_datetime), do: -1

  defp limit(opts, default) do
    opts
    |> Keyword.get(:limit, default)
    |> non_negative_integer(default)
  end

  defp event_limit(opts),
    do: opts |> Keyword.get(:event_limit, @default_event_limit) |> non_negative_integer(@default_event_limit)

  defp exec_limit(opts),
    do: opts |> Keyword.get(:exec_limit, @default_exec_limit) |> non_negative_integer(@default_exec_limit)

  defp store_opts(opts) do
    case Keyword.get(opts, :actor) do
      nil -> []
      actor -> [actor: actor]
    end
  end

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> default
    end
  end

  defp non_negative_integer(_value, default), do: default
end
