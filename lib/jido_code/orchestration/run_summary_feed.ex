defmodule JidoCode.Orchestration.RunSummaryFeed do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  @moduledoc """
  Loads recent governed run summaries for dashboard visibility.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Governance.{ChangeRequest, Decision, Evidence}
  alias JidoCode.Orchestration.{Run, RunBridge, WorkflowRun}

  @default_limit 8
  @default_fetch_error_type "dashboard_run_summary_feed_fetch_failed"

  @default_fetch_remediation """
  Retry dashboard run summary refresh. If this persists, inspect workflow run persistence health.
  """

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type run_summary :: %{
          id: String.t(),
          run_id: String.t(),
          project_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          workflow_name: String.t(),
          status: String.t(),
          current_stage: String.t() | nil,
          evidence_count: non_neg_integer(),
          change_request_status: String.t() | nil,
          latest_decision: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  @spec load() :: {:ok, [run_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def load do
    loader =
      Application.get_env(:jido_code, :dashboard_run_summary_loader, &__MODULE__.default_loader/0)

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       stale_warning(
         "dashboard_run_summary_loader_invalid",
         "Dashboard run summary loader is invalid.",
         @default_fetch_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [run_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def default_loader do
    case Run.read(query: [sort: [started_at: :desc], limit: @default_limit], actor: Actor.operator_actor()) do
      {:ok, []} ->
        fallback_legacy_loader()

      {:ok, runs} ->
        {:ok, Enum.map(runs, &to_run_summary/1), nil}

      {:error, reason} ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard run summary fetch failed (#{format_reason(reason)}).",
           @default_fetch_remediation
         )}
    end
  end

  defp fallback_legacy_loader do
    case WorkflowRun.read(
           query: [sort: [started_at: :desc], limit: @default_limit],
           actor: Actor.operator_actor()
         ) do
      {:ok, runs} -> {:ok, Enum.map(runs, &projected_run_summary/1), nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp projected_run_summary(%WorkflowRun{} = workflow_run) do
    case RunBridge.projected_run_for_workflow_run(workflow_run) do
      {:ok, %Run{} = run} -> to_run_summary(run)
      _other -> to_run_summary(workflow_run)
    end
  end

  defp projected_run_summary(run), do: to_run_summary(run)

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, run_summaries, warning} when is_list(run_summaries) ->
          {:ok, Enum.map(run_summaries, &normalize_run_summary/1), normalize_warning(warning)}

        {:error, warning} ->
          {:error,
           normalize_warning(warning) ||
             stale_warning(
               @default_fetch_error_type,
               "Dashboard run summary data may be stale.",
               @default_fetch_remediation
             )}

        other ->
          {:error,
           stale_warning(
             @default_fetch_error_type,
             "Dashboard run summary loader returned an invalid result (#{inspect(other)}).",
             @default_fetch_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard run summary loader crashed (#{Exception.message(exception)}).",
           @default_fetch_remediation
         )}
    catch
      kind, reason ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard run summary loader threw #{inspect({kind, reason})}.",
           @default_fetch_remediation
         )}
    end
  end

  defp to_run_summary(run) do
    run_id =
      run
      |> map_get(:run_id, "run_id")
      |> normalize_optional_string()

    project_id =
      run
      |> map_get(:legacy_project_id, "legacy_project_id", map_get(run, :project_id, "project_id"))
      |> normalize_optional_string()

    managed_repo_id =
      run
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    governance = governance_summary(run)

    %{
      id: run_summary_id(project_id, run_id),
      run_id: run_id || "unknown-run",
      project_id: project_id,
      managed_repo_id: managed_repo_id,
      workflow_name:
        run
        |> map_get(:workflow_name, "workflow_name")
        |> normalize_optional_string() || "unknown_workflow",
      status:
        run
        |> map_get(:status, "status")
        |> normalize_status(),
      current_stage:
        run
        |> map_get(:current_stage, "current_stage")
        |> normalize_optional_string(),
      evidence_count: Map.get(governance, :evidence_count, 0),
      change_request_status: Map.get(governance, :change_request_status),
      latest_decision: Map.get(governance, :latest_decision),
      started_at:
        run
        |> map_get(:started_at, "started_at")
        |> normalize_datetime(),
      completed_at:
        run
        |> map_get(:completed_at, "completed_at")
        |> normalize_datetime()
    }
  end

  defp normalize_run_summary(run_summary) when is_map(run_summary) do
    run_id =
      run_summary
      |> map_get(:run_id, "run_id")
      |> normalize_optional_string()

    project_id =
      run_summary
      |> map_get(:project_id, "project_id")
      |> normalize_optional_string()

    %{
      id:
        run_summary
        |> map_get(:id, "id")
        |> normalize_optional_string() || run_summary_id(project_id, run_id),
      run_id: run_id || "unknown-run",
      project_id: project_id,
      managed_repo_id:
        run_summary
        |> map_get(:managed_repo_id, "managed_repo_id")
        |> normalize_optional_string(),
      workflow_name:
        run_summary
        |> map_get(:workflow_name, "workflow_name")
        |> normalize_optional_string() || "unknown_workflow",
      status:
        run_summary
        |> map_get(:status, "status")
        |> normalize_status(),
      current_stage:
        run_summary
        |> map_get(:current_stage, "current_stage")
        |> normalize_optional_string(),
      evidence_count:
        run_summary
        |> map_get(:evidence_count, "evidence_count", 0)
        |> normalize_count(),
      change_request_status:
        run_summary
        |> map_get(:change_request_status, "change_request_status")
        |> normalize_optional_string(),
      latest_decision:
        run_summary
        |> map_get(:latest_decision, "latest_decision")
        |> normalize_optional_string(),
      started_at:
        run_summary
        |> map_get(:started_at, "started_at")
        |> normalize_datetime(),
      completed_at:
        run_summary
        |> map_get(:completed_at, "completed_at")
        |> normalize_datetime()
    }
  end

  defp normalize_run_summary(_run_summary) do
    %{
      id: run_summary_id(nil, nil),
      run_id: "unknown-run",
      project_id: nil,
      managed_repo_id: nil,
      workflow_name: "unknown_workflow",
      status: "unknown",
      current_stage: nil,
      evidence_count: 0,
      change_request_status: nil,
      latest_decision: nil,
      started_at: nil,
      completed_at: nil
    }
  end

  defp governance_summary(%Run{} = run) do
    evidence_count =
      case Evidence.read(query: [filter: [run_id: run.id]], actor: Actor.operator_actor()) do
        {:ok, evidence_records} -> length(evidence_records)
        _other -> 0
      end

    change_request_status =
      case ChangeRequest.read(query: [filter: [run_id: run.id], limit: 1], actor: Actor.operator_actor()) do
        {:ok, [change_request | _rest]} ->
          change_request
          |> map_get(:status, "status")
          |> normalize_status()

        _other ->
          nil
      end

    latest_decision =
      case Decision.read(
             query: [filter: [run_id: run.id], sort: [decided_at: :desc], limit: 1],
             actor: Actor.operator_actor()
           ) do
        {:ok, [decision | _rest]} ->
          decision
          |> map_get(:decision, "decision")
          |> normalize_status()

        _other ->
          nil
      end

    %{
      evidence_count: evidence_count,
      change_request_status: change_request_status,
      latest_decision: latest_decision
    }
  end

  defp governance_summary(_run) do
    %{
      evidence_count: 0,
      change_request_status: nil,
      latest_decision: nil
    }
  end

  defp run_summary_id(project_id, run_id) do
    [
      normalize_optional_string(project_id) || "unknown-project",
      normalize_optional_string(run_id) || "unknown-run"
    ]
    |> Enum.join(":")
  end

  defp normalize_status(status) when is_atom(status), do: status |> Atom.to_string() |> normalize_status()

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> case do
      "" -> "unknown"
      normalized_status -> normalized_status
    end
  end

  defp normalize_status(_status), do: "unknown"

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value

  defp normalize_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp normalize_count(_value), do: 0

  defp normalize_warning(warning) when is_map(warning) do
    error_type = warning |> map_get(:error_type, "error_type") |> normalize_optional_string()
    detail = warning |> map_get(:detail, "detail") |> normalize_optional_string()
    remediation = warning |> map_get(:remediation, "remediation") |> normalize_optional_string()

    if error_type && detail && remediation do
      %{error_type: error_type, detail: detail, remediation: remediation}
    else
      nil
    end
  end

  defp normalize_warning(_warning), do: nil

  defp stale_warning(error_type, detail, remediation) do
    %{
      error_type: normalize_optional_string(error_type) || @default_fetch_error_type,
      detail: normalize_optional_string(detail) || "Dashboard run summary data may be stale.",
      remediation: normalize_optional_string(remediation) || @default_fetch_remediation
    }
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp normalize_datetime(%NaiveDateTime{} = naive_datetime) do
    case DateTime.from_naive(naive_datetime, "Etc/UTC") do
      {:ok, datetime} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        DateTime.truncate(datetime, :second)

      _other ->
        nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

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
