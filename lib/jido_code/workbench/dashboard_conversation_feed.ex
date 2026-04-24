defmodule JidoCode.Workbench.DashboardConversationFeed do
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  @moduledoc """
  Loads bounded conversation supervision summaries for dashboard visibility.

  Dashboard callers get action-oriented repo, work-item, and clarification
  signals without taking ownership of transcript-heavy conversation state.
  """

  alias JidoCode.Workbench.Inventory

  @default_error_type "dashboard_conversation_summary_feed_fetch_failed"

  @default_remediation """
  Retry dashboard conversation refresh. If this persists, inspect repository conversation supervision from repo detail.
  """

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type conversation_summary :: %{
          id: String.t(),
          route_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          repo_label: String.t(),
          role_scope: String.t() | nil,
          role_attachment_mode: String.t() | nil,
          role_work_item_id: String.t() | nil,
          latest_status: String.t() | nil,
          active_count: non_neg_integer(),
          clarification_count: non_neg_integer(),
          detail: String.t(),
          latest_work_item_summary: String.t() | nil,
          latest_activity_at: DateTime.t() | nil,
          route: String.t() | nil,
          action_label: String.t()
        }

  @spec load() :: {:ok, [conversation_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def load do
    loader =
      Application.get_env(
        :jido_code,
        :dashboard_conversation_summary_loader,
        &__MODULE__.default_loader/0
      )

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       stale_warning(
         "dashboard_conversation_summary_loader_invalid",
         "Dashboard conversation summary loader is invalid.",
         @default_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [conversation_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def default_loader do
    case Inventory.load() do
      {:ok, rows, warning} ->
        summaries =
          rows
          |> Enum.map(&to_summary/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(&summary_sort_key/1, :desc)

        {:ok, summaries, normalize_warning(warning)}

      {:error, warning} ->
        {:error,
         normalize_warning(warning) ||
           stale_warning(
             @default_error_type,
             "Dashboard conversation supervision may be stale.",
             @default_remediation
           )}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, summaries, warning} when is_list(summaries) ->
          {:ok, Enum.map(summaries, &normalize_summary/1), normalize_warning(warning)}

        {:error, warning} ->
          {:error,
           normalize_warning(warning) ||
             stale_warning(
               @default_error_type,
               "Dashboard conversation supervision may be stale.",
               @default_remediation
             )}

        other ->
          {:error,
           stale_warning(
             @default_error_type,
             "Dashboard conversation summary loader returned an invalid result (#{inspect(other)}).",
             @default_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         stale_warning(
           @default_error_type,
           "Dashboard conversation summary loader crashed (#{Exception.message(exception)}).",
           @default_remediation
         )}
    catch
      kind, reason ->
        {:error,
         stale_warning(
           @default_error_type,
           "Dashboard conversation summary loader threw #{inspect({kind, reason})}.",
           @default_remediation
         )}
    end
  end

  defp to_summary(row) when is_map(row) do
    supervision =
      row
      |> map_get(:conversation_supervision, "conversation_supervision")
      |> normalize_map()

    repo_intake = map_get(supervision, :repo_intake, "repo_intake", %{}) |> normalize_map()
    latest_entry = map_get(supervision, :latest_entry, "latest_entry", %{}) |> normalize_map()

    active_count =
      supervision
      |> map_get(:active_count, "active_count", 0)
      |> normalize_count()

    clarification_count =
      supervision
      |> map_get(:clarification_count, "clarification_count", 0)
      |> normalize_count()

    if active_count > 0 or clarification_count > 0 do
      route_id = normalize_optional_string(map_get(row, :id, "id"))
      managed_repo_id = normalize_optional_string(map_get(row, :managed_repo_id, "managed_repo_id"))
      repo_label = repo_label(row)
      role_projection = role_projection(active_count, latest_entry, repo_intake)
      latest_work_item = map_get(latest_entry, :work_item, "work_item", %{}) |> normalize_map()

      %{
        id: "dashboard-conversation-summary-#{route_id || managed_repo_id || repo_label}",
        route_id: route_id,
        managed_repo_id: managed_repo_id,
        repo_label: repo_label,
        role_scope:
          role_projection
          |> map_get(:conversation, "conversation", %{})
          |> map_get(:scope, "scope")
          |> normalize_optional_string(),
        role_attachment_mode:
          role_projection
          |> map_get(:conversation, "conversation", %{})
          |> map_get(:attachment_mode, "attachment_mode")
          |> normalize_optional_string(),
        role_work_item_id:
          role_projection
          |> map_get(:conversation, "conversation", %{})
          |> map_get(:work_item_id, "work_item_id")
          |> normalize_optional_string(),
        latest_status:
          role_projection
          |> map_get(:conversation, "conversation", %{})
          |> map_get(:status, "status")
          |> normalize_optional_string(),
        active_count: active_count,
        clarification_count: clarification_count,
        detail: summary_detail(active_count, clarification_count, latest_work_item),
        latest_work_item_summary:
          latest_work_item
          |> map_get(:summary, "summary")
          |> normalize_optional_string(),
        latest_activity_at:
          supervision
          |> map_get(:latest_activity_at, "latest_activity_at")
          |> normalize_datetime(),
        route: route_id && "/repos/#{route_id}#project-detail-conversation-panel",
        action_label: action_label(active_count, clarification_count)
      }
    end
  end

  defp to_summary(_row), do: nil

  defp normalize_summary(summary) when is_map(summary) do
    route = normalize_optional_string(map_get(summary, :route, "route"))

    %{
      id:
        normalize_optional_string(map_get(summary, :id, "id")) ||
          "dashboard-conversation-summary-#{System.unique_integer([:positive])}",
      route_id: normalize_optional_string(map_get(summary, :route_id, "route_id")),
      managed_repo_id: normalize_optional_string(map_get(summary, :managed_repo_id, "managed_repo_id")),
      repo_label: normalize_optional_string(map_get(summary, :repo_label, "repo_label")) || "Unknown repository",
      role_scope: normalize_optional_string(map_get(summary, :role_scope, "role_scope")),
      role_attachment_mode: normalize_optional_string(map_get(summary, :role_attachment_mode, "role_attachment_mode")),
      role_work_item_id: normalize_optional_string(map_get(summary, :role_work_item_id, "role_work_item_id")),
      latest_status: normalize_optional_string(map_get(summary, :latest_status, "latest_status")),
      active_count: normalize_count(map_get(summary, :active_count, "active_count", 0)),
      clarification_count: normalize_count(map_get(summary, :clarification_count, "clarification_count", 0)),
      detail:
        normalize_optional_string(map_get(summary, :detail, "detail")) ||
          "Conversation supervision is available from repo detail.",
      latest_work_item_summary:
        normalize_optional_string(map_get(summary, :latest_work_item_summary, "latest_work_item_summary")),
      latest_activity_at:
        summary
        |> map_get(:latest_activity_at, "latest_activity_at")
        |> normalize_datetime(),
      route: route,
      action_label:
        normalize_optional_string(map_get(summary, :action_label, "action_label")) ||
          action_label(
            normalize_count(map_get(summary, :active_count, "active_count", 0)),
            normalize_count(map_get(summary, :clarification_count, "clarification_count", 0))
          )
    }
  end

  defp normalize_summary(_summary) do
    %{
      id: "dashboard-conversation-summary-unknown",
      route_id: nil,
      managed_repo_id: nil,
      repo_label: "Unknown repository",
      role_scope: nil,
      role_attachment_mode: nil,
      role_work_item_id: nil,
      latest_status: nil,
      active_count: 0,
      clarification_count: 0,
      detail: "Conversation supervision is unavailable.",
      latest_work_item_summary: nil,
      latest_activity_at: nil,
      route: nil,
      action_label: "Open repo detail"
    }
  end

  defp role_projection(active_count, latest_entry, _repo_intake)
       when active_count > 0 and map_size(latest_entry) > 0,
       do: latest_entry

  defp role_projection(_active_count, _latest_entry, repo_intake) when map_size(repo_intake) > 0,
    do: repo_intake

  defp role_projection(_active_count, _latest_entry, _repo_intake), do: %{}

  defp summary_detail(active_count, clarification_count, latest_work_item) do
    latest_work_item_summary =
      latest_work_item
      |> map_get(:summary, "summary")
      |> normalize_optional_string()

    cond do
      active_count > 0 and clarification_count > 0 and latest_work_item_summary ->
        "#{active_count_label(active_count)} active. #{clarification_label(clarification_count)}. Latest governed work: #{latest_work_item_summary}."

      active_count > 0 and clarification_count > 0 ->
        "#{active_count_label(active_count)} active. #{clarification_label(clarification_count)}."

      active_count > 0 and latest_work_item_summary ->
        "#{active_count_label(active_count)} active. Latest governed work: #{latest_work_item_summary}."

      active_count > 0 ->
        "#{active_count_label(active_count)} active from repo detail."

      clarification_count > 0 ->
        "Conversation work is waiting on clarification before governed follow-up can continue."

      true ->
        "Conversation supervision is available from repo detail."
    end
  end

  defp active_count_label(1), do: "1 governed conversation"
  defp active_count_label(count), do: "#{count} governed conversations"

  defp clarification_label(1), do: "1 clarification turn needs an answer"
  defp clarification_label(count), do: "#{count} clarification turns need answers"

  defp action_label(active_count, _clarification_count) when active_count > 0,
    do: "Open governed supervision"

  defp action_label(_active_count, clarification_count) when clarification_count > 0,
    do: "Open repo intake"

  defp action_label(_active_count, _clarification_count), do: "Open repo detail"

  defp summary_sort_key(summary) do
    {
      normalize_count(map_get(summary, :clarification_count, "clarification_count", 0)),
      normalize_count(map_get(summary, :active_count, "active_count", 0)),
      sortable_timestamp(map_get(summary, :latest_activity_at, "latest_activity_at")),
      repo_label(summary)
    }
  end

  defp repo_label(row) do
    normalize_optional_string(map_get(row, :repo_label, "repo_label")) ||
      normalize_optional_string(map_get(row, :github_full_name, "github_full_name")) ||
      normalize_optional_string(map_get(row, :name, "name")) ||
      "Unknown repository"
  end

  defp normalize_warning(warning) when is_map(warning) do
    %{
      error_type:
        warning
        |> map_get(:error_type, "error_type")
        |> normalize_optional_string() || @default_error_type,
      detail:
        warning
        |> map_get(:detail, "detail")
        |> normalize_optional_string() || "Dashboard conversation supervision may be stale.",
      remediation:
        warning
        |> map_get(:remediation, "remediation")
        |> normalize_optional_string() || @default_remediation
    }
  end

  defp normalize_warning(_warning), do: nil

  defp stale_warning(error_type, detail, remediation) do
    %{error_type: error_type, detail: detail, remediation: remediation}
  end

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value
  defp normalize_count(value) when is_float(value) and value >= 0, do: trunc(value)

  defp normalize_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> 0
    end
  end

  defp normalize_count(_value), do: 0

  defp sortable_timestamp(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp sortable_timestamp(value) when is_binary(value) do
    value
    |> normalize_datetime()
    |> sortable_timestamp()
  end

  defp sortable_timestamp(_value), do: 0

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
