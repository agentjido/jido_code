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

  alias JidoCode.MemoryGraph.DashboardSummaryFeed
  alias JidoCode.Governance.RuntimeEvidenceFeed
  alias JidoCode.Orchestration.{RunPubSub, RunSummaryFeed}
  alias JidoCode.Workbench.{DashboardConversationFeed, DashboardRepositoryMonitoringFeed}

  @dashboard_sections [:overview, :runs, :conversations, :memory, :runtime]
  @onboarding_next_actions [
    "Run your first workflow",
    "Review the security playbook",
    "Test the RPC client"
  ]

  @run_events_for_refresh MapSet.new(["run_started", "run_completed", "run_failed"])

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
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
      |> assign(:expanded_repository_monitoring_ids, MapSet.new())
      |> assign(:memory_summary_count, 0)
      |> assign(:memory_summary_rows, [])
      |> assign(:memory_summary_warning, nil)
      |> assign(:memory_summary_last_refreshed_at, nil)
      |> assign(:repository_monitoring_count, 0)
      |> assign(:repository_monitoring_rows, [])
      |> assign(:repository_monitoring_warning, nil)
      |> assign(:repository_monitoring_last_refreshed_at, nil)
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

    {:noreply,
     socket
     |> assign(:onboarding_next_actions, onboarding_next_actions)
     |> assign(:dashboard_sections, dashboard_sections)
     |> assign(
       :selected_dashboard_section,
       normalize_dashboard_section(Map.get(params, "section"), dashboard_sections)
     )}
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
  def handle_event("toggle_repository_monitoring_detail", %{"id" => id}, socket) do
    expanded_ids =
      socket.assigns.expanded_repository_monitoring_ids
      |> toggle_repository_monitoring_detail(id)

    {:noreply, assign(socket, :expanded_repository_monitoring_ids, expanded_ids)}
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
        data-dashboard-section={Atom.to_string(@selected_dashboard_section)}
        class="max-w-7xl mx-auto py-8"
      >
        <h1 class="text-2xl font-bold mb-4">Dashboard</h1>
        <p class="text-base-content/70">Welcome, {@current_user.email}</p>
        <p id="dashboard-entry-summary" class="mt-1 text-sm text-base-content/75">
          Dashboard is the authenticated product overview for governed runs, conversations, memory, and runtime posture.
        </p>
        <p id="dashboard-settings-handoff" class="mt-2 text-sm text-base-content/70">
          Provider login and Git automation configuration live in <.link
            navigate={~p"/settings/auth"}
            class="link link-primary"
          >Settings</.link>.
        </p>

        <div id="dashboard-shell" class="mt-6 flex flex-col gap-6 lg:flex-row lg:items-start">
          <section
            id="dashboard-sidebar-shell"
            class="rounded-lg border border-base-300/70 bg-base-200/20 p-3 lg:sticky lg:top-24 lg:w-80 lg:flex-none"
          >
            <div class="space-y-1 px-1">
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/55">
                Dashboard concerns
              </p>
              <p id="dashboard-section-nav-note" class="text-sm text-base-content/70">
                Move between overview, governed runs, conversations, memory, runtime posture, and follow-up work without leaving the authenticated landing route.
              </p>
            </div>

            <nav
              id="dashboard-section-nav"
              class="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-1"
              aria-label="Dashboard concerns"
            >
              <.link
                :for={section <- dashboard_section_nav_items(assigns)}
                id={"dashboard-section-nav-#{section.section}"}
                patch={dashboard_section_path(@onboarding_next_actions, section.section)}
                aria-current={if(section.selected?, do: "page", else: nil)}
                class={[
                  "rounded-lg border px-3 py-3 text-left transition",
                  if(section.selected?,
                    do: "border-primary/60 bg-primary/8 text-base-content shadow-sm",
                    else: "border-base-300/70 bg-base-100/85 text-base-content/80 hover:border-base-300 hover:bg-base-100"
                  )
                ]}
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0 space-y-1">
                    <p class="font-semibold">{section.label}</p>
                    <p class="text-xs leading-5 text-base-content/65">{section.summary}</p>
                  </div>
                  <span
                    :if={section.badge}
                    id={"dashboard-section-nav-#{section.section}-badge"}
                    class={dashboard_section_badge_class(section.badge.tone)}
                  >
                    {section.badge.label}
                  </span>
                </div>
              </.link>
            </nav>
          </section>

          <div id="dashboard-content-shell" class="min-w-0 flex-1">
            <section
              :if={@selected_dashboard_section == :overview}
              id="dashboard-overview-panel"
              class="space-y-4"
            >
              <section class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3">
                <div class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/55">
                    Overview
                  </p>
                  <h2 class="text-xl font-semibold">Repository monitoring working set</h2>
                  <p id="dashboard-overview-note" class="text-sm text-base-content/75">
                    Repositories are ordered by the most recent governed or operator-facing work signal so you can scan the active working set, expand bounded detail in place, and only then jump into a deeper route when needed.
                  </p>
                </div>

                <.operator_state_notice
                  :if={@repository_monitoring_warning}
                  id="dashboard-overview-warning"
                  title="Repository monitoring feed may be stale"
                  state={@repository_monitoring_warning}
                  compact={true}
                />

                <%= if @repository_monitoring_count == 0 do %>
                  <p id="dashboard-overview-empty-state" class="text-sm text-base-content/70">
                    No managed repositories are available for dashboard monitoring yet.
                  </p>
                <% else %>
                  <ol id="dashboard-overview-repository-list" class="space-y-6">
                    <li
                      :for={entry <- @repository_monitoring_rows}
                      id={"dashboard-overview-repository-#{run_summary_dom_token(entry.id)}"}
                      class="space-y-3"
                    >
                      <article
                        id={"dashboard-overview-repository-card-#{run_summary_dom_token(entry.id)}"}
                        class="rounded-3xl border border-base-300/70 bg-base-100 px-5 py-5 shadow-sm shadow-base-300/20"
                      >
                        <div class="flex flex-col gap-5 xl:flex-row xl:items-start xl:justify-between">
                          <div class="min-w-0 flex-1 space-y-4">
                            <div class="flex flex-wrap items-start justify-between gap-3">
                              <div class="min-w-0 space-y-2">
                                <div class="flex flex-wrap items-center gap-2">
                                  <p
                                    id={"dashboard-overview-repository-name-#{run_summary_dom_token(entry.id)}"}
                                    class="text-lg font-semibold tracking-tight"
                                  >
                                    {entry.repo_name}
                                  </p>
                                  <span class="badge badge-outline badge-sm">
                                    {entry.top_card.branch_label}
                                  </span>
                                </div>

                                <p
                                  id={"dashboard-overview-repository-label-#{run_summary_dom_token(entry.id)}"}
                                  class="text-sm text-base-content/75"
                                >
                                  {entry.repo_label}
                                </p>
                              </div>

                              <div class="rounded-2xl bg-base-200/65 px-4 py-3 text-sm text-base-content/75 xl:max-w-xs xl:text-right">
                                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
                                  Most recent signal
                                </p>
                                <p
                                  id={"dashboard-overview-repository-order-label-#{run_summary_dom_token(entry.id)}"}
                                  class="mt-2 font-medium text-base-content/90"
                                >
                                  {entry.top_card.signal_label}
                                </p>
                                <p
                                  id={"dashboard-overview-repository-order-detail-#{run_summary_dom_token(entry.id)}"}
                                  class="mt-1 leading-6"
                                >
                                  {entry.top_card.signal_detail}
                                </p>
                                <p
                                  :if={entry.top_card.last_worked_on_label}
                                  id={"dashboard-overview-repository-last-worked-on-#{run_summary_dom_token(entry.id)}"}
                                  class="mt-2 text-xs text-base-content/65"
                                >
                                  {entry.top_card.last_worked_on_label}
                                </p>
                              </div>
                            </div>

                            <div
                              id={"dashboard-overview-repository-primary-cue-#{run_summary_dom_token(entry.id)}"}
                              class="rounded-2xl bg-base-200/45 px-4 py-4"
                            >
                              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
                                Why it matters now
                              </p>
                              <p
                                id={"dashboard-overview-repository-summary-#{run_summary_dom_token(entry.id)}"}
                                class="mt-2 text-sm leading-6 text-base-content/85"
                              >
                                {entry.top_card.primary_cue}
                              </p>
                            </div>

                            <div class="flex flex-wrap items-center gap-2 text-xs text-base-content/80">
                              <span
                                :for={badge <- entry.top_card.badges}
                                id={"dashboard-overview-repository-#{badge.id}-#{run_summary_dom_token(entry.id)}"}
                                class={badge.class}
                              >
                                {badge.label}
                              </span>
                            </div>

                            <div class="flex flex-wrap items-center gap-4 text-sm">
                              <.link
                                :for={link <- entry.top_card.links}
                                id={"dashboard-overview-repository-#{link.id}-link-#{run_summary_dom_token(entry.id)}"}
                                navigate={link.route}
                                class={link.class}
                              >
                                {link.label}
                              </.link>
                            </div>
                          </div>
                        </div>
                      </article>

                      <section
                        id={"dashboard-overview-repository-accordion-shell-#{run_summary_dom_token(entry.id)}"}
                        class="rounded-3xl bg-base-200/30 px-5 py-4"
                      >
                        <button
                          id={"dashboard-overview-repository-accordion-toggle-#{run_summary_dom_token(entry.id)}"}
                          type="button"
                          class="flex w-full flex-col gap-3 text-left md:flex-row md:items-center md:justify-between"
                          phx-click="toggle_repository_monitoring_detail"
                          phx-value-id={entry.id}
                          aria-expanded={
                            to_string(
                              repository_monitoring_detail_expanded?(
                                @expanded_repository_monitoring_ids,
                                entry.id
                              )
                            )
                          }
                          aria-controls={"dashboard-overview-repository-accordion-panel-#{run_summary_dom_token(entry.id)}"}
                        >
                          <div class="space-y-1">
                            <p class="text-sm font-semibold text-base-content/85">
                              Repository monitoring detail
                            </p>
                            <p class="text-sm text-base-content/70">
                              Expand this repository in place to inspect bounded governed-run, conversation, memory, and runtime signals without leaving dashboard.
                            </p>
                          </div>

                          <span
                            id={"dashboard-overview-repository-accordion-state-#{run_summary_dom_token(entry.id)}"}
                            class="badge badge-outline badge-sm"
                          >
                            {repository_monitoring_detail_state_label(
                              @expanded_repository_monitoring_ids,
                              entry.id
                            )}
                          </span>
                        </button>

                        <div
                          :if={
                            repository_monitoring_detail_expanded?(
                              @expanded_repository_monitoring_ids,
                              entry.id
                            )
                          }
                          id={"dashboard-overview-repository-accordion-panel-#{run_summary_dom_token(entry.id)}"}
                          class="mt-4 space-y-4"
                        >
                          <p
                            :if={entry.detail_empty?}
                            id={"dashboard-overview-repository-accordion-empty-#{run_summary_dom_token(entry.id)}"}
                            class="rounded-2xl border border-dashed border-base-300/70 bg-base-100/80 px-4 py-4 text-sm text-base-content/70"
                          >
                            No governed run, conversation, memory, or runtime detail has materialized for this repository yet. Open the repository route to continue setup or start the first governed action.
                          </p>

                          <div
                            :if={not entry.detail_empty?}
                            class="grid gap-3 xl:grid-cols-2"
                          >
                            <section
                              :for={section <- entry.accordion_sections}
                              id={"dashboard-overview-repository-detail-#{section.id}-#{run_summary_dom_token(entry.id)}"}
                              class="rounded-2xl border border-base-300/70 bg-base-100/85 px-4 py-4 space-y-3"
                            >
                              <div class="flex flex-wrap items-start justify-between gap-3">
                                <div class="space-y-1">
                                  <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
                                    {section.title}
                                  </p>
                                  <p class="text-sm font-medium text-base-content/90">
                                    {section.heading}
                                  </p>
                                </div>
                                <span
                                  :if={section.status_badge}
                                  class={section.status_badge.class}
                                >
                                  {section.status_badge.label}
                                </span>
                              </div>

                              <p class="text-sm text-base-content/75">
                                {section.summary}
                              </p>

                              <p
                                :if={section.meta}
                                class="text-xs text-base-content/65"
                              >
                                {section.meta}
                              </p>

                              <div class="flex flex-wrap items-center gap-3 text-sm">
                                <.link
                                  :for={link <- section.links}
                                  id={"dashboard-overview-repository-detail-#{section.id}-#{link.id}-link-#{run_summary_dom_token(entry.id)}"}
                                  navigate={link.route}
                                  class={link.class}
                                >
                                  {link.label}
                                </.link>
                              </div>
                            </section>
                          </div>
                        </div>
                      </section>
                    </li>
                  </ol>
                <% end %>
              </section>
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
              >
                <:actions>
                  <button
                    id="dashboard-run-summary-refresh"
                    type="button"
                    class="btn btn-sm btn-warning"
                    phx-click="refresh_run_summaries"
                  >
                    Refresh run summaries
                  </button>
                </:actions>
              </.operator_state_notice>

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
                <div class="flex flex-wrap items-center gap-3">
                  <p id="dashboard-conversation-summary-last-refreshed" class="text-xs text-base-content/70">
                    Last refreshed: {summary_refreshed_label(@conversation_summary_last_refreshed_at)}
                  </p>
                  <button
                    id="dashboard-conversation-summary-refresh"
                    type="button"
                    class="btn btn-sm btn-outline"
                    phx-click="refresh_conversation_summaries"
                  >
                    Refresh conversation supervision
                  </button>
                </div>
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
                <div class="flex flex-wrap items-center gap-3">
                  <p id="dashboard-memory-summary-last-refreshed" class="text-xs text-base-content/70">
                    Last refreshed: {summary_refreshed_label(@memory_summary_last_refreshed_at)}
                  </p>
                  <button
                    id="dashboard-memory-summary-refresh"
                    type="button"
                    class="btn btn-sm btn-outline"
                    phx-click="refresh_memory_summaries"
                  >
                    Refresh memory summaries
                  </button>
                </div>
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
                <div class="flex flex-wrap items-center gap-3">
                  <p id="dashboard-runtime-evidence-last-refreshed" class="text-xs text-base-content/70">
                    Last refreshed: {summary_refreshed_label(@runtime_evidence_last_refreshed_at)}
                  </p>
                  <button
                    id="dashboard-runtime-evidence-refresh"
                    type="button"
                    class="btn btn-sm btn-outline"
                    phx-click="refresh_runtime_evidence"
                  >
                    Refresh runtime posture
                  </button>
                </div>
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
          </div>
        </div>
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

  defp dashboard_section_nav_items(assigns) do
    Enum.map(assigns.dashboard_sections, fn section ->
      %{
        section: section,
        label: dashboard_section_label(section),
        summary: dashboard_section_summary(section, assigns),
        badge: dashboard_section_badge(section, assigns),
        selected?: assigns.selected_dashboard_section == section
      }
    end)
  end

  defp dashboard_section_path(onboarding_next_actions, section) do
    params =
      [section: Atom.to_string(section)]
      |> maybe_put_query_param(:onboarding, onboarding_next_actions_query_param(onboarding_next_actions))

    ~p"/dashboard?#{params}"
  end

  defp onboarding_next_actions_query_param(onboarding_next_actions) do
    if Enum.empty?(onboarding_next_actions), do: nil, else: "completed"
  end

  defp normalize_dashboard_section(section_param, available_sections) do
    section_param
    |> normalize_optional_string()
    |> case do
      nil ->
        :overview

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
          _other -> :overview
        end
    end
    |> then(fn section ->
      if section in available_sections, do: section, else: :overview
    end)
  end

  defp dashboard_section_label(:overview), do: "Overview"
  defp dashboard_section_label(:runs), do: "Runs"
  defp dashboard_section_label(:conversations), do: "Conversations"
  defp dashboard_section_label(:memory), do: "Memory"
  defp dashboard_section_label(:runtime), do: "Runtime"
  defp dashboard_section_label(:next_steps), do: "Next Steps"

  defp dashboard_section_summary(:overview, _assigns),
    do: "Repository-first monitoring panels ordered by the most recent governed or operator-facing work."

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

  defp dashboard_section_badge(:overview, _assigns), do: nil

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

  defp dashboard_section_badge_class(:warning),
    do: "badge badge-sm border border-warning/40 bg-warning/10 text-warning"

  defp dashboard_section_badge_class(_tone),
    do: "badge badge-sm border border-base-300/70 bg-base-100 text-base-content/80"

  defp toggle_repository_monitoring_detail(%MapSet{} = expanded_ids, id) do
    case normalize_optional_string(id) do
      nil ->
        expanded_ids

      normalized_id ->
        if MapSet.member?(expanded_ids, normalized_id) do
          MapSet.delete(expanded_ids, normalized_id)
        else
          MapSet.put(expanded_ids, normalized_id)
        end
    end
  end

  defp repository_monitoring_detail_expanded?(%MapSet{} = expanded_ids, id) do
    case normalize_optional_string(id) do
      nil -> false
      normalized_id -> MapSet.member?(expanded_ids, normalized_id)
    end
  end

  defp repository_monitoring_detail_expanded?(_expanded_ids, _id), do: false

  defp repository_monitoring_detail_state_label(expanded_ids, id) do
    if repository_monitoring_detail_expanded?(expanded_ids, id) do
      "Collapse detail"
    else
      "Detail stays collapsed until expanded"
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

    case DashboardRepositoryMonitoringFeed.load(%{
           run_summaries: socket.assigns.run_summary_rows,
           conversation_summaries: socket.assigns.conversation_summary_rows,
           memory_summaries: socket.assigns.memory_summary_rows,
           runtime_summaries: socket.assigns.runtime_evidence_rows
         }) do
      {:ok, summaries, warning} ->
        socket
        |> assign(:repository_monitoring_count, length(summaries))
        |> assign(:repository_monitoring_rows, summaries)
        |> assign(:repository_monitoring_warning, warning)
        |> assign(:repository_monitoring_last_refreshed_at, now)

      {:error, warning} ->
        socket
        |> assign(:repository_monitoring_count, 0)
        |> assign(:repository_monitoring_rows, [])
        |> assign(:repository_monitoring_warning, warning)
        |> assign(:repository_monitoring_last_refreshed_at, now)
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
