defmodule JidoCodeWeb.WorkItemDetailLive do
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
  alias JidoCode.Governance.Decision
  alias JidoCode.MemoryGraph.{FollowUpSurface, GovernedSurfaceContext, OperatorService, ProductService, SurfaceFeedback}
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.Run

  @surface_label "this governed work-item surface"

  @impl true
  def mount(%{"id" => project_id, "work_item_id" => work_item_id}, _session, socket) do
    socket =
      socket
      |> assign(:project_id, project_id)
      |> assign(:memory_action_feedback, nil)
      |> load_work_item_assigns(project_id, work_item_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("recover_memory_graph", _params, socket) do
    with %{managed_repo_id: managed_repo_id, workspace_path: workspace_path} <- socket.assigns.memory_context,
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id,
         workspace_path when is_binary(workspace_path) <- workspace_path do
      case ProductService.recover(managed_repo_id, workspace_path) do
        {:ok, _result} ->
          refreshed_socket = refresh_work_item_assigns(socket)

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
          refreshed_socket = refresh_work_item_assigns(socket)

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
        refreshed_socket = refresh_work_item_assigns(socket)

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
        refreshed_socket = refresh_work_item_assigns(socket)

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
        refreshed_socket = refresh_work_item_assigns(socket)

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
        refreshed_socket = refresh_work_item_assigns(socket)

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
        %{assigns: %{memory_context: %{surface: %{memories: projection}}, decisions: decisions}} = socket
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
            refreshed_socket = refresh_work_item_assigns(socket)

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
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      operator_navigation={JidoCodeWeb.OperatorNavigation.from_view(__MODULE__, assigns)}
    >
      <section class="mx-auto max-w-5xl space-y-6 py-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Governed work item
            </p>
            <h1 :if={@work_item} id="work-item-detail-title" class="text-2xl font-semibold">
              {display_string(@work_item.summary, "Work item detail")}
            </h1>
            <h1 :if={!@work_item} id="work-item-detail-missing-title" class="text-2xl font-semibold">
              Work item not found
            </h1>
          </div>

          <.link
            :if={repo_route(@route_repo_id)}
            navigate={repo_route(@route_repo_id)}
            class="link link-primary text-sm"
          >
            Back to repository
          </.link>
        </div>

        <%= if @work_item do %>
          <section class="grid gap-4 rounded-xl border border-base-300 bg-base-100 p-6 md:grid-cols-2">
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">ID</p>
              <p id="work-item-detail-id" class="font-mono text-sm">{@work_item.id}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Status</p>
              <p id="work-item-detail-status" class="text-sm">{display_atom(@work_item.status)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Priority</p>
              <p id="work-item-detail-priority" class="text-sm">{display_atom(@work_item.priority)}</p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Category</p>
              <p id="work-item-detail-category" class="text-sm">{display_string(@work_item.category)}</p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Summary</p>
              <p id="work-item-detail-summary" class="text-sm">{display_string(@work_item.summary)}</p>
            </div>

            <div class="space-y-1 md:col-span-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Recommended action
              </p>
              <p id="work-item-detail-recommended-action" class="text-sm">
                {display_string(@work_item.recommended_action)}
              </p>
            </div>

            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Managed repo
              </p>
              <p id="work-item-detail-managed-repo" class="font-mono text-sm">
                {display_string(@managed_repo_id)}
              </p>
            </div>
          </section>

          <section class="space-y-2 rounded-xl border border-base-300 bg-base-100 p-6">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <p class="text-sm font-medium">Governed run history</p>
              <p id="work-item-detail-run-history-count" class="text-xs text-base-content/70">
                Linked runs: {length(@related_runs)}
              </p>
            </div>

            <%= if @related_runs == [] do %>
              <p id="work-item-detail-run-history-empty" class="text-sm text-base-content/70">
                No governed runs are currently linked to this work item.
              </p>
            <% else %>
              <ol id="work-item-detail-run-history" class="space-y-2">
                <li
                  :for={{run, index} <- Enum.with_index(@related_runs, 1)}
                  id={"work-item-detail-run-entry-#{index}"}
                  class="rounded border border-base-300/50 bg-base-200/20 p-3"
                >
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div class="space-y-1">
                      <p id={"work-item-detail-run-id-#{index}"} class="text-sm font-medium">
                        {display_string(map_get(run, :run_id, "run_id"))}
                      </p>
                      <p id={"work-item-detail-run-status-#{index}"} class="text-xs text-base-content/70">
                        Status: {display_atom(map_get(run, :status, "status"))}
                      </p>
                    </div>
                    <.link
                      :if={run_route(@route_repo_id, map_get(run, :run_id, "run_id"))}
                      id={"work-item-detail-run-route-#{index}"}
                      navigate={run_route(@route_repo_id, map_get(run, :run_id, "run_id"))}
                      class="link link-primary text-xs"
                    >
                      Open run
                    </.link>
                  </div>
                </li>
              </ol>
            <% end %>
          </section>

          <section
            :if={@memory_context}
            id="work-item-detail-memory-context"
            class="space-y-3 rounded-xl border border-base-300 bg-base-100 p-6"
          >
            <div class="space-y-1">
              <p class="text-sm font-medium">Work item memory context</p>
              <p id="work-item-detail-memory-context-state" class="text-xs text-base-content/70">
                Memory state: {Map.get(@memory_context.graph, :state, :unavailable)}
              </p>
              <.operator_state_notice
                :if={@memory_action_feedback}
                id="work-item-detail-memory-action-feedback"
                title="Work item memory update"
                state={@memory_action_feedback}
                kind={memory_feedback_kind(@memory_action_feedback)}
                compact={true}
              />
              <.memory_status_notice
                :if={@memory_context.notice}
                id="work-item-detail-memory-context-notice"
                title="Work item memory status"
                state={@memory_context.notice}
                kind={Map.get(@memory_context, :notice_kind, :warning)}
                recovery={Map.get(@memory_context, :recovery)}
                recover_event="recover_memory_graph"
                recover_id="work-item-detail-memory-recover"
              />
            </div>

            <%= if @memory_context.surface do %>
              <div class="space-y-3">
                <div class="rounded border border-base-300/50 bg-base-200/20 p-3">
                  <p id="work-item-detail-memory-surface-label" class="text-sm font-medium">
                    {@memory_context.surface.label}
                  </p>
                  <p id="work-item-detail-memory-surface-counts" class="text-xs text-base-content/70">
                    Memory: {@memory_context.surface.memory_count} | Provenance: {@memory_context.surface.provenance_count}
                  </p>
                </div>

                <section
                  :if={@memory_follow_up_preview && @memory_follow_up_preview.available?}
                  id="work-item-detail-memory-follow-up-preview"
                  class="space-y-2 rounded border border-base-300/50 bg-base-200/20 p-3"
                >
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Memory-aware follow-up
                  </p>
                  <p id="work-item-detail-memory-follow-up-preview-summary" class="text-sm font-medium">
                    {@memory_follow_up_preview.summary}
                  </p>
                  <p id="work-item-detail-memory-follow-up-preview-metadata" class="text-xs text-base-content/70">
                    Recommended action: {@memory_follow_up_preview.recommended_action_label} | Priority: {@memory_follow_up_preview.priority} | Urgency: {@memory_follow_up_preview.urgency}
                  </p>
                  <p id="work-item-detail-memory-follow-up-preview-kinds" class="text-xs text-base-content/70">
                    Selected memory kinds: {Enum.join(@memory_follow_up_preview.memory_kinds, ", ")}
                  </p>
                  <.link
                    :if={@memory_follow_up_preview.route}
                    id="work-item-detail-memory-follow-up-preview-route"
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
                    <p id="work-item-detail-memory-empty" class="text-xs text-base-content/70">
                      No durable memories currently point at this work item.
                    </p>
                  <% else %>
                    <ol id="work-item-detail-memory-list" class="space-y-2">
                      <li
                        :for={{item, index} <- Enum.with_index(@memory_context.surface.memories.items, 1)}
                        id={"work-item-detail-memory-item-#{index}"}
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
                            id={"work-item-detail-memory-validate-#{index}"}
                            phx-click="validate_memory"
                            phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                            class="btn btn-xs btn-outline"
                          >
                            Validate
                          </button>
                          <button
                            type="button"
                            id={"work-item-detail-memory-invalidate-#{index}"}
                            phx-click="invalidate_memory"
                            phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                            class="btn btn-xs btn-outline"
                          >
                            Invalidate
                          </button>
                          <button
                            type="button"
                            id={"work-item-detail-memory-promote-#{index}"}
                            phx-click="promote_memory_follow_up"
                            phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                            class="btn btn-xs btn-outline"
                          >
                            Create follow-up
                          </button>
                        </div>
                        <.memory_link_groups dom_prefix={"work-item-detail-memory-#{index}"} item={item} />
                      </li>
                    </ol>
                  <% end %>
                </section>

                <button
                  :if={decision_memory_iri(@memory_context.surface.memories.items) && latest_record(@decisions)}
                  type="button"
                  id={"work-item-detail-memory-supersede-#{map_get(latest_record(@decisions), :id, "id")}"}
                  phx-click="supersede_memory"
                  phx-value-memory_iri={decision_memory_iri(@memory_context.surface.memories.items)}
                  phx-value-decision_id={map_get(latest_record(@decisions), :id, "id")}
                  class="btn btn-xs btn-outline"
                >
                  Supersede with latest decision
                </button>

                <section class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Workflow provenance
                  </p>

                  <%= if @memory_context.surface.provenance.items == [] do %>
                    <p id="work-item-detail-memory-provenance-empty" class="text-xs text-base-content/70">
                      No workflow provenance currently points at this work item.
                    </p>
                  <% else %>
                    <ol id="work-item-detail-memory-provenance-list" class="space-y-2">
                      <li
                        :for={{item, index} <- Enum.with_index(@memory_context.surface.provenance.items, 1)}
                        id={"work-item-detail-memory-provenance-item-#{index}"}
                        class="rounded border border-base-300/50 bg-base-200/20 p-3 space-y-1"
                      >
                        <p class="text-sm font-medium">
                          {provenance_item_kind(item)}: {provenance_item_label(item)}
                        </p>
                        <p class="text-xs text-base-content/70">
                          Revision: {provenance_item_revision(item)}
                        </p>
                        <.memory_link_groups dom_prefix={"work-item-detail-memory-provenance-#{index}"} item={item} />
                      </li>
                    </ol>
                  <% end %>
                </section>
              </div>
            <% end %>
          </section>
        <% else %>
          <section class="rounded-xl border border-warning/40 bg-warning/10 p-6">
            <p id="work-item-detail-missing-detail" class="text-sm text-base-content/80">
              No governed work item with id <span class="font-mono">{@work_item_id}</span>
              is available on this managed-repository route.
            </p>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_work_item_assigns(socket, project_id, work_item_id) do
    case load_work_item_state(project_id, work_item_id) do
      {:ok, state} -> assign_work_item_state(socket, state)
      {:error, :not_found} -> assign_missing_work_item(socket, project_id, work_item_id)
    end
  end

  defp refresh_work_item_assigns(socket) do
    load_work_item_assigns(socket, socket.assigns.project_id, socket.assigns.work_item_id)
  end

  defp load_work_item_state(project_id, work_item_id) do
    with {:ok, scope} <- RepoBridge.repo_scope(project_id),
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id(scope),
         {:ok, [%WorkItem{} = work_item]} <-
           WorkItem.read(
             query: [filter: [id: work_item_id, managed_repo_id: managed_repo_id], limit: 1],
             actor: Actor.operator_actor()
           ) do
      route_repo_id = route_repo_id(scope) || managed_repo_id
      workspace_path = load_repo_workspace_path(scope)

      memory_context =
        GovernedSurfaceContext.load_governed_detail(
          scope,
          :work_item,
          work_item,
          managed_repo_id: managed_repo_id,
          workspace_path: workspace_path,
          current_route: work_item_route(route_repo_id, work_item.id)
        )

      {:ok,
       %{
         project_id: project_id,
         scope: scope,
         work_item: work_item,
         related_runs: load_related_runs(managed_repo_id, work_item.id),
         decisions: load_related_decisions(managed_repo_id, work_item.id),
         memory_context: memory_context,
         memory_follow_up_preview: load_memory_follow_up_preview(memory_context, route_repo_id, work_item)
       }}
    else
      _other -> {:error, :not_found}
    end
  end

  defp assign_work_item_state(socket, state) do
    socket
    |> assign(:project_id, state.project_id)
    |> assign(:work_item, state.work_item)
    |> assign(:work_item_id, state.work_item.id)
    |> assign(:managed_repo_id, managed_repo_id(state.scope))
    |> assign(:route_repo_id, route_repo_id(state.scope) || managed_repo_id(state.scope))
    |> assign(:related_runs, state.related_runs)
    |> assign(:decisions, state.decisions)
    |> assign(:memory_context, state.memory_context)
    |> assign(:memory_follow_up_preview, state.memory_follow_up_preview)
  end

  defp assign_missing_work_item(socket, project_id, work_item_id) do
    socket
    |> assign(:project_id, project_id)
    |> assign(:work_item, nil)
    |> assign(:work_item_id, work_item_id)
    |> assign(:managed_repo_id, nil)
    |> assign(:route_repo_id, normalize_optional_string(project_id))
    |> assign(:related_runs, [])
    |> assign(:decisions, [])
    |> assign(:memory_context, nil)
    |> assign(:memory_follow_up_preview, nil)
  end

  defp load_related_runs(managed_repo_id, work_item_id) do
    case Run.read(
           query: [filter: [managed_repo_id: managed_repo_id, work_item_id: work_item_id], sort: [started_at: :desc]],
           actor: Actor.operator_actor()
         ) do
      {:ok, runs} -> runs
      _other -> []
    end
  end

  defp load_related_decisions(managed_repo_id, work_item_id) do
    case Decision.read(
           query: [filter: [managed_repo_id: managed_repo_id, work_item_id: work_item_id], sort: [decided_at: :desc]],
           actor: Actor.operator_actor()
         ) do
      {:ok, decisions} -> decisions
      _other -> []
    end
  end

  defp load_memory_follow_up_preview(%{surface: %{memories: projection}}, route_repo_id, %WorkItem{} = work_item) do
    FollowUpSurface.preview(
      projection,
      route: work_item_memory_route(route_repo_id, work_item.id),
      category: "governed_follow_up"
    )
  end

  defp load_memory_follow_up_preview(_memory_context, _route_repo_id, _work_item), do: nil

  defp assign_memory_action_error(socket, reason) do
    refreshed_socket = refresh_work_item_assigns(socket)

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
      work_item_id: socket.assigns.work_item && socket.assigns.work_item.id
    ) ++ extra_opts
  end

  defp work_item_memory_route(repo_id, work_item_id) do
    memory_anchor_route(work_item_route(repo_id, work_item_id), "#work-item-detail-memory-context")
  end
end
