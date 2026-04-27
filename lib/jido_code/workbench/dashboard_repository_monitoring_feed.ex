defmodule JidoCode.Workbench.DashboardRepositoryMonitoringFeed do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  @moduledoc """
  Builds the repository-first dashboard monitoring feed.

  The dashboard overview stays bounded and repo-centric by deriving an
  explainable "last worked on" ordering from governed or operator-facing
  activity, then projecting compact monitoring cues for each managed repo.
  """

  alias JidoCode.Workbench.Inventory

  @default_error_type "dashboard_repository_monitoring_feed_fetch_failed"

  @default_remediation """
  Retry dashboard overview refresh. If this persists, inspect managed repository inventory and governed activity projections before relying on dashboard ordering.
  """

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type monitoring_entry :: %{
          id: String.t(),
          route_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          repo_name: String.t(),
          repo_label: String.t(),
          default_branch: String.t(),
          open_issue_count: non_neg_integer(),
          open_pr_count: non_neg_integer(),
          recent_activity_summary: String.t(),
          latest_worked_on_at: DateTime.t() | nil,
          ordering_source: atom(),
          ordering_label: String.t(),
          ordering_detail: String.t(),
          repo_route: String.t() | nil,
          latest_run_route: String.t() | nil,
          latest_run: map() | nil,
          conversation_summary: map() | nil,
          memory_summary: map() | nil,
          runtime_summary: map() | nil
        }

  @spec load(map()) :: {:ok, [monitoring_entry()], stale_warning() | nil} | {:error, stale_warning()}
  def load(sources \\ %{}) when is_map(sources) do
    case Inventory.load() do
      {:ok, inventory_rows, warning} ->
        {:ok,
         build_entries(
           inventory_rows,
           map_get(sources, :run_summaries, "run_summaries", []),
           map_get(sources, :conversation_summaries, "conversation_summaries", []),
           map_get(sources, :memory_summaries, "memory_summaries", []),
           map_get(sources, :runtime_summaries, "runtime_summaries", [])
         ), normalize_warning(warning)}

      {:error, warning} ->
        {:error,
         normalize_warning(warning) ||
           stale_warning(
             @default_error_type,
             "Dashboard repository monitoring feed is unavailable.",
             @default_remediation
           )}
    end
  end

  defp build_entries(inventory_rows, run_summaries, conversation_summaries, memory_summaries, runtime_summaries) do
    latest_runs = latest_runs_by_repo(run_summaries)
    conversations = summaries_by_repo(conversation_summaries)
    memories = summaries_by_repo(memory_summaries)
    runtimes = latest_runtime_by_repo(runtime_summaries)

    inventory_rows
    |> Enum.map(fn row ->
      managed_repo_id = normalize_optional_string(map_get(row, :managed_repo_id, "managed_repo_id"))
      route_id = normalize_optional_string(map_get(row, :id, "id"))
      latest_run = managed_repo_id && Map.get(latest_runs, managed_repo_id)
      conversation_summary = managed_repo_id && Map.get(conversations, managed_repo_id)
      memory_summary = managed_repo_id && Map.get(memories, managed_repo_id)
      runtime_summary = managed_repo_id && Map.get(runtimes, managed_repo_id)

      ordering_signal =
        ordering_signal(
          row,
          latest_run,
          conversation_summary,
          runtime_summary
        )

      repo_name =
        normalize_optional_string(map_get(row, :name, "name")) ||
          normalize_optional_string(map_get(row, :github_full_name, "github_full_name")) ||
          "Unknown repository"

      repo_label =
        normalize_optional_string(map_get(row, :github_full_name, "github_full_name")) || repo_name

      %{
        id: "dashboard-repository-monitoring-#{route_id || managed_repo_id || repo_label}",
        route_id: route_id,
        managed_repo_id: managed_repo_id,
        repo_name: repo_name,
        repo_label: repo_label,
        default_branch: normalize_optional_string(map_get(row, :default_branch, "default_branch")) || "main",
        open_issue_count: normalize_count(map_get(row, :open_issue_count, "open_issue_count", 0)),
        open_pr_count: normalize_count(map_get(row, :open_pr_count, "open_pr_count", 0)),
        recent_activity_summary:
          normalize_optional_string(map_get(row, :recent_activity_summary, "recent_activity_summary")) ||
            "No recent activity metadata.",
        latest_worked_on_at: Map.get(ordering_signal, :at),
        ordering_source: Map.get(ordering_signal, :source, :none),
        ordering_label: normalize_optional_string(Map.get(ordering_signal, :label)) || "No recent operator signal",
        ordering_detail:
          normalize_optional_string(Map.get(ordering_signal, :detail)) ||
            "Repository is onboarded but no recent governed or operator-facing activity has been materialized yet.",
        repo_route: route_id && "/repos/#{route_id}",
        latest_run_route:
          if(route_id && latest_run,
            do: "/repos/#{route_id}/runs/#{normalize_optional_string(map_get(latest_run, :run_id, "run_id"))}",
            else: nil
          ),
        latest_run: latest_run,
        conversation_summary: conversation_summary,
        memory_summary: memory_summary,
        runtime_summary: runtime_summary
      }
    end)
    |> Enum.sort_by(&entry_sort_key/1)
  end

  defp latest_runs_by_repo(run_summaries) do
    run_summaries
    |> Enum.reduce(%{}, fn run_summary, acc ->
      managed_repo_id = normalize_optional_string(map_get(run_summary, :managed_repo_id, "managed_repo_id"))

      if managed_repo_id do
        candidate_at =
          [
            map_get(run_summary, :completed_at, "completed_at"),
            map_get(run_summary, :started_at, "started_at")
          ]
          |> Enum.map(&normalize_datetime/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)

        current = Map.get(acc, managed_repo_id)

        if newer_candidate?(candidate_at, run_candidate_time(current)) do
          Map.put(acc, managed_repo_id, run_summary)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp summaries_by_repo(summaries) do
    Enum.reduce(summaries, %{}, fn summary, acc ->
      managed_repo_id = normalize_optional_string(map_get(summary, :managed_repo_id, "managed_repo_id"))

      if managed_repo_id do
        Map.put(acc, managed_repo_id, summary)
      else
        acc
      end
    end)
  end

  defp latest_runtime_by_repo(runtime_summaries) do
    Enum.reduce(runtime_summaries, %{}, fn runtime_summary, acc ->
      managed_repo_id = normalize_optional_string(map_get(runtime_summary, :managed_repo_id, "managed_repo_id"))

      if managed_repo_id do
        candidate_at = normalize_datetime(map_get(runtime_summary, :updated_at, "updated_at"))
        current = Map.get(acc, managed_repo_id)

        if newer_candidate?(candidate_at, normalize_datetime(map_get(current || %{}, :updated_at, "updated_at"))) do
          Map.put(acc, managed_repo_id, runtime_summary)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp ordering_signal(row, latest_run, conversation_summary, runtime_summary) do
    inventory_activity_at = normalize_datetime(map_get(row, :recent_activity_at, "recent_activity_at"))

    candidates =
      [
        run_ordering_signal(latest_run),
        conversation_ordering_signal(conversation_summary),
        runtime_ordering_signal(runtime_summary),
        inventory_ordering_signal(inventory_activity_at, row)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.max_by(candidates, &candidate_sort_key/1, fn ->
      %{source: :none, label: "No recent operator signal", detail: nil, at: nil}
    end)
  end

  defp run_ordering_signal(nil), do: nil

  defp run_ordering_signal(run_summary) do
    at =
      [
        map_get(run_summary, :completed_at, "completed_at"),
        map_get(run_summary, :started_at, "started_at")
      ]
      |> Enum.map(&normalize_datetime/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)

    if at do
      workflow_name =
        normalize_optional_string(map_get(run_summary, :workflow_name, "workflow_name")) ||
          "unknown_workflow"

      status = normalize_optional_string(map_get(run_summary, :status, "status")) || "unknown"

      %{
        source: :run,
        label: "Recent governed run",
        detail: "#{workflow_name} is #{status}.",
        at: at
      }
    end
  end

  defp conversation_ordering_signal(nil), do: nil

  defp conversation_ordering_signal(summary) do
    at = normalize_datetime(map_get(summary, :latest_activity_at, "latest_activity_at"))

    if at do
      active_count = normalize_count(map_get(summary, :active_count, "active_count", 0))
      clarification_count = normalize_count(map_get(summary, :clarification_count, "clarification_count", 0))

      %{
        source: :conversation,
        label: "Conversation supervision",
        detail:
          "#{active_count} active #{pluralize(active_count, "conversation", "conversations")}, #{clarification_count} clarification #{pluralize(clarification_count, "turn", "turns")} waiting.",
        at: at
      }
    end
  end

  defp runtime_ordering_signal(nil), do: nil

  defp runtime_ordering_signal(summary) do
    at = normalize_datetime(map_get(summary, :updated_at, "updated_at"))

    if at do
      status = normalize_optional_string(map_get(summary, :status, "status")) || "unknown"

      %{
        source: :runtime,
        label: "Runtime posture",
        detail: "Runtime posture is #{status}.",
        at: at
      }
    end
  end

  defp inventory_ordering_signal(nil, _row), do: nil

  defp inventory_ordering_signal(at, row) do
    %{
      source: :inventory,
      label: "Repository activity metadata",
      detail:
        normalize_optional_string(map_get(row, :recent_activity_summary, "recent_activity_summary")) ||
          "Repository activity metadata is present.",
      at: at
    }
  end

  defp candidate_sort_key(%{at: %DateTime{} = at, source: source}) do
    {DateTime.to_unix(at, :microsecond), source_priority(source)}
  end

  defp candidate_sort_key(_candidate), do: {0, 0}

  defp entry_sort_key(entry) do
    {
      -datetime_sort_value(Map.get(entry, :latest_worked_on_at)),
      -source_priority(Map.get(entry, :ordering_source)),
      String.downcase(normalize_optional_string(Map.get(entry, :repo_label)) || "")
    }
  end

  defp run_candidate_time(nil), do: nil

  defp run_candidate_time(run_summary) do
    [
      map_get(run_summary, :completed_at, "completed_at"),
      map_get(run_summary, :started_at, "started_at")
    ]
    |> Enum.map(&normalize_datetime/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  defp newer_candidate?(nil, _current), do: false
  defp newer_candidate?(%DateTime{}, nil), do: true

  defp newer_candidate?(%DateTime{} = candidate, %DateTime{} = current) do
    DateTime.compare(candidate, current) == :gt
  end

  defp source_priority(:run), do: 4
  defp source_priority(:conversation), do: 3
  defp source_priority(:runtime), do: 2
  defp source_priority(:inventory), do: 1
  defp source_priority(_source), do: 0

  defp datetime_sort_value(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_value(_datetime), do: 0

  defp normalize_warning(warning) when is_map(warning) do
    %{
      error_type:
        warning
        |> map_get(:error_type, "error_type")
        |> normalize_optional_string() || @default_error_type,
      detail:
        warning
        |> map_get(:detail, "detail")
        |> normalize_optional_string() || "Dashboard repository monitoring may be stale.",
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

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value

  defp normalize_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _other -> 0
    end
  end

  defp normalize_count(_value), do: 0

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    case Map.fetch(map, atom_key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(map, string_key) do
          {:ok, value} -> value
          :error -> default
        end
    end
  end

  defp map_get(_value, _atom_key, _string_key, default), do: default
end
