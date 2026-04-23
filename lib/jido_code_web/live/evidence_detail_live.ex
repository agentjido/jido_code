defmodule JidoCodeWeb.EvidenceDetailLive do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  # covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
  use JidoCodeWeb, :live_view

  import JidoCodeWeb.GovernedMemoryHelpers

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.MemoryGraph.{FollowUpSurface, GovernedSurfaceContext, OperatorService, ProductService, SurfaceFeedback}
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.Run

  @surface_label "this governed evidence surface"

  @impl true
  def mount(%{"id" => project_id, "evidence_id" => evidence_id}, _session, socket) do
    socket =
      socket
      |> assign(:project_id, project_id)
      |> assign(:memory_action_feedback, nil)
      |> load_evidence_assigns(project_id, evidence_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("recover_memory_graph", _params, socket) do
    with %{managed_repo_id: managed_repo_id, workspace_path: workspace_path} <- socket.assigns.memory_context,
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id,
         workspace_path when is_binary(workspace_path) <- workspace_path do
      case ProductService.recover(managed_repo_id, workspace_path) do
        {:ok, _result} ->
          refreshed_socket = refresh_evidence_assigns(socket)

          {:noreply,
           assign(
             refreshed_socket,
             :memory_action_feedback,
             SurfaceFeedback.recovery_result(
               memory_context_graph(refreshed_socket),
               surface_label: @surface_label
             )
           )}

        {:error, reason, diagnostics} ->
          refreshed_socket = refresh_evidence_assigns(socket)

          {:noreply,
           assign(
             refreshed_socket,
             :memory_action_feedback,
             SurfaceFeedback.recovery_error(
               reason,
               diagnostics,
               graph: memory_context_graph(refreshed_socket),
               surface_label: @surface_label
             )
           )}
      end
    else
      _other ->
        refreshed_socket = refresh_evidence_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.recovery_error(
             :memory_governed_scope_unavailable,
             nil,
             graph: memory_context_graph(refreshed_socket),
             surface_label: @surface_label
           )
         )}
    end
  end

  @impl true
  def handle_event(
        "validate_memory",
        %{"memory_iri" => memory_iri},
        %{assigns: %{memory_context: %{surface: %{memories: projection}}}} = socket
      ) do
    case OperatorService.validate(projection, memory_iri, memory_operator_opts(socket)) do
      {:ok, _result} ->
        refreshed_socket = refresh_evidence_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.action_result(
             :validate,
             graph: memory_context_graph(refreshed_socket),
             surface_label: @surface_label
           )
         )}

      {:error, reason} ->
        {:noreply, assign_memory_action_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("validate_memory", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "invalidate_memory",
        %{"memory_iri" => memory_iri},
        %{assigns: %{memory_context: %{surface: %{memories: projection}}}} = socket
      ) do
    case OperatorService.invalidate(projection, memory_iri, memory_operator_opts(socket)) do
      {:ok, _result} ->
        refreshed_socket = refresh_evidence_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.action_result(
             :invalidate,
             graph: memory_context_graph(refreshed_socket),
             surface_label: @surface_label
           )
         )}

      {:error, reason} ->
        {:noreply, assign_memory_action_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("invalidate_memory", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "promote_memory_follow_up",
        %{"memory_iri" => memory_iri},
        %{assigns: %{memory_context: %{surface: %{memories: projection}}}} = socket
      ) do
    case OperatorService.promote_follow_up(projection, memory_iri, memory_operator_opts(socket)) do
      {:ok, %{result: %{work_item: work_item}, target: :work_item}} ->
        refreshed_socket = refresh_evidence_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.action_result(
             :promote_follow_up,
             graph: memory_context_graph(refreshed_socket),
             surface_label: @surface_label,
             work_item_id: work_item.id
           )
         )}

      {:error, reason} ->
        {:noreply, assign_memory_action_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("promote_memory_follow_up", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "supersede_memory",
        %{"memory_iri" => memory_iri, "decision_id" => decision_id},
        %{assigns: %{memory_context: %{surface: %{memories: projection}}, related_decisions: decisions}} = socket
      ) do
    case Enum.find(decisions, &(normalize_optional_string(map_get(&1, :id, "id")) == decision_id)) do
      %Decision{} = decision ->
        case OperatorService.supersede_with_governed_decision(
               projection,
               memory_iri,
               decision,
               memory_operator_opts(socket, decision_id: decision_id)
             ) do
          {:ok, _result} ->
            refreshed_socket = refresh_evidence_assigns(socket)

            {:noreply,
             assign(
               refreshed_socket,
               :memory_action_feedback,
               SurfaceFeedback.action_result(
                 :supersede_with_governed_decision,
                 graph: memory_context_graph(refreshed_socket),
                 surface_label: @surface_label
               )
             )}

          {:error, reason} ->
            {:noreply, assign_memory_action_error(socket, reason)}
        end

      _other ->
        {:noreply, assign_memory_action_error(socket, :governed_decision_not_found)}
    end
  end

  @impl true
  def handle_event("supersede_memory", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="mx-auto max-w-5xl space-y-6 py-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Governed evidence
            </p>
            <h1 :if={@evidence} id="evidence-detail-title" class="text-2xl font-semibold">
              {display_string(@evidence.summary, "Evidence detail")}
            </h1>
            <h1 :if={!@evidence} id="evidence-detail-missing-title" class="text-2xl font-semibold">
              Evidence not found
            </h1>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <.link
              :if={run_route(@route_repo_id, @run && @run.run_id)}
              navigate={run_route(@route_repo_id, @run && @run.run_id)}
              class="link link-primary text-sm"
            >
              Open related run
            </.link>
            <.link
              :if={repo_route(@route_repo_id)}
              navigate={repo_route(@route_repo_id)}
              class="link link-primary text-sm"
            >
              Back to repository
            </.link>
          </div>
        </div>

        <%= if @evidence do %>
          <section class="grid gap-4 rounded-xl border border-base-300 bg-base-100 p-6 md:grid-cols-2">
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">ID</p>
              <p id="evidence-detail-id" class="font-mono text-sm">{@evidence.id}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Key</p>
              <p id="evidence-detail-key" class="text-sm">{display_string(@evidence.key)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Type</p>
              <p id="evidence-detail-type" class="text-sm">{display_string(@evidence.evidence_type)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Source</p>
              <p id="evidence-detail-source" class="text-sm">{display_string(@evidence.source)}</p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Summary</p>
              <p id="evidence-detail-summary" class="text-sm">{display_string(@evidence.summary)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Run</p>
              <div class="space-y-1">
                <p id="evidence-detail-run-id" class="font-mono text-sm">
                  {display_string(@run && @run.run_id, "Unavailable")}
                </p>
                <.link
                  :if={run_route(@route_repo_id, @run && @run.run_id)}
                  id="evidence-detail-run-route"
                  navigate={run_route(@route_repo_id, @run && @run.run_id)}
                  class="link link-primary text-xs"
                >
                  Open run
                </.link>
              </div>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Work item</p>
              <div class="space-y-1">
                <p id="evidence-detail-work-item-id" class="font-mono text-sm">
                  {display_string(@work_item && @work_item.id, "Unattached")}
                </p>
                <.link
                  :if={work_item_route(@route_repo_id, @work_item && @work_item.id)}
                  id="evidence-detail-work-item-route"
                  navigate={work_item_route(@route_repo_id, @work_item && @work_item.id)}
                  class="link link-primary text-xs"
                >
                  Open work item
                </.link>
              </div>
            </div>
          </section>

          <section class="space-y-2 rounded-xl border border-base-300 bg-base-100 p-6">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <p class="text-sm font-medium">Related decisions</p>
              <p id="evidence-detail-related-decisions-count" class="text-xs text-base-content/70">
                Decisions: {length(@related_decisions)}
              </p>
            </div>

            <%= if @related_decisions == [] do %>
              <p id="evidence-detail-related-decisions-empty" class="text-sm text-base-content/70">
                No governed decisions are currently linked to this evidence run.
              </p>
            <% else %>
              <ol id="evidence-detail-related-decisions" class="space-y-2">
                <li
                  :for={{decision, index} <- Enum.with_index(@related_decisions, 1)}
                  id={"evidence-detail-related-decision-#{index}"}
                  class="rounded border border-base-300/50 bg-base-200/20 p-3"
                >
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div class="space-y-1">
                      <p id={"evidence-detail-related-decision-key-#{index}"} class="text-sm font-medium">
                        {display_string(decision.decision_key)}
                      </p>
                      <p id={"evidence-detail-related-decision-outcome-#{index}"} class="text-xs text-base-content/70">
                        Outcome: {display_atom(decision.decision)}
                      </p>
                    </div>
                    <.link
                      :if={decision_route(@route_repo_id, decision.id)}
                      id={"evidence-detail-related-decision-route-#{index}"}
                      navigate={decision_route(@route_repo_id, decision.id)}
                      class="link link-primary text-xs"
                    >
                      Open decision
                    </.link>
                  </div>
                </li>
              </ol>
            <% end %>
          </section>

          <section
            :if={@memory_context}
            id="evidence-detail-memory-context"
            class="space-y-3 rounded-xl border border-base-300 bg-base-100 p-6"
          >
            <div class="space-y-1">
              <p class="text-sm font-medium">Evidence memory context</p>
              <p id="evidence-detail-memory-context-state" class="text-xs text-base-content/70">
                Memory state: {Map.get(@memory_context.graph, :state, :unavailable)}
              </p>
              <.operator_state_notice
                :if={@memory_action_feedback}
                id="evidence-detail-memory-action-feedback"
                title="Evidence memory update"
                state={@memory_action_feedback}
                kind={memory_feedback_kind(@memory_action_feedback)}
                compact={true}
              />
              <.memory_status_notice
                :if={@memory_context.notice}
                id="evidence-detail-memory-context-notice"
                title="Evidence memory status"
                state={@memory_context.notice}
                kind={Map.get(@memory_context, :notice_kind, :warning)}
                recovery={Map.get(@memory_context, :recovery)}
                recover_event="recover_memory_graph"
                recover_id="evidence-detail-memory-recover"
              />
            </div>

            <%= if @memory_context.surface do %>
              <div class="space-y-3">
                <div class="rounded border border-base-300/50 bg-base-200/20 p-3">
                  <p id="evidence-detail-memory-surface-label" class="text-sm font-medium">
                    {@memory_context.surface.label}
                  </p>
                  <p id="evidence-detail-memory-surface-counts" class="text-xs text-base-content/70">
                    Memory: {@memory_context.surface.memory_count} | Provenance: {@memory_context.surface.provenance_count}
                  </p>
                </div>

                <section
                  :if={@memory_follow_up_preview && @memory_follow_up_preview.available?}
                  id="evidence-detail-memory-follow-up-preview"
                  class="space-y-2 rounded border border-base-300/50 bg-base-200/20 p-3"
                >
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Memory-aware follow-up
                  </p>
                  <p id="evidence-detail-memory-follow-up-preview-summary" class="text-sm font-medium">
                    {@memory_follow_up_preview.summary}
                  </p>
                  <p id="evidence-detail-memory-follow-up-preview-metadata" class="text-xs text-base-content/70">
                    Recommended action: {@memory_follow_up_preview.recommended_action_label} | Priority: {@memory_follow_up_preview.priority} | Urgency: {@memory_follow_up_preview.urgency}
                  </p>
                  <p id="evidence-detail-memory-follow-up-preview-kinds" class="text-xs text-base-content/70">
                    Selected memory kinds: {Enum.join(@memory_follow_up_preview.memory_kinds, ", ")}
                  </p>
                  <.link
                    :if={@memory_follow_up_preview.route}
                    id="evidence-detail-memory-follow-up-preview-route"
                    navigate={@memory_follow_up_preview.route}
                    class="link link-primary text-xs"
                  >
                    {@memory_follow_up_preview.route_label}
                  </.link>
                </section>

                <section class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Durable memories
                  </p>

                  <%= if @memory_context.surface.memories.items == [] do %>
                    <p id="evidence-detail-memory-empty" class="text-xs text-base-content/70">
                      No durable memories currently point at this evidence record.
                    </p>
                  <% else %>
                    <ol id="evidence-detail-memory-list" class="space-y-2">
                      <li
                        :for={{item, index} <- Enum.with_index(@memory_context.surface.memories.items, 1)}
                        id={"evidence-detail-memory-item-#{index}"}
                        class="rounded border border-base-300/50 bg-base-200/20 p-3 space-y-2"
                      >
                        <p class="text-sm font-medium">
                          {memory_item_kind(item)}: {memory_item_content(item)}
                        </p>
                        <p class="text-xs text-base-content/70">
                          Freshness: {memory_item_freshness(item)} | Decision status: {memory_item_decision_status(item)}
                        </p>
                        <div class="flex flex-wrap gap-2">
                          <button
                            type="button"
                            id={"evidence-detail-memory-validate-#{index}"}
                            phx-click="validate_memory"
                            phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                            class="btn btn-xs btn-outline"
                          >
                            Validate
                          </button>
                          <button
                            type="button"
                            id={"evidence-detail-memory-invalidate-#{index}"}
                            phx-click="invalidate_memory"
                            phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                            class="btn btn-xs btn-outline"
                          >
                            Invalidate
                          </button>
                          <button
                            type="button"
                            id={"evidence-detail-memory-promote-#{index}"}
                            phx-click="promote_memory_follow_up"
                            phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                            class="btn btn-xs btn-outline"
                          >
                            Create follow-up
                          </button>
                        </div>
                        <.memory_link_groups dom_prefix={"evidence-detail-memory-#{index}"} item={item} />
                      </li>
                    </ol>
                  <% end %>
                </section>

                <button
                  :if={decision_memory_iri(@memory_context.surface.memories.items) && latest_record(@related_decisions)}
                  type="button"
                  id={"evidence-detail-memory-supersede-#{map_get(latest_record(@related_decisions), :id, "id")}"}
                  phx-click="supersede_memory"
                  phx-value-memory_iri={decision_memory_iri(@memory_context.surface.memories.items)}
                  phx-value-decision_id={map_get(latest_record(@related_decisions), :id, "id")}
                  class="btn btn-xs btn-outline"
                >
                  Supersede with latest decision
                </button>

                <section class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Workflow provenance
                  </p>

                  <%= if @memory_context.surface.provenance.items == [] do %>
                    <p id="evidence-detail-memory-provenance-empty" class="text-xs text-base-content/70">
                      No workflow provenance currently points at this evidence record.
                    </p>
                  <% else %>
                    <ol id="evidence-detail-memory-provenance-list" class="space-y-2">
                      <li
                        :for={{item, index} <- Enum.with_index(@memory_context.surface.provenance.items, 1)}
                        id={"evidence-detail-memory-provenance-item-#{index}"}
                        class="rounded border border-base-300/50 bg-base-200/20 p-3 space-y-1"
                      >
                        <p class="text-sm font-medium">
                          {provenance_item_kind(item)}: {provenance_item_label(item)}
                        </p>
                        <p class="text-xs text-base-content/70">
                          Revision: {provenance_item_revision(item)}
                        </p>
                        <.memory_link_groups dom_prefix={"evidence-detail-memory-provenance-#{index}"} item={item} />
                      </li>
                    </ol>
                  <% end %>
                </section>
              </div>
            <% end %>
          </section>
        <% else %>
          <section class="rounded-xl border border-warning/40 bg-warning/10 p-6">
            <p id="evidence-detail-missing-detail" class="text-sm text-base-content/80">
              No governed evidence with id <span class="font-mono">{@evidence_id}</span> is available on this managed-repository route.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_evidence_assigns(socket, project_id, evidence_id) do
    case load_evidence_state(project_id, evidence_id) do
      {:ok, state} -> assign_evidence_state(socket, state)
      {:error, :not_found} -> assign_missing_evidence(socket, project_id, evidence_id)
    end
  end

  defp refresh_evidence_assigns(socket) do
    load_evidence_assigns(socket, socket.assigns.project_id, socket.assigns.evidence_id)
  end

  defp load_evidence_state(project_id, evidence_id) do
    with {:ok, scope} <- RepoBridge.repo_scope(project_id),
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id(scope),
         {:ok, [%Evidence{} = evidence]} <-
           Evidence.read(
             query: [filter: [id: evidence_id, managed_repo_id: managed_repo_id], limit: 1],
             actor: Actor.operator_actor()
           ) do
      route_repo_id = route_repo_id(scope) || managed_repo_id
      run = load_related_run(managed_repo_id, evidence.run_id)
      work_item = load_related_work_item(managed_repo_id, evidence.work_item_id)

      memory_context =
        GovernedSurfaceContext.load_governed_detail(
          scope,
          :evidence,
          evidence,
          managed_repo_id: managed_repo_id,
          workspace_path: load_repo_workspace_path(scope),
          current_route: evidence_route(route_repo_id, evidence.id)
        )

      {:ok,
       %{
         project_id: project_id,
         scope: scope,
         evidence: evidence,
         run: run,
         work_item: work_item,
         related_decisions: load_related_decisions(managed_repo_id, evidence.run_id),
         memory_context: memory_context,
         memory_follow_up_preview:
           load_memory_follow_up_preview(memory_context, route_repo_id, evidence)
       }}
    else
      _other -> {:error, :not_found}
    end
  end

  defp assign_evidence_state(socket, state) do
    socket
    |> assign(:project_id, state.project_id)
    |> assign(:evidence, state.evidence)
    |> assign(:evidence_id, state.evidence.id)
    |> assign(:managed_repo_id, managed_repo_id(state.scope))
    |> assign(:route_repo_id, route_repo_id(state.scope) || managed_repo_id(state.scope))
    |> assign(:run, state.run)
    |> assign(:work_item, state.work_item)
    |> assign(:related_decisions, state.related_decisions)
    |> assign(:memory_context, state.memory_context)
    |> assign(:memory_follow_up_preview, state.memory_follow_up_preview)
  end

  defp assign_missing_evidence(socket, project_id, evidence_id) do
    socket
    |> assign(:project_id, project_id)
    |> assign(:evidence, nil)
    |> assign(:evidence_id, evidence_id)
    |> assign(:managed_repo_id, nil)
    |> assign(:route_repo_id, normalize_optional_string(project_id))
    |> assign(:run, nil)
    |> assign(:work_item, nil)
    |> assign(:related_decisions, [])
    |> assign(:memory_context, nil)
    |> assign(:memory_follow_up_preview, nil)
  end

  defp load_related_run(managed_repo_id, run_internal_id) do
    case Run.read(
           query: [filter: [id: run_internal_id, managed_repo_id: managed_repo_id], limit: 1],
           actor: Actor.operator_actor()
         ) do
      {:ok, [%Run{} = run]} -> run
      _other -> nil
    end
  end

  defp load_related_work_item(_managed_repo_id, nil), do: nil

  defp load_related_work_item(managed_repo_id, work_item_id) do
    case WorkItem.read(
           query: [filter: [id: work_item_id, managed_repo_id: managed_repo_id], limit: 1],
           actor: Actor.operator_actor()
         ) do
      {:ok, [%WorkItem{} = work_item]} -> work_item
      _other -> nil
    end
  end

  defp load_related_decisions(managed_repo_id, run_internal_id) do
    case Decision.read(
           query: [filter: [managed_repo_id: managed_repo_id, run_id: run_internal_id], sort: [decided_at: :desc]],
           actor: Actor.operator_actor()
         ) do
      {:ok, decisions} -> decisions
      _other -> []
    end
  end

  defp load_memory_follow_up_preview(%{surface: %{memories: projection}}, route_repo_id, %Evidence{} = evidence) do
    FollowUpSurface.preview(
      projection,
      route: evidence_memory_route(route_repo_id, evidence.id),
      category: "governed_follow_up"
    )
  end

  defp load_memory_follow_up_preview(_memory_context, _route_repo_id, _evidence), do: nil

  defp assign_memory_action_error(socket, reason) do
    refreshed_socket = refresh_evidence_assigns(socket)

    assign(
      refreshed_socket,
      :memory_action_feedback,
      SurfaceFeedback.action_error(
        reason,
        graph: memory_context_graph(refreshed_socket),
        surface_label: @surface_label
      )
    )
  end

  defp memory_operator_opts(socket, extra_opts \\ []) do
    memory_operator_base_opts(
      socket,
      run_id: socket.assigns.run && socket.assigns.run.run_id,
      work_item_id: socket.assigns.work_item && socket.assigns.work_item.id,
      evidence_id: socket.assigns.evidence && socket.assigns.evidence.id
    ) ++ extra_opts
  end

  defp evidence_memory_route(repo_id, evidence_id) do
    memory_anchor_route(evidence_route(repo_id, evidence_id), "#evidence-detail-memory-context")
  end
end
