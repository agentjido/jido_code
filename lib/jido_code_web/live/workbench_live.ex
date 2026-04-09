defmodule JidoCodeWeb.WorkbenchLive do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  alias JidoCode.Orchestration.RunPubSub

  alias JidoCode.Workbench.{
    FixWorkflowKickoff,
    Inventory,
    IssueTriageWorkflowKickoff,
    RunOutcomes
  }

  @fallback_row_id_prefix "workbench-row-"
  @filter_validation_error_type "workbench_filter_values_invalid"
  @filter_restore_validation_error_type "workbench_filter_restore_state_invalid"
  @sort_validation_error_type "workbench_sort_order_fallback"

  @default_filter_values %{
    "project_id" => "all",
    "work_state" => "all",
    "freshness_window" => "any",
    "sort_order" => "project_name_asc"
  }

  @work_state_filter_options [
    {"Any issue or PR state", "all"},
    {"Issues open", "issues_open"},
    {"PRs open", "prs_open"},
    {"Issues and PRs open", "issues_and_prs_open"}
  ]

  @freshness_filter_options [
    {"Any freshness", "any"},
    {"Active in last 24 hours", "active_24h"},
    {"Stale for 7+ days", "stale_7d"},
    {"Stale for 30+ days", "stale_30d"}
  ]

  @sort_order_options [
    {"Repository name (A-Z)", "project_name_asc"},
    {"Backlog size (highest first)", "backlog_desc"},
    {"Backlog size (lowest first)", "backlog_asc"},
    {"Recent activity (most recent first)", "recent_activity_desc"},
    {"Recent activity (oldest first)", "recent_activity_asc"}
  ]

  @default_project_filter_value Map.fetch!(@default_filter_values, "project_id")
  @default_work_state_filter_value Map.fetch!(@default_filter_values, "work_state")
  @default_freshness_filter_value Map.fetch!(@default_filter_values, "freshness_window")
  @default_sort_order_value Map.fetch!(@default_filter_values, "sort_order")
  @filter_state_query_keys ["project_id", "work_state", "freshness_window", "sort_order"]
  @run_events_for_outcome_refresh MapSet.new([
                                    "run_started",
                                    "run_completed",
                                    "run_failed",
                                    "run_cancelled"
                                  ])

  @impl true
  def mount(params, _session, socket) do
    initial_filter_values = initial_filter_values(params)

    socket =
      socket
      |> assign(:inventory_count, 0)
      |> assign(:inventory_total_count, 0)
      |> assign(:inventory_rows_all, [])
      |> assign(:stale_warning, nil)
      |> assign(:filter_validation_notice, nil)
      |> assign(:sort_validation_notice, nil)
      |> assign(:fix_workflow_kickoff_states, %{})
      |> assign(:issue_triage_workflow_kickoff_states, %{})
      |> assign(:recent_run_outcomes, %{})
      |> assign(:filter_values, initial_filter_values)
      |> assign(:filter_form, to_filter_form(initial_filter_values))
      |> assign(:filter_chips, filter_chips(initial_filter_values, []))
      |> assign(:project_filter_options, project_filter_options([]))
      |> stream(:inventory_rows, [], reset: true)
      |> load_inventory()
      |> maybe_subscribe_run_events()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case restored_filter_values(params, socket.assigns.inventory_rows_all) do
      {:ok, filter_values} ->
        socket =
          socket
          |> assign(:filter_validation_notice, nil)
          |> apply_filters(filter_values)

        {:noreply, socket}

      {:error, field, invalid_value} ->
        socket =
          socket
          |> assign(
            :filter_validation_notice,
            filter_restore_validation_notice(field, invalid_value)
          )
          |> apply_filters(@default_filter_values)

        {:noreply, socket}

      :none ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry_fetch", _params, socket) do
    {:noreply, load_inventory(socket)}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    socket =
      socket
      |> apply_filter_event(filter_params)
      |> push_filter_state_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_filters", _params, socket) do
    socket =
      socket
      |> apply_invalid_filter_defaults("filters", "missing")
      |> push_filter_state_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    socket =
      socket
      |> assign(:filter_validation_notice, nil)
      |> assign(:sort_validation_notice, nil)
      |> apply_filters(@default_filter_values)
      |> push_filter_state_patch()

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "kickoff_fix_workflow",
        %{"project_id" => project_id, "context_item_type" => context_item_type},
        socket
      ) do
    project_row = find_project_row(socket.assigns.inventory_rows_all, project_id)
    kickoff_result = FixWorkflowKickoff.kickoff(project_row, context_item_type, initiating_actor(socket))

    state_project_id =
      case project_row do
        %{} ->
          project_row
          |> map_get("id", :id)
          |> normalize_optional_string()

        _other ->
          nil
      end || normalize_optional_string(project_id) || "unknown-project"

    socket =
      socket
      |> put_fix_workflow_kickoff_state(state_project_id, context_item_type, kickoff_result)
      |> put_recent_run_outcome_from_kickoff(state_project_id, kickoff_result)
      |> refresh_project_row(project_row)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "kickoff_issue_triage_workflow",
        %{"project_id" => project_id, "context_item_type" => context_item_type},
        socket
      ) do
    project_row = find_project_row(socket.assigns.inventory_rows_all, project_id)

    kickoff_result =
      IssueTriageWorkflowKickoff.kickoff(
        project_row,
        context_item_type,
        initiating_actor(socket)
      )

    state_project_id =
      case project_row do
        %{} ->
          project_row
          |> map_get("id", :id)
          |> normalize_optional_string()

        _other ->
          nil
      end || normalize_optional_string(project_id) || "unknown-project"

    socket =
      socket
      |> put_issue_triage_workflow_kickoff_state(state_project_id, :issue, kickoff_result)
      |> put_recent_run_outcome_from_kickoff(state_project_id, kickoff_result)
      |> refresh_project_row(project_row)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:run_event, payload}, socket) do
    event_name =
      payload
      |> map_get("event", :event)
      |> normalize_optional_string()

    if MapSet.member?(@run_events_for_outcome_refresh, event_name) do
      {:noreply, refresh_recent_run_outcomes(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-2">
        <h1 class="text-2xl font-bold">Workbench</h1>
        <p class="text-base-content/70">
          Unified managed-repository inventory for issue and pull request triage.
        </p>
      </section>

      <.operator_state_notice
        :if={@stale_warning}
        id="workbench-stale-warning"
        title="Workbench data may be stale"
        state={@stale_warning}
      >
        <:actions>
          <button
            id="workbench-retry-fetch"
            type="button"
            class="btn btn-sm btn-warning"
            phx-click="retry_fetch"
          >
            Retry workbench fetch
          </button>
          <.link
            id="workbench-open-setup-recovery"
            class="btn btn-sm btn-outline"
            navigate={~p"/setup?step=7&reason=workbench_data_stale"}
          >
            Review setup diagnostics
          </.link>
        </:actions>
      </.operator_state_notice>

      <.operator_state_notice
        :if={@filter_validation_notice}
        id="workbench-filter-validation-notice"
        dom_prefix="workbench-filter-validation"
        title="Workbench filters were reset to defaults"
        state={@filter_validation_notice}
        kind={:notice}
      />

      <.operator_state_notice
        :if={@sort_validation_notice}
        id="workbench-sort-validation-notice"
        dom_prefix="workbench-sort-validation"
        title="Workbench sort fell back to default order"
        state={@sort_validation_notice}
        kind={:notice}
      />

      <.vue_surface
        id="workbench-summary-widget"
        component="WorkbenchSummaryWidget"
        socket={@socket}
        props={workbench_summary_widget_props(assigns)}
        events={%{"resetFilters" => "reset_filters"}}
      />

      <section id="workbench-filters-panel" class="rounded-lg border border-base-300 bg-base-100 p-4">
        <.form
          for={@filter_form}
          id="workbench-filters-form"
          phx-change="apply_filters"
          phx-submit="apply_filters"
          class="grid gap-3 lg:grid-cols-[minmax(12rem,1fr)_minmax(12rem,1fr)_minmax(12rem,1fr)_minmax(14rem,1fr)_auto]"
        >
          <.input
            id="workbench-filter-project"
            field={@filter_form[:project_id]}
            type="select"
            label="Managed repo"
            options={@project_filter_options}
          />
          <.input
            id="workbench-filter-work-state"
            field={@filter_form[:work_state]}
            type="select"
            label="Issue/PR state"
            options={work_state_filter_options()}
          />
          <.input
            id="workbench-filter-freshness-window"
            field={@filter_form[:freshness_window]}
            type="select"
            label="Freshness window"
            options={freshness_filter_options()}
          />
          <.input
            id="workbench-filter-sort-order"
            field={@filter_form[:sort_order]}
            type="select"
            label="Sort rows by"
            options={sort_order_options()}
          />
          <button id="workbench-apply-filters" type="submit" class="btn btn-primary btn-sm lg:self-end">
            Apply filters
          </button>
        </.form>

        <div id="workbench-filter-chips" class="flex flex-wrap gap-2 pt-2">
          <span id="workbench-filter-chip-project" class="badge badge-outline">
            Managed repo: {@filter_chips.project}
          </span>
          <span id="workbench-filter-chip-work-state" class="badge badge-outline">
            State: {@filter_chips.work_state}
          </span>
          <span id="workbench-filter-chip-freshness-window" class="badge badge-outline">
            Freshness: {@filter_chips.freshness_window}
          </span>
          <span id="workbench-filter-chip-sort-order" class="badge badge-outline">
            Sort: {@filter_chips.sort_order}
          </span>
        </div>

        <p id="workbench-filter-results-count" class="pt-2 text-xs text-base-content/70">
          Showing {@inventory_count} of {@inventory_total_count} managed repositories.
        </p>
      </section>

      <section class="rounded-lg border border-base-300 bg-base-100 overflow-x-auto">
        <table id="workbench-project-table" class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Managed repo</th>
              <th>Open issues</th>
              <th>Open PRs</th>
              <th>Recent activity</th>
              <th>Links</th>
            </tr>
          </thead>
          <tbody id="workbench-project-rows" phx-update="stream">
            <tr :if={@inventory_count == 0} id="workbench-empty-state">
              <td colspan="5" class="text-center text-sm text-base-content/70 py-8">
                {empty_state_message(@inventory_total_count)}
              </td>
            </tr>
            <tr :for={{dom_id, project} <- @streams.inventory_rows} id={dom_id}>
              <td>
                <p id={"workbench-project-name-#{project.id}"} class="font-medium">
                  {project.github_full_name}
                </p>
                <p class="text-xs text-base-content/60">{project.name}</p>
                <div
                  :if={semantic_graph_hint(project)}
                  id={"workbench-project-semantic-hint-#{project.id}"}
                  class="space-y-1 pt-2"
                >
                  <span
                    id={"workbench-project-semantic-hint-badge-#{project.id}"}
                    class={semantic_graph_hint_badge_class(semantic_graph_hint(project))}
                  >
                    {semantic_graph_hint(project).label}
                  </span>
                  <p
                    id={"workbench-project-semantic-hint-detail-#{project.id}"}
                    class="text-[11px] text-base-content/65"
                  >
                    {semantic_graph_hint(project).detail}
                  </p>
                  <.link
                    :if={semantic_graph_hint_recovery_path(project, @filter_values)}
                    id={"workbench-project-semantic-hint-recovery-#{project.id}"}
                    class="link link-primary text-[11px]"
                    href={semantic_graph_hint_recovery_path(project, @filter_values)}
                  >
                    {semantic_graph_hint(project).remediation}
                  </.link>
                </div>
              </td>
              <td id={"workbench-project-open-issues-#{project.id}"}>{project.open_issue_count}</td>
              <td id={"workbench-project-open-prs-#{project.id}"}>{project.open_pr_count}</td>
              <td id={"workbench-project-recent-activity-#{project.id}"} class="text-sm">
                {project.recent_activity_summary}
              </td>
              <td id={"workbench-project-links-#{project.id}"} class="space-y-2 text-xs">
                <div id={"workbench-project-issues-links-#{project.id}"}>
                  <p class="font-medium text-base-content/80">Issues</p>
                  <% triage_policy_state = issue_triage_policy_state(project) %>
                  <div class="flex flex-col gap-0.5">
                    <.row_link
                      link_id={"workbench-project-issues-github-link-#{project.id}"}
                      disabled_id={"workbench-project-issues-github-disabled-#{project.id}"}
                      reason_id={"workbench-project-issues-github-disabled-reason-#{project.id}"}
                      label="GitHub issues"
                      target={issue_github_url(project)}
                      disabled_reason={github_url_unavailable_reason()}
                      external
                    />
                    <.row_link
                      link_id={"workbench-project-issues-project-link-#{project.id}"}
                      disabled_id={"workbench-project-issues-project-disabled-#{project.id}"}
                      reason_id={"workbench-project-issues-project-disabled-reason-#{project.id}"}
                      label="Repo detail"
                      target={project_detail_path(project, @filter_values)}
                      disabled_reason={project_detail_unavailable_reason()}
                    />
                    <.recent_run_outcome_indicator
                      outcome={recent_run_outcome(@recent_run_outcomes, project.id)}
                      dom_prefix={"workbench-project-issues-run-outcome-#{project.id}"}
                    />
                    <%= if Map.get(triage_policy_state, :enabled, true) do %>
                      <button
                        id={"workbench-project-issues-triage-action-#{project.id}"}
                        type="button"
                        class="btn btn-xs btn-outline btn-accent w-fit mt-1"
                        phx-click="kickoff_issue_triage_workflow"
                        phx-value-project_id={project.id}
                        phx-value-context_item_type="issue"
                      >
                        Kick off issue triage workflow
                      </button>
                    <% else %>
                      <.issue_triage_policy_blocked_feedback
                        policy_state={triage_policy_state}
                        dom_prefix={"workbench-project-issues-triage-disabled-#{project.id}"}
                      />
                    <% end %>
                    <.issue_triage_workflow_kickoff_feedback
                      feedback={
                        issue_triage_workflow_kickoff_feedback(
                          @issue_triage_workflow_kickoff_states,
                          project.id,
                          :issue
                        )
                      }
                      dom_prefix={"workbench-project-issues-triage-#{project.id}"}
                    />
                    <button
                      id={"workbench-project-issues-fix-action-#{project.id}"}
                      type="button"
                      class="btn btn-xs btn-outline btn-primary w-fit mt-1"
                      phx-click="kickoff_fix_workflow"
                      phx-value-project_id={project.id}
                      phx-value-context_item_type="issue"
                    >
                      Kick off fix workflow
                    </button>
                    <.fix_workflow_kickoff_feedback
                      feedback={
                        fix_workflow_kickoff_feedback(
                          @fix_workflow_kickoff_states,
                          project.id,
                          :issue
                        )
                      }
                      dom_prefix={"workbench-project-issues-fix-#{project.id}"}
                    />
                  </div>
                </div>
                <div id={"workbench-project-prs-links-#{project.id}"}>
                  <p class="font-medium text-base-content/80">PRs</p>
                  <div class="flex flex-col gap-0.5">
                    <.row_link
                      link_id={"workbench-project-prs-github-link-#{project.id}"}
                      disabled_id={"workbench-project-prs-github-disabled-#{project.id}"}
                      reason_id={"workbench-project-prs-github-disabled-reason-#{project.id}"}
                      label="GitHub PRs"
                      target={pull_request_github_url(project)}
                      disabled_reason={github_url_unavailable_reason()}
                      external
                    />
                    <.row_link
                      link_id={"workbench-project-prs-project-link-#{project.id}"}
                      disabled_id={"workbench-project-prs-project-disabled-#{project.id}"}
                      reason_id={"workbench-project-prs-project-disabled-reason-#{project.id}"}
                      label="Repo detail"
                      target={project_detail_path(project, @filter_values)}
                      disabled_reason={project_detail_unavailable_reason()}
                    />
                    <.recent_run_outcome_indicator
                      outcome={recent_run_outcome(@recent_run_outcomes, project.id)}
                      dom_prefix={"workbench-project-prs-run-outcome-#{project.id}"}
                    />
                    <button
                      id={"workbench-project-prs-fix-action-#{project.id}"}
                      type="button"
                      class="btn btn-xs btn-outline btn-primary w-fit mt-1"
                      phx-click="kickoff_fix_workflow"
                      phx-value-project_id={project.id}
                      phx-value-context_item_type="pull_request"
                    >
                      Kick off fix workflow
                    </button>
                    <.fix_workflow_kickoff_feedback
                      feedback={
                        fix_workflow_kickoff_feedback(
                          @fix_workflow_kickoff_states,
                          project.id,
                          :pull_request
                        )
                      }
                      dom_prefix={"workbench-project-prs-fix-#{project.id}"}
                    />
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end

  defp load_inventory(socket) do
    case Inventory.load() do
      {:ok, rows, stale_warning} ->
        filter_values =
          socket.assigns
          |> Map.get(:filter_values, @default_filter_values)
          |> normalize_filter_values()
          |> validated_filter_values_or_default(rows)

        socket
        |> assign(:inventory_rows_all, rows)
        |> assign(:stale_warning, stale_warning)
        |> assign(:recent_run_outcomes, load_recent_run_outcomes(rows))
        |> assign(:project_filter_options, project_filter_options(rows))
        |> apply_filters(filter_values)

      {:error, stale_warning} ->
        filter_values =
          socket.assigns
          |> Map.get(:filter_values, @default_filter_values)
          |> normalize_filter_values()
          |> validated_filter_values_or_default([])

        socket
        |> assign(:inventory_count, 0)
        |> assign(:inventory_total_count, 0)
        |> assign(:inventory_rows_all, [])
        |> assign(:stale_warning, stale_warning)
        |> assign(:recent_run_outcomes, %{})
        |> assign(:sort_validation_notice, nil)
        |> assign(:project_filter_options, project_filter_options([]))
        |> assign(:filter_values, filter_values)
        |> assign(:filter_form, to_filter_form(filter_values))
        |> assign(:filter_chips, filter_chips(filter_values, []))
        |> stream(:inventory_rows, [], reset: true)
    end
  end

  defp maybe_subscribe_run_events(socket) do
    if connected?(socket) do
      :ok = RunPubSub.subscribe_runs()
      socket
    else
      socket
    end
  end

  defp refresh_recent_run_outcomes(socket) do
    rows = Map.get(socket.assigns, :inventory_rows_all, [])

    filter_values =
      socket.assigns
      |> Map.get(:filter_values, @default_filter_values)
      |> normalize_filter_values()

    socket
    |> assign(:recent_run_outcomes, load_recent_run_outcomes(rows))
    |> apply_filters(filter_values)
  end

  defp load_recent_run_outcomes(rows) when is_list(rows), do: RunOutcomes.load(rows)
  defp load_recent_run_outcomes(_rows), do: %{}

  defp apply_filter_event(socket, filter_params) do
    filter_values = normalize_filter_values(filter_params)

    case validate_filter_values(filter_values, socket.assigns.inventory_rows_all) do
      :ok ->
        socket
        |> assign(:filter_validation_notice, nil)
        |> apply_filters(filter_values)

      {:error, field, invalid_value} ->
        apply_invalid_filter_defaults(socket, field, invalid_value)
    end
  end

  defp apply_invalid_filter_defaults(socket, field, invalid_value) do
    socket
    |> assign(:filter_validation_notice, filter_validation_notice(field, invalid_value))
    |> apply_filters(@default_filter_values)
  end

  defp push_filter_state_patch(socket) do
    filter_values =
      socket.assigns
      |> Map.get(:filter_values, @default_filter_values)
      |> normalize_filter_values()

    push_patch(socket, to: workbench_path_with_filter_values(filter_values))
  end

  defp workbench_summary_widget_props(assigns) do
    filter_values =
      assigns
      |> Map.get(:filter_values, @default_filter_values)
      |> normalize_filter_values()

    filter_chips = Map.get(assigns, :filter_chips, %{})

    rows = Map.get(assigns, :inventory_rows_all, [])
    filtered_rows = filter_rows(rows, filter_values)
    {sorted_rows, _applied_filter_values, _sort_notice} = sort_rows_with_fallback(filtered_rows, filter_values)

    project_summaries =
      Enum.map(Enum.take(sorted_rows, 5), fn row ->
        outcome =
          recent_run_outcome(Map.get(assigns, :recent_run_outcomes, %{}), Map.get(row, :id)) || %{}

        %{
          id: Map.get(row, :id),
          githubFullName: Map.get(row, :github_full_name),
          backlogCount: backlog_size(row),
          recentActivitySummary: Map.get(row, :recent_activity_summary),
          runOutcomeStatus:
            outcome
            |> map_get(:status, "status")
            |> normalize_optional_string(),
          requiresAttention: workbench_summary_attention?(row, outcome)
        }
      end)

    %{
      inventoryCount: Map.get(assigns, :inventory_count, 0),
      inventoryTotalCount: Map.get(assigns, :inventory_total_count, 0),
      attentionCount: Enum.count(project_summaries, & &1.requiresAttention),
      filterChips: %{
        project: Map.get(filter_chips, :project),
        workState: Map.get(filter_chips, :work_state),
        freshnessWindow: Map.get(filter_chips, :freshness_window),
        sortOrder: Map.get(filter_chips, :sort_order)
      },
      projectSummaries: project_summaries,
      resetVisible: filter_values != @default_filter_values
    }
  end

  defp workbench_summary_attention?(row, outcome) do
    backlog_size(row) > 0 and
      normalize_optional_string(map_get(outcome, :status, "status")) not in [nil, "completed"]
  end

  defp apply_filters(socket, filter_values) do
    rows = filter_rows(socket.assigns.inventory_rows_all, filter_values)

    {sorted_rows, applied_filter_values, sort_validation_notice} =
      sort_rows_with_fallback(rows, filter_values)

    project_options = project_filter_options(socket.assigns.inventory_rows_all)

    socket
    |> assign(:inventory_count, length(sorted_rows))
    |> assign(:inventory_total_count, length(socket.assigns.inventory_rows_all))
    |> assign(:sort_validation_notice, sort_validation_notice)
    |> assign(:filter_values, applied_filter_values)
    |> assign(:filter_form, to_filter_form(applied_filter_values))
    |> assign(
      :filter_chips,
      filter_chips(applied_filter_values, socket.assigns.inventory_rows_all)
    )
    |> assign(:project_filter_options, project_options)
    |> stream(:inventory_rows, sorted_rows, reset: true)
  end

  defp filter_rows(rows, filter_values) do
    now = DateTime.utc_now()
    project_id = Map.fetch!(filter_values, "project_id")
    work_state = Map.fetch!(filter_values, "work_state")
    freshness_window = Map.fetch!(filter_values, "freshness_window")

    Enum.filter(rows, fn row ->
      project_filter_match?(row, project_id) and
        work_state_filter_match?(row, work_state) and
        freshness_filter_match?(row, freshness_window, now)
    end)
  end

  defp project_filter_match?(_row, @default_project_filter_value), do: true
  defp project_filter_match?(row, project_id), do: Map.get(row, :id) == project_id

  defp work_state_filter_match?(_row, @default_work_state_filter_value), do: true

  defp work_state_filter_match?(row, "issues_open"),
    do: Map.get(row, :open_issue_count, 0) > 0

  defp work_state_filter_match?(row, "prs_open"),
    do: Map.get(row, :open_pr_count, 0) > 0

  defp work_state_filter_match?(row, "issues_and_prs_open"),
    do: Map.get(row, :open_issue_count, 0) > 0 and Map.get(row, :open_pr_count, 0) > 0

  defp work_state_filter_match?(_row, _work_state), do: false

  defp freshness_filter_match?(_row, @default_freshness_filter_value, _now), do: true

  defp freshness_filter_match?(row, "active_24h", now),
    do: recent_activity_within?(row, now, 24 * 60 * 60)

  defp freshness_filter_match?(row, "stale_7d", now),
    do: stale_for_or_missing?(row, now, 7 * 24 * 60 * 60)

  defp freshness_filter_match?(row, "stale_30d", now),
    do: stale_for_or_missing?(row, now, 30 * 24 * 60 * 60)

  defp freshness_filter_match?(_row, _freshness_window, _now), do: false

  defp recent_activity_within?(row, now, seconds) do
    case row_recent_activity_at(row) do
      %DateTime{} = activity_at ->
        cutoff = DateTime.add(now, -seconds, :second)
        DateTime.compare(activity_at, cutoff) in [:eq, :gt]

      _other ->
        false
    end
  end

  defp stale_for_or_missing?(row, now, seconds) do
    case row_recent_activity_at(row) do
      %DateTime{} = activity_at ->
        cutoff = DateTime.add(now, -seconds, :second)
        DateTime.compare(activity_at, cutoff) in [:lt, :eq]

      _other ->
        true
    end
  end

  defp row_recent_activity_at(row) do
    row
    |> Map.get(:recent_activity_at)
    |> normalize_optional_datetime()
  end

  defp normalize_filter_values(filter_values) when is_map(filter_values) do
    %{
      "project_id" =>
        filter_values
        |> map_get("project_id", :project_id)
        |> normalize_optional_string() || @default_project_filter_value,
      "work_state" =>
        filter_values
        |> map_get("work_state", :work_state)
        |> normalize_optional_string() || @default_work_state_filter_value,
      "freshness_window" =>
        filter_values
        |> map_get("freshness_window", :freshness_window)
        |> normalize_optional_string() || @default_freshness_filter_value,
      "sort_order" =>
        filter_values
        |> map_get("sort_order", :sort_order)
        |> normalize_optional_string() || @default_sort_order_value
    }
  end

  defp normalize_filter_values(_filter_values), do: @default_filter_values

  defp initial_filter_values(params) do
    restored_values = extract_filter_state_params(params || %{})

    if map_size(restored_values) == 0 do
      @default_filter_values
    else
      @default_filter_values
      |> Map.merge(restored_values)
      |> normalize_filter_values()
    end
  end

  defp restored_filter_values(params, rows) do
    restored_values = extract_filter_state_params(params)

    if map_size(restored_values) == 0 do
      :none
    else
      filter_values =
        @default_filter_values
        |> Map.merge(restored_values)
        |> normalize_filter_values()

      case validate_filter_values(filter_values, rows) do
        :ok ->
          {:ok, filter_values}

        {:error, field, invalid_value} ->
          {:error, field, invalid_value}
      end
    end
  end

  defp extract_filter_state_params(params) do
    Enum.reduce(@filter_state_query_keys, %{}, fn key, acc ->
      case Map.get(params, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp validated_filter_values_or_default(filter_values, rows) do
    case validate_filter_values(filter_values, rows) do
      :ok -> filter_values
      {:error, _field, _invalid_value} -> @default_filter_values
    end
  end

  defp validate_filter_values(filter_values, rows) do
    valid_project_values =
      rows
      |> Enum.map(&Map.get(&1, :id))
      |> Enum.reject(&is_nil/1)
      |> then(&MapSet.new([@default_project_filter_value | &1]))

    valid_work_state_values = @work_state_filter_options |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    valid_freshness_values =
      @freshness_filter_options |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    valid_sort_order_values =
      @sort_order_options |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    with :ok <-
           validate_filter_value(
             "project_id",
             Map.fetch!(filter_values, "project_id"),
             valid_project_values
           ),
         :ok <-
           validate_filter_value(
             "work_state",
             Map.fetch!(filter_values, "work_state"),
             valid_work_state_values
           ),
         :ok <-
           validate_filter_value(
             "freshness_window",
             Map.fetch!(filter_values, "freshness_window"),
             valid_freshness_values
           ),
         :ok <-
           validate_filter_value(
             "sort_order",
             Map.fetch!(filter_values, "sort_order"),
             valid_sort_order_values
           ) do
      :ok
    end
  end

  defp validate_filter_value(field, value, valid_values) do
    if MapSet.member?(valid_values, value) do
      :ok
    else
      {:error, field, inspect(value)}
    end
  end

  defp filter_validation_notice(field, invalid_value) do
    %{
      error_type: @filter_validation_error_type,
      detail: "Invalid #{field} value #{invalid_value} was submitted for workbench filters; defaults were restored.",
      remediation: "Select values from the listed project, state, and freshness options and retry."
    }
  end

  defp filter_restore_validation_notice(field, invalid_value) do
    %{
      error_type: @filter_restore_validation_error_type,
      detail:
        "Workbench state restoration failed because #{field} value #{invalid_value} is invalid; defaults were restored.",
      remediation: "Use workbench filters to reselect project, state, freshness, and sort preferences."
    }
  end

  defp workbench_path_with_filter_values(filter_values) do
    query_params =
      @filter_state_query_keys
      |> Enum.reduce([], fn key, acc ->
        value = Map.get(filter_values, key, Map.fetch!(@default_filter_values, key))
        default_value = Map.fetch!(@default_filter_values, key)

        if value == default_value do
          acc
        else
          [{key, value} | acc]
        end
      end)
      |> Enum.reverse()

    case query_params do
      [] -> "/workbench"
      _other -> "/workbench?" <> URI.encode_query(query_params)
    end
  end

  defp filter_chips(filter_values, rows) do
    project_label =
      case Map.fetch!(filter_values, "project_id") do
        @default_project_filter_value ->
          "All repositories"

        project_id ->
          rows
          |> Enum.find(fn row -> Map.get(row, :id) == project_id end)
          |> case do
            nil -> "All repositories"
            row -> row |> Map.get(:github_full_name) |> normalize_optional_string() || project_id
          end
      end

    %{
      project: project_label,
      work_state:
        option_label(
          @work_state_filter_options,
          Map.fetch!(filter_values, "work_state"),
          "Any issue or PR state"
        ),
      freshness_window:
        option_label(
          @freshness_filter_options,
          Map.fetch!(filter_values, "freshness_window"),
          "Any freshness"
        ),
      sort_order:
        option_label(
          @sort_order_options,
          Map.fetch!(filter_values, "sort_order"),
          "Repository name (A-Z)"
        )
    }
  end

  defp sort_rows_with_fallback(rows, filter_values) do
    requested_sort_order = Map.fetch!(filter_values, "sort_order")

    case sort_rows(rows, requested_sort_order) do
      {:ok, sorted_rows} ->
        {sorted_rows, filter_values, nil}

      {:error, reason} ->
        fallback_sort_order = @default_sort_order_value
        {:ok, fallback_rows} = sort_rows(rows, fallback_sort_order)

        {
          fallback_rows,
          Map.put(filter_values, "sort_order", fallback_sort_order),
          sort_validation_notice(requested_sort_order, fallback_sort_order, reason)
        }
    end
  end

  defp sort_rows(rows, @default_sort_order_value) do
    {:ok, Enum.sort_by(rows, &project_sort_key/1)}
  end

  defp sort_rows(rows, "backlog_desc") do
    with :ok <- validate_rows_for_sort(rows, :backlog) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          {-backlog_size(row), project_sort_key(row)}
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(rows, "backlog_asc") do
    with :ok <- validate_rows_for_sort(rows, :backlog) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          {backlog_size(row), project_sort_key(row)}
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(rows, "recent_activity_desc") do
    with :ok <- validate_rows_for_sort(rows, :recent_activity) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          recent_activity_sort_key(row, :desc)
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(rows, "recent_activity_asc") do
    with :ok <- validate_rows_for_sort(rows, :recent_activity) do
      sorted_rows =
        Enum.sort_by(rows, fn row ->
          recent_activity_sort_key(row, :asc)
        end)

      {:ok, sorted_rows}
    end
  end

  defp sort_rows(_rows, _sort_order), do: {:error, :unknown_sort_order}

  defp validate_rows_for_sort(rows, :backlog) do
    if Enum.any?(rows, &malformed_row_for_backlog_sort?/1) do
      {:error, :malformed_backlog_data}
    else
      :ok
    end
  end

  defp validate_rows_for_sort(rows, :recent_activity) do
    if Enum.any?(rows, &malformed_row_for_recent_activity_sort?/1) do
      {:error, :malformed_recent_activity_data}
    else
      :ok
    end
  end

  defp backlog_size(row) do
    Map.get(row, :open_issue_count, 0) + Map.get(row, :open_pr_count, 0)
  end

  defp recent_activity_sort_key(row, direction) do
    activity_at = row_recent_activity_at(row)
    missing_activity = is_nil(activity_at)
    activity_unix = if activity_at, do: DateTime.to_unix(activity_at, :microsecond), else: 0

    case direction do
      :desc ->
        {if(missing_activity, do: 1, else: 0), -activity_unix, project_sort_key(row)}

      :asc ->
        {if(missing_activity, do: 1, else: 0), activity_unix, project_sort_key(row)}
    end
  end

  defp malformed_row_for_backlog_sort?(row) do
    fallback_row_id?(row) or
      not non_negative_integer?(Map.get(row, :open_issue_count)) or
      not non_negative_integer?(Map.get(row, :open_pr_count))
  end

  defp malformed_row_for_recent_activity_sort?(row) do
    fallback_row_id?(row) or
      case row_recent_activity_at(row) do
        %DateTime{} -> false
        nil -> false
        _other -> true
      end
  end

  defp fallback_row_id?(row) do
    case row |> Map.get(:id) |> normalize_optional_string() do
      <<@fallback_row_id_prefix, _::binary>> -> true
      _other -> false
    end
  end

  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp project_sort_key(row) do
    {
      row |> Map.get(:github_full_name) |> sort_string_key(),
      row |> Map.get(:name) |> sort_string_key(),
      row |> Map.get(:id) |> sort_string_key()
    }
  end

  defp sort_string_key(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> ""
      normalized -> String.downcase(normalized)
    end
  end

  defp sort_validation_notice(requested_sort_order, fallback_sort_order, reason) do
    requested_sort_label =
      option_label(@sort_order_options, requested_sort_order, requested_sort_order)

    fallback_sort_label =
      option_label(@sort_order_options, fallback_sort_order, fallback_sort_order)

    %{
      error_type: @sort_validation_error_type,
      detail:
        "Sort order #{requested_sort_label} could not be applied (#{sort_failure_reason(reason)}). #{fallback_sort_label} was applied instead.",
      remediation: "Refresh workbench data and verify backlog and activity metadata before retrying."
    }
  end

  defp sort_failure_reason(:malformed_backlog_data), do: "malformed backlog fields were detected"

  defp sort_failure_reason(:malformed_recent_activity_data),
    do: "malformed activity fields were detected"

  defp sort_failure_reason(:unknown_sort_order), do: "unsupported sort value was submitted"
  defp sort_failure_reason(_reason), do: "sorting metadata validation failed"

  defp option_label(options, value, default_label) do
    Enum.find_value(options, default_label, fn
      {label, ^value} -> label
      _other -> nil
    end)
  end

  defp project_filter_options(rows) do
    dynamic_options =
      rows
      |> Enum.map(fn row ->
        label =
          row
          |> Map.get(:github_full_name)
          |> normalize_optional_string() ||
            row
            |> Map.get(:name)
            |> normalize_optional_string() ||
            Map.get(row, :id)

        {label, Map.get(row, :id)}
      end)
      |> Enum.reject(fn {label, value} -> is_nil(label) or is_nil(value) end)
      |> Enum.uniq_by(fn {_label, value} -> value end)
      |> Enum.sort_by(fn {label, _value} -> String.downcase(label) end)

    [{"All repositories", @default_project_filter_value} | dynamic_options]
  end

  defp work_state_filter_options, do: @work_state_filter_options
  defp freshness_filter_options, do: @freshness_filter_options
  defp sort_order_options, do: @sort_order_options
  defp to_filter_form(filter_values), do: to_form(filter_values, as: :filters)

  defp empty_state_message(0), do: "No imported repositories available yet."
  defp empty_state_message(_inventory_total_count), do: "No repositories match the active filters."

  defp map_get(map, string_key, atom_key) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp find_project_row(rows, project_id) when is_list(rows) do
    normalized_project_id = normalize_optional_string(project_id)

    Enum.find(rows, fn row ->
      row
      |> map_get("id", :id)
      |> normalize_optional_string() == normalized_project_id
    end)
  end

  defp find_project_row(_rows, _project_id), do: nil

  defp put_fix_workflow_kickoff_state(socket, project_id, context_item_type, kickoff_result) do
    state_key = fix_workflow_kickoff_state_key(project_id, context_item_type)
    state_value = kickoff_feedback_state(kickoff_result, project_id)

    update(socket, :fix_workflow_kickoff_states, &Map.put(&1, state_key, state_value))
  end

  defp put_issue_triage_workflow_kickoff_state(
         socket,
         project_id,
         context_item_type,
         kickoff_result
       ) do
    state_key = issue_triage_workflow_kickoff_state_key(project_id, context_item_type)
    state_value = kickoff_feedback_state(kickoff_result, project_id)

    update(socket, :issue_triage_workflow_kickoff_states, &Map.put(&1, state_key, state_value))
  end

  defp put_recent_run_outcome_from_kickoff(socket, project_id, kickoff_result) do
    normalized_project_id = normalize_optional_string(project_id)

    if is_binary(normalized_project_id) do
      case kickoff_run_outcome(kickoff_result, normalized_project_id) do
        %{} = outcome ->
          update(socket, :recent_run_outcomes, &Map.put(&1, normalized_project_id, outcome))

        _other ->
          socket
      end
    else
      socket
    end
  end

  defp kickoff_run_outcome({:ok, kickoff_run}, project_id) when is_map(kickoff_run) do
    run_id =
      kickoff_run
      |> map_get("run_id", :run_id)
      |> normalize_optional_string()

    detail_path =
      kickoff_run
      |> map_get("detail_path", :detail_path)
      |> normalize_optional_string() || run_detail_path(project_id, run_id)

    if run_id && detail_path do
      %{
        status: "pending",
        run_id: run_id,
        detail_path: detail_path,
        error_type: nil,
        detail: nil,
        guidance: nil
      }
    end
  end

  defp kickoff_run_outcome({:error, kickoff_error}, project_id) when is_map(kickoff_error) do
    run_creation_state =
      kickoff_error
      |> map_get("run_creation_state", :run_creation_state)
      |> normalize_run_creation_state()

    run_id =
      kickoff_error
      |> map_get("run_id", :run_id)
      |> normalize_optional_string()

    case {run_creation_state, run_id} do
      {:created, resolved_run_id} when is_binary(resolved_run_id) ->
        %{
          status: "pending",
          run_id: resolved_run_id,
          detail_path: run_detail_path(project_id, resolved_run_id),
          error_type: nil,
          detail: nil,
          guidance: nil
        }

      _other ->
        nil
    end
  end

  defp kickoff_run_outcome(_kickoff_result, _project_id), do: nil

  defp kickoff_feedback_state({:ok, kickoff_run}, _project_id) when is_map(kickoff_run) do
    %{status: :ok, run: kickoff_run, confirmation_state: :confirmed}
  end

  defp kickoff_feedback_state({:error, kickoff_error}, project_id) when is_map(kickoff_error) do
    run_creation_state =
      kickoff_error
      |> map_get("run_creation_state", :run_creation_state)
      |> normalize_run_creation_state()

    run_id =
      kickoff_error
      |> map_get("run_id", :run_id)
      |> normalize_optional_string()

    case {run_creation_state, run_id} do
      {:created, resolved_run_id} when is_binary(resolved_run_id) ->
        %{
          status: :ok,
          run: %{
            run_id: resolved_run_id,
            detail_path: run_detail_path(project_id, resolved_run_id)
          },
          confirmation_state: :confirmed_after_interruption
        }

      {:not_created, _resolved_run_id} ->
        %{
          status: :error,
          error: kickoff_error,
          confirmation_state: :not_created_after_interruption
        }

      _other ->
        %{status: :error, error: kickoff_error, confirmation_state: :failed}
    end
  end

  defp kickoff_feedback_state(_kickoff_result, _project_id) do
    %{
      status: :error,
      error: %{
        error_type: "workbench_workflow_kickoff_invalid_result",
        detail: "Workflow kickoff returned an invalid response shape.",
        remediation: "Retry workflow kickoff from this row.",
        run_creation_state: nil,
        run_id: nil
      },
      confirmation_state: :failed
    }
  end

  defp run_detail_path(project_id, run_id) do
    normalized_project_id = normalize_optional_string(project_id) || "unknown-project"
    normalized_run_id = normalize_optional_string(run_id) || "unknown-run"
    "/repos/#{URI.encode(normalized_project_id)}/runs/#{URI.encode(normalized_run_id)}"
  end

  defp refresh_project_row(socket, project_row) when is_map(project_row) do
    stream_insert(socket, :inventory_rows, project_row)
  end

  defp refresh_project_row(socket, _project_row), do: socket

  defp fix_workflow_kickoff_feedback(states, project_id, context_item_type) when is_map(states) do
    Map.get(states, fix_workflow_kickoff_state_key(project_id, context_item_type))
  end

  defp fix_workflow_kickoff_feedback(_states, _project_id, _context_item_type), do: nil

  defp fix_workflow_kickoff_state_key(project_id, context_item_type) do
    normalized_project_id = normalize_optional_string(project_id) || "unknown-project"
    normalized_context_item_type = normalize_context_item_type_for_state_key(context_item_type)
    "#{normalized_project_id}:#{normalized_context_item_type}"
  end

  defp issue_triage_workflow_kickoff_feedback(states, project_id, context_item_type)
       when is_map(states) do
    Map.get(states, issue_triage_workflow_kickoff_state_key(project_id, context_item_type))
  end

  defp issue_triage_workflow_kickoff_feedback(_states, _project_id, _context_item_type), do: nil

  defp issue_triage_workflow_kickoff_state_key(project_id, context_item_type) do
    normalized_project_id = normalize_optional_string(project_id) || "unknown-project"
    normalized_context_item_type = normalize_context_item_type_for_state_key(context_item_type)
    "#{normalized_project_id}:#{normalized_context_item_type}"
  end

  defp issue_triage_policy_state(project_row) do
    IssueTriageWorkflowKickoff.policy_state(project_row)
  end

  defp normalize_context_item_type_for_state_key(:issue), do: :issue
  defp normalize_context_item_type_for_state_key("issue"), do: :issue
  defp normalize_context_item_type_for_state_key(:pull_request), do: :pull_request
  defp normalize_context_item_type_for_state_key("pull_request"), do: :pull_request
  defp normalize_context_item_type_for_state_key(_context_item_type), do: :unknown

  defp normalize_run_creation_state(:created), do: :created
  defp normalize_run_creation_state("created"), do: :created
  defp normalize_run_creation_state(:not_created), do: :not_created
  defp normalize_run_creation_state("not_created"), do: :not_created
  defp normalize_run_creation_state(_run_creation_state), do: nil

  defp recent_run_outcome(outcomes, project_id) when is_map(outcomes) do
    normalized_project_id = normalize_optional_string(project_id)

    if normalized_project_id do
      Map.get(outcomes, normalized_project_id)
    end
  end

  defp recent_run_outcome(_outcomes, _project_id), do: nil

  defp semantic_graph_hint(project) when is_map(project) do
    case Map.get(project, :semantic_graph_hint) do
      %{} = hint -> hint
      _other -> nil
    end
  end

  defp semantic_graph_hint(_project), do: nil

  defp semantic_graph_hint_badge_class(%{state: :ready}), do: "badge badge-success badge-xs"
  defp semantic_graph_hint_badge_class(%{state: :stale}), do: "badge badge-warning badge-xs"
  defp semantic_graph_hint_badge_class(%{state: :degraded}), do: "badge badge-warning badge-xs"
  defp semantic_graph_hint_badge_class(%{state: :failed}), do: "badge badge-error badge-xs"
  defp semantic_graph_hint_badge_class(%{state: :not_ready}), do: "badge badge-outline badge-xs"
  defp semantic_graph_hint_badge_class(_hint), do: "badge badge-outline badge-xs"

  defp semantic_graph_hint_recovery_path(project, filter_values) do
    hint = semantic_graph_hint(project)

    if hint && get_in(hint, [:recovery, :available?]) do
      project_detail_path(project, filter_values)
    end
  end

  attr(:outcome, :map, default: nil)
  attr(:dom_prefix, :string, required: true)

  defp recent_run_outcome_indicator(assigns) do
    ~H"""
    <section id={"#{@dom_prefix}-container"} class="space-y-1 pt-1">
      <p id={"#{@dom_prefix}-label"} class="text-[11px] text-base-content/70">
        Recent run outcome
      </p>
      <%= case @outcome do %>
        <% nil -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px] text-base-content/60">
            No recent run.
          </p>
        <% %{status: "unknown"} = outcome -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px] text-warning">
            Recent run status: unknown
          </p>
          <p :if={is_binary(outcome.error_type)} id={"#{@dom_prefix}-error-type"} class="text-[11px] text-warning">
            Typed run outcome warning: {outcome.error_type}
          </p>
          <p :if={is_binary(outcome.detail)} id={"#{@dom_prefix}-detail"} class="text-[11px] text-warning">
            {outcome.detail}
          </p>
          <p id={"#{@dom_prefix}-guidance"} class="text-[11px] text-base-content/60">
            {outcome.guidance || "Refresh workbench data to resolve recent run status."}
          </p>
          <.link
            :if={is_binary(outcome.detail_path)}
            id={"#{@dom_prefix}-link"}
            class="link link-primary text-[11px]"
            href={outcome.detail_path}
          >
            Open run detail
          </.link>
        <% outcome -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px]">
            <span class={run_outcome_status_badge_class(outcome.status)}>
              {run_outcome_status_label(outcome.status)}
            </span>
          </p>
          <p id={"#{@dom_prefix}-run-id"} class="text-[11px] text-base-content/70">
            Run: <span class="font-mono">{outcome.run_id}</span>
          </p>
          <.link
            id={"#{@dom_prefix}-link"}
            class="link link-primary text-[11px]"
            href={outcome.detail_path}
          >
            Open run detail
          </.link>
      <% end %>
    </section>
    """
  end

  defp run_outcome_status_badge_class("completed"), do: "badge badge-success badge-xs"
  defp run_outcome_status_badge_class("running"), do: "badge badge-info badge-xs"
  defp run_outcome_status_badge_class("failed"), do: "badge badge-error badge-xs"
  defp run_outcome_status_badge_class("cancelled"), do: "badge badge-warning badge-xs"
  defp run_outcome_status_badge_class("awaiting_approval"), do: "badge badge-warning badge-xs"
  defp run_outcome_status_badge_class("pending"), do: "badge badge-outline badge-xs"
  defp run_outcome_status_badge_class(_status), do: "badge badge-outline badge-xs"

  defp run_outcome_status_label(status) do
    status
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized_status -> normalized_status
    end
  end

  attr(:feedback, :map, default: nil)
  attr(:dom_prefix, :string, required: true)

  defp fix_workflow_kickoff_feedback(assigns) do
    ~H"""
    <section :if={@feedback} id={"#{@dom_prefix}-feedback"} class="space-y-1 pt-1">
      <%= case @feedback.status do %>
        <% :ok -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px] text-success">
            {kickoff_success_status(@feedback)}
          </p>
          <p id={"#{@dom_prefix}-run-id"} class="text-[11px] text-success">
            Run: <span class="font-mono">{@feedback.run.run_id}</span>
          </p>
          <.link
            id={"#{@dom_prefix}-run-link"}
            class="link link-primary text-[11px]"
            href={@feedback.run.detail_path}
          >
            Open run detail
          </.link>
        <% :error -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px] text-error">
            {kickoff_error_status(@feedback)}
          </p>
          <p id={"#{@dom_prefix}-error-type"} class="text-[11px] text-error">
            Typed kickoff error: {@feedback.error.error_type}
          </p>
          <p id={"#{@dom_prefix}-error-detail"} class="text-[11px] text-error">
            {@feedback.error.detail}
          </p>
          <p id={"#{@dom_prefix}-error-remediation"} class="text-[11px] text-base-content/60">
            {@feedback.error.remediation}
          </p>
      <% end %>
    </section>
    """
  end

  attr(:feedback, :map, default: nil)
  attr(:dom_prefix, :string, required: true)

  defp issue_triage_workflow_kickoff_feedback(assigns) do
    ~H"""
    <section :if={@feedback} id={"#{@dom_prefix}-feedback"} class="space-y-1 pt-1">
      <%= case @feedback.status do %>
        <% :ok -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px] text-success">
            {kickoff_success_status(@feedback)}
          </p>
          <p id={"#{@dom_prefix}-run-id"} class="text-[11px] text-success">
            Run: <span class="font-mono">{@feedback.run.run_id}</span>
          </p>
          <.link
            id={"#{@dom_prefix}-run-link"}
            class="link link-primary text-[11px]"
            href={@feedback.run.detail_path}
          >
            Open run detail
          </.link>
        <% :error -> %>
          <p id={"#{@dom_prefix}-status"} class="text-[11px] text-error">
            {kickoff_error_status(@feedback)}
          </p>
          <p id={"#{@dom_prefix}-error-type"} class="text-[11px] text-error">
            Typed kickoff error: {@feedback.error.error_type}
          </p>
          <p id={"#{@dom_prefix}-error-detail"} class="text-[11px] text-error">
            {@feedback.error.detail}
          </p>
          <p id={"#{@dom_prefix}-error-remediation"} class="text-[11px] text-base-content/60">
            {@feedback.error.remediation}
          </p>
      <% end %>
    </section>
    """
  end

  defp kickoff_success_status(feedback) when is_map(feedback) do
    case Map.get(feedback, :confirmation_state) do
      :confirmed_after_interruption ->
        "Kickoff confirmed after interruption: run was created."

      _other ->
        "Kickoff confirmed: run was created."
    end
  end

  defp kickoff_error_status(feedback) when is_map(feedback) do
    case Map.get(feedback, :confirmation_state) do
      :not_created_after_interruption ->
        "Kickoff failed after interruption: run was not created."

      _other ->
        "Kickoff failed: review typed error details."
    end
  end

  attr(:policy_state, :map, required: true)
  attr(:dom_prefix, :string, required: true)

  defp issue_triage_policy_blocked_feedback(assigns) do
    ~H"""
    <section :if={!@policy_state.enabled} id={"#{@dom_prefix}-feedback"} class="space-y-1 pt-1">
      <span
        id={@dom_prefix}
        class="btn btn-xs btn-outline w-fit mt-1 cursor-not-allowed border-base-300 text-base-content/60"
        aria-disabled="true"
        title={@policy_state.detail}
      >
        Kick off issue triage workflow
      </span>
      <p id={"#{@dom_prefix}-type"} class="text-[11px] text-warning">
        Policy state: {@policy_state.error_type}
      </p>
      <p id={"#{@dom_prefix}-reason"} class="text-[11px] text-warning">
        {@policy_state.detail}
      </p>
      <p id={"#{@dom_prefix}-remediation"} class="text-[11px] text-base-content/60">
        {@policy_state.remediation}
      </p>
    </section>
    """
  end

  attr(:link_id, :string, required: true)
  attr(:disabled_id, :string, required: true)
  attr(:reason_id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:target, :string, default: nil)
  attr(:disabled_reason, :string, required: true)
  attr(:external, :boolean, default: false)

  defp row_link(assigns) do
    ~H"""
    <%= if is_binary(@target) do %>
      <.link
        id={@link_id}
        class="link link-primary"
        href={@target}
        target={if @external, do: "_blank"}
        rel={if @external, do: "noopener noreferrer"}
      >
        {@label}
      </.link>
    <% else %>
      <span
        id={@disabled_id}
        class="text-base-content/50 cursor-not-allowed"
        aria-disabled="true"
        title={@disabled_reason}
      >
        {@label}
      </span>
      <p id={@reason_id} class="text-[11px] text-base-content/60">
        Unavailable: {@disabled_reason}
      </p>
    <% end %>
    """
  end

  defp issue_github_url(project) do
    with {:ok, repository_path} <- github_repository_path(project) do
      "#{repository_path}/issues"
    end
  end

  defp pull_request_github_url(project) do
    with {:ok, repository_path} <- github_repository_path(project) do
      "#{repository_path}/pulls"
    end
  end

  defp github_repository_path(project) do
    project
    |> Map.get(:github_full_name)
    |> normalize_optional_string()
    |> parse_github_repository_name()
    |> case do
      {:ok, owner, repository} -> {:ok, "https://github.com/#{owner}/#{repository}"}
      :error -> :error
    end
  end

  defp parse_github_repository_name(nil), do: :error

  defp parse_github_repository_name(github_full_name) do
    case String.split(github_full_name, "/", parts: 2) do
      [owner, repository] ->
        owner = String.trim(owner)
        repository = String.trim(repository)

        if owner == "" or repository == "" or String.contains?(owner <> repository, " ") do
          :error
        else
          {:ok, owner, repository}
        end

      _other ->
        :error
    end
  end

  defp project_detail_path(project, filter_values) do
    project
    |> Map.get(:id)
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      <<@fallback_row_id_prefix, _::binary>> ->
        nil

      project_id ->
        base_path = "/repos/#{URI.encode(project_id)}"
        return_to = workbench_path_with_filter_values(normalize_filter_values(filter_values))

        if return_to == "/workbench" do
          base_path
        else
          "#{base_path}?return_to=#{URI.encode_www_form(return_to)}"
        end
    end
  end

  defp initiating_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        %{
          id:
            user
            |> Map.get(:id)
            |> normalize_optional_string() || "unknown",
          email:
            user
            |> Map.get(:email)
            |> normalize_optional_string()
        }

      _other ->
        %{id: "unknown", email: nil}
    end
  end

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

  defp normalize_optional_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_optional_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> parsed_datetime
      _other -> nil
    end
  end

  defp normalize_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed_datetime, _offset} ->
        parsed_datetime

      _other ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, parsed_naive_datetime} ->
            normalize_optional_datetime(parsed_naive_datetime)

          _fallback ->
            nil
        end
    end
  end

  defp normalize_optional_datetime(_value), do: nil

  defp github_url_unavailable_reason, do: "GitHub repository URL is unavailable for this row."
  defp project_detail_unavailable_reason, do: "Repo detail link is unavailable for this row."
end
