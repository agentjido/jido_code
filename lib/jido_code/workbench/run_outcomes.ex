defmodule JidoCode.Workbench.RunOutcomes do
  @moduledoc """
  Resolves recent governed run outcomes for workbench repository rows.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Orchestration.{Run, WorkflowRun}

  @fallback_row_id_prefix "workbench-row-"
  @query_timeout_ms 5_000

  @known_statuses MapSet.new([
                    "pending",
                    "running",
                    "awaiting_approval",
                    "completed",
                    "failed",
                    "cancelled"
                  ])

  @query_failure_error_type "workbench_recent_run_outcome_lookup_failed"
  @status_unresolved_error_type "workbench_recent_run_status_unresolved"
  @default_unknown_guidance "Refresh workbench data to resolve recent run status."

  @type run_outcome :: %{
          status: String.t(),
          run_id: String.t() | nil,
          detail_path: String.t() | nil,
          error_type: String.t() | nil,
          detail: String.t() | nil,
          guidance: String.t() | nil
        }

  @spec load([map()]) :: %{optional(String.t()) => run_outcome()}
  def load(rows) when is_list(rows) do
    loader =
      Application.get_env(
        :jido_code,
        :workbench_recent_run_outcome_loader,
        &__MODULE__.default_loader/1
      )

    if is_function(loader, 1) do
      safe_invoke_loader(loader, rows)
    else
      fallback_unknown_outcomes(
        rows,
        "Workbench recent run outcome loader is invalid.",
        "workbench_recent_run_outcome_loader_invalid"
      )
    end
  end

  def load(_rows), do: %{}

  @doc false
  @spec default_loader([map()]) :: %{optional(String.t()) => run_outcome()}
  def default_loader(rows) when is_list(rows) do
    row_scopes = row_scopes(rows)

    row_scopes
    |> Task.async_stream(
      &load_project_outcome/1,
      ordered: true,
      timeout: @query_timeout_ms
    )
    |> Enum.zip(Enum.map(row_scopes, & &1.id))
    |> Enum.reduce(%{}, fn
      {{:ok, {:ok, nil}}, _project_id}, outcomes ->
        outcomes

      {{:ok, {:ok, outcome}}, project_id}, outcomes when is_map(outcome) ->
        Map.put(outcomes, project_id, outcome)

      {{:ok, {:error, reason}}, project_id}, outcomes ->
        Map.put(
          outcomes,
          project_id,
          unknown_outcome(
            nil,
            nil,
            "Recent run lookup failed (#{format_reason(reason)}).",
            @query_failure_error_type
          )
        )

      {{:exit, reason}, project_id}, outcomes ->
        Map.put(
          outcomes,
          project_id,
          unknown_outcome(
            nil,
            nil,
            "Recent run lookup crashed (#{format_reason(reason)}).",
            @query_failure_error_type
          )
        )
    end)
  end

  def default_loader(_rows), do: %{}

  defp safe_invoke_loader(loader, rows) do
    try do
      case loader.(rows) do
        {:ok, outcomes} when is_map(outcomes) ->
          normalize_outcomes(outcomes, rows)

        outcomes when is_map(outcomes) ->
          normalize_outcomes(outcomes, rows)

        {:error, reason} ->
          fallback_unknown_outcomes(
            rows,
            "Recent run outcome lookup failed (#{format_reason(reason)}).",
            @query_failure_error_type
          )

        other ->
          fallback_unknown_outcomes(
            rows,
            "Recent run outcome loader returned an invalid result (#{inspect(other)}).",
            @query_failure_error_type
          )
      end
    rescue
      exception ->
        fallback_unknown_outcomes(
          rows,
          "Recent run outcome loader crashed (#{Exception.message(exception)}).",
          @query_failure_error_type
        )
    catch
      kind, reason ->
        fallback_unknown_outcomes(
          rows,
          "Recent run outcome loader threw #{inspect({kind, reason})}.",
          @query_failure_error_type
        )
    end
  end

  defp load_project_outcome(%{id: project_id} = scope) do
    if fallback_row_id?(project_id) do
      {:ok,
       unknown_outcome(
         nil,
         nil,
         "Recent run status is unavailable for synthetic workbench rows.",
         @status_unresolved_error_type
       )}
    else
      case load_governed_run_outcome(scope) do
        {:ok, nil} ->
          load_legacy_run_outcome(scope)

        other ->
          other
      end
    end
  end

  defp load_project_outcome(_scope), do: {:ok, nil}

  defp load_governed_run_outcome(%{managed_repo_id: managed_repo_id, project_id: project_id}) do
    case normalize_optional_string(managed_repo_id) do
      nil ->
        {:ok, nil}

      normalized_managed_repo_id ->
        case Run.read(
               query: [filter: [managed_repo_id: normalized_managed_repo_id], sort: [started_at: :desc], limit: 1],
               actor: Actor.operator_actor()
             ) do
          {:ok, [run | _]} -> {:ok, run_outcome_from_run(project_id, run)}
          {:ok, []} -> {:ok, nil}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp load_legacy_run_outcome(%{project_id: project_id}) do
    case normalize_optional_string(project_id) do
      nil ->
        {:ok, nil}

      normalized_project_id ->
        case WorkflowRun.read(query: [filter: [project_id: normalized_project_id], sort: [started_at: :desc], limit: 1]) do
          {:ok, [run | _]} -> {:ok, run_outcome_from_run(normalized_project_id, run)}
          {:ok, []} -> {:ok, nil}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp run_outcome_from_run(project_id, run) do
    run_id =
      run
      |> map_get(:run_id, "run_id")
      |> normalize_optional_string()

    status =
      run
      |> map_get(:status, "status")
      |> normalize_status()

    detail_path = run_detail_path(project_id, run_id)

    cond do
      status == "unknown" ->
        unknown_outcome(
          run_id,
          detail_path,
          "Recent run status could not be resolved from run history.",
          @status_unresolved_error_type
        )

      is_nil(run_id) ->
        unknown_outcome(
          nil,
          nil,
          "Recent run identifier could not be resolved from run history.",
          @status_unresolved_error_type
        )

      true ->
        %{
          status: status,
          run_id: run_id,
          detail_path: detail_path,
          error_type: nil,
          detail: nil,
          guidance: nil
        }
    end
  end

  defp normalize_outcomes(outcomes, rows) do
    rows
    |> project_ids()
    |> Enum.reduce(%{}, fn project_id, normalized ->
      case outcome_for_project(outcomes, project_id) do
        nil ->
          if fallback_row_id?(project_id) do
            Map.put(
              normalized,
              project_id,
              unknown_outcome(
                nil,
                nil,
                "Recent run status is unavailable for synthetic workbench rows.",
                @status_unresolved_error_type
              )
            )
          else
            normalized
          end

        outcome when is_map(outcome) ->
          Map.put(normalized, project_id, normalize_outcome(outcome, project_id))

        other ->
          Map.put(
            normalized,
            project_id,
            unknown_outcome(
              nil,
              nil,
              "Recent run outcome payload is invalid (#{inspect(other)}).",
              @status_unresolved_error_type
            )
          )
      end
    end)
  end

  defp normalize_outcome(outcome, project_id) do
    run_id =
      outcome
      |> map_get(:run_id, "run_id")
      |> normalize_optional_string()

    status =
      outcome
      |> map_get(:status, "status")
      |> normalize_status()

    detail_path =
      outcome
      |> map_get(:detail_path, "detail_path")
      |> normalize_optional_string() || run_detail_path(project_id, run_id)

    error_type =
      outcome
      |> map_get(:error_type, "error_type")
      |> normalize_optional_string()

    detail =
      outcome
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    guidance =
      outcome
      |> map_get(:guidance, "guidance")
      |> normalize_optional_string()

    cond do
      status == "unknown" ->
        unknown_outcome(
          run_id,
          detail_path,
          detail || "Recent run status could not be resolved.",
          error_type || @status_unresolved_error_type,
          guidance
        )

      is_nil(run_id) ->
        unknown_outcome(
          nil,
          nil,
          detail || "Recent run identifier could not be resolved.",
          error_type || @status_unresolved_error_type,
          guidance
        )

      true ->
        %{
          status: status,
          run_id: run_id,
          detail_path: detail_path,
          error_type: nil,
          detail: nil,
          guidance: nil
        }
    end
  end

  defp fallback_unknown_outcomes(rows, detail, error_type) do
    rows
    |> project_ids()
    |> Enum.reduce(%{}, fn project_id, outcomes ->
      Map.put(
        outcomes,
        project_id,
        unknown_outcome(
          nil,
          nil,
          detail,
          error_type
        )
      )
    end)
  end

  defp unknown_outcome(run_id, detail_path, detail, error_type, guidance \\ nil) do
    %{
      status: "unknown",
      run_id: normalize_optional_string(run_id),
      detail_path: normalize_optional_string(detail_path),
      error_type: normalize_optional_string(error_type) || @status_unresolved_error_type,
      detail: normalize_optional_string(detail) || "Recent run status could not be resolved.",
      guidance: normalize_optional_string(guidance) || @default_unknown_guidance
    }
  end

  defp outcome_for_project(outcomes, project_id) when is_map(outcomes) do
    Enum.find_value(outcomes, fn {candidate_project_id, candidate_outcome} ->
      if normalize_optional_string(candidate_project_id) == project_id do
        candidate_outcome
      end
    end)
  end

  defp run_detail_path(project_id, run_id) do
    normalized_project_id = normalize_optional_string(project_id)
    normalized_run_id = normalize_optional_string(run_id)

    if normalized_project_id && normalized_run_id do
      "/projects/#{URI.encode(normalized_project_id)}/runs/#{URI.encode(normalized_run_id)}"
    end
  end

  defp project_ids(rows) when is_list(rows) do
    rows
    |> Enum.map(fn row ->
      row
      |> map_get(:id, "id")
      |> normalize_optional_string()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp project_ids(_rows), do: []

  defp row_scopes(rows) when is_list(rows) do
    rows
    |> Enum.map(fn row ->
      %{
        id:
          row
          |> map_get(:id, "id")
          |> normalize_optional_string(),
        project_id:
          row
          |> map_get(:legacy_project_id, "legacy_project_id")
          |> normalize_optional_string() ||
            row
            |> map_get(:id, "id")
            |> normalize_optional_string(),
        managed_repo_id:
          row
          |> map_get(:managed_repo_id, "managed_repo_id")
          |> normalize_optional_string()
      }
    end)
    |> Enum.reject(&is_nil(&1.id))
  end

  defp row_scopes(_rows), do: []

  defp fallback_row_id?(project_id) do
    case normalize_optional_string(project_id) do
      <<@fallback_row_id_prefix, _::binary>> -> true
      _other -> false
    end
  end

  defp normalize_status(status) when is_atom(status),
    do: status |> Atom.to_string() |> normalize_status()

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> case do
      normalized_status when normalized_status in [""] ->
        "unknown"

      normalized_status ->
        if MapSet.member?(@known_statuses, normalized_status),
          do: normalized_status,
          else: "unknown"
    end
  end

  defp normalize_status(_status), do: "unknown"

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

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
