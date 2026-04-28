defmodule JidoCodeWeb.DashboardLive do
  # covers: package.jido_code.primary_implementation_repo
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  import JidoCodeWeb.ManagedRepoInventoryComponents

  alias JidoCode.MemoryGraph.DashboardSummaryFeed
  alias JidoCode.Governance.RuntimeEvidenceFeed
  alias JidoCode.Orchestration.{RunPubSub, RunSummaryFeed}
  alias JidoCodeWeb.OperatorShell
  alias JidoCode.Workbench.{
    DashboardConversationFeed,
    FixWorkflowKickoff,
    InventoryActionState,
    InventorySurface,
    IssueTriageWorkflowKickoff
  }

  @dashboard_subject_order [:work, :knowledge, :runtime]
  @dashboard_sections [:overview, :runs, :conversations, :memory, :runtime]
  @onboarding_next_actions [
    "Run your first workflow",
    "Review the security playbook",
    "Test the RPC client"
  ]

  @run_events_for_refresh MapSet.new([
                                    "run_started",
                                    "run_completed",
                                    "run_failed",
                                    "run_cancelled"
                                  ])

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:selected_dashboard_subject, :work)
      |> assign(:selected_dashboard_section, :overview)
      |> assign(:dashboard_sections, @dashboard_sections)
      |> assign(:onboarding_next_actions, [])
      |> assign(:run_summary_count, 0)
      |> assign(:run_summary_rows, [])
      |> assign(:run_summary_widget_rows, [])
      |> assign(:run_summary_warning, nil)
      |> assign(:run_summary_last_refreshed_at, nil)
      |> assign(:conversation_summary_count, 0)
      |> assign(:conversation_summary_rows, [])
      |> assign(:conversation_summary_warning, nil)
      |> assign(:conversation_summary_last_refreshed_at, nil)
      |> assign(:runtime_evidence_count, 0)
      |> assign(:runtime_evidence_rows, [])
      |> assign(:runtime_evidence_widget_rows, [])
      |> assign(:runtime_evidence_warning, nil)
      |> assign(:runtime_evidence_last_refreshed_at, nil)
      |> assign(:runtime_evidence_summary, nil)
      |> assign(:memory_summary_count, 0)
      |> assign(:memory_summary_rows, [])
      |> assign(:memory_summary_warning, nil)
      |> assign(:memory_summary_last_refreshed_at, nil)
      |> assign(:repository_monitoring_count, 0)
      |> assign(:repository_monitoring_rows, [])
      |> assign(:repository_monitoring_warning, nil)
      |> assign(:repository_monitoring_last_refreshed_at, nil)
      |> assign(:recent_run_outcomes, %{})
      |> assign(:fix_workflow_kickoff_states, %{})
      |> assign(:issue_triage_workflow_kickoff_states, %{})
      |> stream_configure(:conversation_summaries, dom_id: &conversation_summary_dom_id/1)
      |> stream(:conversation_summaries, [], reset: true)
      |> stream_configure(:memory_summaries, dom_id: &memory_summary_dom_id/1)
      |> stream(:memory_summaries, [], reset: true)
      |> stream_configure(:runtime_evidence_summaries, dom_id: &runtime_evidence_dom_id/1)
      |> stream(:runtime_evidence_summaries, [], reset: true)
      |> stream_configure(:run_summaries, dom_id: &run_summary_dom_id/1)
      |> stream(:run_summaries, [], reset: true)
      |> load_run_summaries()
      |> load_conversation_summaries()
      |> load_memory_summaries()
      |> load_runtime_evidence_summaries()
      |> load_repository_monitoring_summaries()
      |> maybe_subscribe_run_events()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    onboarding_next_actions =
      if Map.get(params, "onboarding") == "completed" do
        @onboarding_next_actions
      else
        []
      end

    dashboard_sections = dashboard_sections(onboarding_next_actions)

    {selected_dashboard_subject, selected_dashboard_section} =
      normalize_dashboard_selection(params, onboarding_next_actions)

    {:noreply,
     socket
     |> assign(:onboarding_next_actions, onboarding_next_actions)
     |> assign(:dashboard_sections, dashboard_sections)
     |> assign(:selected_dashboard_subject, selected_dashboard_subject)
     |> assign(:selected_dashboard_section, selected_dashboard_section)}
  end

  @impl true
  def handle_event("refresh_dashboard_overview", _params, socket) do
    {:noreply,
     socket
     |> load_run_summaries()
     |> load_conversation_summaries()
     |> load_memory_summaries()
     |> load_runtime_evidence_summaries()
     |> load_repository_monitoring_summaries()}
  end

  @impl true
  def handle_event("refresh_run_summaries", _params, socket) do
    {:noreply, socket |> load_run_summaries() |> load_repository_monitoring_summaries()}
  end

  @impl true
  def handle_event("refresh_conversation_summaries", _params, socket) do
    {:noreply, socket |> load_conversation_summaries() |> load_repository_monitoring_summaries()}
  end

  @impl true
  def handle_event("refresh_runtime_evidence", _params, socket) do
    {:noreply, socket |> load_runtime_evidence_summaries() |> load_repository_monitoring_summaries()}
  end

  @impl true
  def handle_event("refresh_memory_summaries", _params, socket) do
    {:noreply, socket |> load_memory_summaries() |> load_repository_monitoring_summaries()}
  end

  @impl true
  def handle_event(
        "kickoff_fix_workflow",
        %{"project_id" => project_id, "context_item_type" => context_item_type},
        socket
      ) do
    project_row = find_project_row(socket.assigns.repository_monitoring_rows, project_id)
    kickoff_result = FixWorkflowKickoff.kickoff(project_row, context_item_type, initiating_actor(socket))

    {:noreply,
     socket
     |> put_fix_workflow_kickoff_state(project_id, context_item_type, kickoff_result)
     |> put_recent_run_outcome_from_kickoff(project_id, kickoff_result)}
  end

  @impl true
  def handle_event(
        "kickoff_issue_triage_workflow",
        %{"project_id" => project_id, "context_item_type" => context_item_type},
        socket
      ) do
    project_row = find_project_row(socket.assigns.repository_monitoring_rows, project_id)

    kickoff_result =
      IssueTriageWorkflowKickoff.kickoff(
        project_row,
        context_item_type,
        initiating_actor(socket)
      )

    {:noreply,
     socket
     |> put_issue_triage_workflow_kickoff_state(project_id, context_item_type, kickoff_result)
     |> put_recent_run_outcome_from_kickoff(project_id, kickoff_result)}
  end

  @impl true
  def handle_info({:run_event, payload}, socket) do
    event_name =
      payload
      |> map_get(:event, "event")
      |> normalize_optional_string()

    if MapSet.member?(@run_events_for_refresh, event_name) do
      {:noreply,
       socket
       |> load_run_summaries()
       |> load_conversation_summaries()
       |> load_memory_summaries()
       |> load_runtime_evidence_summaries()
       |> load_repository_monitoring_summaries()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div
        id="dashboard-root"
        data-dashboard-subject={Atom.to_string(@selected_dashboard_subject)}
        data-dashboard-section={Atom.to_string(@selected_dashboard_section)}
        class="max-w-7xl mx-auto py-8"
      >
        <h1 class="text-2xl font-bold mb-4">Dashboard</h1>
        <p class="text-base-content/70">Welcome, {@current_user.email}</p>
        <p id="dashboard-entry-summary" class="mt-1 text-sm text-base-content/75">
          Dashboard is the authenticated product home for managed-repository inventory, governed runs, conversations, memory, and runtime posture.
        </p>
        <p id="dashboard-settings-handoff" class="mt-2 text-sm text-base-content/70">
          Provider login and Git automation configuration live in <.link
            navigate={~p"/settings/auth"}
            class="link link-primary"
          >Settings</.link>.
        </p>

        <.subject_tree_shell
          id="dashboard-shell"
          class="mt-6"
          breadcrumbs={dashboard_breadcrumbs(assigns)}
          parent_subjects={dashboard_parent_subjects(assigns)}
          child_subjects={dashboard_section_nav_items(assigns)}
          child_nav_id="dashboard-section-nav"
          child_nav_label={dashboard_child_nav_label(assigns.selected_dashboard_subject)}
          child_nav_heading={dashboard_child_nav_heading(assigns.selected_dashboard_subject)}
          child_nav_summary={dashboard_child_nav_summary(assigns.selected_dashboard_subject)}
          sidebar_id="dashboard-sidebar-shell"
          content_id="dashboard-content-shell"
        >
          <.subject_pane pane={dashboard_selected_pane(assigns)}>
            <section
              :if={@selected_dashboard_section == :overview}
              id="dashboard-overview-panel"
              class="space-y-4"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Managed repo inventory</h2>
                  <p id="dashboard-overview-note" class="text-sm text-base-content/80">
                    Dashboard Work is the primary signed-in home for repository inventory, governed triage, and repo-detail follow-up. <.link
                      id="dashboard-overview-workbench-link"
                      navigate={dashboard_workbench_path(assigns)}
                      class="link link-primary"
                    >Workbench</.link> stays available as the denser specialist mode.
                  </p>
                </div>
                <p id="dashboard-overview-last-refreshed" class="text-xs text-base-content/70">
                  Last refreshed: {summary_refreshed_label(@repository_monitoring_last_refreshed_at)}
                </p>
              </div>

              <.operator_state_notice
                :if={@repository_monitoring_warning}
                id="dashboard-overview-warning"
                title="Managed repo inventory may be stale"
                state={@repository_monitoring_warning}
                compact={true}
              />

              <%= if @repository_monitoring_count == 0 do %>
                <p id="dashboard-overview-empty-state" class="text-sm text-base-content/70">
                  No managed-repository inventory is available yet.
                </p>
              <% else %>
                <ol id="dashboard-overview-repository-list" class="grid gap-4 xl:grid-cols-2">
                  <li
                    :for={entry <- @repository_monitoring_rows}
                    id={"dashboard-overview-repository-card-#{repo_monitoring_dom_token(entry.id)}"}
                    class="rounded-xl border border-base-300/70 bg-base-200/20 p-4 space-y-4"
                  >
                    <div class="flex flex-wrap items-start justify-between gap-3">
                      <div class="space-y-1">
                        <p
                          id={"dashboard-overview-repository-label-#{repo_monitoring_dom_token(entry.id)}"}
                          class="text-sm font-semibold"
                        >
                          {entry.github_full_name}
                        </p>
                        <p
                          id={"dashboard-overview-repository-detail-#{repo_monitoring_dom_token(entry.id)}"}
                          class="text-xs text-base-content/65"
                        >
                          {entry.name}
                        </p>
                      </div>

                      <div class="flex flex-wrap gap-2">
                        <span
                          id={"dashboard-overview-repository-badge-issues-#{repo_monitoring_dom_token(entry.id)}"}
                          class="badge badge-outline badge-sm"
                        >
                          {entry.open_issue_count} open {pluralize(entry.open_issue_count, "issue", "issues")}
                        </span>
                        <span
                          id={"dashboard-overview-repository-badge-prs-#{repo_monitoring_dom_token(entry.id)}"}
                          class="badge badge-outline badge-sm"
                        >
                          {entry.open_pr_count} open PR{if(entry.open_pr_count == 1, do: "", else: "s")}
                        </span>
                        <span
                          :if={runtime_badge = dashboard_runtime_inventory_badge(@runtime_evidence_rows, entry)}
                          id={"dashboard-overview-repository-badge-runtime-#{repo_monitoring_dom_token(entry.id)}"}
                          class={runtime_badge.class}
                        >
                          {runtime_badge.label}
                        </span>
                      </div>
                    </div>

                    <p
                      id={"dashboard-overview-repository-summary-#{repo_monitoring_dom_token(entry.id)}"}
                      class="text-sm text-base-content/80"
                    >
                      {entry.recent_activity_summary}
                    </p>

                    <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-base-content/70">
                      <p id={"dashboard-overview-repository-branch-#{repo_monitoring_dom_token(entry.id)}"}>
                        Branch: {entry.default_branch}
                      </p>
                      <p id={"dashboard-overview-repository-activity-#{repo_monitoring_dom_token(entry.id)}"}>
                        {dashboard_inventory_activity_label(entry)}
                      </p>
                    </div>

                    <.managed_repo_hint_stack
                      row={entry}
                      dom_prefix="dashboard-overview-repository"
                      detail_path={dashboard_inventory_detail_path(assigns, entry)}
                    />

                    <div class="grid gap-4 lg:grid-cols-2">
                      <.managed_repo_action_cluster
                        row={entry}
                        dom_prefix="dashboard-overview-repository-issues"
                        detail_path={dashboard_inventory_detail_path(assigns, entry)}
                        kind={:issue}
                        recent_run_outcome={InventorySurface.recent_run_outcome(@recent_run_outcomes, entry.id)}
                        triage_policy_state={InventorySurface.issue_triage_policy_state(entry)}
                        issue_triage_feedback={
                          InventoryActionState.issue_triage_feedback(
                            @issue_triage_workflow_kickoff_states,
                            entry.id,
                            :issue
                          )
                        }
                        fix_feedback={
                          InventoryActionState.fix_feedback(
                            @fix_workflow_kickoff_states,
                            entry.id,
                            :issue
                          )
                        }
                      />

                      <.managed_repo_action_cluster
                        row={entry}
                        dom_prefix="dashboard-overview-repository-prs"
                        detail_path={dashboard_inventory_detail_path(assigns, entry)}
                        kind={:pull_request}
                        recent_run_outcome={InventorySurface.recent_run_outcome(@recent_run_outcomes, entry.id)}
                        fix_feedback={
                          InventoryActionState.fix_feedback(
                            @fix_workflow_kickoff_states,
                            entry.id,
                            :pull_request
                          )
                        }
                      />
                    </div>
                  </li>
                </ol>
              <% end %>
            </section>

            <section
              :if={@selected_dashboard_section == :runs}
              id="dashboard-run-summaries"
              class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <h2 class="text-lg font-semibold">Recent governed runs</h2>
                <p id="dashboard-run-summary-last-refreshed" class="text-xs text-base-content/70">
                  Last refreshed: {summary_refreshed_label(@run_summary_last_refreshed_at)}
                </p>
              </div>

              <.operator_state_notice
                :if={@run_summary_warning}
                id="dashboard-run-summary-warning"
                title="Run summary feed may be stale"
                state={@run_summary_warning}
                compact={true}
              />

              <.vue_surface
                id="dashboard-run-summary-widget"
                component="DashboardRunSummaryWidget"
                socket={@socket}
                props={
                  %{
                    runSummaries: @run_summary_widget_rows,
                    runSummaryCount: @run_summary_count,
                    lastRefreshedLabel: summary_refreshed_label(@run_summary_last_refreshed_at)
                  }
                }
              />

              <details
                id="dashboard-run-summary-fallback"
                class="rounded-lg border border-base-300/70 bg-base-200/20"
              >
                <summary class="cursor-pointer px-4 py-3 text-sm font-medium">
                  LiveView detail fallback
                </summary>
                <div class="overflow-x-auto border-t border-base-300/70">
                  <table id="dashboard-run-summaries-table" class="table w-full">
                    <thead>
                      <tr>
                        <th>Run</th>
                        <th>Status</th>
                        <th>Recency</th>
                      </tr>
                    </thead>
                    <tbody :if={@run_summary_count == 0} id="dashboard-run-summaries-empty">
                      <tr id="dashboard-run-summaries-empty-state">
                        <td colspan="3" class="py-6 text-center text-sm text-base-content/70">
                          No recent runs available.
                        </td>
                      </tr>
                    </tbody>
                    <tbody id="dashboard-run-summaries-rows" phx-update="stream">
                      <tr :for={{dom_id, run_summary} <- @streams.run_summaries} id={dom_id}>
                        <td id={"dashboard-run-id-#{run_summary_dom_token(run_summary.run_id)}"} class="font-mono text-xs">
                          <.link
                            id={"dashboard-run-link-#{run_summary_dom_token(run_summary.run_id)}"}
                            class="link link-primary"
                            navigate={run_detail_path(run_summary)}
                          >
                            {run_summary.run_id}
                          </.link>
                          <p class="text-xs text-base-content/70">{run_summary.workflow_name}</p>
                        </td>
                        <td id={"dashboard-run-status-#{run_summary_dom_token(run_summary.run_id)}"}>
                          <span class={run_status_badge_class(run_summary.status)}>
                            {run_summary.status}
                          </span>
                          <p
                            :if={run_governance_summary(run_summary)}
                            id={"dashboard-run-governance-#{run_summary_dom_token(run_summary.run_id)}"}
                            class="pt-1 text-xs text-base-content/70"
                          >
                            {run_governance_summary(run_summary)}
                          </p>
                        </td>
                        <td id={"dashboard-run-recency-#{run_summary_dom_token(run_summary.run_id)}"} class="text-xs">
                          {run_recency_label(run_summary)}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </details>
            </section>

            <section
              :if={@selected_dashboard_section == :conversations}
              id="dashboard-conversation-supervision"
              class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Conversation supervision</h2>
                  <p id="dashboard-conversation-summary-note" class="text-sm text-base-content/80">
                    Active governed conversations and clarification-needed repository work stay bounded here and route back to canonical repo detail.
                  </p>
                </div>
                <p id="dashboard-conversation-summary-last-refreshed" class="text-xs text-base-content/70">
                  Last refreshed: {summary_refreshed_label(@conversation_summary_last_refreshed_at)}
                </p>
              </div>

              <.operator_state_notice
                :if={@conversation_summary_warning}
                id="dashboard-conversation-summary-warning"
                title="Conversation supervision may be stale"
                state={@conversation_summary_warning}
                compact={true}
              />

              <%= if @conversation_summary_count == 0 do %>
                <p id="dashboard-conversation-summary-empty" class="text-sm text-base-content/70">
                  No active governed conversations or clarification-needed repository work are available yet.
                </p>
              <% else %>
                <ol id="dashboard-conversation-summary-list" class="space-y-3" phx-update="stream">
                  <li
                    :for={{dom_id, summary} <- @streams.conversation_summaries}
                    id={dom_id}
                    class="rounded border border-base-300/70 bg-base-200/20 p-3 space-y-2"
                  >
                    <div class="flex flex-wrap items-start justify-between gap-3">
                      <div class="space-y-1">
                        <p
                          id={"dashboard-conversation-summary-repo-#{run_summary_dom_token(summary.id)}"}
                          class="text-sm font-medium"
                        >
                          {summary.repo_label}
                        </p>
                        <p
                          id={"dashboard-conversation-summary-detail-#{run_summary_dom_token(summary.id)}"}
                          class="text-xs text-base-content/80"
                        >
                          {summary.detail}
                        </p>
                      </div>
                      <div class="flex flex-wrap items-center gap-2">
                        <.conversation_role_badge
                          id={"dashboard-conversation-summary-role-#{run_summary_dom_token(summary.id)}"}
                          scope={summary.role_scope}
                          attachment_mode={summary.role_attachment_mode}
                          work_item_id={summary.role_work_item_id}
                        />
                        <.conversation_status_badge
                          :if={summary.latest_status}
                          id={"dashboard-conversation-summary-status-#{run_summary_dom_token(summary.id)}"}
                          status={summary.latest_status}
                        />
                        <span
                          :if={summary.clarification_count > 0}
                          id={"dashboard-conversation-summary-clarification-#{run_summary_dom_token(summary.id)}"}
                          class="badge badge-warning badge-outline badge-sm font-medium"
                        >
                          {conversation_clarification_badge(summary.clarification_count)}
                        </span>
                      </div>
                    </div>

                    <p
                      id={"dashboard-conversation-summary-counts-#{run_summary_dom_token(summary.id)}"}
                      class="text-xs text-base-content/70"
                    >
                      Active governed conversations: {summary.active_count} | Clarification needed: {summary.clarification_count}
                    </p>

                    <p
                      :if={summary.latest_work_item_summary}
                      id={"dashboard-conversation-summary-work-item-#{run_summary_dom_token(summary.id)}"}
                      class="text-xs text-base-content/70"
                    >
                      Latest governed work: {summary.latest_work_item_summary}
                    </p>

                    <p
                      :if={summary.latest_activity_at}
                      id={"dashboard-conversation-summary-activity-#{run_summary_dom_token(summary.id)}"}
                      class="text-xs text-base-content/70"
                    >
                      Latest activity: {summary_refreshed_label(summary.latest_activity_at)}
                    </p>

                    <.link
                      :if={summary.route && summary.action_label}
                      id={"dashboard-conversation-summary-link-#{run_summary_dom_token(summary.id)}"}
                      class="link link-primary text-sm"
                      navigate={summary.route}
                    >
                      {summary.action_label}
                    </.link>
                  </li>
                </ol>
              <% end %>
            </section>

            <section
              :if={@selected_dashboard_section == :memory}
              id="dashboard-memory-summaries"
              class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Repository memory</h2>
                  <p id="dashboard-memory-summary-note" class="text-sm text-base-content/80">
                    Memory summaries stay bounded and route back to canonical managed-repository surfaces for deeper review.
                  </p>
                </div>
                <p id="dashboard-memory-summary-last-refreshed" class="text-xs text-base-content/70">
                  Last refreshed: {summary_refreshed_label(@memory_summary_last_refreshed_at)}
                </p>
              </div>

              <.operator_state_notice
                :if={@memory_summary_warning}
                id="dashboard-memory-summary-warning"
                title="Repository memory summaries may be stale"
                state={@memory_summary_warning}
                compact={true}
              />

              <%= if @memory_summary_count == 0 do %>
                <p id="dashboard-memory-summary-empty" class="text-sm text-base-content/70">
                  No bounded repository memory summaries are available yet.
                </p>
              <% else %>
                <ol id="dashboard-memory-summary-list" class="space-y-3" phx-update="stream">
                  <li
                    :for={{dom_id, summary} <- @streams.memory_summaries}
                    id={dom_id}
                    class="rounded border border-base-300/70 bg-base-200/20 p-3 space-y-2"
                  >
                    <div class="flex flex-wrap items-start justify-between gap-3">
                      <div class="space-y-1">
                        <p
                          id={"dashboard-memory-summary-repo-#{run_summary_dom_token(summary.id)}"}
                          class="text-sm font-medium"
                        >
                          {summary.repo_label}
                        </p>
                        <p
                          id={"dashboard-memory-summary-detail-#{run_summary_dom_token(summary.id)}"}
                          class="text-xs text-base-content/80"
                        >
                          {summary.detail}
                        </p>
                      </div>
                      <span
                        id={"dashboard-memory-summary-state-#{run_summary_dom_token(summary.id)}"}
                        class={memory_summary_badge_class(summary.state)}
                      >
                        {summary.label}
                      </span>
                    </div>

                    <p
                      id={"dashboard-memory-summary-counts-#{run_summary_dom_token(summary.id)}"}
                      class="text-xs text-base-content/70"
                    >
                      Durable memory: {summary.memory_count} | Workflow provenance: {summary.provenance_count}
                    </p>

                    <p
                      :if={summary.latest_revision}
                      id={"dashboard-memory-summary-revision-#{run_summary_dom_token(summary.id)}"}
                      class="text-xs text-base-content/70"
                    >
                      Latest revision: {summary.latest_revision}
                    </p>

                    <p
                      :if={summary.remediation}
                      id={"dashboard-memory-summary-remediation-#{run_summary_dom_token(summary.id)}"}
                      class="text-xs text-base-content/70"
                    >
                      {summary.remediation}
                    </p>

                    <div class="flex flex-wrap items-center gap-3">
                      <span
                        :if={summary.action_needed?}
                        id={"dashboard-memory-summary-action-needed-#{run_summary_dom_token(summary.id)}"}
                        class="badge badge-warning badge-outline"
                      >
                        action needed
                      </span>

                      <.link
                        :if={summary.route && summary.action_label}
                        id={"dashboard-memory-summary-link-#{run_summary_dom_token(summary.id)}"}
                        class="link link-primary text-sm"
                        navigate={summary.route}
                      >
                        {summary.action_label}
                      </.link>
                    </div>
                  </li>
                </ol>
              <% end %>
            </section>

            <section
              :if={@selected_dashboard_section == :runtime}
              id="dashboard-runtime-evidence"
              class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Runtime posture</h2>
                  <p id="dashboard-runtime-evidence-summary" class="text-sm text-base-content/80">
                    {runtime_evidence_summary(@runtime_evidence_summary)}
                  </p>
                  <p id="dashboard-runtime-evidence-note" class="text-xs text-base-content/70">
                    Product records remain the source of truth; runtime posture only contributes bounded readiness and degraded-path evidence.
                  </p>
                </div>
                <p id="dashboard-runtime-evidence-last-refreshed" class="text-xs text-base-content/70">
                  Last refreshed: {summary_refreshed_label(@runtime_evidence_last_refreshed_at)}
                </p>
              </div>

              <.operator_state_notice
                :if={@runtime_evidence_warning}
                id="dashboard-runtime-evidence-warning"
                title="Runtime posture may be stale"
                state={@runtime_evidence_warning}
                compact={true}
              />

              <.vue_surface
                id="dashboard-runtime-posture-widget"
                component="DashboardRuntimePostureWidget"
                socket={@socket}
                props={
                  %{
                    counts: runtime_evidence_widget_counts(@runtime_evidence_summary),
                    runtimeEvidenceSummaries: @runtime_evidence_widget_rows
                  }
                }
              />

              <details
                id="dashboard-runtime-evidence-fallback"
                class="rounded-lg border border-base-300/70 bg-base-200/20"
              >
                <summary class="cursor-pointer px-4 py-3 text-sm font-medium">
                  LiveView posture details
                </summary>

                <div class="space-y-4 border-t border-base-300/70 p-4">
                  <div
                    :if={@runtime_evidence_summary}
                    id="dashboard-runtime-evidence-counts"
                    class="grid gap-3 md:grid-cols-3"
                  >
                    <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
                      <p class="text-xs uppercase text-base-content/60">Blocked repos</p>
                      <p id="dashboard-runtime-evidence-count-blocked" class="mt-1 text-2xl font-semibold">
                        {Map.get(@runtime_evidence_summary, :blocked_count, 0)}
                      </p>
                    </div>
                    <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
                      <p class="text-xs uppercase text-base-content/60">Review-required repos</p>
                      <p id="dashboard-runtime-evidence-count-degraded" class="mt-1 text-2xl font-semibold">
                        {Map.get(@runtime_evidence_summary, :degraded_count, 0)}
                      </p>
                    </div>
                    <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
                      <p class="text-xs uppercase text-base-content/60">Stable repos</p>
                      <p id="dashboard-runtime-evidence-count-available" class="mt-1 text-2xl font-semibold">
                        {Map.get(@runtime_evidence_summary, :available_count, 0)}
                      </p>
                    </div>
                  </div>

                  <%= if @runtime_evidence_count == 0 do %>
                    <p id="dashboard-runtime-evidence-empty" class="text-sm text-base-content/70">
                      No runtime-service posture has been materialized yet.
                    </p>
                  <% else %>
                    <ol id="dashboard-runtime-evidence-list" class="space-y-2">
                      <li
                        :for={{dom_id, runtime_summary} <- @streams.runtime_evidence_summaries}
                        id={dom_id}
                        class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
                      >
                        <div class="flex flex-wrap items-center gap-2">
                          <p class="text-sm font-medium">{runtime_summary.repo_label}</p>
                          <span class={runtime_evidence_badge_class(runtime_summary.status)}>
                            {runtime_evidence_status_label(runtime_summary.status)}
                          </span>
                          <span
                            :if={runtime_summary.review_required}
                            class="badge badge-warning badge-outline"
                          >
                            review required
                          </span>
                        </div>
                        <p
                          id={"dashboard-runtime-evidence-item-summary-#{run_summary_dom_token(runtime_summary.id)}"}
                          class="text-xs text-base-content/80"
                        >
                          {runtime_summary.summary}
                        </p>
                        <p
                          id={"dashboard-runtime-evidence-item-details-#{run_summary_dom_token(runtime_summary.id)}"}
                          class="text-xs text-base-content/70"
                        >
                          {runtime_evidence_details(runtime_summary)}
                        </p>
                      </li>
                    </ol>
                  <% end %>
                </div>
              </details>
            </section>

            <section
              :if={!Enum.empty?(@onboarding_next_actions) and @selected_dashboard_section == :next_steps}
              id="dashboard-onboarding-next-actions"
              class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3"
            >
              <div class="space-y-1">
                <h2 class="text-lg font-semibold">Suggested next actions</h2>
                <p id="dashboard-next-steps-note" class="text-sm text-base-content/75">
                  These follow-up actions remain bounded onboarding completion cues, not a permanent dashboard concern when no setup follow-up exists.
                </p>
              </div>
              <ul class="mt-2 space-y-1 text-sm text-base-content/80">
                <li
                  :for={{next_action, index} <- Enum.with_index(@onboarding_next_actions, 1)}
                  id={"dashboard-next-action-#{index}"}
                >
                  {next_action}
                </li>
              </ul>
            </section>
            <:footer_actions>
              <.link
                :if={@selected_dashboard_section == :overview}
                id="dashboard-overview-open-workbench"
                navigate={dashboard_workbench_path(assigns)}
                class="btn btn-sm btn-outline"
              >
                Open dense Workbench mode
              </.link>

              <button
                :if={@selected_dashboard_section == :overview}
                id="dashboard-overview-refresh"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="refresh_dashboard_overview"
              >
                Refresh overview signals
              </button>

              <button
                :if={@selected_dashboard_section == :runs}
                id="dashboard-run-summary-refresh"
                type="button"
                class="btn btn-sm btn-warning"
                phx-click="refresh_run_summaries"
              >
                Refresh run summaries
              </button>

              <button
                :if={@selected_dashboard_section == :conversations}
                id="dashboard-conversation-summary-refresh"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="refresh_conversation_summaries"
              >
                Refresh conversation supervision
              </button>

              <button
                :if={@selected_dashboard_section == :memory}
                id="dashboard-memory-summary-refresh"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="refresh_memory_summaries"
              >
                Refresh memory summaries
              </button>

              <button
                :if={@selected_dashboard_section == :runtime}
                id="dashboard-runtime-evidence-refresh"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="refresh_runtime_evidence"
              >
                Refresh runtime posture
              </button>
            </:footer_actions>
          </.subject_pane>
        </.subject_tree_shell>
      </div>
    </Layouts.app>
    """
  end

  defp load_run_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case RunSummaryFeed.load() do
      {:ok, run_summaries, warning} ->
        socket
        |> assign(:run_summary_count, length(run_summaries))
        |> assign(:run_summary_rows, run_summaries)
        |> assign(:run_summary_widget_rows, Enum.map(run_summaries, &dashboard_run_summary_widget/1))
        |> assign(:run_summary_warning, warning)
        |> assign(:run_summary_last_refreshed_at, now)
        |> stream(:run_summaries, run_summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:run_summary_count, 0)
        |> assign(:run_summary_rows, [])
        |> assign(:run_summary_widget_rows, [])
        |> assign(:run_summary_warning, warning)
        |> assign(:run_summary_last_refreshed_at, now)
        |> stream(:run_summaries, [], reset: true)
    end
  end

  defp load_conversation_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case DashboardConversationFeed.load() do
      {:ok, summaries, warning} ->
        socket
        |> assign(:conversation_summary_count, length(summaries))
        |> assign(:conversation_summary_rows, summaries)
        |> assign(:conversation_summary_warning, warning)
        |> assign(:conversation_summary_last_refreshed_at, now)
        |> stream(:conversation_summaries, summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:conversation_summary_count, 0)
        |> assign(:conversation_summary_rows, [])
        |> assign(:conversation_summary_warning, warning)
        |> assign(:conversation_summary_last_refreshed_at, now)
        |> stream(:conversation_summaries, [], reset: true)
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

  defp dashboard_sections(onboarding_next_actions) when is_list(onboarding_next_actions) do
    if Enum.empty?(onboarding_next_actions) do
      @dashboard_sections
    else
      @dashboard_sections ++ [:next_steps]
    end
  end

  defp dashboard_subject_sections(onboarding_next_actions) when is_list(onboarding_next_actions) do
    %{
      work:
        if(Enum.empty?(onboarding_next_actions),
          do: [:overview, :runs, :conversations],
          else: [:overview, :runs, :conversations, :next_steps]
        ),
      knowledge: [:memory],
      runtime: [:runtime]
    }
  end

  defp dashboard_section_nav_items(assigns) do
    assigns.onboarding_next_actions
    |> dashboard_subject_sections()
    |> Map.fetch!(assigns.selected_dashboard_subject)
    |> Enum.map(fn section ->
      OperatorShell.child_subject(%{
        id: section,
        label: dashboard_section_label(section),
        summary: dashboard_section_summary(section, assigns),
        badge: dashboard_section_badge(section, assigns),
        pane_id: "dashboard-pane-#{section}",
        selected?: assigns.selected_dashboard_section == section,
        patch:
          dashboard_selection_path(
            assigns.onboarding_next_actions,
            assigns.selected_dashboard_subject,
            section
          )
      })
      |> Map.put(:section, section)
    end)
  end

  defp dashboard_breadcrumbs(assigns) do
    [
      OperatorShell.breadcrumb(%{
        id: "dashboard-breadcrumb-dashboard",
        label: "Dashboard",
        patch: dashboard_selection_path(assigns.onboarding_next_actions, :work, :overview)
      }),
      OperatorShell.breadcrumb(%{
        id: "dashboard-breadcrumb-subject",
        label: dashboard_subject_label(assigns.selected_dashboard_subject),
        patch:
          dashboard_subject_path(
            assigns.onboarding_next_actions,
            assigns.selected_dashboard_subject
          )
      }),
      OperatorShell.breadcrumb(%{
        id: "dashboard-breadcrumb-current",
        label: dashboard_section_label(assigns.selected_dashboard_section),
        current?: true
      })
    ]
  end

  defp dashboard_parent_subjects(assigns) do
    assigns.onboarding_next_actions
    |> dashboard_subject_sections()
    |> then(fn subject_sections ->
      Enum.map(@dashboard_subject_order, fn subject ->
        OperatorShell.parent_subject(%{
          id: subject,
          label: dashboard_subject_label(subject),
          description: dashboard_subject_description(subject),
          selected?: assigns.selected_dashboard_subject == subject,
          patch: dashboard_subject_path(assigns.onboarding_next_actions, subject)
        })
      end)
      |> Enum.filter(fn subject -> Map.has_key?(subject_sections, subject.id) end)
    end)
  end

  defp dashboard_selected_pane(assigns) do
    section = assigns.selected_dashboard_section

    OperatorShell.pane(%{
      id: "dashboard-pane-#{section}",
      title: dashboard_pane_title(section),
      summary: dashboard_pane_summary(section)
    })
  end

  defp dashboard_child_nav_label(:work), do: "Dashboard work subjects"
  defp dashboard_child_nav_label(:knowledge), do: "Dashboard knowledge subjects"
  defp dashboard_child_nav_label(:runtime), do: "Dashboard runtime subjects"

  defp dashboard_child_nav_heading(:work), do: "Work"
  defp dashboard_child_nav_heading(:knowledge), do: "Knowledge"
  defp dashboard_child_nav_heading(:runtime), do: "Runtime"

  defp dashboard_child_nav_summary(:work) do
    "Primary managed-repository inventory, governed runs, governed conversations, and ready follow-up stay grouped here without leaving the authenticated landing route."
  end

  defp dashboard_child_nav_summary(:knowledge) do
    "Bounded memory attention stays here and routes back to canonical managed-repository detail when a deeper review is needed."
  end

  defp dashboard_child_nav_summary(:runtime) do
    "Delivery readiness and degraded-path runtime posture stay grouped here as bounded product signals."
  end

  defp dashboard_subject_path(onboarding_next_actions, subject) do
    dashboard_selection_path(
      onboarding_next_actions,
      subject,
      default_dashboard_section_for_subject(subject, onboarding_next_actions)
    )
  end

  defp dashboard_selection_path(onboarding_next_actions, subject, section) do
    params =
      [subject: Atom.to_string(subject), section: Atom.to_string(section)]
      |> maybe_put_query_param(:onboarding, onboarding_next_actions_query_param(onboarding_next_actions))

    ~p"/dashboard?#{params}"
  end

  defp onboarding_next_actions_query_param(onboarding_next_actions) do
    if Enum.empty?(onboarding_next_actions), do: nil, else: "completed"
  end

  defp normalize_dashboard_selection(params, onboarding_next_actions) do
    subject_sections = dashboard_subject_sections(onboarding_next_actions)
    available_sections = dashboard_sections(onboarding_next_actions)

    case normalize_dashboard_section(Map.get(params, "section"), available_sections) do
      section when is_atom(section) ->
        {dashboard_subject_for_section(section, onboarding_next_actions), section}

      nil ->
        subject =
          params
          |> Map.get("subject")
          |> parse_dashboard_subject(subject_sections)

        {subject, default_dashboard_section_for_subject(subject, onboarding_next_actions)}
    end
  end

  defp parse_dashboard_subject(subject_param, subject_sections) when is_map(subject_sections) do
    available_subjects = Map.keys(subject_sections)

    case normalize_optional_string(subject_param) do
      nil ->
        :work

      normalized ->
        normalized
        |> String.trim()
        |> String.downcase()
        |> String.replace("-", "_")
        |> case do
          "work" -> :work
          "knowledge" -> :knowledge
          "runtime" -> :runtime
          _other -> :work
        end
        |> then(fn subject -> if subject in available_subjects, do: subject, else: :work end)
    end
  end

  defp normalize_dashboard_section(section_param, available_sections) do
    parse_dashboard_section(section_param, available_sections) || :overview
  end

  defp parse_dashboard_section(section_param, available_sections) do
    section_param
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized ->
        normalized
        |> String.trim()
        |> String.downcase()
        |> String.replace("-", "_")
        |> case do
          "next_steps" -> :next_steps
          "overview" -> :overview
          "runs" -> :runs
          "conversations" -> :conversations
          "memory" -> :memory
          "runtime" -> :runtime
          _other -> nil
        end
    end
    |> then(fn section ->
      if section in available_sections, do: section, else: nil
    end)
  end

  defp default_dashboard_section_for_subject(subject, onboarding_next_actions) do
    onboarding_next_actions
    |> dashboard_subject_sections()
    |> Map.fetch!(subject)
    |> List.first()
  end

  defp dashboard_subject_for_section(section, onboarding_next_actions) do
    onboarding_next_actions
    |> dashboard_subject_sections()
    |> Enum.find_value(:work, fn {subject, sections} ->
      if section in sections, do: subject, else: nil
    end)
  end

  defp dashboard_subject_label(:work), do: "Work"
  defp dashboard_subject_label(:knowledge), do: "Knowledge"
  defp dashboard_subject_label(:runtime), do: "Runtime"

  defp dashboard_subject_description(:work) do
    "Managed-repository inventory, governed activity, and ready follow-up stay grouped here."
  end

  defp dashboard_subject_description(:knowledge) do
    "Bounded memory attention and repo knowledge signals stay grouped here."
  end

  defp dashboard_subject_description(:runtime) do
    "Delivery readiness and degraded-path runtime posture stay grouped here."
  end

  defp dashboard_section_label(:overview), do: "Overview"
  defp dashboard_section_label(:runs), do: "Runs"
  defp dashboard_section_label(:conversations), do: "Conversations"
  defp dashboard_section_label(:memory), do: "Memory"
  defp dashboard_section_label(:runtime), do: "Posture"
  defp dashboard_section_label(:next_steps), do: "Follow-up"

  defp dashboard_pane_title(:overview), do: "Managed repo inventory"
  defp dashboard_pane_title(:runs), do: "Recent governed runs"
  defp dashboard_pane_title(:conversations), do: "Conversation supervision"
  defp dashboard_pane_title(:memory), do: "Repository memory"
  defp dashboard_pane_title(:runtime), do: "Runtime posture"
  defp dashboard_pane_title(:next_steps), do: "Suggested next actions"

  defp dashboard_pane_summary(:overview),
    do: "Dashboard Work owns the primary managed-repository inventory here while Workbench remains the denser specialist mode."

  defp dashboard_pane_summary(:runs),
    do: "Review bounded governed-run status here without leaving the authenticated landing route."

  defp dashboard_pane_summary(:conversations),
    do: "Active governed conversations stay bounded here and route back to canonical repository detail."

  defp dashboard_pane_summary(:memory),
    do: "Memory summaries remain bounded and action-oriented here rather than becoming parallel product truth."

  defp dashboard_pane_summary(:runtime),
    do: "Runtime rollout and recovery posture stay product-shaped here instead of exposing runtime internals."

  defp dashboard_pane_summary(:next_steps),
    do: "Post-onboarding follow-up remains bounded here instead of replacing the durable landing route."

  defp dashboard_section_summary(:overview, assigns) do
    if assigns.repository_monitoring_count == 0 do
      "No managed-repository inventory is visible yet."
    else
      "#{assigns.repository_monitoring_count} managed repositories ready for inventory and triage review."
    end
  end

  defp dashboard_section_summary(:runs, assigns) do
    if assigns.run_summary_count == 0 do
      "No recent governed runs are visible yet."
    else
      "#{assigns.run_summary_count} recent governed run #{pluralize(assigns.run_summary_count, "summary", "summaries")}."
    end
  end

  defp dashboard_section_summary(:conversations, assigns) do
    clarification_count = conversation_clarification_total(assigns.conversation_summary_rows)

    cond do
      assigns.conversation_summary_count == 0 ->
        "No active governed conversation supervision is visible yet."

      clarification_count > 0 ->
        "#{assigns.conversation_summary_count} repo #{pluralize(assigns.conversation_summary_count, "summary", "summaries")} with #{clarification_count} clarification #{pluralize(clarification_count, "turn", "turns")} pending."

      true ->
        "#{assigns.conversation_summary_count} repo #{pluralize(assigns.conversation_summary_count, "summary", "summaries")} with active governed work."
    end
  end

  defp dashboard_section_summary(:memory, assigns) do
    action_needed_count = memory_action_needed_count(assigns.memory_summary_rows)

    cond do
      assigns.memory_summary_count == 0 ->
        "No bounded memory summaries are visible yet."

      action_needed_count > 0 ->
        "#{assigns.memory_summary_count} repo #{pluralize(assigns.memory_summary_count, "summary", "summaries")} and #{action_needed_count} requiring operator follow-up."

      true ->
        "#{assigns.memory_summary_count} repository memory #{pluralize(assigns.memory_summary_count, "summary", "summaries")} are available for review."
    end
  end

  defp dashboard_section_summary(:runtime, assigns),
    do: runtime_evidence_summary(assigns.runtime_evidence_summary)

  defp dashboard_section_summary(:next_steps, assigns) do
    count = length(assigns.onboarding_next_actions)
    "#{count} ready-state follow-up #{pluralize(count, "action", "actions")}."
  end

  defp dashboard_section_badge(:overview, assigns) do
    cond do
      assigns.repository_monitoring_warning ->
        %{label: "stale", tone: :warning}

      assigns.repository_monitoring_count > 0 ->
        %{label: Integer.to_string(assigns.repository_monitoring_count), tone: :neutral}

      true ->
        nil
    end
  end

  defp dashboard_section_badge(:runs, assigns) do
    if assigns.run_summary_count > 0 do
      %{label: Integer.to_string(assigns.run_summary_count), tone: :neutral}
    else
      nil
    end
  end

  defp dashboard_section_badge(:conversations, assigns) do
    clarification_count = conversation_clarification_total(assigns.conversation_summary_rows)

    cond do
      clarification_count > 0 ->
        %{label: "#{clarification_count} waiting", tone: :warning}

      assigns.conversation_summary_count > 0 ->
        %{label: Integer.to_string(assigns.conversation_summary_count), tone: :neutral}

      true ->
        nil
    end
  end

  defp dashboard_section_badge(:memory, assigns) do
    action_needed_count = memory_action_needed_count(assigns.memory_summary_rows)

    cond do
      action_needed_count > 0 ->
        %{label: "#{action_needed_count} action", tone: :warning}

      assigns.memory_summary_count > 0 ->
        %{label: Integer.to_string(assigns.memory_summary_count), tone: :neutral}

      true ->
        nil
    end
  end

  defp dashboard_section_badge(:runtime, assigns) do
    case runtime_attention_badge(assigns.runtime_evidence_summary) do
      nil -> nil
      badge -> badge
    end
  end

  defp dashboard_section_badge(:next_steps, assigns) do
    count = length(assigns.onboarding_next_actions)

    if count > 0 do
      %{label: Integer.to_string(count), tone: :warning}
    else
      nil
    end
  end

  defp summary_refreshed_label(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp summary_refreshed_label(_datetime), do: "not yet"

  defp run_summary_dom_id(run_summary) do
    "dashboard-run-summary-#{run_summary_dom_token(run_summary.id)}"
  end

  defp conversation_summary_dom_id(summary) do
    "dashboard-conversation-summary-#{run_summary_dom_token(summary.id)}"
  end

  defp runtime_evidence_dom_id(runtime_summary) do
    "dashboard-runtime-evidence-#{run_summary_dom_token(runtime_summary.id)}"
  end

  defp memory_summary_dom_id(summary) do
    "dashboard-memory-summary-#{run_summary_dom_token(summary.id)}"
  end

  defp repo_monitoring_dom_token(value), do: run_summary_dom_token(value)

  defp run_summary_dom_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      token -> token
    end
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
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

  defp runtime_evidence_status_label(status) do
    case normalize_optional_string(status) do
      "blocked" -> "blocked"
      "degraded" -> "review required"
      "available" -> "stable"
      nil -> "unknown"
      other -> other
    end
  end

  defp run_recency_label(run_summary) do
    case Map.get(run_summary, :started_at) do
      %DateTime{} = started_at ->
        started_iso8601 = DateTime.to_iso8601(DateTime.truncate(started_at, :second))
        "Started #{relative_time_label(started_at)} (#{started_iso8601})"

      _other ->
        "Recency unavailable"
    end
  end

  defp run_governance_summary(run_summary) do
    evidence_count =
      run_summary
      |> Map.get(:evidence_count, 0)
      |> normalize_non_negative_integer()

    current_stage =
      run_summary
      |> Map.get(:current_stage)
      |> normalize_optional_string()

    change_request_status =
      run_summary
      |> Map.get(:change_request_status)
      |> normalize_optional_string()

    latest_decision =
      run_summary
      |> Map.get(:latest_decision)
      |> normalize_optional_string()

    [
      current_stage && "Stage: #{current_stage}",
      evidence_count > 0 && "Evidence: #{evidence_count}",
      change_request_status && "Review: #{change_request_status}",
      latest_decision && "Decision: #{latest_decision}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp runtime_evidence_summary(%{} = summary) do
    "Runtime posture tracks #{Map.get(summary, :total_count, 0)} repo(s): #{Map.get(summary, :blocked_count, 0)} blocked, #{Map.get(summary, :degraded_count, 0)} review-required, #{Map.get(summary, :available_count, 0)} stable."
  end

  defp runtime_evidence_summary(_summary),
    do: "Runtime posture status is unavailable."

  defp runtime_attention_badge(%{} = summary) do
    blocked = Map.get(summary, :blocked_count, 0)
    degraded = Map.get(summary, :degraded_count, 0)

    cond do
      blocked > 0 -> %{label: "#{blocked} blocked", tone: :warning}
      degraded > 0 -> %{label: "#{degraded} review", tone: :warning}
      Map.get(summary, :total_count, 0) > 0 -> %{label: "#{Map.get(summary, :total_count, 0)} repos", tone: :neutral}
      true -> nil
    end
  end

  defp runtime_attention_badge(_summary), do: nil

  defp conversation_clarification_badge(1), do: "1 clarification needed"
  defp conversation_clarification_badge(count), do: "#{count} clarifications needed"

  defp conversation_clarification_total(summaries) when is_list(summaries) do
    Enum.reduce(summaries, 0, fn summary, total ->
      total + normalize_non_negative_integer(Map.get(summary, :clarification_count, 0))
    end)
  end

  defp memory_action_needed_count(summaries) when is_list(summaries) do
    Enum.count(summaries, &Map.get(&1, :action_needed?, false))
  end

  defp runtime_evidence_details(runtime_summary) do
    [
      runtime_summary.delivery_mode && "Delivery: #{humanize_runtime_value(runtime_summary.delivery_mode)}",
      runtime_summary.reason_code && "Reason: #{humanize_runtime_value(runtime_summary.reason_code)}",
      runtime_summary.latest_provider && "Latest provider: #{runtime_summary.latest_provider}",
      runtime_summary.supervision_mode && "Supervision: #{runtime_summary.supervision_mode}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "No additional runtime posture details."
      parts -> Enum.join(parts, " · ")
    end
  end

  defp load_runtime_evidence_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case RuntimeEvidenceFeed.load() do
      {:ok, summaries, warning} ->
        socket
        |> assign(:runtime_evidence_count, length(summaries))
        |> assign(:runtime_evidence_rows, summaries)
        |> assign(:runtime_evidence_widget_rows, Enum.map(summaries, &dashboard_runtime_evidence_widget/1))
        |> assign(:runtime_evidence_warning, warning)
        |> assign(:runtime_evidence_last_refreshed_at, now)
        |> assign(:runtime_evidence_summary, summarize_runtime_evidence(summaries))
        |> stream(:runtime_evidence_summaries, summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:runtime_evidence_count, 0)
        |> assign(:runtime_evidence_rows, [])
        |> assign(:runtime_evidence_widget_rows, [])
        |> assign(:runtime_evidence_warning, warning)
        |> assign(:runtime_evidence_last_refreshed_at, now)
        |> assign(:runtime_evidence_summary, nil)
        |> stream(:runtime_evidence_summaries, [], reset: true)
    end
  end

  defp load_repository_monitoring_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case InventorySurface.load() do
      {:ok, rows, recent_run_outcomes, warning} ->
        socket
        |> assign(:repository_monitoring_count, length(rows))
        |> assign(:repository_monitoring_rows, rows)
        |> assign(:repository_monitoring_warning, warning)
        |> assign(:repository_monitoring_last_refreshed_at, now)
        |> assign(:recent_run_outcomes, recent_run_outcomes)

      {:error, warning} ->
        socket
        |> assign(:repository_monitoring_count, 0)
        |> assign(:repository_monitoring_rows, [])
        |> assign(:repository_monitoring_warning, warning)
        |> assign(:repository_monitoring_last_refreshed_at, now)
        |> assign(:recent_run_outcomes, %{})
    end
  end

  defp load_memory_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case DashboardSummaryFeed.load() do
      {:ok, summaries, warning} ->
        socket
        |> assign(:memory_summary_count, length(summaries))
        |> assign(:memory_summary_rows, summaries)
        |> assign(:memory_summary_warning, warning)
        |> assign(:memory_summary_last_refreshed_at, now)
        |> stream(:memory_summaries, summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:memory_summary_count, 0)
        |> assign(:memory_summary_rows, [])
        |> assign(:memory_summary_warning, warning)
        |> assign(:memory_summary_last_refreshed_at, now)
        |> stream(:memory_summaries, [], reset: true)
    end
  end

  defp dashboard_run_summary_widget(run_summary) do
    status =
      run_summary
      |> Map.get(:status)
      |> normalize_optional_string() || "pending"

    %{
      id:
        run_summary
        |> Map.get(:id)
        |> run_summary_dom_token(),
      runId:
        run_summary
        |> Map.get(:run_id)
        |> normalize_optional_string() || "unknown",
      workflowName:
        run_summary
        |> Map.get(:workflow_name)
        |> normalize_optional_string() || "unknown_workflow",
      status: status,
      statusBadgeClass: run_status_badge_class(status),
      governanceSummary: run_governance_summary(run_summary),
      recencyLabel: run_recency_label(run_summary),
      detailPath: run_detail_path(run_summary),
      requiresAttention: run_requires_attention?(status),
      terminal: run_terminal?(status)
    }
  end

  defp dashboard_runtime_evidence_widget(runtime_summary) do
    status =
      runtime_summary
      |> Map.get(:status)
      |> normalize_optional_string() || "unknown"

    %{
      id:
        runtime_summary
        |> Map.get(:id)
        |> run_summary_dom_token(),
      repoLabel:
        runtime_summary
        |> Map.get(:repo_label)
        |> normalize_optional_string() || "Unknown repo",
      status: status,
      statusLabel: runtime_evidence_status_label(status),
      statusBadgeClass: runtime_evidence_badge_class(status),
      reviewRequired: Map.get(runtime_summary, :review_required, false),
      summary:
        runtime_summary
        |> Map.get(:summary)
        |> normalize_optional_string() || "Runtime posture status is unavailable.",
      details: runtime_evidence_details(runtime_summary)
    }
  end

  defp runtime_evidence_widget_counts(%{} = summary) do
    %{
      blocked: Map.get(summary, :blocked_count, 0),
      degraded: Map.get(summary, :degraded_count, 0),
      available: Map.get(summary, :available_count, 0)
    }
  end

  defp runtime_evidence_widget_counts(_summary), do: %{blocked: 0, degraded: 0, available: 0}

  defp dashboard_workbench_path(_assigns), do: ~p"/workbench"

  defp dashboard_inventory_detail_path(assigns, project) do
    InventorySurface.project_detail_path(
      project,
      dashboard_selection_path(assigns.onboarding_next_actions, :work, :overview)
    )
  end

  defp dashboard_runtime_inventory_badge(runtime_rows, project) when is_list(runtime_rows) do
    managed_repo_id =
      project
      |> Map.get(:managed_repo_id)
      |> normalize_optional_string()

    runtime_rows
    |> Enum.find(fn runtime_summary ->
      runtime_summary
      |> Map.get(:managed_repo_id)
      |> normalize_optional_string() == managed_repo_id
    end)
    |> case do
      %{review_required: true} = runtime_summary ->
        %{
          label: "Runtime: review required",
          class: runtime_evidence_badge_class(Map.get(runtime_summary, :status))
        }

      %{} = runtime_summary ->
        %{
          label: "Runtime: #{runtime_evidence_status_label(Map.get(runtime_summary, :status))}",
          class: runtime_evidence_badge_class(Map.get(runtime_summary, :status))
        }

      _other ->
        nil
    end
  end

  defp dashboard_runtime_inventory_badge(_runtime_rows, _project), do: nil

  defp dashboard_inventory_activity_label(project) do
    case Map.get(project, :recent_activity_at) do
      %DateTime{} = recent_activity_at ->
        "Recent activity #{relative_time_label(recent_activity_at)}"

      _other ->
        "Recent activity timing is unavailable."
    end
  end

  defp find_project_row(rows, project_id), do: InventoryActionState.find_row(rows, project_id)

  defp put_fix_workflow_kickoff_state(socket, project_id, context_item_type, kickoff_result) do
    update(socket, :fix_workflow_kickoff_states, fn states ->
      InventoryActionState.put_fix_feedback(states, project_id, context_item_type, kickoff_result)
    end)
  end

  defp put_issue_triage_workflow_kickoff_state(
         socket,
         project_id,
         context_item_type,
         kickoff_result
       ) do
    update(socket, :issue_triage_workflow_kickoff_states, fn states ->
      InventoryActionState.put_issue_triage_feedback(
        states,
        project_id,
        context_item_type,
        kickoff_result
      )
    end)
  end

  defp put_recent_run_outcome_from_kickoff(socket, project_id, kickoff_result) do
    update(socket, :recent_run_outcomes, fn outcomes ->
      InventoryActionState.put_recent_run_outcome(outcomes, project_id, kickoff_result)
    end)
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

  defp summarize_runtime_evidence(summaries) when is_list(summaries) do
    %{
      total_count: length(summaries),
      blocked_count: Enum.count(summaries, &(&1.status == "blocked")),
      degraded_count: Enum.count(summaries, &(&1.status == "degraded")),
      available_count: Enum.count(summaries, &(&1.status == "available"))
    }
  end

  defp humanize_runtime_value(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized -> normalized |> String.replace("_", " ")
    end
  end

  defp relative_time_label(%DateTime{} = datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 0 ->
        "in the future"

      seconds < 60 ->
        "just now"

      seconds < 3_600 ->
        "#{div(seconds, 60)}m ago"

      seconds < 86_400 ->
        "#{div(seconds, 3_600)}h ago"

      true ->
        "#{div(seconds, 86_400)}d ago"
    end
  end

  defp run_detail_path(run_summary) do
    project_id =
      run_summary
      |> Map.get(:project_id)
      |> normalize_optional_string()

    run_id =
      run_summary
      |> Map.get(:run_id)
      |> normalize_optional_string()

    if project_id && run_id do
      ~p"/repos/#{project_id}/runs/#{run_id}"
    else
      ~p"/dashboard"
    end
  end

  defp run_requires_attention?(status), do: status in ["awaiting_approval", "cancelled", "failed"]

  defp run_terminal?(status), do: status in ["cancelled", "completed", "failed"]

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp normalize_non_negative_integer(_value), do: 0

  defp maybe_put_query_param(params, _key, nil), do: params
  defp maybe_put_query_param(params, key, value), do: Keyword.put(params, key, value)

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

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
