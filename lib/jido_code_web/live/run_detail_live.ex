defmodule JidoCodeWeb.RunDetailLive do
  # covers: package.jido_code.primary_implementation_repo
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Governance.{ChangeRequest, Decision, Evidence, RepoPosture}
  alias JidoCode.Orchestration.{Run, RunBridge, RunPubSub, WorkflowRun}

  @run_events_for_refresh MapSet.new([
                            "run_started",
                            "step_started",
                            "step_completed",
                            "step_failed",
                            "approval_requested",
                            "approval_granted",
                            "approval_rejected",
                            "run_completed",
                            "run_failed",
                            "run_cancelled"
                          ])
  @run_event_refresh_delay_ms 50
  @artifact_categories [
    %{id: "logs", label: "Logs"},
    %{id: "diff_summaries", label: "Diff summaries"},
    %{id: "reports", label: "Reports"},
    %{id: "pr_metadata", label: "PR metadata"}
  ]

  @impl true
  def mount(%{"id" => project_id, "run_id" => run_id}, _session, socket) do
    socket =
      case load_run_state(project_id, run_id) do
        {:ok, run_state} ->
          socket
          |> assign(:project_id, project_id)
          |> assign(:run_id, run_id)
          |> assign_run_state(run_state)
          |> assign(:approval_action_error, nil)
          |> assign(:retry_action_error, nil)

        {:error, :not_found} ->
          assign_missing_run(socket, project_id, run_id)

        {:error, _reason} ->
          assign_missing_run(socket, project_id, run_id)
      end

    {:ok, maybe_subscribe_run_events(socket)}
  end

  @impl true
  def handle_info({:run_event, payload}, socket) do
    if refresh_for_run_event?(payload, socket) do
      Process.send_after(self(), :refresh_run_after_event, @run_event_refresh_delay_ms)
      {:noreply, refresh_run_assigns(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_run_after_event, socket), do: {:noreply, refresh_run_assigns(socket)}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("approve_run", _params, %{assigns: %{workflow_run: %WorkflowRun{} = run}} = socket) do
    case WorkflowRun.approve(run, %{
           actor: approving_actor(socket),
           current_step: "resume_execution"
         }) do
      {:ok, %WorkflowRun{} = _approved_run} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:approval_action_error, nil)
         |> assign(:retry_action_error, nil)}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:approval_action_error, normalize_approval_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("approve_run", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reject_run", params, %{assigns: %{workflow_run: %WorkflowRun{} = run}} = socket) do
    rationale =
      params
      |> map_get(:rationale, "rationale")
      |> normalize_optional_string()

    case WorkflowRun.reject(run, %{
           actor: approving_actor(socket),
           rationale: rationale
         }) do
      {:ok, %WorkflowRun{} = _rejected_run} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:approval_action_error, nil)
         |> assign(:retry_action_error, nil)}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:approval_action_error, normalize_approval_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("reject_run", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("retry_run", _params, %{assigns: %{workflow_run: %WorkflowRun{} = run}} = socket) do
    case WorkflowRun.retry(run, %{actor: approving_actor(socket)}) do
      {:ok, %WorkflowRun{} = retried_run} ->
        {:noreply,
         socket
         |> assign(:retry_action_error, nil)
         |> assign(:approval_action_error, nil)
         |> put_flash(:info, "Full-run retry started as #{retried_run.run_id}.")
         |> push_navigate(to: ~p"/repos/#{socket.assigns.project_id}/runs/#{retried_run.run_id}")}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:retry_action_error, normalize_retry_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("retry_run", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("retry_step", _params, %{assigns: %{workflow_run: %WorkflowRun{} = run}} = socket) do
    case WorkflowRun.retry_step(run, %{actor: approving_actor(socket)}) do
      {:ok, %WorkflowRun{} = retried_run} ->
        {:noreply,
         socket
         |> assign(:retry_action_error, nil)
         |> assign(:approval_action_error, nil)
         |> put_flash(
           :info,
           "Step-level retry started at #{retried_run.current_step} as #{retried_run.run_id}."
         )
         |> push_navigate(to: ~p"/repos/#{socket.assigns.project_id}/runs/#{retried_run.run_id}")}

      {:error, typed_failure} ->
        {:noreply,
         socket
         |> refresh_run_assigns()
         |> assign(:retry_action_error, normalize_retry_action_failure(typed_failure))}
    end
  end

  @impl true
  def handle_event("retry_step", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="run-detail-page" class="space-y-4">
        <%= if @run do %>
          <section id="run-detail-header" class="space-y-1">
            <h1 id="run-detail-title" class="text-2xl font-bold">Workflow run detail</h1>
            <p id="run-detail-run-id" class="text-sm">
              Run: <span class="font-mono">{@run.run_id}</span>
            </p>
            <p id="run-detail-status" class="text-sm">
              Status: {status_label(@run.status)}
            </p>
            <p id="run-detail-current-step" class="text-sm">
              Current step: {current_step_label(@run.current_step)}
            </p>
            <p id="run-detail-retry-attempt" class="text-sm">
              Attempt: {Map.get(@run, :retry_attempt, 1)}
            </p>
            <p
              :if={normalize_optional_string(Map.get(@run, :retry_of_run_id))}
              id="run-detail-retry-parent-run"
              class="text-sm"
            >
              Retry parent: <span class="font-mono">{Map.get(@run, :retry_of_run_id)}</span>
            </p>
            <p
              :if={normalize_optional_string(Map.get(@run, :current_stage))}
              id="run-detail-current-stage"
              class="text-sm text-base-content/80"
            >
              Governed stage: {Map.get(@run, :current_stage)}
            </p>
            <p
              :if={normalize_optional_string(Map.get(@run, :managed_repo_id))}
              id="run-detail-managed-repo-id"
              class="text-xs text-base-content/70"
            >
              Managed repo: {Map.get(@run, :managed_repo_id)}
            </p>
          </section>

          <.vue_surface
            id="run-detail-governance-overview-widget"
            component="RunGovernanceOverviewWidget"
            socket={@socket}
            props={run_governance_widget_props(assigns)}
          />

          <section
            id="run-detail-governance-summary"
            class="space-y-3 rounded border border-base-300 bg-base-100 p-4"
          >
            <h2 class="text-lg font-semibold">Governance</h2>

            <section
              :if={@change_request}
              id="run-detail-change-request"
              class="space-y-1 rounded border border-base-300/70 bg-base-200/30 p-3"
            >
              <p id="run-detail-change-request-status" class="text-sm">
                Review request: {Map.get(@change_request, :status) |> status_label()}
              </p>
              <p id="run-detail-change-request-summary" class="text-sm text-base-content/80">
                {Map.get(@change_request, :summary) |> normalize_optional_string()}
              </p>
            </section>

            <section id="run-detail-evidence-records" class="space-y-2">
              <p class="text-sm font-medium">Evidence records</p>

              <%= if @evidence_records == [] do %>
                <p id="run-detail-evidence-empty" class="text-xs text-base-content/70">
                  No governed evidence records have been captured yet.
                </p>
              <% else %>
                <ol id="run-detail-evidence-list" class="space-y-2">
                  <li
                    :for={{evidence, index} <- Enum.with_index(@evidence_records, 1)}
                    id={"run-detail-evidence-entry-#{index}"}
                    class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
                  >
                    <p id={"run-detail-evidence-key-#{index}"} class="text-sm font-medium">
                      {Map.get(evidence, :key)}
                    </p>
                    <p id={"run-detail-evidence-summary-#{index}"} class="text-xs text-base-content/80">
                      {Map.get(evidence, :summary)}
                    </p>
                  </li>
                </ol>
              <% end %>
            </section>

            <section id="run-detail-runtime-evidence" class="space-y-2">
              <p class="text-sm font-medium">Runtime evidence</p>

              <%= if @runtime_evidence_summary do %>
                <div class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1">
                  <p id="run-detail-runtime-evidence-status" class="text-sm">
                    Runtime posture:
                    <span class={runtime_evidence_badge_class(@runtime_evidence_summary.status)}>
                      {runtime_evidence_status_label(@runtime_evidence_summary.status)}
                    </span>
                  </p>
                  <p id="run-detail-runtime-evidence-summary" class="text-xs text-base-content/80">
                    {@runtime_evidence_summary.summary}
                  </p>
                  <p
                    :if={@runtime_evidence_summary.delivery_mode}
                    id="run-detail-runtime-evidence-delivery-mode"
                    class="text-xs text-base-content/80"
                  >
                    Delivery path: {humanize_runtime_value(@runtime_evidence_summary.delivery_mode)}
                  </p>
                  <p
                    :if={@runtime_evidence_summary.reason_code}
                    id="run-detail-runtime-evidence-reason"
                    class="text-xs text-base-content/80"
                  >
                    Runtime reason: {humanize_runtime_value(@runtime_evidence_summary.reason_code)}
                  </p>
                  <p
                    :if={@runtime_evidence_summary.integration_summary}
                    id="run-detail-runtime-evidence-integration"
                    class="text-xs text-base-content/80"
                  >
                    Latest integration signal: {@runtime_evidence_summary.integration_summary}
                  </p>
                  <p id="run-detail-runtime-evidence-note" class="text-xs text-base-content/70">
                    Product governance stores bounded runtime evidence here; runtime transport remains opaque.
                  </p>
                </div>
              <% else %>
                <p id="run-detail-runtime-evidence-empty" class="text-xs text-base-content/70">
                  No bounded runtime evidence has been materialized for this run yet.
                </p>
              <% end %>
            </section>

            <section id="run-detail-decisions" class="space-y-2">
              <p class="text-sm font-medium">Decisions</p>

              <%= if @decisions == [] do %>
                <p id="run-detail-decisions-empty" class="text-xs text-base-content/70">
                  No governance decisions have been recorded yet.
                </p>
              <% else %>
                <ol id="run-detail-decision-list" class="space-y-2">
                  <li
                    :for={{decision, index} <- Enum.with_index(@decisions, 1)}
                    id={"run-detail-decision-entry-#{index}"}
                    class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
                  >
                    <p id={"run-detail-decision-value-#{index}"} class="text-sm font-medium">
                      {Map.get(decision, :decision) |> status_label()}
                    </p>
                    <p
                      :if={normalize_optional_string(Map.get(decision, :rationale))}
                      id={"run-detail-decision-rationale-#{index}"}
                      class="text-xs text-base-content/80"
                    >
                      {Map.get(decision, :rationale)}
                    </p>
                  </li>
                </ol>
              <% end %>
            </section>
          </section>

          <%= if @issue_triage_artifacts do %>
            <section
              id="run-detail-issue-triage-artifacts"
              class="space-y-2 rounded border border-base-300 bg-base-100 p-4"
            >
              <h2 class="text-lg font-semibold">Issue triage artifacts</h2>
              <p id="run-detail-issue-artifact-persistence-status" class="text-sm text-base-content/80">
                Persistence status: {@issue_triage_artifacts.persistence_status}
              </p>
              <p id="run-detail-issue-triage-classification" class="text-sm">
                Classification: {@issue_triage_artifacts.classification}
              </p>
              <p id="run-detail-issue-research-summary" class="text-sm text-base-content/80">
                {@issue_triage_artifacts.research_summary}
              </p>
              <p id="run-detail-issue-response-draft" class="text-sm text-base-content/80">
                {@issue_triage_artifacts.proposed_response}
              </p>
              <p id="run-detail-issue-response-post-status" class="text-sm text-base-content/80">
                Response post status: {@issue_triage_artifacts.response_post_status}
              </p>
              <p
                :if={@issue_triage_artifacts.posted_comment_url}
                id="run-detail-issue-response-post-url"
                class="text-sm text-base-content/80"
              >
                Posted comment:
                <.link
                  href={@issue_triage_artifacts.posted_comment_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary break-all"
                >
                  {@issue_triage_artifacts.posted_comment_url}
                </.link>
              </p>
              <p
                :if={@issue_triage_artifacts.posted_comment_id}
                id="run-detail-issue-response-post-comment-id"
                class="text-xs text-base-content/70"
              >
                Posted comment ID: {@issue_triage_artifacts.posted_comment_id}
              </p>
              <p
                :if={@issue_triage_artifacts.response_posted_at}
                id="run-detail-issue-response-posted-at"
                class="text-xs text-base-content/70"
              >
                Posted at: {@issue_triage_artifacts.response_posted_at}
              </p>
              <p
                :if={@issue_triage_artifacts.issue_reference}
                id="run-detail-issue-artifact-issue-reference"
                class="text-xs text-base-content/70"
              >
                Issue reference: {@issue_triage_artifacts.issue_reference}
              </p>
              <p
                :if={@issue_triage_artifacts.source_issue_number}
                id="run-detail-issue-artifact-source-issue-number"
                class="text-xs text-base-content/70"
              >
                Source issue number: {@issue_triage_artifacts.source_issue_number}
              </p>
              <p
                :if={@issue_triage_artifacts.linked_run_id}
                id="run-detail-issue-artifact-run-id"
                class="text-xs text-base-content/70"
              >
                Linked run: <span class="font-mono">{@issue_triage_artifacts.linked_run_id}</span>
              </p>

              <%= if @issue_triage_artifacts.typed_failure do %>
                <section
                  id="run-detail-issue-artifact-persistence-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-issue-artifact-persistence-error-type" class="text-sm font-semibold text-error">
                    Typed persistence failure: {@issue_triage_artifacts.typed_failure.error_type}
                  </p>
                  <p id="run-detail-issue-artifact-persistence-error-detail" class="text-sm text-base-content/80">
                    {@issue_triage_artifacts.typed_failure.detail}
                  </p>
                  <p id="run-detail-issue-artifact-persistence-error-remediation" class="text-sm text-base-content/80">
                    {@issue_triage_artifacts.typed_failure.remediation}
                  </p>
                </section>
              <% end %>

              <%= if @issue_triage_artifacts.response_post_failure do %>
                <section
                  id="run-detail-issue-response-post-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-issue-response-post-error-type" class="text-sm font-semibold text-error">
                    Typed post failure: {@issue_triage_artifacts.response_post_failure.error_type}
                  </p>
                  <p id="run-detail-issue-response-post-error-detail" class="text-sm text-base-content/80">
                    {@issue_triage_artifacts.response_post_failure.detail}
                  </p>
                  <p id="run-detail-issue-response-post-error-remediation" class="text-sm text-base-content/80">
                    {@issue_triage_artifacts.response_post_failure.remediation}
                  </p>
                </section>
              <% end %>
            </section>
          <% end %>

          <section id="run-detail-artifact-browser" class="space-y-3 rounded border border-base-300 bg-base-100 p-4">
            <h2 class="text-lg font-semibold">Run artifacts</h2>
            <p id="run-detail-artifact-browser-note" class="text-sm text-base-content/80">
              Browse persisted artifact records grouped by category.
            </p>

            <section
              :for={category <- @artifact_categories}
              id={"run-detail-artifact-category-#{category.id}"}
              class="space-y-2 rounded border border-base-300/70 bg-base-200/30 p-3"
            >
              <h3 id={"run-detail-artifact-category-title-#{category.id}"} class="text-sm font-semibold">
                {category.label}
              </h3>

              <%= if category.entries == [] do %>
                <p id={"run-detail-artifact-category-missing-#{category.id}"} class="text-xs text-warning">
                  Missing artifact records for this category.
                </p>
              <% else %>
                <ol id={"run-detail-artifact-category-list-#{category.id}"} class="space-y-2">
                  <li
                    :for={entry <- category.entries}
                    id={"run-detail-artifact-entry-#{entry.identifier}"}
                    class="space-y-1 rounded border border-base-300 bg-base-100 p-2"
                  >
                    <p id={"run-detail-artifact-identifier-#{entry.identifier}"} class="text-xs">
                      Identifier: <span class="font-mono">{entry.identifier}</span>
                    </p>
                    <p id={"run-detail-artifact-source-#{entry.identifier}"} class="text-xs text-base-content/80">
                      Source: <span class="font-mono">{entry.source}</span>
                    </p>
                    <.link
                      id={"run-detail-artifact-view-#{entry.identifier}"}
                      href={"#run-detail-artifact-payload-#{entry.identifier}"}
                      class="link link-primary text-xs"
                    >
                      View artifact
                    </.link>
                    <article
                      id={"run-detail-artifact-payload-#{entry.identifier}"}
                      class="rounded border border-base-300/70 bg-base-200/40 p-2"
                    >
                      <p class="text-xs font-medium">{entry.summary}</p>
                      <pre
                        id={"run-detail-artifact-payload-content-#{entry.identifier}"}
                        class="mt-1 overflow-x-auto whitespace-pre-wrap text-xs leading-5"
                      >{entry.payload}</pre>
                    </article>
                  </li>
                </ol>
              <% end %>
            </section>
          </section>

          <%= if @failure_context do %>
            <section id="run-detail-failure-context" class="space-y-2 rounded border border-error/40 bg-error/5 p-4">
              <h2 class="text-lg font-semibold text-error">Failure context</h2>
              <p id="run-detail-failure-error-type" class="text-sm">
                Error type: <span class="font-mono">{@failure_context.error_type}</span>
              </p>
              <p id="run-detail-failure-reason-type" class="text-sm">
                Typed reason: <span class="font-mono">{@failure_context.reason_type}</span>
              </p>
              <p id="run-detail-failure-last-successful-step" class="text-sm">
                Last successful step: <span class="font-mono">{@failure_context.last_successful_step}</span>
              </p>
              <p id="run-detail-failure-failed-step" class="text-sm">
                Failed step: <span class="font-mono">{@failure_context.failed_step}</span>
              </p>
              <p id="run-detail-failure-detail" class="text-sm text-base-content/80">
                {@failure_context.detail}
              </p>
              <p id="run-detail-failure-remediation" class="text-sm text-base-content/80">
                {@failure_context.remediation}
              </p>

              <%= if @failure_context.missing_fields != [] do %>
                <p id="run-detail-failure-missing-fields" class="text-sm text-base-content/80">
                  Missing failure context fields: {Enum.join(@failure_context.missing_fields, ", ")}
                </p>
              <% end %>
            </section>
          <% end %>

          <%= if awaiting_approval?(@run.status) do %>
            <section id="run-detail-approval-panel" class="space-y-3 rounded border border-base-300 bg-base-100 p-4">
              <h2 class="text-lg font-semibold">Approval request payload</h2>
              <p id="run-detail-approval-panel-note" class="text-sm text-base-content/80">
                Review this context before approving.
              </p>

              <%= if @approval_context do %>
                <div id="run-detail-approval-context" class="space-y-2 rounded border border-base-300 p-3">
                  <p id="run-detail-approval-diff-summary" class="text-sm">
                    Diff summary: {@approval_context.diff_summary}
                  </p>
                  <p id="run-detail-approval-test-summary" class="text-sm">
                    Test summary: {@approval_context.test_summary}
                  </p>
                  <div class="space-y-1">
                    <p class="text-sm font-medium">Risk notes</p>
                    <ul id="run-detail-approval-risk-notes" class="list-disc pl-5 text-sm text-base-content/80">
                      <li
                        :for={{risk_note, index} <- Enum.with_index(@approval_context.risk_notes, 1)}
                        id={"run-detail-approval-risk-note-#{index}"}
                      >
                        {risk_note}
                      </li>
                    </ul>
                  </div>
                </div>
              <% else %>
                <p id="run-detail-approval-context-missing" class="text-sm text-warning">
                  Approval context is unavailable.
                </p>
              <% end %>

              <%= if @approval_context_blocker do %>
                <section
                  id="run-detail-approval-context-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-approval-context-error-message" class="text-sm font-semibold text-error">
                    {@approval_context_blocker.message}
                  </p>
                  <p id="run-detail-approval-context-error-detail" class="text-sm text-base-content/80">
                    {@approval_context_blocker.detail}
                  </p>
                  <p id="run-detail-approval-context-remediation" class="text-sm text-base-content/80">
                    {@approval_context_blocker.remediation}
                  </p>
                </section>
              <% end %>

              <div id="run-detail-approval-actions" class="space-y-3">
                <button
                  id="run-detail-approve-button"
                  type="button"
                  class="btn btn-primary"
                  phx-click="approve_run"
                >
                  Approve
                </button>

                <form id="run-detail-reject-form" phx-submit="reject_run" class="space-y-2">
                  <.input
                    id="run-detail-reject-rationale"
                    type="textarea"
                    name="rationale"
                    label="Rejection rationale (optional)"
                    value=""
                  />
                  <button id="run-detail-reject-button" type="submit" class="btn btn-outline">
                    Reject
                  </button>
                </form>
              </div>

              <%= if @approval_action_error do %>
                <section
                  id="run-detail-approval-action-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-approval-action-error-type" class="text-sm font-semibold text-error">
                    Typed action failure: {@approval_action_error.error_type}
                  </p>
                  <p id="run-detail-approval-action-error-detail" class="text-sm text-base-content/80">
                    {@approval_action_error.detail}
                  </p>
                  <p id="run-detail-approval-action-error-remediation" class="text-sm text-base-content/80">
                    {@approval_action_error.remediation}
                  </p>
                </section>
              <% end %>
            </section>
          <% end %>

          <%= if full_run_retry_available?(@run.status) do %>
            <section id="run-detail-retry-panel" class="space-y-3 rounded border border-base-300 bg-base-100 p-4">
              <h2 class="text-lg font-semibold">Retry run</h2>
              <p id="run-detail-retry-note" class="text-sm text-base-content/80">
                Starts a full-run retry attempt and preserves failure lineage for artifact and reason lookup.
              </p>
              <button
                id="run-detail-retry-button"
                type="button"
                class="btn btn-outline"
                phx-click="retry_run"
              >
                Retry full run
              </button>

              <%= if @step_retry_state.available do %>
                <section id="run-detail-step-retry-panel" class="space-y-2 rounded border border-base-300 p-3">
                  <p id="run-detail-step-retry-note" class="text-sm text-base-content/80">
                    Restarts retry at contract step <span class="font-mono">{@step_retry_state.retry_step}</span>
                    while preserving prior failure lineage.
                  </p>
                  <button
                    id="run-detail-step-retry-button"
                    type="button"
                    class="btn btn-outline"
                    phx-click="retry_step"
                  >
                    Retry from contract step
                  </button>
                </section>
              <% else %>
                <section
                  :if={@step_retry_state.guidance}
                  id="run-detail-step-retry-guidance"
                  class="space-y-1 rounded border border-base-300/70 bg-base-200/40 p-3"
                >
                  <p id="run-detail-step-retry-guidance-detail" class="text-sm text-base-content/80">
                    {@step_retry_state.guidance.detail}
                  </p>
                  <p id="run-detail-step-retry-guidance-remediation" class="text-sm text-base-content/80">
                    {@step_retry_state.guidance.remediation}
                  </p>
                </section>
              <% end %>

              <%= if @retry_action_error do %>
                <section
                  id="run-detail-retry-action-error"
                  class="space-y-1 rounded border border-error/40 bg-error/5 p-3"
                >
                  <p id="run-detail-retry-action-error-type" class="text-sm font-semibold text-error">
                    Typed action failure: {@retry_action_error.error_type}
                  </p>
                  <p id="run-detail-retry-action-error-detail" class="text-sm text-base-content/80">
                    {@retry_action_error.detail}
                  </p>
                  <p id="run-detail-retry-action-error-remediation" class="text-sm text-base-content/80">
                    {@retry_action_error.remediation}
                  </p>
                </section>
              <% end %>
            </section>
          <% end %>

          <%= if @retry_lineage_entries != [] do %>
            <section id="run-detail-retry-lineage" class="space-y-2">
              <h2 class="text-lg font-semibold">Retry lineage</h2>
              <ol id="run-detail-retry-lineage-list" class="space-y-2">
                <li
                  :for={{entry, index} <- Enum.with_index(@retry_lineage_entries, 1)}
                  id={"run-detail-retry-lineage-entry-#{index}"}
                  class="rounded border border-base-300 bg-base-100 p-3 space-y-1"
                >
                  <p id={"run-detail-retry-lineage-run-id-#{index}"} class="text-sm">
                    Prior run: <span class="font-mono">{entry.run_id}</span>
                  </p>
                  <p id={"run-detail-retry-lineage-status-#{index}"} class="text-xs text-base-content/80">
                    Status: {entry.status} (attempt {entry.retry_attempt})
                  </p>
                  <p id={"run-detail-retry-lineage-reason-type-#{index}"} class="text-xs text-base-content/80">
                    Typed reason: {entry.reason_type}
                  </p>
                  <p id={"run-detail-retry-lineage-detail-#{index}"} class="text-xs text-base-content/80">
                    {entry.detail}
                  </p>
                  <p id={"run-detail-retry-lineage-artifact-count-#{index}"} class="text-xs text-base-content/80">
                    Preserved artifact keys: {entry.artifact_count}
                  </p>
                </li>
              </ol>
            </section>
          <% end %>

          <section id="run-detail-timeline" class="space-y-2">
            <h2 class="text-lg font-semibold">Status timeline</h2>

            <%= if @timeline_entries == [] do %>
              <p id="run-detail-timeline-empty" class="text-sm text-base-content/70">
                No status transitions recorded.
              </p>
            <% else %>
              <ol id="run-detail-timeline-list" class="space-y-2">
                <li
                  :for={{entry, index} <- Enum.with_index(@timeline_entries, 1)}
                  id={"run-detail-timeline-entry-#{index}"}
                  class="rounded border border-base-300 bg-base-100 p-3 space-y-1"
                >
                  <p id={"run-detail-timeline-transition-#{index}"} class="text-sm font-medium">
                    {entry.to_status}
                  </p>
                  <p id={"run-detail-timeline-step-#{index}"} class="text-xs text-base-content/80">
                    Step: {entry.current_step}
                  </p>
                  <p id={"run-detail-timeline-duration-#{index}"} class="text-xs text-base-content/70">
                    Duration: {entry.duration}
                  </p>
                  <p id={"run-detail-timeline-at-#{index}"} class="text-xs text-base-content/70">
                    Recorded at: {entry.transitioned_at}
                  </p>
                  <%= if entry.approval_audit do %>
                    <p id={"run-detail-timeline-approval-audit-#{index}"} class="text-xs text-base-content/80">
                      Approval audit: {entry.approval_audit}
                    </p>
                  <% end %>
                </li>
              </ol>
            <% end %>
          </section>
        <% else %>
          <section id="run-detail-missing" class="rounded border border-error/40 bg-error/5 p-4 space-y-2">
            <h1 id="run-detail-missing-title" class="text-lg font-semibold">Run not found</h1>
            <p id="run-detail-missing-detail" class="text-sm text-base-content/80">
              Could not find run <span class="font-mono">{@run_id}</span> for this project.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp assign_missing_run(socket, project_id, run_id) do
    socket
    |> assign(:project_id, project_id)
    |> assign(:run_id, run_id)
    |> assign(:run, nil)
    |> assign(:workflow_run, nil)
    |> assign(:evidence_records, [])
    |> assign(:change_request, nil)
    |> assign(:decisions, [])
    |> assign(:timeline_entries, [])
    |> assign(:retry_lineage_entries, [])
    |> assign(:artifact_categories, default_artifact_categories())
    |> assign(:failure_context, nil)
    |> assign(:issue_triage_artifacts, nil)
    |> assign(:approval_context, nil)
    |> assign(:approval_context_blocker, nil)
    |> assign(:runtime_evidence_summary, nil)
    |> assign(:step_retry_state, step_retry_state(nil))
    |> assign(:approval_action_error, nil)
    |> assign(:retry_action_error, nil)
  end

  defp timeline_entries(%WorkflowRun{} = run) do
    run
    |> Map.get(:status_transitions, [])
    |> normalize_timeline_entries()
  end

  defp timeline_entries(_run), do: []

  defp assign_run_state(
         socket,
         %{
           run: run,
           workflow_run: workflow_run,
           evidence_records: evidence_records,
           change_request: change_request,
           decisions: decisions,
           repo_posture: repo_posture
         }
       ) do
    socket
    |> assign(:run, run || workflow_run)
    |> assign(:workflow_run, workflow_run)
    |> assign(:evidence_records, evidence_records)
    |> assign(:change_request, change_request)
    |> assign(:decisions, decisions)
    |> assign(:runtime_evidence_summary, runtime_evidence_summary(run || workflow_run, evidence_records, repo_posture))
    |> assign(:timeline_entries, timeline_entries(workflow_run))
    |> assign(:retry_lineage_entries, retry_lineage_entries(workflow_run))
    |> assign(:artifact_categories, artifact_categories(workflow_run))
    |> assign(:failure_context, failure_context(workflow_run))
    |> assign(:issue_triage_artifacts, issue_triage_artifacts(workflow_run))
    |> assign(:approval_context, approval_context(workflow_run))
    |> assign(:approval_context_blocker, approval_context_blocker(workflow_run))
    |> assign(:step_retry_state, step_retry_state(workflow_run))
  end

  defp refresh_run_assigns(%{assigns: %{project_id: project_id, run_id: run_id}} = socket) do
    case load_run_state(project_id, run_id) do
      {:ok, run_state} -> assign_run_state(socket, run_state)
      _other -> assign_missing_run(socket, project_id, run_id)
    end
  end

  defp load_run_state(project_id, run_id) do
    with {:ok, project_scope} <- RepoBridge.repo_scope(project_id),
         {:ok, run} <- load_governed_run(project_scope, run_id),
         {:ok, workflow_run} <- load_workflow_run(run, project_scope, run_id) do
      {:ok,
       %{
         run: run,
         workflow_run: workflow_run,
         evidence_records: load_evidence_records(run),
         change_request: load_change_request(run),
         decisions: load_decisions(run),
         repo_posture: load_repo_posture(run)
       }}
    else
      {:error, :governed_run_not_found} ->
        load_legacy_run_state(project_id, run_id)

      {:error, :repo_scope_not_found} ->
        load_legacy_run_state(project_id, run_id)

      {:error, :workflow_run_not_found} ->
        load_legacy_run_state(project_id, run_id)

      {:error, _reason} = error ->
        error
    end
  end

  defp load_governed_run(project_scope, run_id) do
    managed_repo_id =
      project_scope
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    normalized_run_id = normalize_optional_string(run_id)

    cond do
      is_nil(managed_repo_id) or is_nil(normalized_run_id) ->
        {:error, :governed_run_not_found}

      true ->
        case Run.get_by_managed_repo_and_run_id(managed_repo_id, normalized_run_id, actor: Actor.operator_actor()) do
          {:ok, %Run{} = run} -> {:ok, run}
          {:ok, nil} -> {:error, :governed_run_not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp load_workflow_run(%Run{} = run, _project_scope, _run_id) do
    workflow_run_id =
      run
      |> map_get(:workflow_run_id, "workflow_run_id")
      |> normalize_optional_string()

    if is_nil(workflow_run_id) do
      {:error, :workflow_run_not_found}
    else
      case WorkflowRun.read(
             query: [filter: [id: workflow_run_id], limit: 1],
             actor: Actor.operator_actor()
           ) do
        {:ok, [%WorkflowRun{} = workflow_run | _rest]} -> {:ok, workflow_run}
        {:ok, []} -> {:error, :workflow_run_not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp load_workflow_run(_run, _project_scope, _run_id), do: {:error, :workflow_run_not_found}

  defp load_legacy_run_state(project_id, run_id) do
    case WorkflowRun.get_by_project_and_run_id(
           %{project_id: project_id, run_id: run_id},
           actor: Actor.operator_actor()
         ) do
      {:ok, %WorkflowRun{} = workflow_run} ->
        case RunBridge.projected_run_for_workflow_run(workflow_run) do
          {:ok, %Run{} = run} ->
            {:ok,
             %{
               run: run,
               workflow_run: workflow_run,
               evidence_records: load_evidence_records(run),
               change_request: load_change_request(run),
               decisions: load_decisions(run),
               repo_posture: load_repo_posture(run)
             }}

          _other ->
            {:ok,
             %{
               run: workflow_run,
               workflow_run: workflow_run,
               evidence_records: [],
               change_request: nil,
               decisions: [],
               repo_posture: nil
             }}
        end

      {:ok, nil} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_evidence_records(%Run{} = run) do
    case Evidence.read(
           query: [filter: [run_id: run.id], sort: [recorded_at: :asc]],
           actor: Actor.operator_actor()
         ) do
      {:ok, evidence_records} -> evidence_records
      _other -> []
    end
  end

  defp load_evidence_records(_run), do: []

  defp load_change_request(%Run{} = run) do
    case ChangeRequest.read(query: [filter: [run_id: run.id], limit: 1], actor: Actor.operator_actor()) do
      {:ok, [change_request | _rest]} -> change_request
      _other -> nil
    end
  end

  defp load_change_request(_run), do: nil

  defp load_decisions(%Run{} = run) do
    case Decision.read(
           query: [filter: [run_id: run.id], sort: [decided_at: :desc]],
           actor: Actor.operator_actor()
         ) do
      {:ok, decisions} -> decisions
      _other -> []
    end
  end

  defp load_decisions(_run), do: []

  defp load_repo_posture(%Run{} = run) do
    managed_repo_id =
      run
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    if is_nil(managed_repo_id) do
      nil
    else
      case RepoPosture.get_by_managed_repo_id(managed_repo_id, actor: Actor.operator_actor()) do
        {:ok, %RepoPosture{} = repo_posture} -> repo_posture
        _other -> nil
      end
    end
  end

  defp load_repo_posture(_run), do: nil

  defp run_governance_widget_props(assigns) do
    %{
      runStatus:
        assigns
        |> Map.get(:run)
        |> map_get(:status, "status")
        |> status_label(),
      currentStage:
        assigns
        |> Map.get(:run)
        |> map_get(:current_stage, "current_stage")
        |> normalize_optional_string(),
      changeRequestStatus:
        assigns
        |> Map.get(:change_request)
        |> map_get(:status, "status")
        |> normalize_optional_string(),
      evidenceCount: length(Map.get(assigns, :evidence_records, [])),
      decisionCount: length(Map.get(assigns, :decisions, [])),
      runtimeEvidence: run_runtime_evidence_widget(assigns),
      evidenceEntries:
        Enum.map(Map.get(assigns, :evidence_records, []), fn evidence ->
          %{
            key:
              evidence
              |> map_get(:key, "key")
              |> normalize_optional_string() || "unknown",
            summary:
              evidence
              |> map_get(:summary, "summary")
              |> normalize_optional_string() || "Evidence summary unavailable."
          }
        end),
      decisionEntries:
        Enum.map(Map.get(assigns, :decisions, []), fn decision ->
          %{
            decision:
              decision
              |> map_get(:decision, "decision")
              |> status_label(),
            rationale:
              decision
              |> map_get(:rationale, "rationale")
              |> normalize_optional_string()
          }
        end)
    }
  end

  defp run_runtime_evidence_widget(assigns) do
    case Map.get(assigns, :runtime_evidence_summary) do
      %{} = runtime_evidence ->
        %{
          statusLabel:
            runtime_evidence
            |> map_get(:status, "status")
            |> runtime_evidence_status_label(),
          summary:
            runtime_evidence
            |> map_get(:summary, "summary")
            |> normalize_optional_string() || "Runtime evidence summary unavailable.",
          deliveryMode: widget_runtime_detail_value(map_get(runtime_evidence, :delivery_mode, "delivery_mode")),
          reason: widget_runtime_detail_value(map_get(runtime_evidence, :reason_code, "reason_code")),
          integration:
            runtime_evidence
            |> map_get(:integration_summary, "integration_summary")
            |> normalize_optional_string()
        }

      _other ->
        nil
    end
  end

  defp widget_runtime_detail_value(value) do
    case normalize_optional_string(value) do
      nil -> nil
      normalized -> humanize_runtime_value(normalized)
    end
  end

  defp maybe_subscribe_run_events(socket) do
    run_id =
      socket.assigns
      |> Map.get(:run_id)
      |> normalize_optional_string()

    if connected?(socket) and run_id do
      :ok = RunPubSub.subscribe_run(run_id)
    end

    socket
  end

  defp refresh_for_run_event?(payload, socket) do
    event_name =
      payload
      |> map_get(:event, "event")
      |> normalize_optional_string()

    payload_run_id =
      payload
      |> map_get(:run_id, "run_id")
      |> normalize_optional_string()

    socket_run_id =
      socket.assigns
      |> Map.get(:run_id)
      |> normalize_optional_string()

    MapSet.member?(@run_events_for_refresh, event_name) and
      (is_nil(payload_run_id) or payload_run_id == socket_run_id)
  end

  defp failure_context(%WorkflowRun{} = run) do
    if failed_status?(Map.get(run, :status)) do
      error =
        run
        |> Map.get(:error, %{})
        |> normalize_map()

      if map_size(error) == 0 do
        nil
      else
        missing_fields =
          error
          |> map_get(:missing_failure_context_fields, "missing_failure_context_fields", [])
          |> normalize_missing_failure_fields()

        %{
          error_type:
            error
            |> map_get(:error_type, "error_type")
            |> normalize_optional_string() || "workflow_run_failed",
          reason_type:
            error
            |> map_get(:reason_type, "reason_type")
            |> normalize_optional_string() || "workflow_run_failed",
          last_successful_step:
            error
            |> map_get(:last_successful_step, "last_successful_step")
            |> normalize_optional_string() || "unknown",
          failed_step:
            error
            |> map_get(:failed_step, "failed_step")
            |> normalize_optional_string() ||
              (run
               |> Map.get(:current_step)
               |> normalize_optional_string() || "unknown"),
          detail:
            error
            |> map_get(:detail, "detail")
            |> normalize_optional_string() ||
              "Workflow run failed before full failure context was captured.",
          remediation:
            error
            |> map_get(:remediation, "remediation")
            |> normalize_optional_string() ||
              "Inspect failure artifacts and retry from run detail after resolving the failing step.",
          missing_fields: missing_fields
        }
      end
    else
      nil
    end
  end

  defp failure_context(_run), do: nil

  defp issue_triage_artifacts(%WorkflowRun{} = run) do
    workflow_name =
      run
      |> Map.get(:workflow_name)
      |> normalize_optional_string()

    if workflow_name == "issue_triage" do
      step_results =
        run
        |> Map.get(:step_results, %{})
        |> normalize_map()

      triage_artifact =
        step_results
        |> map_get(:run_issue_triage, "run_issue_triage", %{})
        |> normalize_map()

      research_artifact =
        step_results
        |> map_get(:run_issue_research, "run_issue_research", %{})
        |> normalize_map()

      response_artifact =
        step_results
        |> map_get(:compose_issue_response, "compose_issue_response", %{})
        |> normalize_map()

      artifact_lineage =
        step_results
        |> map_get(:issue_bot_artifact_lineage, "issue_bot_artifact_lineage", %{})
        |> normalize_map()

      response_post_artifact =
        step_results
        |> map_get(:post_issue_response, "post_issue_response", %{})
        |> normalize_map()

      if map_size(triage_artifact) == 0 and map_size(research_artifact) == 0 and
           map_size(response_artifact) == 0 and map_size(artifact_lineage) == 0 and
           map_size(response_post_artifact) == 0 do
        nil
      else
        linked_run =
          triage_artifact
          |> map_get(:linked_run, "linked_run")
          |> normalize_map()
          |> case do
            linked_run when map_size(linked_run) > 0 ->
              linked_run

            _other ->
              research_artifact
              |> map_get(:linked_run, "linked_run")
              |> normalize_map()
              |> case do
                linked_run when map_size(linked_run) > 0 ->
                  linked_run

                _other ->
                  response_artifact
                  |> map_get(:linked_run, "linked_run")
                  |> normalize_map()
                  |> case do
                    linked_run when map_size(linked_run) > 0 ->
                      linked_run

                    _other ->
                      artifact_lineage
                      |> map_get(:linked_run, "linked_run", %{})
                      |> normalize_map()
                  end
              end
          end

        source_issue =
          linked_run
          |> map_get(:source_issue, "source_issue")
          |> normalize_map()
          |> case do
            source_issue when map_size(source_issue) > 0 ->
              source_issue

            _other ->
              run
              |> Map.get(:trigger, %{})
              |> map_get(:source_issue, "source_issue", %{})
              |> normalize_map()
          end

        typed_failure =
          artifact_lineage
          |> map_get(:typed_failure, "typed_failure")
          |> normalize_map()
          |> case do
            typed_failure when map_size(typed_failure) > 0 ->
              %{
                error_type:
                  typed_failure
                  |> map_get(:error_type, "error_type")
                  |> normalize_optional_string() || "issue_triage_artifact_persistence_failed",
                detail:
                  typed_failure
                  |> map_get(:detail, "detail")
                  |> normalize_optional_string() || "Issue triage artifact persistence failed.",
                remediation:
                  typed_failure
                  |> map_get(:remediation, "remediation")
                  |> normalize_optional_string() || "Retry artifact persistence from run detail."
              }

            _other ->
              nil
          end

        response_post_failure =
          response_post_artifact
          |> map_get(:typed_failure, "typed_failure")
          |> normalize_map()
          |> case do
            typed_failure when map_size(typed_failure) > 0 ->
              %{
                error_type:
                  typed_failure
                  |> map_get(:error_type, "error_type")
                  |> normalize_optional_string() || "issue_triage_response_post_failed",
                detail:
                  typed_failure
                  |> map_get(:detail, "detail")
                  |> normalize_optional_string() || "Issue response post failed.",
                remediation:
                  typed_failure
                  |> map_get(:remediation, "remediation")
                  |> normalize_optional_string() ||
                    "Retry issue response posting from run detail."
              }

            _other ->
              nil
          end

        %{
          classification:
            triage_artifact
            |> map_get(:classification, "classification")
            |> normalize_optional_string() || "unavailable",
          research_summary:
            research_artifact
            |> map_get(:summary, "summary")
            |> normalize_optional_string() || "Research summary is unavailable.",
          proposed_response:
            response_artifact
            |> map_get(:proposed_response, "proposed_response")
            |> normalize_optional_string() || "Proposed response draft is unavailable.",
          response_post_status:
            response_post_artifact
            |> map_get(:status, "status")
            |> normalize_optional_string() || "not_attempted",
          posted_comment_url:
            response_post_artifact
            |> map_get(:comment_url, "comment_url")
            |> normalize_optional_string(),
          posted_comment_id:
            response_post_artifact
            |> map_get(:comment_id, "comment_id")
            |> normalize_optional_integer(),
          response_posted_at:
            response_post_artifact
            |> map_get(
              :posted_at,
              "posted_at",
              map_get(response_post_artifact, :attempted_at, "attempted_at")
            )
            |> normalize_optional_string(),
          issue_reference:
            linked_run
            |> map_get(:issue_reference, "issue_reference")
            |> normalize_optional_string() ||
              run
              |> Map.get(:inputs, %{})
              |> map_get(:issue_reference, "issue_reference")
              |> normalize_optional_string(),
          source_issue_number:
            source_issue
            |> map_get(:number, "number")
            |> normalize_optional_integer(),
          linked_run_id:
            linked_run
            |> map_get(:run_id, "run_id")
            |> normalize_optional_string() ||
              run
              |> Map.get(:run_id)
              |> normalize_optional_string(),
          persistence_status:
            artifact_lineage
            |> map_get(:status, "status")
            |> normalize_optional_string() || "unknown",
          typed_failure: typed_failure,
          response_post_failure: response_post_failure
        }
      end
    else
      nil
    end
  end

  defp issue_triage_artifacts(_run), do: nil

  defp runtime_evidence_summary(run, evidence_records, %RepoPosture{} = repo_posture) do
    posture_metadata = normalize_map(repo_posture.posture_metadata)

    runtime_state =
      posture_metadata
      |> Map.get("runtime_service_evidence_state", posture_metadata["runtime_capability_state"] || %{})
      |> normalize_map()

    runtime_delivery_evidence =
      evidence_records
      |> List.wrap()
      |> Enum.find(&((Map.get(&1, :key) || Map.get(&1, "key")) == "runtime_service_delivery"))

    runtime_delivery =
      runtime_delivery_evidence
      |> map_get(:evidence_details, "evidence_details", %{})
      |> normalize_map()

    latest_invocation =
      runtime_state
      |> get_in(["integration_outcomes", "latest_invocation"])
      |> normalize_map()

    summary =
      posture_metadata["runtime_service_evidence_summary"] ||
        posture_metadata["runtime_capability_summary"] ||
        Map.get(runtime_delivery_evidence || %{}, :summary) ||
        Map.get(run, :summary)

    if is_binary(summary) and String.trim(summary) != "" do
      %{
        status:
          Map.get(runtime_state, "status") ||
            posture_metadata
            |> Map.get("runtime_capability_state", %{})
            |> normalize_map()
            |> Map.get("status") || "absent",
        summary: summary,
        delivery_mode:
          Map.get(runtime_delivery, "delivery_mode") ||
            get_in(runtime_state, ["runtime_delivery", "delivery_mode"]),
        reason_code:
          Map.get(runtime_delivery, "reason_code") ||
            get_in(runtime_state, ["runtime_delivery", "reason_code"]),
        integration_summary:
          Map.get(latest_invocation, "summary") ||
            case {Map.get(latest_invocation, "provider"), Map.get(latest_invocation, "operation_id")} do
              {provider, operation_id} when is_binary(provider) and is_binary(operation_id) ->
                "#{provider}:#{operation_id}"

              _other ->
                nil
            end
      }
    end
  end

  defp runtime_evidence_summary(_run, _evidence_records, _repo_posture), do: nil

  defp runtime_evidence_badge_class("blocked"), do: "badge badge-error"
  defp runtime_evidence_badge_class("degraded"), do: "badge badge-warning"
  defp runtime_evidence_badge_class("available"), do: "badge badge-success"
  defp runtime_evidence_badge_class(_status), do: "badge badge-outline"

  defp runtime_evidence_status_label(status) do
    case normalize_optional_string(status) do
      "blocked" -> "blocked"
      "degraded" -> "review required"
      "available" -> "stable"
      nil -> "unknown"
      other -> other
    end
  end

  defp humanize_runtime_value(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized -> normalized |> String.replace("_", " ")
    end
  end

  defp default_artifact_categories do
    Enum.map(@artifact_categories, fn category ->
      Map.put(category, :entries, [])
    end)
  end

  defp artifact_categories(%WorkflowRun{} = run) do
    step_results =
      run
      |> Map.get(:step_results, %{})
      |> normalize_map()

    artifact_nodes = collect_artifact_nodes(step_results)

    Enum.map(@artifact_categories, fn category ->
      entries =
        artifact_nodes
        |> Enum.filter(&artifact_matches_category?(&1, category.id))
        |> Enum.map(&artifact_entry(category.id, &1))
        |> Enum.uniq_by(& &1.source)
        |> Enum.sort_by(& &1.source)

      Map.put(category, :entries, entries)
    end)
  end

  defp artifact_categories(_run), do: default_artifact_categories()

  defp collect_artifact_nodes(%{} = value), do: collect_artifact_nodes(value, [])

  defp collect_artifact_nodes(%{} = value, path) when is_list(path) do
    Enum.flat_map(value, fn {key, nested_value} ->
      path_segment = artifact_path_segment(key)
      next_path = path ++ [path_segment]

      [%{path: next_path, value: nested_value} | collect_artifact_nodes(nested_value, next_path)]
    end)
  end

  defp collect_artifact_nodes(value, path) when is_list(value) and is_list(path) do
    value
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {nested_value, index} ->
      collect_artifact_nodes(nested_value, path ++ ["item_#{index}"])
    end)
  end

  defp collect_artifact_nodes(_value, _path), do: []

  defp artifact_matches_category?(artifact_node, category_id) when is_map(artifact_node) do
    artifact_key =
      artifact_node
      |> Map.get(:path, [])
      |> List.last()
      |> normalize_optional_string()
      |> case do
        nil -> ""
        value -> String.downcase(value)
      end

    artifact_value = Map.get(artifact_node, :value)

    case category_id do
      "logs" ->
        artifact_key in ["run_logs", "logs", "log", "stdout", "stderr"] or
          String.ends_with?(artifact_key, "_logs") or String.ends_with?(artifact_key, "_log")

      "diff_summaries" ->
        artifact_key == "diff_summary" or String.ends_with?(artifact_key, "_diff_summary")

      "reports" ->
        artifact_key == "report" or artifact_key == "failure_report" or
          String.ends_with?(artifact_key, "_report")

      "pr_metadata" ->
        artifact_key in ["pull_request", "pr_metadata", "pr"] or
          String.starts_with?(artifact_key, "pr_") or String.ends_with?(artifact_key, "_pr") or
          pr_metadata_map?(artifact_value)

      _other ->
        false
    end
  end

  defp artifact_matches_category?(_artifact_node, _category_id), do: false

  defp pr_metadata_map?(%{} = artifact_value) do
    artifact_value
    |> Map.keys()
    |> Enum.map(fn key ->
      key
      |> normalize_optional_string()
      |> case do
        nil -> nil
        value -> String.downcase(value)
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn key ->
      key in ["pr_url", "pr_number", "pr_title", "pull_request_url", "pull_request_number"]
    end)
  end

  defp pr_metadata_map?(_artifact_value), do: false

  defp artifact_entry(category_id, artifact_node)
       when is_binary(category_id) and is_map(artifact_node) do
    source_path =
      artifact_node
      |> Map.get(:path, [])
      |> Enum.map(&artifact_path_segment/1)
      |> Enum.join(".")

    artifact_value = Map.get(artifact_node, :value)

    %{
      identifier: artifact_identifier(category_id, source_path),
      source: source_path,
      summary: artifact_summary(artifact_value),
      payload: artifact_payload(artifact_value)
    }
  end

  defp artifact_entry(category_id, _artifact_node) do
    %{
      identifier: artifact_identifier(category_id, "artifact"),
      source: "artifact",
      summary: "Artifact payload unavailable.",
      payload: "Artifact payload unavailable."
    }
  end

  defp artifact_identifier(category_id, source_path)
       when is_binary(category_id) and is_binary(source_path) do
    [category_id, source_path]
    |> Enum.join("-")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "artifact"
      identifier -> identifier
    end
  end

  defp artifact_identifier(_category_id, _source_path), do: "artifact"

  defp artifact_summary(%{} = value), do: "Map artifact (#{map_size(value)} keys)"
  defp artifact_summary(value) when is_list(value), do: "List artifact (#{length(value)} items)"

  defp artifact_summary(value) when is_binary(value) do
    trimmed_value = String.trim(value)

    if String.length(trimmed_value) > 96 do
      String.slice(trimmed_value, 0, 96) <> "..."
    else
      trimmed_value
    end
  end

  defp artifact_summary(value), do: inspect(value)

  defp artifact_payload(value) do
    inspect(value, pretty: true, limit: :infinity, printable_limit: :infinity, width: 120)
  end

  defp artifact_path_segment(segment) do
    segment
    |> normalize_optional_string()
    |> case do
      nil -> inspect(segment)
      normalized_segment -> normalized_segment
    end
  end

  defp approval_context(%WorkflowRun{} = run) do
    step_results =
      run
      |> Map.get(:step_results, %{})
      |> normalize_map()

    context =
      step_results
      |> map_get(:approval_context, "approval_context")
      |> normalize_map()

    diff_summary =
      context
      |> map_get(:diff_summary, "diff_summary")
      |> normalize_optional_string()

    test_summary =
      context
      |> map_get(:test_summary, "test_summary")
      |> normalize_optional_string()

    risk_notes =
      context
      |> map_get(:risk_notes, "risk_notes")
      |> normalize_risk_notes()

    case {diff_summary, test_summary, risk_notes} do
      {nil, nil, []} ->
        nil

      _other ->
        %{
          diff_summary: diff_summary || "Diff summary unavailable.",
          test_summary: test_summary || "Test summary unavailable.",
          risk_notes:
            if(risk_notes == [],
              do: ["Risk notes unavailable. Review changes carefully before approving."],
              else: risk_notes
            )
        }
    end
  end

  defp approval_context(_run), do: nil

  defp approval_context_blocker(%WorkflowRun{} = run) do
    diagnostics =
      run
      |> Map.get(:error, %{})
      |> normalize_map()
      |> Map.get("approval_context_diagnostics", [])
      |> normalize_diagnostics()

    diagnostics
    |> List.last()
    |> normalize_approval_context_diagnostic()
  end

  defp approval_context_blocker(_run), do: nil

  defp retry_lineage_entries(%WorkflowRun{} = run) do
    run
    |> Map.get(:retry_lineage, [])
    |> normalize_retry_lineage_entries()
  end

  defp retry_lineage_entries(_run), do: []

  defp normalize_retry_lineage_entries(entries) when is_list(entries) do
    Enum.map(entries, fn entry ->
      typed_failure =
        entry
        |> map_get(:typed_failure, "typed_failure", %{})
        |> normalize_map()

      failure_artifacts =
        entry
        |> map_get(:failure_artifacts, "failure_artifacts", %{})
        |> normalize_map()

      %{
        run_id:
          entry
          |> map_get(:run_id, "run_id")
          |> normalize_optional_string() || "unknown",
        status:
          entry
          |> map_get(:status, "status")
          |> normalize_optional_string() || "unknown",
        retry_attempt:
          entry
          |> map_get(:retry_attempt, "retry_attempt")
          |> normalize_optional_integer() || 1,
        reason_type:
          typed_failure
          |> map_get(:reason_type, "reason_type")
          |> normalize_optional_string() || "unknown",
        detail:
          typed_failure
          |> map_get(:detail, "detail")
          |> normalize_optional_string() || "Prior failure details were not captured.",
        artifact_count: map_size(failure_artifacts)
      }
    end)
  end

  defp normalize_retry_lineage_entries(_entries), do: []

  defp step_retry_state(%WorkflowRun{} = run) do
    case WorkflowRun.step_retry_contract(run) do
      {:ok, step_retry_contract} ->
        %{
          available: true,
          retry_step:
            step_retry_contract
            |> map_get(:retry_step, "retry_step")
            |> normalize_optional_string(),
          guidance: nil
        }

      {:error, typed_failure} ->
        %{
          available: false,
          retry_step: nil,
          guidance: normalize_retry_action_failure(typed_failure)
        }
    end
  end

  defp step_retry_state(_run) do
    %{
      available: false,
      retry_step: nil,
      guidance: nil
    }
  end

  defp full_run_retry_available?(status) when is_atom(status), do: status in [:failed, :cancelled]

  defp full_run_retry_available?(status) when is_binary(status) do
    case String.trim(status) do
      "failed" -> true
      "cancelled" -> true
      _other -> false
    end
  end

  defp full_run_retry_available?(_status), do: false

  defp failed_status?(status) when is_atom(status), do: status == :failed

  defp failed_status?(status) when is_binary(status) do
    String.trim(status) == "failed"
  end

  defp failed_status?(_status), do: false

  defp awaiting_approval?(status) when is_atom(status), do: status == :awaiting_approval

  defp awaiting_approval?(status) when is_binary(status),
    do: String.trim(status) == "awaiting_approval"

  defp awaiting_approval?(_status), do: false

  defp normalize_timeline_entries(entries) when is_list(entries) do
    normalized_entries =
      Enum.map(entries, fn entry ->
        transitioned_at =
          entry
          |> map_get(:transitioned_at, "transitioned_at")
          |> normalize_transitioned_at_datetime()

        %{
          to_status:
            entry
            |> map_get(:to_status, "to_status")
            |> normalize_optional_string() || "unknown",
          current_step:
            entry
            |> map_get(:current_step, "current_step")
            |> normalize_optional_string() || "unknown",
          transitioned_at: format_transitioned_at(transitioned_at),
          transitioned_at_datetime: transitioned_at,
          approval_audit: normalize_timeline_approval_audit(entry)
        }
      end)

    next_entries = Enum.drop(normalized_entries, 1) ++ [nil]

    normalized_entries
    |> Enum.zip(next_entries)
    |> Enum.map(fn {entry, next_entry} ->
      duration =
        timeline_duration(
          Map.get(entry, :transitioned_at_datetime),
          next_entry && Map.get(next_entry, :transitioned_at_datetime)
        )

      entry
      |> Map.put(:duration, duration)
      |> Map.delete(:transitioned_at_datetime)
    end)
  end

  defp normalize_timeline_entries(_entries), do: []

  defp normalize_approval_context_diagnostic(%{} = diagnostic) do
    message =
      diagnostic
      |> map_get(:message, "message")
      |> normalize_optional_string()

    detail =
      diagnostic
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    remediation =
      diagnostic
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string()

    if is_nil(message) and is_nil(detail) and is_nil(remediation) do
      nil
    else
      %{
        message: message || "Approval context generation failed.",
        detail: detail || "Approval payload generation did not produce complete context.",
        remediation:
          remediation ||
            "Regenerate approval payload data with diff, test, and risk summaries before retrying."
      }
    end
  end

  defp normalize_approval_context_diagnostic(_diagnostic), do: nil

  defp normalize_approval_action_failure(typed_failure) when is_map(typed_failure) do
    error_type =
      typed_failure
      |> map_get(:error_type, "error_type")
      |> normalize_optional_string()

    detail =
      typed_failure
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    remediation =
      typed_failure
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string()

    %{
      error_type: error_type || "workflow_run_approval_action_failed",
      detail: detail || "Approval action failed and run remains blocked.",
      remediation: remediation || "Review run state and retry from run detail."
    }
  end

  defp normalize_approval_action_failure(_typed_failure) do
    %{
      error_type: "workflow_run_approval_action_failed",
      detail: "Approval action failed and run remains blocked.",
      remediation: "Review run state and retry from run detail."
    }
  end

  defp normalize_retry_action_failure(typed_failure) when is_map(typed_failure) do
    error_type =
      typed_failure
      |> map_get(:error_type, "error_type")
      |> normalize_optional_string()

    detail =
      typed_failure
      |> map_get(:detail, "detail")
      |> normalize_optional_string()

    remediation =
      typed_failure
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string()

    %{
      error_type: error_type || "workflow_run_retry_action_failed",
      detail: detail || "Retry action failed and no new attempt was created.",
      remediation: remediation || "Review workflow retry policy and retry from run detail."
    }
  end

  defp normalize_retry_action_failure(_typed_failure) do
    %{
      error_type: "workflow_run_retry_action_failed",
      detail: "Retry action failed and no new attempt was created.",
      remediation: "Review workflow retry policy and retry from run detail."
    }
  end

  defp status_label(status) do
    status
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized_status -> normalized_status
    end
  end

  defp current_step_label(current_step) do
    current_step
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized_step -> normalized_step
    end
  end

  defp normalize_transitioned_at_datetime(%DateTime{} = transitioned_at) do
    DateTime.truncate(transitioned_at, :second)
  end

  defp normalize_transitioned_at_datetime(transitioned_at) when is_binary(transitioned_at) do
    case DateTime.from_iso8601(transitioned_at) do
      {:ok, parsed_transitioned_at, _offset} -> DateTime.truncate(parsed_transitioned_at, :second)
      _other -> nil
    end
  end

  defp normalize_transitioned_at_datetime(_transitioned_at), do: nil

  defp format_transitioned_at(%DateTime{} = transitioned_at) do
    DateTime.to_iso8601(transitioned_at)
  end

  defp format_transitioned_at(transitioned_at) when is_binary(transitioned_at) do
    case DateTime.from_iso8601(transitioned_at) do
      {:ok, parsed_transitioned_at, _offset} -> DateTime.to_iso8601(parsed_transitioned_at)
      _other -> transitioned_at
    end
  end

  defp format_transitioned_at(_transitioned_at), do: "unknown"

  defp timeline_duration(%DateTime{} = started_at, %DateTime{} = completed_at) do
    case DateTime.diff(completed_at, started_at, :second) do
      seconds when is_integer(seconds) and seconds >= 0 ->
        format_duration_seconds(seconds)

      _other ->
        "unknown"
    end
  end

  defp timeline_duration(_started_at, _completed_at), do: "unknown"

  defp format_duration_seconds(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration_seconds(seconds) when seconds < 3_600 do
    "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  end

  defp format_duration_seconds(seconds) do
    hours = div(seconds, 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    remaining_seconds = rem(seconds, 60)

    "#{hours}h #{minutes}m #{remaining_seconds}s"
  end

  defp normalize_timeline_approval_audit(entry) when is_map(entry) do
    decision =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:decision, "decision")
      |> normalize_optional_string()

    actor =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:actor, "actor", %{})

    actor_id = actor |> map_get(:id, "id") |> normalize_optional_string()
    actor_email = actor |> map_get(:email, "email") |> normalize_optional_string()

    timestamp =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:timestamp, "timestamp")
      |> normalize_optional_string()

    rationale =
      entry
      |> map_get(:metadata, "metadata", %{})
      |> map_get(:approval_decision, "approval_decision", %{})
      |> map_get(:rationale, "rationale")
      |> normalize_optional_string()

    actor_label = actor_email || actor_id

    parts =
      [
        if(decision, do: "decision=#{decision}"),
        if(actor_label, do: "actor=#{actor_label}"),
        if(timestamp, do: "at=#{format_transitioned_at(timestamp)}"),
        if(rationale, do: "rationale=#{rationale}")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      audit_parts -> Enum.join(audit_parts, " ")
    end
  end

  defp normalize_timeline_approval_audit(_entry), do: nil

  defp approving_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        Actor.operator_actor(%{
          "id" => user |> Map.get(:id) |> normalize_optional_string() || "unknown",
          "email" => user |> Map.get(:email) |> normalize_optional_string()
        })

      _other ->
        Actor.operator_actor(%{"id" => "unknown", "email" => nil})
    end
  end

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp normalize_diagnostics(diagnostics) when is_list(diagnostics) do
    Enum.filter(diagnostics, &is_map/1)
  end

  defp normalize_diagnostics(_diagnostics), do: []

  defp normalize_risk_notes(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_risk_notes(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> []
      risk_note -> [risk_note]
    end
  end

  defp normalize_missing_failure_fields(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_missing_failure_fields(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_missing_failure_fields(_value), do: []

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

  defp normalize_optional_string(%Ash.CiString{} = value),
    do: value |> to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value

  defp normalize_optional_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp normalize_optional_integer(_value), do: nil
end
