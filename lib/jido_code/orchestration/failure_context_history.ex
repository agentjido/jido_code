defmodule JidoCode.Orchestration.FailureContextHistory do
  @moduledoc """
  Queries failed run context history for dashboard trend review.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Orchestration.WorkflowRun

  @default_window_days 30
  @default_limit 200
  @max_limit 500
  @default_error_type "workflow_run_failed"
  @default_last_successful_step "unknown"

  @validation_error_type "dashboard_failure_history_query_validation_failed"
  @query_error_type "dashboard_failure_history_query_failed"
  @query_operation "query_failure_context_history"

  @validation_remediation """
  Provide valid `window_start` and `window_end` values (ISO8601 or DateTime) and retry the query.
  """

  @query_remediation """
  Retry failure history query. If this persists, inspect workflow run persistence health.
  """

  @default_remediation_hint """
  Inspect failure artifacts and run timeline, then retry after resolving the failing step.
  """

  @type failure_history_entry :: %{
          run_id: String.t(),
          project_id: String.t() | nil,
          workflow_name: String.t(),
          failed_at: DateTime.t(),
          error_type: String.t(),
          last_successful_step: String.t(),
          remediation_hint: String.t()
        }

  @type typed_error :: %{
          error_type: String.t(),
          operation: String.t(),
          reason_type: String.t(),
          detail: String.t(),
          remediation: String.t(),
          field_errors: [map()],
          partial_results: [failure_history_entry()]
        }

  @type query_params :: %{
          window_start: DateTime.t(),
          window_end: DateTime.t(),
          limit: pos_integer()
        }

  @spec query(map() | keyword()) :: {:ok, [failure_history_entry()]} | {:error, typed_error()}
  def query(params \\ %{}) do
    with {:ok, query_params} <- normalize_query_params(params),
         {:ok, loader} <- resolve_loader() do
      safe_invoke_loader(loader, query_params)
    end
  end

  @doc false
  @spec default_loader(query_params()) ::
          {:ok, [failure_history_entry()]} | {:error, typed_error()}
  def default_loader(query_params) when is_map(query_params) do
    case WorkflowRun.read(
           query: [filter: [status: :failed], sort: [completed_at: :desc]],
           actor: Actor.operator_actor()
         ) do
      {:ok, runs} ->
        failure_history =
          runs
          |> Enum.map(&to_failure_history_entry/1)
          |> Enum.filter(&within_time_window?(&1, query_params))
          |> Enum.sort_by(
            fn entry ->
              entry
              |> Map.fetch!(:failed_at)
              |> DateTime.to_unix(:microsecond)
            end,
            :desc
          )
          |> Enum.take(Map.fetch!(query_params, :limit))

        {:ok, failure_history}

      {:error, reason} ->
        {:error,
         query_error(
           "Failure history query failed (#{format_reason(reason)}).",
           "query_failed"
         )}
    end
  end

  def default_loader(_query_params) do
    {:error,
     query_error(
       "Failure history query parameters are invalid.",
       "query_parameters_invalid"
     )}
  end

  defp resolve_loader do
    loader =
      Application.get_env(
        :jido_code,
        :dashboard_failure_history_loader,
        &__MODULE__.default_loader/1
      )

    if is_function(loader, 1) do
      {:ok, loader}
    else
      {:error,
       query_error(
         "Dashboard failure history loader is invalid.",
         "loader_invalid"
       )}
    end
  end

  defp safe_invoke_loader(loader, query_params)
       when is_function(loader, 1) and is_map(query_params) do
    try do
      case loader.(query_params) do
        {:ok, entries} when is_list(entries) ->
          {:ok, normalize_entries(entries)}

        entries when is_list(entries) ->
          {:ok, normalize_entries(entries)}

        {:error, typed_error} when is_map(typed_error) ->
          {:error, normalize_query_error(typed_error)}

        other ->
          {:error,
           query_error(
             "Failure history loader returned an invalid result (#{inspect(other)}).",
             "loader_result_invalid"
           )}
      end
    rescue
      exception ->
        {:error,
         query_error(
           "Failure history loader crashed (#{Exception.message(exception)}).",
           "loader_crashed"
         )}
    catch
      kind, reason ->
        {:error,
         query_error(
           "Failure history loader threw #{inspect({kind, reason})}.",
           "loader_threw"
         )}
    end
  end

  defp safe_invoke_loader(_loader, _query_params) do
    {:error,
     query_error(
       "Failure history loader is invalid.",
       "loader_invalid"
     )}
  end

  defp normalize_query_params(params) when is_list(params) do
    params
    |> Enum.into(%{})
    |> normalize_query_params()
  end

  defp normalize_query_params(params) when is_map(params) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    default_window_start = DateTime.add(now, -@default_window_days * 86_400, :second)

    with {:ok, window_start} <-
           parse_datetime(
             map_get(params, :window_start, "window_start", default_window_start),
             "window_start"
           ),
         {:ok, window_end} <-
           parse_datetime(map_get(params, :window_end, "window_end", now), "window_end"),
         {:ok, limit} <- parse_limit(map_get(params, :limit, "limit", @default_limit)),
         :ok <- validate_time_window(window_start, window_end) do
      {:ok, %{window_start: window_start, window_end: window_end, limit: limit}}
    else
      {:error, field_errors} when is_list(field_errors) ->
        {:error,
         validation_error(
           "Failure history query parameters are invalid.",
           field_errors
         )}
    end
  end

  defp normalize_query_params(_params) do
    {:error,
     validation_error(
       "Failure history query parameters are invalid.",
       [field_error("params", "invalid_type", "Query params must be a map or keyword list.")]
     )}
  end

  defp parse_datetime(value, field_name) do
    case normalize_optional_datetime(value) do
      %DateTime{} = parsed_datetime ->
        {:ok, parsed_datetime}

      nil ->
        {:error,
         [
           field_error(
             field_name,
             "invalid_datetime",
             "Expected an ISO8601 datetime or DateTime value."
           )
         ]}
    end
  end

  defp parse_limit(value) when is_integer(value) and value >= 1 and value <= @max_limit,
    do: {:ok, value}

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed_limit, ""} -> parse_limit(parsed_limit)
      _other -> {:error, [field_error("limit", "invalid", limit_error_detail())]}
    end
  end

  defp parse_limit(_value), do: {:error, [field_error("limit", "invalid", limit_error_detail())]}

  defp validate_time_window(window_start, window_end) do
    case DateTime.compare(window_start, window_end) do
      :gt ->
        {:error,
         [
           field_error(
             "window_start",
             "out_of_range",
             "`window_start` must be less than or equal to `window_end`."
           ),
           field_error(
             "window_end",
             "out_of_range",
             "`window_end` must be greater than or equal to `window_start`."
           )
         ]}

      _other ->
        :ok
    end
  end

  defp limit_error_detail do
    "Expected a positive integer between 1 and #{@max_limit}."
  end

  defp to_failure_history_entry(run) when is_map(run) do
    error =
      run
      |> map_get(:error, "error", %{})
      |> normalize_map()

    %{
      run_id:
        run
        |> map_get(:run_id, "run_id")
        |> normalize_optional_string() || "unknown-run",
      project_id:
        run
        |> map_get(:project_id, "project_id")
        |> normalize_optional_string(),
      workflow_name:
        run
        |> map_get(:workflow_name, "workflow_name")
        |> normalize_optional_string() || "unknown_workflow",
      failed_at: resolve_failed_at(run, error),
      error_type:
        error
        |> map_get(:error_type, "error_type")
        |> normalize_optional_string() || @default_error_type,
      last_successful_step:
        error
        |> map_get(:last_successful_step, "last_successful_step")
        |> normalize_optional_string() || @default_last_successful_step,
      remediation_hint:
        error
        |> map_get(:remediation, "remediation")
        |> normalize_optional_string() ||
          error
          |> map_get(:remediation_hint, "remediation_hint")
          |> normalize_optional_string() || String.trim(@default_remediation_hint)
    }
  end

  defp to_failure_history_entry(_run) do
    %{
      run_id: "unknown-run",
      project_id: nil,
      workflow_name: "unknown_workflow",
      failed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      error_type: @default_error_type,
      last_successful_step: @default_last_successful_step,
      remediation_hint: String.trim(@default_remediation_hint)
    }
  end

  defp resolve_failed_at(run, error) do
    run
    |> map_get(:completed_at, "completed_at")
    |> normalize_optional_datetime() ||
      error
      |> map_get(:timestamp, "timestamp")
      |> normalize_optional_datetime() ||
      run
      |> map_get(:updated_at, "updated_at")
      |> normalize_optional_datetime() ||
      run
      |> map_get(:started_at, "started_at")
      |> normalize_optional_datetime() || DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp within_time_window?(entry, query_params) when is_map(entry) and is_map(query_params) do
    failed_at =
      entry
      |> Map.get(:failed_at)
      |> normalize_optional_datetime()

    window_start = Map.fetch!(query_params, :window_start)
    window_end = Map.fetch!(query_params, :window_end)

    if is_nil(failed_at) do
      false
    else
      DateTime.compare(failed_at, window_start) in [:eq, :gt] and
        DateTime.compare(failed_at, window_end) in [:eq, :lt]
    end
  end

  defp within_time_window?(_entry, _query_params), do: false

  defp normalize_entries(entries) when is_list(entries) do
    entries
    |> Enum.map(fn
      entry when is_map(entry) ->
        normalize_entry(entry)

      entry ->
        to_failure_history_entry(entry)
    end)
    |> Enum.sort_by(
      fn entry ->
        entry
        |> Map.fetch!(:failed_at)
        |> DateTime.to_unix(:microsecond)
      end,
      :desc
    )
  end

  defp normalize_entries(_entries), do: []

  defp normalize_entry(entry) when is_map(entry) do
    %{
      run_id: entry |> map_get(:run_id, "run_id") |> normalize_optional_string() || "unknown-run",
      project_id: entry |> map_get(:project_id, "project_id") |> normalize_optional_string(),
      workflow_name:
        entry
        |> map_get(:workflow_name, "workflow_name")
        |> normalize_optional_string() || "unknown_workflow",
      failed_at:
        entry
        |> map_get(:failed_at, "failed_at")
        |> normalize_optional_datetime() || DateTime.utc_now() |> DateTime.truncate(:second),
      error_type:
        entry
        |> map_get(:error_type, "error_type")
        |> normalize_optional_string() || @default_error_type,
      last_successful_step:
        entry
        |> map_get(:last_successful_step, "last_successful_step")
        |> normalize_optional_string() || @default_last_successful_step,
      remediation_hint:
        entry
        |> map_get(:remediation_hint, "remediation_hint")
        |> normalize_optional_string() ||
          entry
          |> map_get(:remediation, "remediation")
          |> normalize_optional_string() || String.trim(@default_remediation_hint)
    }
  end

  defp normalize_query_error(error) when is_map(error) do
    %{
      error_type:
        error
        |> map_get(:error_type, "error_type")
        |> normalize_optional_string() || @query_error_type,
      operation:
        error
        |> map_get(:operation, "operation")
        |> normalize_optional_string() || @query_operation,
      reason_type:
        error
        |> map_get(:reason_type, "reason_type")
        |> normalize_optional_string() || "query_failed",
      detail:
        error
        |> map_get(:detail, "detail")
        |> normalize_optional_string() || "Failure history query failed.",
      remediation:
        error
        |> map_get(:remediation, "remediation")
        |> normalize_optional_string() || String.trim(@query_remediation),
      field_errors:
        error
        |> map_get(:field_errors, "field_errors", [])
        |> normalize_field_errors(),
      partial_results: []
    }
  end

  defp normalize_query_error(_error),
    do: query_error("Failure history query failed.", "query_failed")

  defp validation_error(detail, field_errors) do
    %{
      error_type: @validation_error_type,
      operation: @query_operation,
      reason_type: "invalid_query_parameters",
      detail: normalize_optional_string(detail) || "Failure history query parameters are invalid.",
      remediation: String.trim(@validation_remediation),
      field_errors: normalize_field_errors(field_errors),
      partial_results: []
    }
  end

  defp query_error(detail, reason_type) do
    %{
      error_type: @query_error_type,
      operation: @query_operation,
      reason_type: normalize_optional_string(reason_type) || "query_failed",
      detail: normalize_optional_string(detail) || "Failure history query failed.",
      remediation: String.trim(@query_remediation),
      field_errors: [],
      partial_results: []
    }
  end

  defp normalize_field_errors(field_errors) when is_list(field_errors) do
    field_errors
    |> Enum.map(&normalize_field_error/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_field_errors(_field_errors), do: []

  defp normalize_field_error(field_error) when is_map(field_error) do
    field =
      field_error
      |> map_get(:field, "field")
      |> normalize_optional_string()

    if is_binary(field) do
      %{
        field: field,
        error_type:
          field_error
          |> map_get(:error_type, "error_type")
          |> normalize_optional_string() || "invalid",
        detail:
          field_error
          |> map_get(:detail, "detail")
          |> normalize_optional_string() || "Invalid field value."
      }
    end
  end

  defp normalize_field_error(_field_error), do: nil

  defp field_error(field, error_type, detail) do
    %{
      field: normalize_optional_string(field) || "unknown",
      error_type: normalize_optional_string(error_type) || "invalid",
      detail: normalize_optional_string(detail) || "Invalid field value."
    }
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp normalize_optional_datetime(%DateTime{} = datetime),
    do: DateTime.truncate(datetime, :second)

  defp normalize_optional_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> DateTime.truncate(parsed_datetime, :second)
      _other -> nil
    end
  end

  defp normalize_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed_datetime, _offset} ->
        DateTime.truncate(parsed_datetime, :second)

      _other ->
        nil
    end
  end

  defp normalize_optional_datetime(_value), do: nil

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil
end
