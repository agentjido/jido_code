defmodule JidoCode.Conversations.DashboardSummaryFeed do
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  @moduledoc """
  Loads bounded managed-repository conversation summaries for dashboard visibility.

  Dashboard callers get canonical repo and work-item conversation state without
  reconstructing it from transcript history or page-local browser state.
  """

  alias JidoCode.Workbench.Inventory

  @default_fetch_error_type "dashboard_conversation_summary_feed_fetch_failed"

  @default_fetch_remediation """
  Retry dashboard conversation refresh. If this persists, inspect repository conversation projection from the managed-repository route.
  """

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type work_item_summary :: %{
          id: String.t() | nil,
          summary: String.t(),
          status: String.t(),
          route: String.t() | nil
        }

  @type conversation_summary :: %{
          id: String.t(),
          route_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          repo_label: String.t(),
          label: String.t(),
          detail: String.t(),
          route: String.t() | nil,
          action_label: String.t() | nil,
          primary_route: String.t() | nil,
          primary_action_label: String.t() | nil,
          active_work_item_count: non_neg_integer(),
          repo_intake_active?: boolean(),
          multiple_active?: boolean(),
          work_items: [work_item_summary()]
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
         @default_fetch_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [conversation_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def default_loader do
    case Inventory.load() do
      {:ok, rows, warning} ->
        {:ok, rows |> Enum.map(&to_summary/1) |> Enum.filter(&include_summary?/1), normalize_warning(warning)}

      {:error, warning} ->
        {:error,
         normalize_warning(warning) ||
           stale_warning(
             @default_fetch_error_type,
             "Dashboard conversation summary data may be stale.",
             @default_fetch_remediation
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
               @default_fetch_error_type,
               "Dashboard conversation summary data may be stale.",
               @default_fetch_remediation
             )}

        other ->
          {:error,
           stale_warning(
             @default_fetch_error_type,
             "Dashboard conversation summary loader returned an invalid result (#{inspect(other)}).",
             @default_fetch_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard conversation summary loader crashed (#{Exception.message(exception)}).",
           @default_fetch_remediation
         )}
    catch
      kind, reason ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard conversation summary loader threw #{inspect({kind, reason})}.",
           @default_fetch_remediation
         )}
    end
  end

  defp to_summary(row) do
    projection =
      row
      |> map_get(:repo_conversation, "repo_conversation", %{})
      |> normalize_map()

    route_id = row |> map_get(:id, "id") |> normalize_optional_string()
    managed_repo_id = row |> map_get(:managed_repo_id, "managed_repo_id") |> normalize_optional_string()

    repo_label =
      row
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string() ||
        row
        |> map_get(:name, "name")
        |> normalize_optional_string() || "Unknown repository"

    active_work_items =
      projection
      |> map_get(:active_work_items, "active_work_items", [])
      |> normalize_list()
      |> Enum.map(&to_work_item_summary(&1, route_id))

    active_work_item_count = length(active_work_items)
    repo_intake_active? = repo_intake_active?(projection)
    route = route_id && "#{repo_detail_path(route_id)}#project-detail-conversation-panel"
    primary_route = active_work_items |> List.first() |> map_get(:route, "route")

    %{
      id: "dashboard-conversation-summary-#{route_id || managed_repo_id || repo_label}",
      route_id: route_id,
      managed_repo_id: managed_repo_id,
      repo_label: repo_label,
      label: summary_label(repo_intake_active?, active_work_item_count),
      detail: summary_detail(repo_intake_active?, active_work_item_count),
      route: route,
      action_label: route && "Open repo detail",
      primary_route: primary_route,
      primary_action_label: primary_route && "Continue governed conversation",
      active_work_item_count: active_work_item_count,
      repo_intake_active?: repo_intake_active?,
      multiple_active?: active_work_item_count > 1,
      work_items: Enum.take(active_work_items, 3)
    }
  end

  defp normalize_summary(summary) when is_map(summary) do
    %{
      id:
        summary
        |> map_get(:id, "id")
        |> normalize_optional_string() ||
          "dashboard-conversation-summary-#{System.unique_integer([:positive])}",
      route_id: summary |> map_get(:route_id, "route_id") |> normalize_optional_string(),
      managed_repo_id:
        summary
        |> map_get(:managed_repo_id, "managed_repo_id")
        |> normalize_optional_string(),
      repo_label:
        summary
        |> map_get(:repo_label, "repo_label")
        |> normalize_optional_string() || "Unknown repository",
      label:
        summary
        |> map_get(:label, "label")
        |> normalize_optional_string() || "Governed conversation activity",
      detail:
        summary
        |> map_get(:detail, "detail")
        |> normalize_optional_string() || "Conversation summary is unavailable.",
      route: summary |> map_get(:route, "route") |> normalize_optional_string(),
      action_label:
        summary
        |> map_get(:action_label, "action_label")
        |> normalize_optional_string(),
      primary_route:
        summary
        |> map_get(:primary_route, "primary_route")
        |> normalize_optional_string(),
      primary_action_label:
        summary
        |> map_get(:primary_action_label, "primary_action_label")
        |> normalize_optional_string(),
      active_work_item_count:
        summary
        |> map_get(:active_work_item_count, "active_work_item_count", 0)
        |> normalize_count(),
      repo_intake_active?:
        summary
        |> map_get(:repo_intake_active?, "repo_intake_active?")
        |> truthy?(),
      multiple_active?:
        summary
        |> map_get(:multiple_active?, "multiple_active?")
        |> truthy?(),
      work_items:
        summary
        |> map_get(:work_items, "work_items", [])
        |> normalize_list()
        |> Enum.map(&normalize_work_item_summary/1)
    }
  end

  defp normalize_summary(_summary) do
    %{
      id: "dashboard-conversation-summary-unknown",
      route_id: nil,
      managed_repo_id: nil,
      repo_label: "Unknown repository",
      label: "Governed conversation activity",
      detail: "Conversation summary is unavailable.",
      route: nil,
      action_label: nil,
      primary_route: nil,
      primary_action_label: nil,
      active_work_item_count: 0,
      repo_intake_active?: false,
      multiple_active?: false,
      work_items: []
    }
  end

  defp include_summary?(summary) when is_map(summary) do
    Map.get(summary, :active_work_item_count, 0) > 0
  end

  defp include_summary?(_summary), do: false

  defp to_work_item_summary(projection, route_id) do
    work_item =
      projection
      |> map_get(:work_item, "work_item", %{})
      |> normalize_map()

    work_item_id = work_item |> map_get(:id, "id") |> normalize_optional_string()

    %{
      id: work_item_id,
      summary:
        work_item
        |> map_get(:summary, "summary")
        |> normalize_optional_string() || "Governed work item",
      status:
        projection
        |> map_get(:conversation, "conversation", %{})
        |> map_get(:status, "status")
        |> normalize_optional_string() || "unknown",
      route: build_work_item_route(route_id, work_item_id)
    }
  end

  defp normalize_work_item_summary(summary) when is_map(summary) do
    %{
      id: summary |> map_get(:id, "id") |> normalize_optional_string(),
      summary:
        summary
        |> map_get(:summary, "summary")
        |> normalize_optional_string() || "Governed work item",
      status:
        summary
        |> map_get(:status, "status")
        |> normalize_optional_string() || "unknown",
      route: summary |> map_get(:route, "route") |> normalize_optional_string()
    }
  end

  defp normalize_work_item_summary(_summary) do
    %{id: nil, summary: "Governed work item", status: "unknown", route: nil}
  end

  defp repo_intake_active?(projection) when is_map(projection) do
    projection
    |> map_get(:repo_intake, "repo_intake", %{})
    |> map_get(:conversation, "conversation", %{})
    |> map_get(:status, "status")
    |> normalize_optional_string()
    |> case do
      "active" -> true
      "paused" -> true
      _other -> false
    end
  end

  defp repo_intake_active?(_projection), do: false

  defp summary_label(repo_intake_active?, active_work_item_count) do
    cond do
      repo_intake_active? and active_work_item_count > 0 ->
        "Repo intake + governed conversations"

      active_work_item_count > 1 ->
        "#{active_work_item_count} governed conversations active"

      active_work_item_count == 1 ->
        "Governed conversation active"

      repo_intake_active? ->
        "Repo intake active"

      true ->
        "Governed conversation activity"
    end
  end

  defp summary_detail(repo_intake_active?, active_work_item_count) do
    cond do
      repo_intake_active? and active_work_item_count > 0 ->
        "Repo intake is still active while governed work continues across canonical WorkItems."

      active_work_item_count > 1 ->
        "#{active_work_item_count} governed conversations are active for this managed repository."

      active_work_item_count == 1 ->
        "One governed conversation is active for this managed repository."

      repo_intake_active? ->
        "Repo intake is active and ready to promote durable work onto a canonical WorkItem."

      true ->
        "No active governed conversation state is available."
    end
  end

  defp build_work_item_route(route_id, work_item_id)
       when is_binary(route_id) and is_binary(work_item_id) do
    "#{repo_detail_path(route_id)}?work_item_id=#{URI.encode_www_form(work_item_id)}#project-detail-conversation-panel"
  end

  defp build_work_item_route(_route_id, _work_item_id), do: nil

  defp repo_detail_path(route_id), do: "/repos/#{URI.encode(route_id)}"

  defp normalize_warning(nil), do: nil

  defp normalize_warning(warning) do
    stale_warning(
      map_get(warning, :error_type, "error_type", @default_fetch_error_type),
      map_get(warning, :detail, "detail", "Dashboard conversation summary data may be stale."),
      map_get(warning, :remediation, "remediation", @default_fetch_remediation)
    )
  end

  defp stale_warning(error_type, detail, remediation) do
    %{
      error_type: error_type,
      detail: detail,
      remediation: remediation
    }
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value) and not is_struct(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_map(nested_value) and not is_struct(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value), do: value

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(_value), do: []

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value

  defp normalize_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp normalize_count(_value), do: 0

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false
end
