defmodule JidoCodeWeb.ProjectDetailLive do
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  # covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  alias JidoCode.Conversations.PubSub, as: ConversationPubSub
  alias JidoCode.Workbench.ProjectDetail
  alias JidoCode.Workbench.ProjectConversation
  alias JidoCode.Workbench.ProjectMemoryInspection
  alias JidoCode.Workbench.ProjectSemanticInspection
  alias JidoCode.Workbench.ProjectDetailWorkflowKickoff

  @conversation_degraded_mode_message "Live conversation stream unavailable. Showing the latest repository conversation snapshot only."

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:project_detail, nil)
     |> assign(:project_load_error, nil)
     |> assign(:semantic_inspection, nil)
     |> assign(:semantic_action_feedback, nil)
     |> assign(:memory_inspection, nil)
     |> assign(:memory_action_feedback, nil)
     |> assign(:conversation_surface, empty_conversation_surface())
     |> assign(:conversation_snapshot, nil)
     |> assign(:conversation_events, [])
     |> assign(:conversation_last_event_sequence, 0)
     |> assign(:conversation_input, "")
     |> assign(:conversation_action_feedback, nil)
     |> assign(:conversation_action_feedback_kind, :info)
     |> assign(:conversation_stream_mode, :idle)
     |> assign(:conversation_stream_degraded_reason, nil)
     |> assign(:conversation_stream_discontinuity_count, 0)
     |> assign(:conversation_degraded_mode_message, @conversation_degraded_mode_message)
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, "/workbench")
     |> assign(:supported_workflows, ProjectDetailWorkflowKickoff.supported_workflows())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = Map.get(params, "id")
    return_to_path = normalize_return_to_path(Map.get(params, "return_to"))

    socket =
      socket
      |> maybe_unsubscribe_conversation()
      |> case do
        socket ->
          case ProjectDetail.load(project_id) do
            {:ok, project_detail} ->
              socket
              |> assign(:project_detail, project_detail)
              |> assign(:project_load_error, nil)
              |> assign(:semantic_inspection, ProjectSemanticInspection.load_repo_detail(project_detail))
              |> assign(:semantic_action_feedback, nil)
              |> assign(:memory_inspection, ProjectMemoryInspection.load_repo_detail(project_detail))
              |> assign(:memory_action_feedback, nil)
              |> assign(:conversation_action_feedback, nil)
              |> assign(:conversation_action_feedback_kind, :info)
              |> assign_project_conversation(project_detail)

            {:error, project_load_error} ->
              socket
              |> assign(:project_detail, nil)
              |> assign(:project_load_error, project_load_error)
              |> assign(:semantic_inspection, nil)
              |> assign(:semantic_action_feedback, nil)
              |> assign(:memory_inspection, nil)
              |> assign(:memory_action_feedback, nil)
              |> clear_project_conversation()
          end
      end

    {:noreply,
     socket
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, return_to_path)}
  end

  @impl true
  def handle_event("kickoff_workflow", %{"workflow_name" => workflow_name}, socket) do
    workflow_key = normalize_workflow_name(workflow_name)

    kickoff_result =
      ProjectDetailWorkflowKickoff.kickoff(
        socket.assigns.project_detail,
        workflow_name,
        initiating_actor(socket)
      )

    {:noreply, put_workflow_launch_state(socket, workflow_key, kickoff_result)}
  end

  @impl true
  def handle_event("recover_semantic_graph", _params, socket) do
    project_detail = Map.get(socket.assigns, :project_detail)

    case ProjectSemanticInspection.recover(project_detail) do
      {:ok, %{inspection: inspection, feedback: feedback}} ->
        {:noreply,
         socket
         |> assign(:semantic_inspection, inspection)
         |> assign(:semantic_action_feedback, feedback)}

      {:error, %{inspection: inspection, feedback: feedback}} ->
        {:noreply,
         socket
         |> assign(:semantic_inspection, inspection)
         |> assign(:semantic_action_feedback, feedback)}
    end
  end

  @impl true
  def handle_event("recover_memory_graph", _params, socket) do
    project_detail = Map.get(socket.assigns, :project_detail)

    case ProjectMemoryInspection.recover(project_detail) do
      {:ok, %{inspection: inspection, feedback: feedback}} ->
        {:noreply,
         socket
         |> assign(:memory_inspection, inspection)
         |> assign(:memory_action_feedback, feedback)}

      {:error, %{inspection: inspection, feedback: feedback}} ->
        {:noreply,
         socket
         |> assign(:memory_inspection, inspection)
         |> assign(:memory_action_feedback, feedback)}
    end
  end

  @impl true
  def handle_event("open_repo_conversation", _params, socket) do
    case ProjectConversation.open_repo_detail(
           socket.assigns.project_detail,
           actor: initiating_actor(socket)
         ) do
      {:ok, %{conversation: conversation, snapshot: snapshot}} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, nil)
         |> assign(:conversation_action_feedback_kind, :info)
         |> assign(:conversation_input, "")
         |> assign_opened_conversation(conversation, snapshot)
         |> maybe_subscribe_conversation()}

      {:error, notice} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, notice)
         |> assign(:conversation_action_feedback_kind, :error)}
    end
  end

  def handle_event("update_conversation_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, :conversation_input, value)}
  end

  def handle_event("send_conversation", params, socket) do
    input =
      params
      |> Map.get("input", socket.assigns.conversation_input)
      |> normalize_optional_string()
      |> Kernel.||("")

    conversation_id = conversation_id(socket)

    cond do
      input == "" ->
        {:noreply, socket}

      not is_binary(conversation_id) ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, %{
           error_type: "project_detail_conversation_missing",
           detail: "Open a repository conversation before submitting work.",
           remediation: "Use the repository conversation action above and then retry the request."
         })
         |> assign(:conversation_action_feedback_kind, :error)}

      socket.assigns.conversation_snapshot &&
          socket.assigns.conversation_snapshot.status == :paused ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, %{
           error_type: "project_detail_conversation_paused",
           detail: "Resume the repository conversation before submitting new work.",
           remediation: "Use the Resume control and then retry the request."
         })
         |> assign(:conversation_action_feedback_kind, :error)}

      true ->
        case JidoCode.AgentWorkspace.handle_conversation_command(
               conversation_id,
               conversation_input_command(socket, input),
               actor: initiating_actor(socket)
             ) do
          {:ok, snapshot} ->
            {:noreply,
             socket
             |> assign(:conversation_input, "")
             |> assign(:conversation_action_feedback, nil)
             |> assign(:conversation_action_feedback_kind, :info)
             |> assign_conversation_snapshot(snapshot)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:conversation_action_feedback, %{
               error_type: "project_detail_conversation_submit_failed",
               detail: "Repository conversation work could not be submitted (#{inspect(reason)}).",
               remediation: "Retry the request or reopen the repository conversation if the prior turn cannot continue."
             })
             |> assign(:conversation_action_feedback_kind, :error)}
        end
    end
  end

  def handle_event("pause_conversation", _params, socket) do
    dispatch_conversation_control(socket, "session.pause", %{
      reason: "Operator paused the repository conversation."
    })
  end

  def handle_event("resume_conversation", _params, socket) do
    dispatch_conversation_control(socket, "session.resume", %{})
  end

  def handle_event("stop_conversation_turn", _params, socket) do
    if is_binary(active_child_work_id(socket.assigns.conversation_snapshot)) do
      case JidoCode.AgentWorkspace.handle_conversation_command(
             conversation_id(socket),
             %{type: "turn.stop", payload: %{reason: "Operator requested a stop."}},
             actor: initiating_actor(socket)
           ) do
        {:ok, snapshot} ->
          {:noreply,
           socket
           |> assign(:conversation_action_feedback, nil)
           |> assign(:conversation_action_feedback_kind, :info)
           |> assign_conversation_snapshot(snapshot)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:conversation_action_feedback, %{
             error_type: "project_detail_conversation_stop_failed",
             detail: "The active repository conversation turn could not be stopped (#{inspect(reason)}).",
             remediation: "Retry the stop request or let the active turn settle before continuing."
           })
           |> assign(:conversation_action_feedback_kind, :error)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:conversation_event, event}, socket) do
    if conversation_event_applies?(socket, event) do
      event_sequence = map_get(event, :sequence, "sequence")

      cond do
        not is_integer(event_sequence) ->
          {:noreply, socket}

        event_sequence <= socket.assigns.conversation_last_event_sequence ->
          {:noreply, socket}

        event_sequence == socket.assigns.conversation_last_event_sequence + 1 ->
          {:noreply, sync_conversation_event(socket, event)}

        true ->
          {:noreply, recover_project_conversation_gap(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-2">
        <h1 id="project-detail-title" class="text-2xl font-bold">Managed repo detail</h1>
        <p class="text-base-content/70">
          Launch builtin workflows from the managed-repository control view with governed run traceability.
        </p>
      </section>

      <.operator_state_notice
        :if={@project_load_error}
        id="project-detail-load-error"
        title="Managed repository detail is unavailable"
        state={@project_load_error}
        kind={:error}
      />

      <section
        :if={@project_detail}
        id={"project-detail-panel-#{@project_detail.id}"}
        class="space-y-4 rounded-lg border border-base-300 bg-base-100 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p id="project-detail-github-full-name" class="text-lg font-semibold">
              {@project_detail.github_full_name}
            </p>
            <p id="project-detail-project-name" class="text-sm text-base-content/70">
              {@project_detail.name}
            </p>
          </div>
          <.link id="project-detail-return-link" class="btn btn-sm btn-outline" navigate={@return_to_path}>
            Back
          </.link>
        </div>

        <.vue_surface
          id="project-detail-overview-widget"
          component="ProjectDetailOverviewWidget"
          socket={@socket}
          props={project_detail_overview_props(assigns)}
        />

        <section id="project-detail-conversation-panel" class="space-y-4">
          <div class="space-y-1">
            <h2 class="text-lg font-semibold">Repository conversation</h2>
            <p class="text-sm text-base-content/70">
              Repository-scoped conversations stay product-owned on this managed-repository route and recover from the latest durable snapshot when live delivery degrades.
            </p>
          </div>

          <.operator_state_notice
            :if={@conversation_action_feedback}
            id="project-detail-conversation-feedback"
            title="Repository conversation update"
            state={@conversation_action_feedback}
            kind={@conversation_action_feedback_kind}
          />

          <.operator_state_notice
            :if={conversation_notice_visible?(@conversation_surface)}
            id="project-detail-conversation-notice"
            title="Repository conversation status"
            state={@conversation_surface.notice}
            kind={:warning}
          />

          <div
            :if={@conversation_stream_mode == :degraded}
            id="project-detail-conversation-degraded"
            class="rounded-lg border border-warning/60 bg-warning/10 p-3 text-sm text-warning-content"
          >
            <p class="font-semibold">Conversation stream degraded</p>
            <p class="mt-1">{@conversation_degraded_mode_message}</p>
          </div>

          <%= if @conversation_surface.snapshot do %>
            <div class="grid gap-3 lg:grid-cols-[2fr,1fr]">
              <section class="rounded-lg border border-base-300/70 bg-base-100">
                <div class="border-b border-base-300/70 px-4 py-3">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <h3 class="font-semibold">Conversation transcript</h3>
                      <p
                        id="project-detail-conversation-id"
                        class="text-xs font-mono text-base-content/60"
                      >
                        {@conversation_surface.conversation.id}
                      </p>
                    </div>

                    <div class="flex flex-wrap items-center gap-2 text-xs">
                      <span
                        id="project-detail-conversation-stream-mode"
                        class="rounded-full bg-base-200 px-3 py-1 font-medium"
                      >
                        {@conversation_stream_mode}
                      </span>
                      <span
                        id="project-detail-conversation-sequence"
                        class="rounded-full bg-base-200 px-3 py-1 font-medium"
                      >
                        seq {@conversation_last_event_sequence}
                      </span>
                      <span
                        id="project-detail-conversation-discontinuities"
                        class="rounded-full bg-base-200 px-3 py-1 font-medium"
                      >
                        discontinuities: {@conversation_stream_discontinuity_count}
                      </span>
                    </div>
                  </div>
                </div>

                <div id="project-detail-conversation-events" class="max-h-96 space-y-3 overflow-y-auto px-4 py-4">
                  <%= for event <- @conversation_events do %>
                    <article
                      id={"project-detail-conversation-event-#{map_get(event, :id, "id")}"}
                      class="rounded-md border border-base-300/70 bg-base-200/30 p-3"
                    >
                      <div class="flex flex-wrap items-center justify-between gap-2">
                        <div class="flex items-center gap-2">
                          <span class="font-mono text-xs text-base-content/60">
                            #{map_get(event, :sequence, "sequence")}
                          </span>
                          <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
                            {conversation_event_label(event)}
                          </span>
                          <span class="text-xs text-base-content/60">
                            {map_get(event, :name, "name")}
                          </span>
                        </div>
                        <time class="text-xs text-base-content/60">
                          {format_time(map_get(event, :occurred_at, "occurred_at"))}
                        </time>
                      </div>
                      <p class="mt-2 text-sm font-medium">
                        {conversation_event_title(event)}
                      </p>
                      <p
                        :if={conversation_event_excerpt(event)}
                        class="mt-1 whitespace-pre-wrap text-xs text-base-content/70"
                      >
                        {conversation_event_excerpt(event)}
                      </p>
                    </article>
                  <% end %>
                </div>

                <div class="border-t border-base-300/70 px-4 py-4">
                  <div
                    :if={conversation_pending_clarification(@conversation_snapshot)}
                    id="project-detail-conversation-pending-clarification"
                    class="mb-3 rounded-lg border border-warning/60 bg-warning/10 p-3 text-sm"
                  >
                    <p class="font-semibold">Input required</p>
                    <p class="mt-1">
                      {conversation_clarification_prompt(@conversation_snapshot) ||
                        "The active turn is waiting on clarification."}
                    </p>
                  </div>

                  <form id="project-detail-conversation-form" phx-submit="send_conversation" class="flex flex-col gap-3 sm:flex-row">
                    <input
                      id="project-detail-conversation-input"
                      type="text"
                      name="input"
                      value={@conversation_input}
                      phx-change="update_conversation_input"
                      placeholder={
                        if conversation_awaiting_input?(@conversation_snapshot) do
                          conversation_clarification_prompt(@conversation_snapshot) ||
                            "Provide the missing clarification…"
                        else
                          "Describe the repository work this conversation should coordinate…"
                        end
                      }
                      class="input input-bordered flex-1"
                      autocomplete="off"
                    />
                    <button
                      id="project-detail-conversation-submit"
                      type="submit"
                      class="btn btn-primary"
                      disabled={String.trim(@conversation_input) == "" || conversation_paused?(@conversation_snapshot)}
                    >
                      {if conversation_awaiting_input?(@conversation_snapshot),
                        do: "Resume turn",
                        else: "Submit turn"}
                    </button>
                  </form>
                </div>
              </section>

              <aside class="space-y-3">
                <section class="rounded-lg border border-base-300/70 bg-base-100 p-4">
                  <h3 class="font-semibold">Conversation state</h3>
                  <dl class="mt-3 space-y-2 text-sm">
                    <div class="flex justify-between gap-3">
                      <dt class="text-base-content/70">Status</dt>
                      <dd id="project-detail-conversation-status" class="font-medium">
                        {Map.get(@conversation_surface.conversation, :status)}
                      </dd>
                    </div>
                    <div class="flex justify-between gap-3">
                      <dt class="text-base-content/70">Scope</dt>
                      <dd id="project-detail-conversation-scope" class="font-medium">
                        {Map.get(@conversation_surface.conversation, :scope)}
                      </dd>
                    </div>
                    <div class="flex justify-between gap-3">
                      <dt class="text-base-content/70">Attachment</dt>
                      <dd id="project-detail-conversation-attachment" class="font-medium">
                        {Map.get(@conversation_surface.conversation, :attachment_mode)}
                      </dd>
                    </div>
                    <div class="flex justify-between gap-3">
                      <dt class="text-base-content/70">Work item</dt>
                      <dd id="project-detail-conversation-work-item" class="font-medium">
                        {Map.get(@conversation_snapshot, :work_item_id) || "repo-scoped"}
                      </dd>
                    </div>
                    <div class="flex justify-between gap-3">
                      <dt class="text-base-content/70">Active turn</dt>
                      <dd class="font-medium">
                        {conversation_turn_state(@conversation_snapshot)}
                      </dd>
                    </div>
                  </dl>
                </section>

                <section class="rounded-lg border border-base-300/70 bg-base-100 p-4">
                  <h3 class="font-semibold">Execution</h3>
                  <div
                    :if={conversation_latest_progress(@conversation_snapshot)}
                    id="project-detail-conversation-progress"
                    class="mt-3 rounded-lg border border-info/40 bg-info/10 p-3 text-sm"
                  >
                    <p class="font-semibold">Latest progress</p>
                    <p class="mt-1">
                      {conversation_latest_progress(@conversation_snapshot)["summary"] ||
                        "Runtime progress update received."}
                    </p>
                  </div>

                  <div
                    :if={conversation_stdout_preview(@conversation_snapshot) != []}
                    id="project-detail-conversation-stdout"
                    class="mt-3 rounded-lg border border-base-300/70 bg-base-200/30 p-3 text-sm"
                  >
                    <p class="font-semibold">Recent tool output</p>
                    <pre class="mt-2 whitespace-pre-wrap font-mono text-xs">
                      <%= for line <- conversation_stdout_preview(@conversation_snapshot) do %>
                        {line}
                      <% end %>
                    </pre>
                  </div>

                  <div class="mt-4 flex flex-wrap gap-2">
                    <button
                      id="project-detail-conversation-pause"
                      type="button"
                      class="btn btn-sm btn-outline"
                      phx-click="pause_conversation"
                      disabled={
                        conversation_paused?(@conversation_snapshot) ||
                          !is_binary(Map.get(@conversation_surface.conversation || %{}, :id))
                      }
                    >
                      Pause
                    </button>
                    <button
                      id="project-detail-conversation-resume"
                      type="button"
                      class="btn btn-sm btn-outline"
                      phx-click="resume_conversation"
                      disabled={!conversation_paused?(@conversation_snapshot)}
                    >
                      Resume
                    </button>
                    <button
                      id="project-detail-conversation-stop-turn"
                      type="button"
                      class="btn btn-sm btn-outline"
                      phx-click="stop_conversation_turn"
                      disabled={!conversation_active_turn?(@conversation_snapshot)}
                    >
                      Stop turn
                    </button>
                  </div>
                </section>
              </aside>
            </div>
          <% else %>
            <div class="rounded-lg border border-dashed border-base-300 bg-base-200/30 p-4 space-y-3">
              <p class="text-sm text-base-content/70">
                Open a repository conversation to coordinate repo-scoped work without leaving the managed-repository detail route.
              </p>
              <button
                id="project-detail-conversation-open"
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="open_repo_conversation"
              >
                {@conversation_surface.action_label}
              </button>
            </div>
          <% end %>
        </section>

        <section id="project-detail-semantic-inspection" class="space-y-4">
          <div class="space-y-1">
            <h2 class="text-lg font-semibold">Semantic repository inspection</h2>
            <p class="text-sm text-base-content/70">
              Semantic source-code graph insights stay repo-scoped, bounded, and product-owned on this managed-repository route.
            </p>
          </div>

          <.operator_state_notice
            :if={@semantic_action_feedback}
            id="project-detail-semantic-feedback"
            title="Semantic graph recovery update"
            state={@semantic_action_feedback}
            kind={:info}
          />

          <.operator_state_notice
            :if={semantic_notice_visible?(@semantic_inspection)}
            id="project-detail-semantic-notice"
            title="Semantic graph status"
            state={@semantic_inspection.notice}
            kind={semantic_notice_kind(@semantic_inspection)}
          >
            <:actions>
              <button
                :if={semantic_recovery_available?(@semantic_inspection)}
                id="project-detail-semantic-recover"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="recover_semantic_graph"
              >
                {semantic_recovery_label(@semantic_inspection)}
              </button>
            </:actions>
          </.operator_state_notice>

          <.vue_surface
            id="project-detail-semantic-explorer-widget"
            component="ProjectDetailSemanticExplorerWidget"
            socket={@socket}
            props={project_detail_semantic_explorer_props(assigns)}
            events={%{"requestRecovery" => "recover_semantic_graph"}}
            fallback_title="Interactive semantic explorer temporarily unavailable"
            fallback_detail="This repository is using the server-rendered semantic summary while the richer explorer is unavailable."
          >
            <section id="project-detail-semantic-fallback" class="space-y-3">
              <div class="grid gap-3 md:grid-cols-4">
                <article
                  id="project-detail-semantic-fallback-modules"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Modules</p>
                  <p class="mt-1 text-xl font-semibold">{semantic_group_count(@semantic_inspection.summary, :modules)}</p>
                </article>
                <article
                  id="project-detail-semantic-fallback-functions"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Functions</p>
                  <p class="mt-1 text-xl font-semibold">{semantic_result_count(@semantic_inspection.functions)}</p>
                </article>
                <article
                  id="project-detail-semantic-fallback-runtime-patterns"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Runtime patterns</p>
                  <p class="mt-1 text-xl font-semibold">
                    {semantic_result_count(@semantic_inspection.runtime_patterns)}
                  </p>
                </article>
                <article
                  id="project-detail-semantic-fallback-impact"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Impact relationships</p>
                  <p class="mt-1 text-xl font-semibold">{semantic_result_count(@semantic_inspection.impact)}</p>
                </article>
              </div>

              <div class="grid gap-3 lg:grid-cols-2">
                <section id="project-detail-semantic-fallback-module-list" class="space-y-2">
                  <h3 class="font-medium">Modules</h3>
                  <p
                    :if={Enum.empty?(semantic_items(@semantic_inspection.modules))}
                    class="text-sm text-base-content/70"
                  >
                    No module summaries are currently available.
                  </p>
                  <ul :if={!Enum.empty?(semantic_items(@semantic_inspection.modules))} class="space-y-1 text-sm">
                    <li :for={item <- semantic_items(@semantic_inspection.modules)}>
                      {Map.get(item, :module_name) || "Unnamed module"}
                    </li>
                  </ul>
                </section>

                <section id="project-detail-semantic-fallback-impact-list" class="space-y-2">
                  <h3 class="font-medium">Impact</h3>
                  <p
                    :if={Enum.empty?(semantic_items(@semantic_inspection.impact))}
                    class="text-sm text-base-content/70"
                  >
                    No bounded impact relationships are currently available.
                  </p>
                  <ul :if={!Enum.empty?(semantic_items(@semantic_inspection.impact))} class="space-y-1 text-sm">
                    <li :for={item <- semantic_items(@semantic_inspection.impact)}>
                      {Map.get(item, :predicate_name) || "relationship"}
                    </li>
                  </ul>
                </section>
              </div>
            </section>
          </.vue_surface>
        </section>

        <section id="project-detail-memory-inspection" class="space-y-4">
          <div class="space-y-1">
            <h2 class="text-lg font-semibold">Repository memory and provenance</h2>
            <p class="text-sm text-base-content/70">
              Durable coding memory and workflow provenance stay repository-scoped, freshness-aware, and product-owned on this managed-repository route.
            </p>
          </div>

          <.operator_state_notice
            :if={@memory_action_feedback}
            id="project-detail-memory-feedback"
            title="Memory graph recovery update"
            state={@memory_action_feedback}
            kind={memory_feedback_kind(@memory_action_feedback)}
          />

          <.memory_status_notice
            :if={is_map(@memory_inspection.notice)}
            id="project-detail-memory-notice"
            title="Repository memory status"
            state={@memory_inspection.notice}
            kind={Map.get(@memory_inspection, :notice_kind, :warning)}
            recovery={Map.get(@memory_inspection, :recovery)}
            recover_event="recover_memory_graph"
            recover_id="project-detail-memory-recover"
          />

          <div id="project-detail-memory-summary" class="grid gap-3 md:grid-cols-4">
            <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
              <p class="text-xs uppercase text-base-content/60">Durable memories</p>
              <p id="project-detail-memory-summary-memories" class="mt-1 text-xl font-semibold">
                {memory_group_count(@memory_inspection.summary, :memories)}
              </p>
            </article>
            <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
              <p class="text-xs uppercase text-base-content/60">Workflow provenance</p>
              <p id="project-detail-memory-summary-provenance" class="mt-1 text-xl font-semibold">
                {memory_group_count(@memory_inspection.summary, :provenance)}
              </p>
            </article>
            <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
              <p class="text-xs uppercase text-base-content/60">Memory state</p>
              <p id="project-detail-memory-summary-state" class="mt-1 text-sm font-semibold">
                {Map.get(@memory_inspection.graph, :state, :unavailable)}
              </p>
            </article>
            <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
              <p class="text-xs uppercase text-base-content/60">Validated revision</p>
              <p id="project-detail-memory-summary-revision" class="mt-1 text-sm font-semibold break-all">
                {Map.get(@memory_inspection.graph, :validated_revision) || "Not validated"}
              </p>
            </article>
          </div>

          <div class="grid gap-3 lg:grid-cols-2">
            <section id="project-detail-memory-list" class="space-y-2">
              <h3 class="font-medium">Durable memory</h3>
              <p :if={Enum.empty?(memory_items(@memory_inspection.memories))} class="text-sm text-base-content/70">
                No durable memory is currently available for this repository.
              </p>
              <ul :if={!Enum.empty?(memory_items(@memory_inspection.memories))} class="space-y-2 text-sm">
                <li
                  :for={item <- memory_items(@memory_inspection.memories)}
                  id={"project-detail-memory-item-#{memory_item_dom_id(item)}"}
                  class="rounded-md border border-base-300/60 bg-base-100 p-3"
                >
                  <p class="font-medium">
                    {Map.get(item, :memory_kind) || "Memory"}
                  </p>
                  <p class="text-base-content/80">{Map.get(item, :content)}</p>
                  <p :if={Map.get(item, :module_name)} class="text-xs text-base-content/60">
                    Code anchor: {Map.get(item, :module_name)}
                  </p>
                  <.memory_link_groups
                    dom_prefix={"project-detail-memory-item-#{memory_item_dom_id(item)}"}
                    item={item}
                  />
                </li>
              </ul>
            </section>

            <section id="project-detail-provenance-list" class="space-y-2">
              <h3 class="font-medium">Workflow provenance</h3>
              <p :if={Enum.empty?(memory_items(@memory_inspection.provenance))} class="text-sm text-base-content/70">
                No workflow provenance is currently available for this repository.
              </p>
              <ul :if={!Enum.empty?(memory_items(@memory_inspection.provenance))} class="space-y-2 text-sm">
                <li
                  :for={item <- memory_items(@memory_inspection.provenance)}
                  id={"project-detail-provenance-item-#{memory_item_dom_id(item)}"}
                  class="rounded-md border border-base-300/60 bg-base-100 p-3"
                >
                  <p class="font-medium">
                    {Map.get(item, :label) || Map.get(item, :provenance_kind) || "Provenance"}
                  </p>
                  <p :if={Map.get(item, :content)} class="text-base-content/80">{Map.get(item, :content)}</p>
                  <p :if={Map.get(item, :module_name)} class="text-xs text-base-content/60">
                    Code anchor: {Map.get(item, :module_name)}
                  </p>
                  <.memory_link_groups
                    dom_prefix={"project-detail-provenance-item-#{memory_item_dom_id(item)}"}
                    item={item}
                  />
                </li>
              </ul>
            </section>
          </div>
        </section>

        <section
          id="project-detail-workflow-defaults"
          class="rounded-lg border border-base-300 bg-base-200/40 p-3 space-y-1"
        >
          <p class="text-sm font-medium">Managed repository launch defaults</p>
          <p id="project-detail-default-branch" class="text-sm text-base-content/80">
            Default branch: {@project_detail.default_branch}
          </p>
          <p id="project-detail-default-repository" class="text-sm text-base-content/80">
            Repository: {@project_detail.github_full_name}
          </p>
          <p
            :if={@project_detail.managed_repo_id}
            id="project-detail-managed-repo-id"
            class="text-xs text-base-content/70"
          >
            Managed repo: {@project_detail.managed_repo_id}
          </p>
        </section>

        <section
          :if={!project_ready_for_launch?(@project_detail)}
          id="project-detail-launch-disabled-guidance"
          class="rounded-lg border border-warning/60 bg-warning/10 p-3 space-y-1"
        >
          <p id="project-detail-launch-disabled-label" class="font-semibold">
            Workflow launch controls are disabled
          </p>
          <p id="project-detail-launch-disabled-type" class="text-xs">
            Typed readiness state: {project_readiness(@project_detail).error_type}
          </p>
          <p id="project-detail-launch-disabled-detail" class="text-sm">
            {project_readiness(@project_detail).detail}
          </p>
          <p id="project-detail-launch-disabled-remediation" class="text-sm">
            {project_readiness(@project_detail).remediation}
          </p>
        </section>

        <section id="project-detail-workflow-controls" class="grid gap-3 md:grid-cols-2">
          <article
            :for={workflow <- @supported_workflows}
            id={"project-detail-workflow-card-#{workflow_dom_id(workflow.name)}"}
            class="rounded-lg border border-base-300 p-3 space-y-2"
          >
            <div>
              <h2
                id={"project-detail-workflow-label-#{workflow_dom_id(workflow.name)}"}
                class="font-semibold"
              >
                {workflow.label}
              </h2>
              <p
                id={"project-detail-workflow-name-#{workflow_dom_id(workflow.name)}"}
                class="text-xs font-mono text-base-content/70"
              >
                {workflow.name}
              </p>
            </div>

            <%= if project_ready_for_launch?(@project_detail) do %>
              <button
                id={"project-detail-launch-#{workflow_dom_id(workflow.name)}"}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="kickoff_workflow"
                phx-value-workflow_name={workflow.name}
              >
                Launch workflow
              </button>
            <% else %>
              <span
                id={"project-detail-launch-disabled-#{workflow_dom_id(workflow.name)}"}
                class="btn btn-sm btn-disabled cursor-not-allowed"
                aria-disabled="true"
              >
                Launch workflow
              </span>
            <% end %>

            <.workflow_launch_feedback
              feedback={workflow_launch_feedback(@workflow_launch_states, workflow.name)}
              dom_prefix={"project-detail-launch-#{workflow_dom_id(workflow.name)}"}
            />
          </article>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp empty_conversation_surface do
    %{
      available?: false,
      managed_repo_id: nil,
      conversation: nil,
      snapshot: nil,
      recent_events: [],
      notice: nil,
      action_label: "Open repo conversation"
    }
  end

  defp assign_project_conversation(socket, project_detail) do
    projection = ProjectConversation.load_repo_detail(project_detail, actor: initiating_actor(socket))

    socket
    |> assign_conversation_surface(projection)
    |> maybe_subscribe_conversation()
  end

  defp clear_project_conversation(socket) do
    socket
    |> assign(:conversation_surface, empty_conversation_surface())
    |> assign(:conversation_snapshot, nil)
    |> assign(:conversation_events, [])
    |> assign(:conversation_last_event_sequence, 0)
    |> assign(:conversation_input, "")
    |> assign(:conversation_action_feedback, nil)
    |> assign(:conversation_action_feedback_kind, :info)
    |> assign(:conversation_stream_mode, :idle)
    |> assign(:conversation_stream_degraded_reason, nil)
    |> assign(:conversation_stream_discontinuity_count, 0)
  end

  defp assign_opened_conversation(socket, conversation, snapshot) do
    projection = %{
      available?: true,
      managed_repo_id: conversation.managed_repo_id,
      conversation: %{
        id: conversation.id,
        status: conversation.status,
        scope: conversation.scope,
        attachment_mode: conversation.attachment_mode,
        title: conversation.title,
        objective: conversation.objective,
        source: conversation.source,
        work_item_id: conversation.work_item_id,
        last_activity_at: conversation.last_activity_at
      },
      snapshot: snapshot,
      recent_events: Enum.take(snapshot.events || [], -10),
      notice: nil,
      action_label: "Continue repo conversation"
    }

    assign_conversation_surface(socket, projection)
  end

  defp assign_conversation_surface(socket, projection) do
    snapshot = Map.get(projection, :snapshot)
    recent_events = Map.get(projection, :recent_events, [])

    socket
    |> assign(:conversation_surface, projection)
    |> assign(:conversation_snapshot, snapshot)
    |> assign(:conversation_events, recent_events)
    |> assign(:conversation_last_event_sequence, snapshot && snapshot.last_event_sequence || 0)
    |> assign(:conversation_stream_mode, conversation_stream_mode(projection))
    |> assign(:conversation_stream_degraded_reason, conversation_stream_reason(projection))
    |> assign(:conversation_stream_discontinuity_count, 0)
  end

  defp assign_conversation_snapshot(socket, snapshot) do
    recent_events = Enum.take(snapshot.events || [], -10)

    socket
    |> assign(:conversation_snapshot, snapshot)
    |> assign(:conversation_events, recent_events)
    |> assign(:conversation_last_event_sequence, snapshot.last_event_sequence || 0)
    |> update(:conversation_surface, fn surface ->
      surface
      |> Map.put(:snapshot, snapshot)
      |> Map.put(:recent_events, recent_events)
      |> update_conversation_summary(snapshot)
    end)
  end

  defp update_conversation_summary(%{conversation: %{} = conversation} = surface, snapshot) do
    Map.put(
      surface,
      :conversation,
      conversation
      |> Map.put(:status, snapshot.status)
      |> Map.put(:work_item_id, snapshot.work_item_id)
    )
  end

  defp update_conversation_summary(surface, _snapshot), do: surface

  defp maybe_subscribe_conversation(socket) do
    if connected?(socket) do
      case conversation_id(socket) do
        conversation_id when is_binary(conversation_id) ->
          case ConversationPubSub.subscribe_conversation(conversation_id) do
            :ok ->
              socket
              |> assign(:conversation_stream_mode, :live)
              |> assign(:conversation_stream_degraded_reason, nil)

            {:error, reason} ->
              socket
              |> assign(:conversation_stream_mode, :degraded)
              |> assign(:conversation_stream_degraded_reason, inspect(reason))

            other ->
              socket
              |> assign(:conversation_stream_mode, :degraded)
              |> assign(:conversation_stream_degraded_reason, inspect(other))
          end

        _other ->
          socket
      end
    else
      socket
    end
  end

  defp maybe_unsubscribe_conversation(socket) do
    case conversation_id(socket) do
      conversation_id when is_binary(conversation_id) ->
        _ = ConversationPubSub.unsubscribe_conversation(conversation_id)
        socket

      _other ->
        socket
    end
  end

  defp dispatch_conversation_control(socket, command_type, payload) do
    case JidoCode.AgentWorkspace.handle_conversation_command(
           conversation_id(socket),
           %{type: command_type, payload: payload},
           actor: initiating_actor(socket)
         ) do
      {:ok, snapshot} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, nil)
         |> assign(:conversation_action_feedback_kind, :info)
         |> assign_conversation_snapshot(snapshot)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, %{
           error_type: "project_detail_conversation_control_failed",
           detail: "The repository conversation could not be updated (#{inspect(reason)}).",
           remediation: "Retry the control action after the active conversation state is available again."
         })
         |> assign(:conversation_action_feedback_kind, :error)}
    end
  end

  defp recover_project_conversation_gap(socket) do
    case conversation_id(socket) do
      conversation_id when is_binary(conversation_id) ->
        case JidoCode.AgentWorkspace.conversation_snapshot(conversation_id) do
          {:ok, snapshot} ->
            socket
            |> assign_conversation_snapshot(snapshot)
            |> assign(
              :conversation_stream_discontinuity_count,
              socket.assigns.conversation_stream_discontinuity_count + 1
            )

          {:error, reason} ->
            socket
            |> assign(:conversation_stream_mode, :degraded)
            |> assign(:conversation_stream_degraded_reason, inspect(reason))
        end

      _other ->
        socket
    end
  end

  defp append_conversation_event(socket, event) do
    updated_events =
      socket.assigns.conversation_events
      |> Kernel.++([event])
      |> Enum.take(-10)

    socket
    |> assign(:conversation_events, updated_events)
    |> assign(:conversation_last_event_sequence, map_get(event, :sequence, "sequence"))
    |> update(:conversation_surface, &Map.put(&1, :recent_events, updated_events))
  end

  defp sync_conversation_event(socket, event) do
    case conversation_id(socket) do
      conversation_id when is_binary(conversation_id) ->
        case JidoCode.AgentWorkspace.conversation_snapshot(conversation_id) do
          {:ok, snapshot} ->
            socket
            |> assign_conversation_snapshot(snapshot)
            |> assign(:conversation_stream_mode, :live)
            |> assign(:conversation_stream_degraded_reason, nil)

          {:error, _reason} ->
            append_conversation_event(socket, event)
        end

      _other ->
        append_conversation_event(socket, event)
    end
  end

  defp conversation_event_applies?(socket, event) do
    event_conversation_id = map_get(event, :conversation_id, "conversation_id")
    is_binary(event_conversation_id) and event_conversation_id == conversation_id(socket)
  end

  defp conversation_notice_visible?(%{notice: notice}) when is_map(notice), do: true
  defp conversation_notice_visible?(_surface), do: false

  defp conversation_stream_mode(%{notice: notice}) when is_map(notice), do: :degraded
  defp conversation_stream_mode(%{snapshot: nil}), do: :idle
  defp conversation_stream_mode(%{snapshot: _snapshot}), do: :live
  defp conversation_stream_mode(_surface), do: :idle

  defp conversation_stream_reason(%{notice: notice}) when is_map(notice), do: notice.detail
  defp conversation_stream_reason(_surface), do: nil

  defp conversation_id(%{assigns: %{conversation_surface: %{conversation: %{} = conversation}}}) do
    Map.get(conversation, :id)
  end

  defp conversation_id(_socket), do: nil

  defp conversation_input_command(socket, input) do
    case socket.assigns.conversation_snapshot do
      %{active_turn_id: turn_id} = snapshot when is_binary(turn_id) ->
        if conversation_awaiting_input?(snapshot) do
          %{type: "turn.resume", payload: %{turn_id: turn_id, response: input}}
        else
          %{type: "turn.submit", payload: %{instruction: input}}
        end

      _other ->
        %{type: "turn.submit", payload: %{instruction: input}}
    end
  end

  defp active_child_work_id(nil), do: nil
  defp active_child_work_id(snapshot), do: snapshot.active_child_work_id

  defp conversation_active_turn?(%{active_turn_id: turn_id}) when is_binary(turn_id), do: true
  defp conversation_active_turn?(_snapshot), do: false

  defp conversation_paused?(%{status: :paused}), do: true
  defp conversation_paused?(_snapshot), do: false

  defp conversation_turn_state(%{active_turn: %{state: state}}), do: state
  defp conversation_turn_state(_snapshot), do: "none"

  defp conversation_awaiting_input?(%{active_turn: %{state: :awaiting_input}}), do: true

  defp conversation_awaiting_input?(%{
         shared_context: %{"pending_clarification" => %{} = _pending_clarification}
       }),
       do: true

  defp conversation_awaiting_input?(_snapshot), do: false

  defp conversation_pending_clarification(%{
         shared_context: %{"pending_clarification" => %{} = pending_clarification}
       }),
       do: pending_clarification

  defp conversation_pending_clarification(_snapshot), do: nil

  defp conversation_clarification_prompt(snapshot) do
    snapshot
    |> conversation_pending_clarification()
    |> case do
      %{"prompt" => %{"prompt" => prompt}} -> prompt
      %{"prompt" => %{"details" => %{"prompt" => prompt}}} -> prompt
      %{"prompt" => prompt} when is_binary(prompt) -> prompt
      _other -> nil
    end
  end

  defp conversation_latest_progress(%{active_child_work: %{result: %{} = result}}) do
    case result do
      %{"latest_progress" => %{} = latest_progress} -> latest_progress
      _other -> nil
    end
  end

  defp conversation_latest_progress(_snapshot), do: nil

  defp conversation_stdout_preview(%{active_child_work: %{result: %{"stdout" => stdout}}})
       when is_list(stdout),
       do: Enum.take(stdout, -4)

  defp conversation_stdout_preview(_snapshot), do: []

  defp conversation_event_label(event) do
    event
    |> map_get(:name, "name", "")
    |> case do
      "" -> "event"
      name -> name |> String.split(".", parts: 2) |> List.first()
    end
  end

  defp conversation_event_title(event) do
    case map_get(event, :name, "name") do
      "conversation.message_added" ->
        payload = conversation_event_payload(event)
        command_payload = map_get(payload, :payload, "payload", %{})

        map_get(command_payload, :instruction, "instruction") ||
          map_get(command_payload, :response, "response") ||
          map_get(command_payload, :reason, "reason") ||
          "Recorded repository conversation input."

      "conversation.status_changed" ->
        "Conversation status is now #{map_get(conversation_event_payload(event), :status, "status") || "active"}."

      "turn.intent_announced" ->
        map_get(conversation_event_payload(event), :text, "text") || "Intent announced."

      "turn.queued" ->
        "Queued a new repository work turn."

      "turn.started" ->
        "Started the active repository turn."

      "turn.awaiting_input" ->
        map_get(conversation_event_payload(event), :prompt, "prompt") ||
          "Waiting for clarification before continuing."

      "turn.delta" ->
        map_get(conversation_event_payload(event), :text, "text") ||
          "Streaming turn update received."

      "turn.cancelling" ->
        "Stopping the active repository turn."

      "turn.completed" ->
        "The active repository turn completed."

      "turn.cancelled" ->
        "The active repository turn was cancelled."

      "tool.started" ->
        "Started a child tool execution."

      "tool.progress" ->
        map_get(conversation_event_payload(event), :summary, "summary") ||
          "Progress update received."

      "tool.stdout" ->
        map_get(conversation_event_payload(event), :text, "text") ||
          "Tool output received."

      "tool.needs_input" ->
        map_get(conversation_event_payload(event), :prompt, "prompt") ||
          "The active tool requested more input."

      "tool.completed" ->
        conversation_result_summary(event) || "The active tool completed."

      "tool.cancelled" ->
        conversation_result_summary(event) || "The active tool cancelled cleanly."

      "tool.failed" ->
        conversation_error_detail(event) || "The active tool failed."

      "tool.cancel_failed" ->
        conversation_error_detail(event) || "The active tool failed while cancelling."

      other when is_binary(other) ->
        other

      _other ->
        "Conversation event"
    end
  end

  defp conversation_event_excerpt(event) do
    actor_id =
      event
      |> map_get(:actor, "actor", %{})
      |> map_get(:id, "id")

    tool_call_id = map_get(event, :tool_call_id, "tool_call_id")
    payload = conversation_event_payload(event)

    %{}
    |> maybe_put("actor", actor_id)
    |> maybe_put("tool_call_id", tool_call_id)
    |> maybe_put("summary", map_get(payload, :summary, "summary"))
    |> maybe_put("prompt", map_get(payload, :prompt, "prompt"))
    |> maybe_put("error", conversation_error_detail(event))
    |> maybe_put(
      "text",
      map_get(payload, :text, "text") || map_get(payload, :chunk, "chunk")
    )
    |> case do
      empty when empty == %{} -> nil
      details -> inspect(details, pretty: false)
    end
  end

  defp conversation_event_payload(event), do: map_get(event, :payload, "payload", %{})

  defp conversation_result_summary(event) do
    result =
      event
      |> conversation_event_payload()
      |> map_get(:result, "result", %{})

    map_get(result, :summary, "summary") || map_get(result, :reason, "reason")
  end

  defp conversation_error_detail(event) do
    error =
      event
      |> conversation_event_payload()
      |> map_get(:error, "error", %{})

    map_get(error, :detail, "detail") || map_get(error, :error_type, "error_type")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_time(nil), do: "n/a"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_value), do: "n/a"

  attr(:feedback, :map, default: nil)
  attr(:dom_prefix, :string, required: true)

  defp workflow_launch_feedback(assigns) do
    ~H"""
    <section :if={@feedback} id={"#{@dom_prefix}-feedback"} class="space-y-1">
      <%= case @feedback.status do %>
        <% :ok -> %>
          <p id={"#{@dom_prefix}-run-id"} class="text-xs text-success">
            Run: <span class="font-mono">{@feedback.run.run_id}</span>
          </p>
          <.link
            id={"#{@dom_prefix}-run-link"}
            class="link link-primary text-xs"
            href={@feedback.run.detail_path}
          >
            Open run detail
          </.link>
        <% :error -> %>
          <p id={"#{@dom_prefix}-error-type"} class="text-xs text-error">
            Typed kickoff error: {@feedback.error.error_type}
          </p>
          <p id={"#{@dom_prefix}-error-detail"} class="text-xs text-error">
            {@feedback.error.detail}
          </p>
          <p id={"#{@dom_prefix}-error-remediation"} class="text-xs text-base-content/70">
            {@feedback.error.remediation}
          </p>
      <% end %>
    </section>
    """
  end

  defp put_workflow_launch_state(socket, workflow_name, kickoff_result) do
    state_value =
      case kickoff_result do
        {:ok, kickoff_run} ->
          %{status: :ok, run: kickoff_run}

        {:error, kickoff_error} ->
          %{status: :error, error: kickoff_error}
      end

    update(socket, :workflow_launch_states, &Map.put(&1, workflow_name, state_value))
  end

  defp workflow_launch_feedback(states, workflow_name) when is_map(states) do
    states
    |> Map.get(normalize_workflow_name(workflow_name))
  end

  defp workflow_launch_feedback(_states, _workflow_name), do: nil

  defp project_detail_overview_props(assigns) do
    project_detail = Map.get(assigns, :project_detail, %{})
    supported_workflows = Map.get(assigns, :supported_workflows, [])

    %{
      githubFullName:
        project_detail
        |> map_get(:github_full_name, "github_full_name")
        |> normalize_optional_string() || "unknown/repository",
      projectName:
        project_detail
        |> map_get(:name, "name")
        |> normalize_optional_string() || "Unnamed project",
      defaultBranch:
        project_detail
        |> map_get(:default_branch, "default_branch")
        |> normalize_optional_string() || "main",
      managedRepoId:
        project_detail
        |> map_get(:managed_repo_id, "managed_repo_id")
        |> normalize_optional_string(),
      launchReady: project_ready_for_launch?(project_detail),
      launchSummary: project_launch_summary(project_detail),
      workflowCards:
        Enum.map(supported_workflows, fn workflow ->
          workflow_feedback =
            workflow_launch_feedback(Map.get(assigns, :workflow_launch_states, %{}), workflow.name)

          %{
            id: workflow_dom_id(workflow.name),
            label: workflow.label,
            name: workflow.name,
            launchable: project_ready_for_launch?(project_detail),
            feedbackStatus: workflow_feedback_status(workflow_feedback),
            feedbackMessage: workflow_feedback_message(workflow_feedback)
          }
        end)
    }
  end

  defp project_launch_summary(project_detail) do
    if project_ready_for_launch?(project_detail) do
      "Managed-repository launch defaults are ready for builtin workflow kickoff."
    else
      readiness = project_readiness(project_detail)

      readiness
      |> map_get(:detail, "detail")
      |> normalize_optional_string() ||
        "Managed-repository launch controls remain blocked until workspace readiness is restored."
    end
  end

  defp workflow_feedback_status(%{status: :ok}), do: "ok"
  defp workflow_feedback_status(%{status: :error}), do: "error"
  defp workflow_feedback_status(_feedback), do: nil

  defp workflow_feedback_message(%{status: :ok, run: run}) do
    run
    |> map_get(:run_id, "run_id")
    |> normalize_optional_string()
    |> case do
      nil -> "Workflow kickoff succeeded."
      run_id -> "Latest kickoff run: #{run_id}"
    end
  end

  defp workflow_feedback_message(%{status: :error, error: error}) do
    error
    |> map_get(:detail, "detail")
    |> normalize_optional_string() || "Workflow kickoff failed."
  end

  defp workflow_feedback_message(_feedback), do: nil

  defp project_detail_semantic_explorer_props(assigns) do
    inspection = Map.get(assigns, :semantic_inspection) || %{}
    graph = Map.get(inspection, :graph, %{})

    %{
      managedRepoId: Map.get(inspection, :managed_repo_id),
      graph: %{
        state: graph |> Map.get(:state, :unavailable) |> to_string(),
        ready: Map.get(graph, :ready?, false),
        stale: Map.get(graph, :stale?, false),
        degraded: Map.get(graph, :degraded?, false),
        importedRevision: Map.get(graph, :imported_revision),
        currentRevision: Map.get(graph, :current_revision)
      },
      summaryCards: [
        %{
          id: "modules",
          label: "Modules",
          count: semantic_group_count(Map.get(inspection, :summary), :modules),
          detail: "Bounded module summaries from the managed repository semantic graph."
        },
        %{
          id: "functions",
          label: "Functions",
          count: semantic_result_count(Map.get(inspection, :functions)),
          detail: "Function summaries stay bounded to product-authored semantic projections."
        },
        %{
          id: "runtime_patterns",
          label: "Runtime patterns",
          count: semantic_result_count(Map.get(inspection, :runtime_patterns)),
          detail: "Runtime patterns remain explainable without exposing raw graph internals."
        },
        %{
          id: "impact",
          label: "Impact",
          count: semantic_result_count(Map.get(inspection, :impact)),
          detail: "Impact relationships stay repo-scoped and recovery-aware."
        }
      ],
      modules:
        Enum.map(semantic_items(Map.get(inspection, :modules)), fn item ->
          %{
            moduleName: Map.get(item, :module_name),
            moduleIri: Map.get(item, :module_iri)
          }
        end),
      functions:
        Enum.map(semantic_items(Map.get(inspection, :functions)), fn item ->
          %{
            moduleName: Map.get(item, :module_name),
            functionName: Map.get(item, :function_name),
            arity: Map.get(item, :arity)
          }
        end),
      runtimePatterns:
        Enum.map(semantic_items(Map.get(inspection, :runtime_patterns)), fn item ->
          %{
            patternName: Map.get(item, :pattern_name),
            patternIri: Map.get(item, :pattern_iri)
          }
        end),
      impact:
        Enum.map(semantic_items(Map.get(inspection, :impact)), fn item ->
          %{
            predicateName: Map.get(item, :predicate_name),
            sourceIri: Map.get(item, :source_iri),
            targetIri: Map.get(item, :target_iri)
          }
        end),
      recovery: %{
        available: semantic_recovery_available?(inspection),
        label: semantic_recovery_label(inspection)
      }
    }
  end

  defp semantic_notice_visible?(%{notice: notice}) when is_map(notice), do: true
  defp semantic_notice_visible?(_inspection), do: false

  defp semantic_notice_kind(%{notice_kind: notice_kind}) when is_atom(notice_kind), do: notice_kind
  defp semantic_notice_kind(_inspection), do: :warning

  defp semantic_recovery_available?(%{recovery: %{available?: true}}), do: true
  defp semantic_recovery_available?(_inspection), do: false

  defp semantic_recovery_label(%{recovery: %{label: label}}) when is_binary(label), do: label
  defp semantic_recovery_label(_inspection), do: "Recover semantic graph"

  defp semantic_group_count(%{groups: groups}, group_key) when is_map(groups) do
    groups
    |> Map.get(group_key, %{})
    |> Map.get(:count, 0)
  end

  defp semantic_group_count(_summary, _group_key), do: 0

  defp semantic_result_count(%{result_group: result_group}) when is_map(result_group),
    do: Map.get(result_group, :count, 0)

  defp semantic_result_count(_projection), do: 0

  defp semantic_items(%{items: items}) when is_list(items), do: items
  defp semantic_items(_projection), do: []

  defp memory_feedback_kind(%{kind: kind}) when is_atom(kind), do: kind
  defp memory_feedback_kind(_feedback), do: :info

  defp memory_group_count(%{groups: groups}, group_key) when is_map(groups) do
    groups
    |> Map.get(group_key, %{})
    |> Map.get(:count, 0)
  end

  defp memory_group_count(_summary, _group_key), do: 0

  defp memory_items(%{items: items}) when is_list(items), do: items
  defp memory_items(_projection), do: []

  defp memory_item_dom_id(item) when is_map(item) do
    Map.get(item, :memory_iri) ||
      Map.get(item, :resource_iri) ||
      "memory-item"
      |> to_string()
      |> Base.url_encode64(padding: false)
  end

  defp project_ready_for_launch?(project_detail) do
    ProjectDetail.ready_for_execution?(project_detail)
  end

  defp project_readiness(project_detail) do
    project_detail
    |> Map.get(:execution_readiness, %{})
    |> case do
      %{} = readiness -> readiness
      _other -> %{}
    end
  end

  defp workflow_dom_id(workflow_name) do
    workflow_name
    |> normalize_workflow_name()
    |> String.replace("_", "-")
  end

  defp normalize_workflow_name(workflow_name) do
    normalize_optional_string(workflow_name) || "unknown-workflow"
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

  defp normalize_return_to_path(return_to) do
    case normalize_optional_string(return_to) do
      nil ->
        "/workbench"

      "/" <> _path = normalized_path ->
        normalized_path

      _other ->
        "/workbench"
    end
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
