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
  activity, then projecting explicit top-card cues and bounded accordion
  sections for each managed repo.
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

  @type monitoring_badge :: %{
          id: atom(),
          label: String.t(),
          class: String.t()
        }

  @type monitoring_link :: %{
          id: atom(),
          label: String.t(),
          route: String.t(),
          class: String.t()
        }

  @type top_card :: %{
          branch_label: String.t(),
          signal_label: String.t(),
          signal_detail: String.t(),
          last_worked_on_label: String.t() | nil,
          primary_cue: String.t(),
          badges: [monitoring_badge()],
          links: [monitoring_link()]
        }

  @type accordion_section :: %{
          id: atom(),
          title: String.t(),
          heading: String.t(),
          summary: String.t(),
          meta: String.t() | nil,
          status_badge: monitoring_badge() | nil,
          links: [monitoring_link()]
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
          runtime_summary: map() | nil,
          detail_empty?: boolean(),
          top_card: top_card(),
          accordion_sections: [accordion_section()]
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

      repo_route = route_id && "/repos/#{route_id}"

      latest_run_route =
        if(route_id && latest_run,
          do: "/repos/#{route_id}/runs/#{normalize_optional_string(map_get(latest_run, :run_id, "run_id"))}",
          else: nil
        )

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
        repo_route: repo_route,
        latest_run_route: latest_run_route,
        latest_run: latest_run,
        conversation_summary: conversation_summary,
        memory_summary: memory_summary,
        runtime_summary: runtime_summary,
        detail_empty?: is_nil(latest_run) and is_nil(conversation_summary) and is_nil(memory_summary) and is_nil(runtime_summary),
        top_card:
          build_top_card(
            normalize_optional_string(map_get(row, :default_branch, "default_branch")) || "main",
            ordering_signal,
            normalize_optional_string(map_get(row, :recent_activity_summary, "recent_activity_summary")) ||
              "No recent activity metadata.",
            latest_worked_on_at(Map.get(ordering_signal, :at)),
            normalize_count(map_get(row, :open_issue_count, "open_issue_count", 0)),
            normalize_count(map_get(row, :open_pr_count, "open_pr_count", 0)),
            latest_run,
            conversation_summary,
            memory_summary,
            runtime_summary,
            repo_route,
            latest_run_route
          ),
        accordion_sections:
          build_accordion_sections(
            repo_route,
            latest_run_route,
            latest_run,
            conversation_summary,
            memory_summary,
            runtime_summary
          )
      }
    end)
    |> Enum.sort_by(&entry_sort_key/1)
  end

  defp build_top_card(
         default_branch,
         ordering_signal,
         recent_activity_summary,
         last_worked_on_label,
         open_issue_count,
         open_pr_count,
         latest_run,
         conversation_summary,
         memory_summary,
         runtime_summary,
         repo_route,
         latest_run_route
       ) do
    %{
      branch_label: "branch #{default_branch}",
      signal_label: normalize_optional_string(Map.get(ordering_signal, :label)) || "No recent operator signal",
      signal_detail:
        normalize_optional_string(Map.get(ordering_signal, :detail)) ||
          "Repository is onboarded but no recent governed or operator-facing activity has been materialized yet.",
      last_worked_on_label: last_worked_on_label,
      primary_cue: recent_activity_summary,
      badges:
        [
          %{id: :issues, label: "#{open_issue_count} open #{pluralize(open_issue_count, "issue", "issues")}", class: "badge badge-outline badge-sm"},
          %{id: :prs, label: "#{open_pr_count} open PR#{if(open_pr_count == 1, do: "", else: "s")}", class: "badge badge-outline badge-sm"},
          latest_run &&
            %{id: :run, label: "Latest run: #{map_get(latest_run, :workflow_name, "workflow_name")} #{map_get(latest_run, :status, "status")}", class: run_status_badge_class(map_get(latest_run, :status, "status"))},
          conversation_summary &&
            %{id: :conversations, label: "#{normalize_count(map_get(conversation_summary, :active_count, "active_count", 0))} active conversations", class: "badge badge-outline badge-sm"},
          normalize_count(map_get(conversation_summary || %{}, :clarification_count, "clarification_count", 0)) > 0 &&
            %{id: :clarifications, label: "#{normalize_count(map_get(conversation_summary, :clarification_count, "clarification_count", 0))} clarifications waiting", class: "badge badge-warning badge-outline badge-sm"},
          memory_summary &&
            %{id: :memory, label: "Memory: #{normalize_optional_string(map_get(memory_summary, :label, "label")) || "review required"}", class: memory_summary_badge_class(map_get(memory_summary, :state, "state"))},
          runtime_summary &&
            %{id: :runtime, label: "Runtime: #{runtime_status_label(map_get(runtime_summary, :status, "status"))}", class: runtime_evidence_badge_class(map_get(runtime_summary, :status, "status"))}
        ]
        |> Enum.filter(&is_map/1),
      links:
        [
          repo_route && %{id: :repo, label: "Open repository", route: repo_route, class: "link link-primary"},
          latest_run_route &&
            %{id: :latest_run, label: "Open latest run", route: latest_run_route, class: "link link-secondary"}
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp build_accordion_sections(
         repo_route,
         latest_run_route,
         latest_run,
         conversation_summary,
         memory_summary,
         runtime_summary
       ) do
    [
      %{
        id: :run,
        title: "Governed run",
        heading: run_heading(latest_run),
        summary: run_summary_detail(latest_run),
        meta: latest_run && run_recency_label(latest_run),
        status_badge: latest_run && status_badge(:run, map_get(latest_run, :status, "status")),
        links:
          [
            latest_run_route &&
              %{id: :run, label: "Open governed run", route: latest_run_route, class: "link link-primary"},
            repo_route &&
              %{id: :repo, label: "Open repository", route: repo_route, class: "link link-secondary"}
          ]
          |> Enum.reject(&is_nil/1)
      },
      %{
        id: :conversations,
        title: "Conversations",
        heading: conversation_heading(conversation_summary),
        summary: conversation_detail(conversation_summary),
        meta:
          case normalize_datetime(map_get(conversation_summary || %{}, :latest_activity_at, "latest_activity_at")) do
            %DateTime{} = at -> "Latest activity: #{format_datetime(at)}"
            _other -> nil
          end,
        status_badge:
          if normalize_count(map_get(conversation_summary || %{}, :clarification_count, "clarification_count", 0)) > 0 do
            clarification_count = normalize_count(map_get(conversation_summary, :clarification_count, "clarification_count", 0))
            %{id: :clarification, label: "#{clarification_count} clarification#{if(clarification_count == 1, do: "", else: "s")} needed", class: "badge badge-warning badge-outline badge-sm"}
          end,
        links:
          [
            conversation_route(conversation_summary, repo_route) &&
              %{id: :conversation, label: conversation_action_label(conversation_summary), route: conversation_route(conversation_summary, repo_route), class: "link link-primary"},
            repo_route &&
              %{id: :repo, label: "Open repository", route: repo_route, class: "link link-secondary"}
          ]
          |> Enum.reject(&is_nil/1)
      },
      %{
        id: :memory,
        title: "Memory",
        heading: memory_heading(memory_summary),
        summary: memory_detail(memory_summary),
        meta:
          memory_summary &&
            "Durable memory: #{normalize_count(map_get(memory_summary, :memory_count, "memory_count", 0))} | Workflow provenance: #{normalize_count(map_get(memory_summary, :provenance_count, "provenance_count", 0))}",
        status_badge: memory_summary && status_badge(:memory, map_get(memory_summary, :state, "state"), map_get(memory_summary, :label, "label")),
        links:
          [
            memory_route(memory_summary, repo_route) &&
              %{id: :memory, label: memory_action_label(memory_summary), route: memory_route(memory_summary, repo_route), class: "link link-primary"},
            repo_route &&
              %{id: :repo, label: "Open repository", route: repo_route, class: "link link-secondary"}
          ]
          |> Enum.reject(&is_nil/1)
      },
      %{
        id: :runtime,
        title: "Runtime",
        heading: runtime_heading(runtime_summary),
        summary: runtime_detail(runtime_summary),
        meta: runtime_summary && runtime_details(runtime_summary),
        status_badge: runtime_summary && status_badge(:runtime, map_get(runtime_summary, :status, "status")),
        links:
          [
            repo_route &&
              %{id: :repo, label: "Open repository", route: repo_route, class: "link link-primary"},
            %{id: :settings, label: "Open settings", route: "/settings/auth", class: "link link-secondary"}
          ]
      }
    ]
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

  defp latest_worked_on_at(%DateTime{} = at), do: "Last worked on #{format_datetime(at)}"
  defp latest_worked_on_at(_at), do: nil

  defp run_heading(nil), do: "No governed run materialized yet"

  defp run_heading(run_summary) do
    "#{normalize_optional_string(map_get(run_summary, :workflow_name, "workflow_name")) || "unknown_workflow"} #{normalize_optional_string(map_get(run_summary, :status, "status")) || "unknown"}"
  end

  defp run_summary_detail(nil) do
    "Latest governed run state will appear here once repository work starts from dashboard or repo detail."
  end

  defp run_summary_detail(run_summary) do
    [
      normalize_optional_string(map_get(run_summary, :current_stage, "current_stage")) &&
        "Stage: #{normalize_optional_string(map_get(run_summary, :current_stage, "current_stage"))}",
      normalize_count(map_get(run_summary, :evidence_count, "evidence_count", 0)) > 0 &&
        "Evidence: #{normalize_count(map_get(run_summary, :evidence_count, "evidence_count", 0))}",
      normalize_optional_string(map_get(run_summary, :change_request_status, "change_request_status")) &&
        "Review: #{normalize_optional_string(map_get(run_summary, :change_request_status, "change_request_status"))}",
      normalize_optional_string(map_get(run_summary, :latest_decision, "latest_decision")) &&
        "Decision: #{normalize_optional_string(map_get(run_summary, :latest_decision, "latest_decision"))}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        "Run status is #{normalize_optional_string(map_get(run_summary, :status, "status")) || "unknown"} with no additional governance detail yet."

      parts ->
        Enum.join(parts, " · ")
    end
  end

  defp run_recency_label(run_summary) do
    case normalize_datetime(map_get(run_summary, :started_at, "started_at")) do
      %DateTime{} = started_at -> "Started #{relative_time_label(started_at)} (#{format_datetime(started_at)})"
      _other -> nil
    end
  end

  defp conversation_heading(nil), do: "No active governed conversation supervision"

  defp conversation_heading(summary) do
    active_count = normalize_count(map_get(summary, :active_count, "active_count", 0))
    "#{active_count} active #{pluralize(active_count, "conversation", "conversations")}"
  end

  defp conversation_detail(nil) do
    "Conversation detail will appear here once governed work or clarification-required supervision materializes."
  end

  defp conversation_detail(summary) do
    normalize_optional_string(map_get(summary, :detail, "detail")) ||
      "Active governed conversations: #{normalize_count(map_get(summary, :active_count, "active_count", 0))} | Clarification needed: #{normalize_count(map_get(summary, :clarification_count, "clarification_count", 0))}"
  end

  defp conversation_route(nil, repo_route), do: repo_route

  defp conversation_route(summary, repo_route) do
    normalize_optional_string(map_get(summary, :route, "route")) || repo_route
  end

  defp conversation_action_label(nil), do: "Open conversation supervision"

  defp conversation_action_label(summary) do
    normalize_optional_string(map_get(summary, :action_label, "action_label")) ||
      "Open conversation supervision"
  end

  defp memory_heading(nil), do: "No repository memory summary yet"

  defp memory_heading(summary) do
    normalize_optional_string(map_get(summary, :label, "label")) ||
      "Repository memory summary available"
  end

  defp memory_detail(nil) do
    "Memory attention cues will appear here once durable memory or provenance state is materialized for this repository."
  end

  defp memory_detail(summary) do
    normalize_optional_string(map_get(summary, :detail, "detail")) ||
      normalize_optional_string(map_get(summary, :remediation, "remediation")) ||
      "Repository memory summary is available for deeper review."
  end

  defp memory_route(nil, repo_route), do: repo_route

  defp memory_route(summary, repo_route) do
    normalize_optional_string(map_get(summary, :route, "route")) || repo_route
  end

  defp memory_action_label(nil), do: "Open memory review"

  defp memory_action_label(summary) do
    normalize_optional_string(map_get(summary, :action_label, "action_label")) || "Open memory review"
  end

  defp runtime_heading(nil), do: "No runtime posture summary yet"

  defp runtime_heading(summary) do
    "Runtime posture is #{runtime_status_label(map_get(summary, :status, "status"))}"
  end

  defp runtime_detail(nil) do
    "Runtime posture detail will appear here once bounded delivery and readiness evidence is projected for this repository."
  end

  defp runtime_detail(summary) do
    normalize_optional_string(map_get(summary, :summary, "summary")) ||
      "Runtime posture evidence is available for this repository."
  end

  defp runtime_details(summary) do
    [
      normalize_optional_string(map_get(summary, :delivery_mode, "delivery_mode")) &&
        "Delivery: #{humanize_runtime_value(map_get(summary, :delivery_mode, "delivery_mode"))}",
      normalize_optional_string(map_get(summary, :reason_code, "reason_code")) &&
        "Reason: #{humanize_runtime_value(map_get(summary, :reason_code, "reason_code"))}",
      normalize_optional_string(map_get(summary, :latest_provider, "latest_provider")) &&
        "Latest provider: #{normalize_optional_string(map_get(summary, :latest_provider, "latest_provider"))}",
      normalize_optional_string(map_get(summary, :supervision_mode, "supervision_mode")) &&
        "Supervision: #{normalize_optional_string(map_get(summary, :supervision_mode, "supervision_mode"))}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp status_badge(:run, status) do
    normalized_status = normalize_optional_string(status) || "unknown"
    %{id: :status, label: normalized_status, class: run_status_badge_class(normalized_status)}
  end

  defp status_badge(:runtime, status) do
    normalized_status = normalize_optional_string(status)
    %{id: :status, label: runtime_status_label(normalized_status), class: runtime_evidence_badge_class(normalized_status)}
  end

  defp status_badge(:memory, state, label) do
    %{id: :status, label: normalize_optional_string(label) || "review required", class: memory_summary_badge_class(state)}
  end

  defp run_status_badge_class("completed"), do: "badge badge-success"
  defp run_status_badge_class("running"), do: "badge badge-info"
  defp run_status_badge_class("failed"), do: "badge badge-error"
  defp run_status_badge_class("cancelled"), do: "badge badge-warning"
  defp run_status_badge_class("awaiting_approval"), do: "badge badge-warning"
  defp run_status_badge_class("pending"), do: "badge badge-outline"
  defp run_status_badge_class(_status), do: "badge badge-outline"

  defp runtime_evidence_badge_class("blocked"), do: "badge badge-error"
  defp runtime_evidence_badge_class("degraded"), do: "badge badge-warning"
  defp runtime_evidence_badge_class("available"), do: "badge badge-success"
  defp runtime_evidence_badge_class(_status), do: "badge badge-outline"

  defp memory_summary_badge_class(:ready), do: "badge badge-success"
  defp memory_summary_badge_class(:degraded), do: "badge badge-warning"
  defp memory_summary_badge_class(:stale), do: "badge badge-warning"
  defp memory_summary_badge_class(:invalidated), do: "badge badge-warning"
  defp memory_summary_badge_class(:failed), do: "badge badge-error"
  defp memory_summary_badge_class(:not_ready), do: "badge badge-outline"
  defp memory_summary_badge_class(:disabled), do: "badge badge-outline"
  defp memory_summary_badge_class(_state), do: "badge badge-outline"

  defp runtime_status_label("blocked"), do: "blocked"
  defp runtime_status_label("degraded"), do: "review required"
  defp runtime_status_label("available"), do: "stable"
  defp runtime_status_label(nil), do: "unknown"
  defp runtime_status_label(other), do: other

  defp relative_time_label(%DateTime{} = datetime) do
    seconds = max(DateTime.diff(DateTime.utc_now(), datetime, :second), 0)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp humanize_runtime_value(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> nil
      normalized -> normalized |> String.replace("_", " ")
    end
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
