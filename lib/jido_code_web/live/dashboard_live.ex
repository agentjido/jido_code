defmodule JidoCodeWeb.DashboardLive do
  # covers: package.jido_code.primary_implementation_repo
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.compatibility_rollout_exposes_removal_and_rollback_state
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.CompatibilityRollout
  alias JidoCode.Governance.RuntimeEvidenceFeed
  alias JidoCode.Orchestration.{RunPubSub, RunSummaryFeed}

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
      |> assign(:onboarding_next_actions, [])
      |> assign(:run_summary_count, 0)
      |> assign(:run_summary_widget_rows, [])
      |> assign(:run_summary_warning, nil)
      |> assign(:run_summary_last_refreshed_at, nil)
      |> assign(:runtime_evidence_count, 0)
      |> assign(:runtime_evidence_widget_rows, [])
      |> assign(:runtime_evidence_warning, nil)
      |> assign(:runtime_evidence_last_refreshed_at, nil)
      |> assign(:runtime_evidence_summary, nil)
      |> stream_configure(:runtime_evidence_summaries, dom_id: &runtime_evidence_dom_id/1)
      |> stream(:runtime_evidence_summaries, [], reset: true)
      |> assign(:compatibility_rollout_report, nil)
      |> assign(:compatibility_rollout_warning, nil)
      |> assign(:compatibility_rollout_backfill, nil)
      |> assign(:compatibility_rollout_last_refreshed_at, nil)
      |> stream_configure(:run_summaries, dom_id: &run_summary_dom_id/1)
      |> stream(:run_summaries, [], reset: true)
      |> load_run_summaries()
      |> load_runtime_evidence_summaries()
      |> load_compatibility_rollout_report()
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

    {:noreply, assign(socket, :onboarding_next_actions, onboarding_next_actions)}
  end

  @impl true
  def handle_event("refresh_run_summaries", _params, socket) do
    {:noreply, load_run_summaries(socket)}
  end

  @impl true
  def handle_event("refresh_runtime_evidence", _params, socket) do
    {:noreply, load_runtime_evidence_summaries(socket)}
  end

  @impl true
  def handle_event("refresh_compatibility_rollout", _params, socket) do
    {:noreply, run_compatibility_backfill(socket)}
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
       |> load_runtime_evidence_summaries()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-4xl mx-auto py-8">
        <h1 class="text-2xl font-bold mb-4">Dashboard</h1>
        <p class="text-base-content/70">Welcome, {@current_user.email}</p>

        <section
          id="dashboard-run-summaries"
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4 space-y-3"
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
          id="dashboard-runtime-evidence"
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4 space-y-4"
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
          id="dashboard-compatibility-rollout"
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4 space-y-4"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="space-y-1">
              <h2 class="text-lg font-semibold">Compatibility rollout</h2>
              <p id="dashboard-compatibility-summary" class="text-sm text-base-content/80">
                {compatibility_summary(@compatibility_rollout_report)}
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <p id="dashboard-compatibility-last-refreshed" class="text-xs text-base-content/70">
                Last refreshed: {summary_refreshed_label(@compatibility_rollout_last_refreshed_at)}
              </p>
              <button
                id="dashboard-compatibility-refresh"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="refresh_compatibility_rollout"
              >
                Run compatibility backfill
              </button>
            </div>
          </div>

          <.operator_state_notice
            :if={@compatibility_rollout_warning}
            id="dashboard-compatibility-warning"
            title="Compatibility rollout report may be stale"
            state={@compatibility_rollout_warning}
            compact={true}
          />

          <section
            :if={@compatibility_rollout_backfill}
            id="dashboard-compatibility-backfill"
            class="rounded-lg border border-base-300/70 bg-base-200/30 p-3"
          >
            <p class="text-sm font-medium">Latest backfill run</p>
            <div class="mt-2 grid gap-3 text-xs text-base-content/80 md:grid-cols-3">
              <p id="dashboard-compatibility-backfill-projects">
                Projects backfilled: {@compatibility_rollout_backfill.projects_backfilled}
              </p>
              <p id="dashboard-compatibility-backfill-workflow-runs">
                Workflow runs backfilled: {@compatibility_rollout_backfill.workflow_runs_backfilled}
              </p>
              <p id="dashboard-compatibility-backfill-rollback-safe">
                Rollback safe: {yes_no_label(@compatibility_rollout_backfill.rollback_safe)}
              </p>
            </div>
          </section>

          <div
            :if={@compatibility_rollout_report}
            id="dashboard-compatibility-counts"
            class="grid gap-3 md:grid-cols-3"
          >
            <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
              <p class="text-xs uppercase text-base-content/60">Projects missing managed repos</p>
              <p id="dashboard-compatibility-count-project-gaps" class="mt-1 text-2xl font-semibold">
                {compatibility_count(@compatibility_rollout_report, :projects_missing_managed_repo)}
              </p>
            </div>
            <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
              <p class="text-xs uppercase text-base-content/60">Workflow runs missing governed runs</p>
              <p id="dashboard-compatibility-count-run-gaps" class="mt-1 text-2xl font-semibold">
                {compatibility_count(@compatibility_rollout_report, :workflow_runs_missing_governed_run)}
              </p>
            </div>
            <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
              <p class="text-xs uppercase text-base-content/60">Governed run projections</p>
              <p id="dashboard-compatibility-count-governed-runs" class="mt-1 text-2xl font-semibold">
                {compatibility_count(@compatibility_rollout_report, :governed_runs_total)}
              </p>
            </div>
          </div>

          <section :if={@compatibility_rollout_report} id="dashboard-compatibility-surfaces" class="space-y-2">
            <h3 class="text-sm font-semibold uppercase text-base-content/70">Remaining shim dependencies</h3>
            <ol class="space-y-2">
              <li
                :for={surface <- compatibility_surfaces(@compatibility_rollout_report)}
                id={"dashboard-compatibility-surface-#{surface.id}"}
                class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
              >
                <div class="flex flex-wrap items-center gap-2">
                  <p class="text-sm font-medium">{surface.label}</p>
                  <span class={compatibility_status_badge_class(surface.status)}>
                    {compatibility_status_label(surface.status)}
                  </span>
                </div>
                <p class="text-xs text-base-content/80">
                  Depends on {surface.dependency}. {surface.detail}
                </p>
              </li>
            </ol>
          </section>

          <section :if={@compatibility_rollout_report} id="dashboard-compatibility-removal" class="space-y-2">
            <h3 class="text-sm font-semibold uppercase text-base-content/70">Removal criteria</h3>
            <ol class="space-y-2">
              <li
                :for={criterion <- removal_criteria(@compatibility_rollout_report)}
                id={"dashboard-compatibility-removal-#{criterion.id}"}
                class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
              >
                <div class="flex flex-wrap items-center gap-2">
                  <p class="text-sm font-medium">{criterion.label}</p>
                  <span class={compatibility_status_badge_class(criterion.status)}>
                    {compatibility_status_label(criterion.status)}
                  </span>
                </div>
                <p class="text-xs text-base-content/80">{criterion.detail}</p>
              </li>
            </ol>
          </section>

          <section :if={@compatibility_rollout_report} id="dashboard-compatibility-rollback" class="space-y-2">
            <h3 class="text-sm font-semibold uppercase text-base-content/70">Rollback procedures</h3>
            <ol class="space-y-2">
              <li
                :for={procedure <- rollback_procedures(@compatibility_rollout_report)}
                id={"dashboard-compatibility-rollback-#{procedure.id}"}
                class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
              >
                <p class="text-sm font-medium">{procedure.label}</p>
                <p class="text-xs text-base-content/80">Trigger: {procedure.trigger}</p>
                <p class="text-xs text-base-content/80">{procedure.procedure}</p>
              </li>
            </ol>
          </section>
        </section>

        <section
          :if={!Enum.empty?(@onboarding_next_actions)}
          id="dashboard-onboarding-next-actions"
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4"
        >
          <h2 class="text-lg font-semibold">Onboarding next actions</h2>
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
    </Layouts.app>
    """
  end

  defp load_run_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case RunSummaryFeed.load() do
      {:ok, run_summaries, warning} ->
        socket
        |> assign(:run_summary_count, length(run_summaries))
        |> assign(:run_summary_widget_rows, Enum.map(run_summaries, &dashboard_run_summary_widget/1))
        |> assign(:run_summary_warning, warning)
        |> assign(:run_summary_last_refreshed_at, now)
        |> stream(:run_summaries, run_summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:run_summary_count, 0)
        |> assign(:run_summary_widget_rows, [])
        |> assign(:run_summary_warning, warning)
        |> assign(:run_summary_last_refreshed_at, now)
        |> stream(:run_summaries, [], reset: true)
    end
  end

  defp load_compatibility_rollout_report(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case CompatibilityRollout.report() do
      {:ok, report} ->
        socket
        |> assign(:compatibility_rollout_report, report)
        |> assign(:compatibility_rollout_warning, nil)
        |> assign(:compatibility_rollout_last_refreshed_at, now)

      {:error, warning} ->
        socket
        |> assign(:compatibility_rollout_report, nil)
        |> assign(:compatibility_rollout_warning, warning)
        |> assign(:compatibility_rollout_last_refreshed_at, now)
    end
  end

  defp run_compatibility_backfill(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case CompatibilityRollout.backfill_and_report() do
      {:ok, %{backfill: backfill, report: report}} ->
        socket
        |> assign(:compatibility_rollout_report, report)
        |> assign(:compatibility_rollout_backfill, backfill)
        |> assign(:compatibility_rollout_warning, nil)
        |> assign(:compatibility_rollout_last_refreshed_at, now)

      {:error, warning} ->
        socket
        |> assign(:compatibility_rollout_warning, warning)
        |> assign(:compatibility_rollout_last_refreshed_at, now)
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

  defp summary_refreshed_label(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp summary_refreshed_label(_datetime), do: "not yet"

  defp run_summary_dom_id(run_summary) do
    "dashboard-run-summary-#{run_summary_dom_token(run_summary.id)}"
  end

  defp runtime_evidence_dom_id(runtime_summary) do
    "dashboard-runtime-evidence-#{run_summary_dom_token(runtime_summary.id)}"
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

  defp compatibility_status_badge_class("ready"), do: "badge badge-success"
  defp compatibility_status_badge_class("ready_to_retire"), do: "badge badge-success"
  defp compatibility_status_badge_class("legacy_dependency_present"), do: "badge badge-warning"
  defp compatibility_status_badge_class("coexistence_active"), do: "badge badge-info"
  defp compatibility_status_badge_class("pending"), do: "badge badge-outline"
  defp compatibility_status_badge_class(_status), do: "badge badge-outline"

  defp runtime_evidence_badge_class("blocked"), do: "badge badge-error"
  defp runtime_evidence_badge_class("degraded"), do: "badge badge-warning"
  defp runtime_evidence_badge_class("available"), do: "badge badge-success"
  defp runtime_evidence_badge_class(_status), do: "badge badge-outline"

  defp compatibility_status_label(status) do
    case normalize_optional_string(status) do
      "ready_to_retire" -> "ready to retire"
      "legacy_dependency_present" -> "legacy dependency present"
      "coexistence_active" -> "coexistence active"
      "pending" -> "pending"
      "ready" -> "ready"
      nil -> "unknown"
      other -> other
    end
  end

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

  defp compatibility_summary(%{} = report) do
    report
    |> Map.get(:summary)
    |> normalize_optional_string() || "Compatibility rollout status is unavailable."
  end

  defp compatibility_summary(_report), do: "Compatibility rollout status is unavailable."

  defp runtime_evidence_summary(%{} = summary) do
    "Runtime posture tracks #{Map.get(summary, :total_count, 0)} repo(s): #{Map.get(summary, :blocked_count, 0)} blocked, #{Map.get(summary, :degraded_count, 0)} review-required, #{Map.get(summary, :available_count, 0)} stable."
  end

  defp runtime_evidence_summary(_summary),
    do: "Runtime posture status is unavailable."

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
        |> assign(:runtime_evidence_widget_rows, Enum.map(summaries, &dashboard_runtime_evidence_widget/1))
        |> assign(:runtime_evidence_warning, warning)
        |> assign(:runtime_evidence_last_refreshed_at, now)
        |> assign(:runtime_evidence_summary, summarize_runtime_evidence(summaries))
        |> stream(:runtime_evidence_summaries, summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:runtime_evidence_count, 0)
        |> assign(:runtime_evidence_widget_rows, [])
        |> assign(:runtime_evidence_warning, warning)
        |> assign(:runtime_evidence_last_refreshed_at, now)
        |> assign(:runtime_evidence_summary, nil)
        |> stream(:runtime_evidence_summaries, [], reset: true)
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

  defp compatibility_count(report, key) when is_map(report) do
    report
    |> Map.get(:counts, %{})
    |> Map.get(key, 0)
    |> normalize_non_negative_integer()
  end

  defp compatibility_count(_report, _key), do: 0

  defp compatibility_surfaces(report) when is_map(report) do
    report
    |> Map.get(:compatibility_surfaces, [])
    |> Enum.map(&normalize_compatibility_item/1)
  end

  defp compatibility_surfaces(_report), do: []

  defp removal_criteria(report) when is_map(report) do
    report
    |> Map.get(:removal_criteria, [])
    |> Enum.map(&normalize_compatibility_item/1)
  end

  defp removal_criteria(_report), do: []

  defp rollback_procedures(report) when is_map(report) do
    report
    |> Map.get(:rollback_procedures, [])
    |> Enum.map(&normalize_compatibility_item/1)
  end

  defp rollback_procedures(_report), do: []

  defp normalize_compatibility_item(item) when is_map(item) do
    %{
      id:
        item
        |> Map.get(:id)
        |> normalize_optional_string() || "unknown",
      label:
        item
        |> Map.get(:label)
        |> normalize_optional_string() || "Unknown",
      dependency:
        item
        |> Map.get(:dependency)
        |> normalize_optional_string(),
      status:
        item
        |> Map.get(:status)
        |> normalize_optional_string() || "pending",
      detail:
        item
        |> Map.get(:detail)
        |> normalize_optional_string(),
      trigger:
        item
        |> Map.get(:trigger)
        |> normalize_optional_string(),
      procedure:
        item
        |> Map.get(:procedure)
        |> normalize_optional_string()
    }
  end

  defp normalize_compatibility_item(_item) do
    %{
      id: "unknown",
      label: "Unknown",
      dependency: nil,
      status: "pending",
      detail: nil,
      trigger: nil,
      procedure: nil
    }
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
      ~p"/projects/#{project_id}/runs/#{run_id}"
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

  defp yes_no_label(true), do: "Yes"
  defp yes_no_label(false), do: "No"
  defp yes_no_label(_value), do: "No"

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
