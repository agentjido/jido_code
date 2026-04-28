defmodule JidoCodeWeb.ProjectDetailLive do
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
  # covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  # covers: architecture.conversation_orchestration.route_level_runtime_readiness_and_continuity_are_operator_readable
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  alias JidoCode.Conversations.PubSub, as: ConversationPubSub
  alias JidoCode.Conversations.RuntimeReadiness
  alias JidoCode.LLMSelection
  alias JidoCodeWeb.OperatorShell
  alias JidoCode.Workbench.ProjectDetail
  alias JidoCode.Workbench.ProjectConversation
  alias JidoCode.Workbench.ProjectMemoryInspection
  alias JidoCode.Workbench.ProjectSemanticInspection
  alias JidoCode.Workbench.ProjectDetailWorkflowKickoff
  alias JidoCode.Workbench.ProjectWorkspaceBinding
  alias JidoCode.Workbench.ProjectWorkspaceBindingNotice

  @conversation_degraded_mode_message "Live conversation stream unavailable. Showing the latest repository conversation snapshot only."
  @detail_sections [:overview, :conversations, :semantic, :memory, :workflows]

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
     |> assign(:repo_intake_surface, empty_conversation_surface())
     |> assign(:conversation_surface, empty_conversation_surface())
     |> assign(:conversation_roster, [])
     |> assign(:conversation_roster_notice, nil)
     |> assign(:conversation_snapshot, nil)
     |> assign(:conversation_events, [])
     |> assign(:conversation_runtime, empty_conversation_runtime())
     |> assign(:conversation_last_event_sequence, 0)
     |> assign(:conversation_input, "")
     |> assign(:conversation_action_feedback, nil)
     |> assign(:conversation_action_feedback_kind, :info)
     |> assign(:conversation_stream_mode, :idle)
     |> assign(:conversation_stream_degraded_reason, nil)
     |> assign(:conversation_stream_discontinuity_count, 0)
     |> assign(:conversation_degraded_mode_message, @conversation_degraded_mode_message)
     |> assign(:selected_work_item_id, nil)
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, "/workbench")
     |> assign(:selected_detail_section, :overview)
     |> assign(
       :workspace_binding_form,
       to_form(%{"workspace_environment" => "sprite", "workspace_path" => ""}, as: :workspace_binding)
     )
     |> assign(:workspace_binding_form_values, %{"workspace_environment" => "sprite", "workspace_path" => ""})
     |> assign(:workspace_binding_feedback, nil)
     |> assign(:workspace_binding_feedback_kind, :info)
     |> assign(:supported_workflows, ProjectDetailWorkflowKickoff.supported_workflows())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = Map.get(params, "id")
    return_to_path = normalize_return_to_path(Map.get(params, "return_to"))
    selected_work_item_id = present_optional_string(Map.get(params, "work_item_id"))
    selected_detail_section = normalize_detail_section(Map.get(params, "section"))

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
              |> assign(:selected_work_item_id, selected_work_item_id)
              |> assign_workspace_binding_form(project_detail)
              |> assign_project_conversation(project_detail, selected_work_item_id)

            {:error, project_load_error} ->
              socket
              |> assign(:project_detail, nil)
              |> assign(:project_load_error, project_load_error)
              |> assign(:semantic_inspection, nil)
              |> assign(:semantic_action_feedback, nil)
              |> assign(:memory_inspection, nil)
              |> assign(:memory_action_feedback, nil)
              |> assign(
                :workspace_binding_form,
                to_form(%{"workspace_environment" => "sprite", "workspace_path" => ""}, as: :workspace_binding)
              )
              |> assign(:workspace_binding_form_values, %{"workspace_environment" => "sprite", "workspace_path" => ""})
              |> clear_project_conversation()
          end
      end

    {:noreply,
     socket
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, return_to_path)
     |> assign(:selected_detail_section, selected_detail_section)}
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
    open_result =
      ProjectConversation.open_repo_detail(
        socket.assigns.project_detail,
        actor: initiating_actor(socket)
      )

    case open_result do
      {:ok, %{conversation: _conversation, snapshot: _snapshot}} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, nil)
         |> assign(:conversation_action_feedback_kind, :info)
         |> assign(:conversation_input, "")
         |> assign_project_conversation(
           socket.assigns.project_detail,
           nil
         )}

      {:error, notice} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, notice)
         |> assign(:conversation_action_feedback_kind, :error)}
    end
  end

  @impl true
  def handle_event("open_selected_conversation", _params, socket) do
    case socket.assigns.selected_work_item_id do
      work_item_id when is_binary(work_item_id) ->
        case ProjectConversation.open_work_item_detail(
               work_item_id,
               actor: initiating_actor(socket)
             ) do
          {:ok, %{conversation: _conversation, snapshot: _snapshot}} ->
            {:noreply,
             socket
             |> assign(:conversation_action_feedback, nil)
             |> assign(:conversation_action_feedback_kind, :info)
             |> assign(:conversation_input, "")
             |> assign_project_conversation(
               socket.assigns.project_detail,
               work_item_id
             )}

          {:error, notice} ->
            {:noreply,
             socket
             |> assign(:conversation_action_feedback, notice)
             |> assign(:conversation_action_feedback_kind, :error)}
        end

      _other ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_workspace_binding", %{"workspace_binding" => params}, socket) do
    {:noreply,
     socket
     |> assign_workspace_binding_form(params)
     |> assign(:workspace_binding_feedback, nil)
     |> assign(:workspace_binding_feedback_kind, :info)}
  end

  @impl true
  def handle_event("save_workspace_binding", %{"workspace_binding" => params}, socket) do
    workspace_binding_attrs = normalize_workspace_binding_form_params(params)
    managed_repo_id = socket.assigns.project_detail && socket.assigns.project_detail.managed_repo_id

    case ProjectWorkspaceBinding.update(managed_repo_id, workspace_binding_attrs, initiating_actor(socket)) do
      {:ok, %{workspace_settings: workspace_settings}} ->
        {:noreply,
         socket
         |> refresh_project_detail_surface()
         |> assign_workspace_binding_form(workspace_binding_form_values(workspace_settings))
         |> assign(:workspace_binding_feedback, %{
           error_type: "managed_repo_workspace_binding_updated",
           detail: "Repo-scoped workspace binding saved for #{socket.assigns.project_detail.github_full_name}.",
           remediation:
             "Conversation, semantic, memory, and workflow readiness on this route now read from the updated repo-scoped binding."
         })
         |> assign(:workspace_binding_feedback_kind, :info)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_workspace_binding_form(params)
         |> assign(:workspace_binding_feedback, error)
         |> assign(:workspace_binding_feedback_kind, :error)}
    end
  end

  @impl true
  def handle_event("focus_repo_intake_conversation", _params, socket) do
    {:noreply,
     push_patch(
       socket,
       to:
         project_detail_conversation_path(
           socket.assigns.project_detail,
           socket.assigns.return_to_path,
           nil
         )
     )}
  end

  @impl true
  def handle_event("focus_work_item_conversation", %{"work_item_id" => work_item_id}, socket) do
    case present_optional_string(work_item_id) do
      nil ->
        {:noreply, socket}

      selected_work_item_id ->
        {:noreply,
         push_patch(
           socket,
           to:
             project_detail_conversation_path(
               socket.assigns.project_detail,
               socket.assigns.return_to_path,
               selected_work_item_id
             )
         )}
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
               conversation_input_command(socket, input, params),
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

      <section :if={@project_detail} class="space-y-3">
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
      </section>

      <section
        :if={@project_detail}
        id={"project-detail-panel-#{@project_detail.id}"}
        data-detail-section={Atom.to_string(@selected_detail_section)}
        class="space-y-4"
      >
        <.subject_tree_shell
          id="project-detail-shell"
          breadcrumbs={project_detail_breadcrumbs(assigns)}
          parent_subjects={project_detail_parent_subjects()}
          child_subjects={detail_section_items(assigns)}
          child_nav_id="project-detail-section-nav"
          child_nav_label="Repo sections"
          child_nav_heading="Repo sections"
          child_nav_summary="Move between repository summary, productive work, knowledge, and launch controls without leaving this managed-repository route."
          sidebar_id="project-detail-section-sidebar"
          content_id="project-detail-section-content"
        >
          <.subject_pane pane={project_detail_selected_pane(assigns)}>
            <section :if={@selected_detail_section == :overview} id="project-detail-overview-panel" class="space-y-4">
              <div class="space-y-1">
                <h2 class="text-lg font-semibold">Repository overview</h2>
                <p class="text-sm text-base-content/70">
                  Start with repository identity, launch posture, and high-level workflow readiness before drilling into work, knowledge, or execution detail.
                </p>
              </div>

              <.vue_surface
                id="project-detail-overview-widget"
                component="ProjectDetailOverviewWidget"
                socket={@socket}
                props={project_detail_overview_props(assigns)}
              />

              <section
                id="project-detail-workspace-binding-panel"
                class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-4"
              >
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="space-y-1">
                    <h3 class="font-semibold">Repo-scoped workspace binding</h3>
                    <p class="text-sm text-base-content/70">
                      Setup runtime defaults only seed new imports. This repository keeps its own execution binding here.
                    </p>
                  </div>
                  <span
                    id="project-detail-workspace-binding-badge"
                    class={[
                      "badge border font-medium",
                      detail_section_badge_class(workspace_binding_badge_tone(@project_detail))
                    ]}
                  >
                    {workspace_binding_badge_label(@project_detail)}
                  </span>
                </div>

                <div class="grid gap-3 md:grid-cols-4">
                  <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
                    <p class="text-xs uppercase text-base-content/60">Execution mode</p>
                    <p id="project-detail-workspace-binding-environment" class="mt-1 text-sm font-semibold">
                      {workspace_binding_environment_label(@project_detail)}
                    </p>
                  </article>
                  <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
                    <p class="text-xs uppercase text-base-content/60">Repository workspace path</p>
                    <p
                      id="project-detail-workspace-binding-path"
                      class="mt-1 text-sm font-semibold break-all"
                    >
                      {workspace_binding_path_label(@project_detail)}
                    </p>
                  </article>
                  <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
                    <p class="text-xs uppercase text-base-content/60">Derived parent directory</p>
                    <p
                      id="project-detail-workspace-binding-root"
                      class="mt-1 text-sm font-semibold break-all"
                    >
                      {workspace_binding_root_label(@project_detail)}
                    </p>
                  </article>
                  <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
                    <p class="text-xs uppercase text-base-content/60">Route runtime readiness</p>
                    <p id="project-detail-workspace-binding-readiness" class="mt-1 text-sm font-semibold">
                      {workspace_binding_route_readiness_label(@project_detail)}
                    </p>
                  </article>
                </div>

                <.operator_state_notice
                  :if={@workspace_binding_feedback}
                  id="project-detail-workspace-binding-feedback"
                  title="Repo workspace binding update"
                  state={@workspace_binding_feedback}
                  kind={@workspace_binding_feedback_kind}
                  compact={true}
                />

                <.form
                  id="project-detail-workspace-binding-form"
                  for={@workspace_binding_form}
                  phx-change="change_workspace_binding"
                  phx-submit="save_workspace_binding"
                  class="space-y-3"
                >
                  <div class="grid gap-3 lg:grid-cols-[14rem_minmax(0,1fr)]">
                    <.input
                      id="project-detail-workspace-binding-environment-input"
                      field={@workspace_binding_form[:workspace_environment]}
                      type="select"
                      label="Workspace binding mode"
                      options={[{"Local", "local"}, {"Cloud default only", "sprite"}]}
                    />

                    <.input
                      :if={workspace_binding_form_local?(@workspace_binding_form_values)}
                      id="project-detail-workspace-binding-path-input"
                      field={@workspace_binding_form[:workspace_path]}
                      type="text"
                      label="Repository workspace path"
                      placeholder="/absolute/path/to/this/repository"
                      autocomplete="off"
                    />
                  </div>

                  <p
                    :if={workspace_binding_form_local?(@workspace_binding_form_values)}
                    id="project-detail-workspace-binding-derived-root-note"
                    class="text-xs text-base-content/65"
                  >
                    {workspace_binding_derived_root_note(@workspace_binding_form_values)}
                  </p>

                  <p
                    :if={!workspace_binding_form_local?(@workspace_binding_form_values)}
                    id="project-detail-workspace-binding-sprite-note"
                    class="text-xs text-base-content/65"
                  >
                    Cloud-default mode leaves this repository unbound until you later save a local workspace path here.
                  </p>

                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <p id="project-detail-workspace-binding-form-note" class="text-sm text-base-content/70">
                      This updates only {@project_detail.github_full_name}. It does not rewrite setup defaults or sibling repositories.
                    </p>

                    <button
                      id="project-detail-workspace-binding-save"
                      type="submit"
                      class="btn btn-primary"
                    >
                      {workspace_binding_save_button_label(@workspace_binding_form_values)}
                    </button>
                  </div>
                </.form>
              </section>

              <section id="project-detail-overview-family-guides" class="grid gap-3 md:grid-cols-2">
                <article
                  :for={section <- overview_family_guides(assigns)}
                  id={"project-detail-overview-guide-#{section.section}"}
                  class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-3"
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="space-y-1">
                      <h3 class="font-semibold">{section.label}</h3>
                      <p
                        id={"project-detail-overview-guide-#{section.section}-summary"}
                        class="text-sm text-base-content/70"
                      >
                        {section.summary}
                      </p>
                    </div>
                    <span
                      :if={section.badge}
                      id={"project-detail-overview-guide-#{section.section}-badge"}
                      class={[
                        "badge badge-sm border font-medium",
                        detail_section_badge_class(section.badge.tone)
                      ]}
                    >
                      {section.badge.label}
                    </span>
                  </div>

                  <.link
                    id={"project-detail-overview-open-#{section.section}"}
                    class="btn btn-xs btn-outline"
                    patch={
                      project_detail_section_path(
                        @project_detail,
                        @return_to_path,
                        section: section.section,
                        work_item_id: @selected_work_item_id
                      )
                    }
                  >
                    Open {section.label}
                  </.link>
                </article>
              </section>
            </section>

            <section
              :if={@selected_detail_section == :conversations}
              id="project-detail-conversation-panel"
              class="space-y-4"
            >
              <div class="space-y-1">
                <h2 class="text-lg font-semibold">Repository conversation</h2>
                <p class="text-sm text-base-content/70">
                  Repository conversations stay product-owned on this managed-repository route: repo intake stays bounded here, governed work-item conversations stay resumable here, and live delivery recovers from the latest durable snapshot when the stream degrades.
                </p>
              </div>

              <section id="project-detail-conversation-workspace-summary" class="grid gap-3 md:grid-cols-3">
                <article class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/55">
                    Current focus
                  </p>
                  <p id="project-detail-conversation-workspace-focus" class="font-semibold">
                    {conversation_workspace_focus_label(
                      @selected_work_item_id,
                      @conversation_surface,
                      @repo_intake_surface
                    )}
                  </p>
                  <p class="text-sm text-base-content/70">
                    {conversation_workspace_focus_summary(
                      @selected_work_item_id,
                      @conversation_surface,
                      @repo_intake_surface
                    )}
                  </p>
                </article>

                <article class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/55">
                    Governed work
                  </p>
                  <p id="project-detail-conversation-governed-count" class="font-semibold">
                    {length(@conversation_roster)} active thread{if length(@conversation_roster) == 1, do: "", else: "s"}
                  </p>
                  <p class="text-sm text-base-content/70">
                    {conversation_governed_summary(@conversation_roster)}
                  </p>
                </article>

                <article class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/55">
                    Runtime posture
                  </p>
                  <p id="project-detail-conversation-workspace-runtime" class="font-semibold">
                    {conversation_workspace_runtime_label(
                      @conversation_runtime,
                      @conversation_stream_mode
                    )}
                  </p>
                  <p class="text-sm text-base-content/70">
                    {conversation_workspace_runtime_summary(
                      @conversation_runtime,
                      @conversation_stream_mode
                    )}
                  </p>
                </article>
              </section>

              <.operator_state_notice
                :if={@conversation_action_feedback}
                id="project-detail-conversation-feedback"
                title="Repository conversation update"
                state={@conversation_action_feedback}
                kind={@conversation_action_feedback_kind}
              />

              <div class="grid gap-4 xl:grid-cols-[minmax(18rem,22rem)_minmax(0,1fr)]">
                <aside class="space-y-4">
                  <section
                    id="project-detail-conversation-intake"
                    class="rounded-lg border border-base-300/70 bg-base-100 p-4 space-y-3"
                  >
                    <div class="flex flex-wrap items-start justify-between gap-3">
                      <div class="space-y-1">
                        <h3 class="font-semibold">Repo intake</h3>
                        <p class="text-sm text-base-content/70">
                          Keep triage and pre-work clarification here before work settles onto governed WorkItems.
                        </p>
                      </div>
                      <.conversation_role_badge
                        :if={@repo_intake_surface && @repo_intake_surface.conversation}
                        id="project-detail-conversation-intake-role"
                        scope={Map.get(@repo_intake_surface.conversation, :scope)}
                        attachment_mode={Map.get(@repo_intake_surface.conversation, :attachment_mode)}
                        work_item_id={Map.get(@repo_intake_surface.conversation, :work_item_id)}
                      />
                    </div>

                    <%= if @repo_intake_surface.conversation do %>
                      <div class="space-y-2">
                        <div class="flex flex-wrap items-center gap-2">
                          <.conversation_status_badge
                            id="project-detail-conversation-intake-status"
                            status={Map.get(@repo_intake_surface.conversation, :status)}
                          />
                          <p
                            id="project-detail-conversation-intake-id"
                            class="text-xs font-mono text-base-content/60"
                          >
                            {Map.get(@repo_intake_surface.conversation, :id)}
                          </p>
                        </div>
                        <p
                          id="project-detail-conversation-intake-detail"
                          class="text-sm text-base-content/80"
                        >
                          {repo_intake_summary(@repo_intake_surface)}
                        </p>
                        <p
                          :if={repo_intake_handoff_work_item_id(@repo_intake_surface)}
                          id="project-detail-conversation-intake-handoff"
                          class="text-xs text-base-content/70"
                        >
                          Latest handoff targets WorkItem {repo_intake_handoff_work_item_id(@repo_intake_surface)}.
                        </p>
                        <p
                          :if={conversation_latest_activity_label(@repo_intake_surface)}
                          id="project-detail-conversation-intake-latest-activity"
                          class="text-xs text-base-content/70"
                        >
                          Latest activity: {conversation_latest_activity_label(@repo_intake_surface)}
                        </p>
                      </div>
                    <% else %>
                      <p id="project-detail-conversation-intake-empty" class="text-sm text-base-content/70">
                        No repo intake conversation is open yet for this managed repository.
                      </p>
                    <% end %>

                    <.operator_state_notice
                      :if={conversation_notice_visible?(@repo_intake_surface)}
                      id="project-detail-conversation-intake-notice"
                      title="Repo intake state"
                      state={@repo_intake_surface.notice}
                      kind={:warning}
                      compact={true}
                    />

                    <div class="flex flex-wrap gap-2">
                      <button
                        :if={@selected_work_item_id}
                        id="project-detail-conversation-focus-intake"
                        type="button"
                        class="btn btn-xs btn-outline"
                        phx-click="focus_repo_intake_conversation"
                      >
                        View repo intake detail
                      </button>
                      <button
                        id="project-detail-conversation-open"
                        type="button"
                        class="btn btn-sm btn-primary"
                        phx-click="open_repo_conversation"
                      >
                        {@repo_intake_surface.action_label}
                      </button>
                    </div>
                  </section>

                  <section
                    id="project-detail-conversation-roster"
                    class="rounded-lg border border-base-300/70 bg-base-100 p-4 space-y-3"
                  >
                    <div class="flex flex-wrap items-center justify-between gap-3">
                      <div class="space-y-1">
                        <h3 class="font-semibold">Active governed conversations</h3>
                        <p class="text-sm text-base-content/70">
                          Each active work item keeps its own productive conversation thread.
                        </p>
                      </div>
                      <span id="project-detail-conversation-roster-count" class="badge badge-outline">
                        {length(@conversation_roster)}
                      </span>
                    </div>

                    <.operator_state_notice
                      :if={@conversation_roster_notice}
                      id="project-detail-conversation-roster-notice"
                      title="Governed conversation roster"
                      state={@conversation_roster_notice}
                      kind={:warning}
                      compact={true}
                    />

                    <%= if @conversation_roster == [] do %>
                      <p id="project-detail-conversation-roster-empty" class="text-sm text-base-content/70">
                        No active governed work-item conversations are attached to this repository yet.
                      </p>
                    <% else %>
                      <ol id="project-detail-conversation-roster-list" class="space-y-3">
                        <li
                          :for={entry <- @conversation_roster}
                          id={"project-detail-conversation-roster-entry-#{Map.get(entry.work_item || %{}, :id)}"}
                          class={[
                            "rounded-lg border p-3 space-y-2",
                            if(conversation_roster_selected?(@selected_work_item_id, entry),
                              do: "border-primary/60 bg-primary/5",
                              else: "border-base-300/70 bg-base-200/20"
                            )
                          ]}
                        >
                          <div class="flex flex-wrap items-start justify-between gap-2">
                            <div class="space-y-1">
                              <p
                                id={"project-detail-conversation-roster-work-item-#{Map.get(entry.work_item || %{}, :id)}"}
                                class="text-sm font-medium"
                              >
                                {Map.get(entry.work_item || %{}, :summary)}
                              </p>
                              <p class="text-xs text-base-content/70">
                                {Map.get(entry.work_item || %{}, :id)}
                              </p>
                            </div>
                            <div class="flex flex-wrap items-center gap-2">
                              <.conversation_role_badge
                                id={"project-detail-conversation-roster-role-#{Map.get(entry.work_item || %{}, :id)}"}
                                scope={Map.get(entry.conversation || %{}, :scope)}
                                attachment_mode={Map.get(entry.conversation || %{}, :attachment_mode)}
                                work_item_id={Map.get(entry.conversation || %{}, :work_item_id)}
                              />
                              <.conversation_status_badge
                                id={"project-detail-conversation-roster-status-#{Map.get(entry.work_item || %{}, :id)}"}
                                status={Map.get(entry.conversation || %{}, :status)}
                              />
                            </div>
                          </div>

                          <p
                            id={"project-detail-conversation-roster-detail-#{Map.get(entry.work_item || %{}, :id)}"}
                            class="text-sm text-base-content/80"
                          >
                            {conversation_surface_summary(entry)}
                          </p>

                          <p
                            :if={conversation_latest_activity_label(entry)}
                            id={"project-detail-conversation-roster-latest-activity-#{Map.get(entry.work_item || %{}, :id)}"}
                            class="text-xs text-base-content/70"
                          >
                            Latest activity: {conversation_latest_activity_label(entry)}
                          </p>

                          <p
                            :if={entry.historical_conversation}
                            id={"project-detail-conversation-roster-history-#{Map.get(entry.work_item || %{}, :id)}"}
                            class="text-xs text-base-content/70"
                          >
                            Historical lineage preserved from {entry.historical_conversation.id}.
                          </p>

                          <div class="flex flex-wrap items-center gap-2">
                            <button
                              id={"project-detail-conversation-roster-focus-#{Map.get(entry.work_item || %{}, :id)}"}
                              type="button"
                              class="btn btn-xs btn-outline"
                              phx-click="focus_work_item_conversation"
                              phx-value-work_item_id={Map.get(entry.work_item || %{}, :id)}
                            >
                              {if conversation_roster_selected?(@selected_work_item_id, entry),
                                do: "Selected detail",
                                else: "View governed detail"}
                            </button>
                          </div>
                        </li>
                      </ol>
                    <% end %>
                  </section>
                </aside>

                <section
                  id="project-detail-conversation-detail"
                  class="rounded-lg border border-base-300/70 bg-base-100"
                >
                  <div class="border-b border-base-300/70 px-4 py-3 space-y-2">
                    <div class="flex flex-wrap items-start justify-between gap-3">
                      <div class="space-y-1">
                        <h3 id="project-detail-conversation-detail-title" class="font-semibold">
                          {selected_conversation_title(@selected_work_item_id, @conversation_surface)}
                        </h3>
                        <p class="text-sm text-base-content/70">
                          {selected_conversation_summary(@selected_work_item_id, @conversation_surface)}
                        </p>
                        <p
                          :if={@selected_work_item_id && @conversation_surface.work_item}
                          id="project-detail-selected-work-item"
                          class="text-xs text-base-content/70"
                        >
                          Following governed conversation for WorkItem {@selected_work_item_id}.
                        </p>
                      </div>
                      <div class="flex flex-wrap items-center gap-2 text-xs">
                        <.conversation_role_badge
                          :if={@conversation_surface.conversation}
                          id="project-detail-conversation-role"
                          scope={Map.get(@conversation_surface.conversation, :scope)}
                          attachment_mode={Map.get(@conversation_surface.conversation, :attachment_mode)}
                          work_item_id={Map.get(@conversation_surface.conversation, :work_item_id)}
                          historical={!is_nil(@conversation_surface.historical_conversation)}
                        />
                        <.conversation_status_badge
                          :if={@conversation_surface.conversation}
                          id="project-detail-conversation-status"
                          status={Map.get(@conversation_surface.conversation, :status)}
                        />
                        <p
                          :if={@conversation_surface.conversation}
                          id="project-detail-conversation-id"
                          class="text-xs font-mono text-base-content/60"
                        >
                          {Map.get(@conversation_surface.conversation, :id)}
                        </p>
                      </div>
                    </div>

                    <.operator_state_notice
                      :if={conversation_notice_visible?(@conversation_surface)}
                      id="project-detail-conversation-notice"
                      title="Selected conversation state"
                      state={@conversation_surface.notice}
                      kind={:warning}
                      compact={true}
                    />

                    <section
                      id="project-detail-conversation-runtime"
                      class="rounded-lg border border-base-300/70 bg-base-200/20 p-3 space-y-3"
                    >
                      <div class="flex flex-wrap items-start justify-between gap-3">
                        <div class="space-y-1">
                          <h4 class="font-semibold">Conversation runtime readiness</h4>
                          <p class="text-xs text-base-content/60">
                            Selected LLM, repo-scoped workspace binding, and readiness stay visible on the route before runtime metadata.
                          </p>
                        </div>
                        <span
                          id="project-detail-conversation-runtime-status"
                          class={[
                            "badge badge-sm badge-outline font-medium",
                            conversation_runtime_status_class(@conversation_runtime)
                          ]}
                        >
                          {conversation_runtime_status_label(@conversation_runtime)}
                        </span>
                      </div>

                      <div class="grid gap-2 md:grid-cols-3">
                        <article class="rounded-md border border-base-300/70 bg-base-100 p-3">
                          <p class="text-[11px] uppercase tracking-wide text-base-content/60">
                            Selected LLM
                          </p>
                          <p id="project-detail-conversation-runtime-llm" class="mt-1 text-sm font-medium break-all">
                            {conversation_runtime_llm_label(@conversation_runtime)}
                          </p>
                        </article>
                        <article class="rounded-md border border-base-300/70 bg-base-100 p-3">
                          <p class="text-[11px] uppercase tracking-wide text-base-content/60">
                            Selection source
                          </p>
                          <p id="project-detail-conversation-runtime-source" class="mt-1 text-sm font-medium">
                            {conversation_runtime_source_label(@conversation_runtime)}
                          </p>
                        </article>
                        <article class="rounded-md border border-base-300/70 bg-base-100 p-3">
                          <p class="text-[11px] uppercase tracking-wide text-base-content/60">
                            Repo workspace path
                          </p>
                          <p
                            id="project-detail-conversation-runtime-workspace"
                            class="mt-1 text-sm font-medium break-all"
                          >
                            {conversation_runtime_workspace_label(@conversation_runtime)}
                          </p>
                        </article>
                      </div>

                      <.operator_state_notice
                        :if={conversation_runtime_notice_visible?(@conversation_runtime)}
                        id="project-detail-conversation-runtime-notice"
                        title="Conversation runtime readiness"
                        state={@conversation_runtime.notice}
                        kind={:error}
                        compact={true}
                      >
                        <:actions>
                          <.link
                            :if={workspace_binding_repair_visible?(@conversation_runtime.notice)}
                            id="project-detail-conversation-runtime-repair"
                            patch={
                              project_detail_section_path(
                                @project_detail,
                                @return_to_path,
                                section: :overview,
                                work_item_id: @selected_work_item_id,
                                anchor: "project-detail-workspace-binding-panel"
                              )
                            }
                            class="btn btn-xs btn-outline"
                          >
                            Repair workspace binding
                          </.link>
                        </:actions>
                        <p
                          :if={conversation_runtime_preserves_state?(@conversation_runtime, @conversation_surface)}
                          id="project-detail-conversation-runtime-preserved"
                          class="text-sm"
                        >
                          Latest transcript and governed linkage remain visible below while this repository's workspace binding recovers.
                        </p>
                      </.operator_state_notice>
                    </section>

                    <div
                      :if={@conversation_stream_mode == :degraded}
                      id="project-detail-conversation-degraded"
                      class="rounded-lg border border-warning/60 bg-warning/10 p-3 text-sm text-warning-content"
                    >
                      <p class="font-semibold">Conversation stream degraded</p>
                      <p class="mt-1">{@conversation_degraded_mode_message}</p>
                    </div>
                  </div>

                  <%= cond do %>
                    <% @conversation_surface.snapshot -> %>
                      <div class="grid gap-3 lg:grid-cols-[2fr,1fr] p-4">
                        <section class="rounded-lg border border-base-300/70 bg-base-100">
                          <div class="border-b border-base-300/70 px-4 py-3">
                            <div class="flex flex-wrap items-start justify-between gap-3">
                              <div>
                                <h3 class="font-semibold">Conversation transcript</h3>
                                <p class="text-xs text-base-content/60">
                                  Recent event-driven transcript and operator controls for the selected conversation.
                                </p>
                              </div>
                            </div>

                            <div id="project-detail-conversation-continuity" class="mt-3 grid gap-2 md:grid-cols-3">
                              <article class="rounded-md border border-base-300/70 bg-base-200/20 p-3">
                                <p class="text-[11px] uppercase tracking-wide text-base-content/60">
                                  Stream continuity
                                </p>
                                <div class="mt-2 flex flex-wrap items-center gap-2">
                                  <.conversation_stream_badge
                                    id="project-detail-conversation-stream-mode"
                                    stream_mode={@conversation_stream_mode}
                                    discontinuity_count={@conversation_stream_discontinuity_count}
                                  />
                                </div>
                                <p
                                  id="project-detail-conversation-continuity-detail"
                                  class="mt-2 text-xs text-base-content/70"
                                >
                                  {conversation_continuity_detail(
                                    @conversation_stream_mode,
                                    @conversation_stream_discontinuity_count
                                  )}
                                </p>
                              </article>

                              <article class="rounded-md border border-base-300/70 bg-base-200/20 p-3">
                                <p class="text-[11px] uppercase tracking-wide text-base-content/60">
                                  Latest activity
                                </p>
                                <p
                                  id="project-detail-conversation-latest-activity"
                                  class="mt-1 text-sm font-medium"
                                >
                                  {conversation_latest_activity_label(@conversation_surface) ||
                                    "No recent conversation activity"}
                                </p>
                                <p class="mt-2 text-xs text-base-content/70">
                                  Route continuity stays anchored to the latest durable snapshot.
                                </p>
                              </article>

                              <article class="rounded-md border border-base-300/70 bg-base-200/20 p-3">
                                <p class="text-[11px] uppercase tracking-wide text-base-content/60">
                                  Current turn
                                </p>
                                <p
                                  id="project-detail-conversation-turn-state"
                                  class="mt-1 text-sm font-medium"
                                >
                                  {conversation_turn_summary(@conversation_snapshot)}
                                </p>
                                <p
                                  id="project-detail-conversation-sequence-summary"
                                  class="mt-2 text-xs text-base-content/70"
                                >
                                  {conversation_sequence_summary(
                                    @conversation_last_event_sequence,
                                    @conversation_stream_discontinuity_count
                                  )}
                                </p>
                              </article>
                            </div>
                          </div>

                          <div id="project-detail-conversation-events" class="max-h-96 space-y-3 overflow-y-auto px-4 py-4">
                            <%= for event <- @conversation_events do %>
                              <.conversation_event_row
                                id={"project-detail-conversation-event-#{map_get(event, :id, "id")}"}
                                sequence={map_get(event, :sequence, "sequence")}
                                label={conversation_event_label(event)}
                                event_name={map_get(event, :name, "name")}
                                occurred_at={format_time(map_get(event, :occurred_at, "occurred_at"))}
                                title={conversation_event_title(event)}
                                excerpt={conversation_event_excerpt(event)}
                                tone={conversation_event_tone(event)}
                              />
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

                            <form
                              id="project-detail-conversation-form"
                              phx-submit="send_conversation"
                              class="flex flex-col gap-3 sm:flex-row"
                            >
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
                                disabled={
                                  String.trim(@conversation_input) == "" || conversation_paused?(@conversation_snapshot)
                                }
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
                                <dd class="font-medium">
                                  <.conversation_status_badge
                                    id="project-detail-conversation-status-detail"
                                    status={Map.get(@conversation_surface.conversation, :status)}
                                  />
                                </dd>
                              </div>
                              <div class="flex justify-between gap-3">
                                <dt class="text-base-content/70">Scope</dt>
                                <dd class="font-medium">
                                  <.conversation_role_badge
                                    id="project-detail-conversation-scope"
                                    scope={Map.get(@conversation_surface.conversation, :scope)}
                                    attachment_mode={Map.get(@conversation_surface.conversation, :attachment_mode)}
                                    work_item_id={Map.get(@conversation_surface.conversation, :work_item_id)}
                                  />
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
                                <dt class="text-base-content/70">Resolution</dt>
                                <dd id="project-detail-conversation-work-resolution" class="font-medium">
                                  {conversation_work_resolution_action(@conversation_surface)}
                                </dd>
                              </div>
                              <div class="flex justify-between gap-3">
                                <dt class="text-base-content/70">Active turn</dt>
                                <dd class="font-medium">
                                  {conversation_turn_state(@conversation_snapshot)}
                                </dd>
                              </div>
                            </dl>

                            <section
                              :if={@conversation_surface.work_item}
                              id="project-detail-conversation-governed-work"
                              class="mt-4 rounded-lg border border-base-300/70 bg-base-200/20 p-3"
                            >
                              <div class="flex items-start justify-between gap-3">
                                <div class="space-y-1">
                                  <p class="text-xs uppercase tracking-wide text-base-content/60">
                                    Governed work item
                                  </p>
                                  <p
                                    id="project-detail-conversation-governed-work-summary"
                                    class="font-semibold"
                                  >
                                    {Map.get(@conversation_surface.work_item, :summary)}
                                  </p>
                                  <p
                                    id="project-detail-conversation-governed-work-id"
                                    class="text-xs font-mono text-base-content/60"
                                  >
                                    {Map.get(@conversation_surface.work_item, :id)}
                                  </p>
                                </div>
                                <span
                                  id="project-detail-conversation-governed-work-status"
                                  class="rounded-full bg-base-200 px-3 py-1 text-xs font-semibold"
                                >
                                  {Map.get(@conversation_surface.work_item, :status)}
                                </span>
                              </div>

                              <p
                                id="project-detail-conversation-work-resolution-detail"
                                class="mt-2 text-sm text-base-content/70"
                              >
                                {conversation_work_resolution_detail(@conversation_surface)}
                              </p>

                              <div class="mt-3 flex flex-wrap gap-2">
                                <.link
                                  :if={conversation_workbench_path(@project_detail)}
                                  id="project-detail-conversation-open-workbench"
                                  class="btn btn-xs btn-outline"
                                  navigate={conversation_workbench_path(@project_detail)}
                                >
                                  Open in Workbench
                                </.link>
                              </div>
                            </section>
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
                    <% @conversation_surface.conversation || @conversation_surface.work_item -> %>
                      <div class="p-4 space-y-4">
                        <section class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-3">
                          <p
                            :if={@conversation_surface.conversation}
                            id="project-detail-conversation-detail-summary"
                            class="text-sm text-base-content/80"
                          >
                            {conversation_surface_summary(@conversation_surface)}
                          </p>
                          <p
                            :if={@conversation_surface.work_item}
                            id="project-detail-conversation-detail-work-item"
                            class="text-sm text-base-content/70"
                          >
                            Governed work item: {Map.get(@conversation_surface.work_item, :summary)}
                          </p>
                          <p
                            :if={@conversation_surface.historical_conversation}
                            id="project-detail-conversation-detail-history"
                            class="text-xs text-base-content/70"
                          >
                            Historical lineage preserved from {@conversation_surface.historical_conversation.id}.
                          </p>
                          <div class="flex flex-wrap gap-2">
                            <button
                              :if={@selected_work_item_id}
                              id="project-detail-conversation-open-selected"
                              type="button"
                              class="btn btn-sm btn-primary"
                              phx-click="open_selected_conversation"
                            >
                              {@conversation_surface.action_label}
                            </button>
                            <button
                              :if={!@selected_work_item_id}
                              id="project-detail-conversation-open-detail"
                              type="button"
                              class="btn btn-sm btn-primary"
                              phx-click="open_repo_conversation"
                            >
                              {@repo_intake_surface.action_label}
                            </button>
                          </div>
                        </section>
                      </div>
                    <% true -> %>
                      <div class="p-4">
                        <div class="rounded-lg border border-dashed border-base-300 bg-base-200/30 p-4 space-y-3">
                          <p class="text-sm text-base-content/70">
                            Open a repository conversation to coordinate repo-scoped work without leaving the managed-repository detail route.
                          </p>
                          <button
                            id="project-detail-conversation-open-empty"
                            type="button"
                            class="btn btn-primary btn-sm"
                            phx-click="open_repo_conversation"
                          >
                            {@repo_intake_surface.action_label}
                          </button>
                        </div>
                      </div>
                  <% end %>
                </section>
              </div>
            </section>

            <section :if={@selected_detail_section == :semantic} id="project-detail-semantic-inspection" class="space-y-4">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Semantic repository inspection</h2>
                  <p class="text-sm text-base-content/70">
                    Semantic source-code graph insights stay repo-scoped, bounded, product-owned, and tied to this repository's own workspace binding.
                  </p>
                </div>
                <.link
                  id="project-detail-semantic-open-memory"
                  class="btn btn-xs btn-outline"
                  patch={
                    project_detail_section_path(
                      @project_detail,
                      @return_to_path,
                      section: :memory,
                      work_item_id: @selected_work_item_id
                    )
                  }
                >
                  Open memory and provenance
                </.link>
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
                  <.link
                    :if={workspace_binding_repair_visible?(@semantic_inspection.notice)}
                    id="project-detail-semantic-repair-workspace"
                    patch={
                      project_detail_section_path(
                        @project_detail,
                        @return_to_path,
                        section: :overview,
                        work_item_id: @selected_work_item_id,
                        anchor: "project-detail-workspace-binding-panel"
                      )
                    }
                    class="btn btn-sm btn-outline"
                  >
                    Repair workspace binding
                  </.link>
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
                      <p class="mt-1 text-xl font-semibold">
                        {semantic_group_count(@semantic_inspection.summary, :modules)}
                      </p>
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

            <section :if={@selected_detail_section == :memory} id="project-detail-memory-inspection" class="space-y-4">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Repository memory and provenance</h2>
                  <p class="text-sm text-base-content/70">
                    Durable coding memory and workflow provenance stay repository-scoped, freshness-aware, product-owned, and tied to this repository's own workspace binding.
                  </p>
                </div>
                <.link
                  id="project-detail-memory-open-semantic"
                  class="btn btn-xs btn-outline"
                  patch={
                    project_detail_section_path(
                      @project_detail,
                      @return_to_path,
                      section: :semantic,
                      work_item_id: @selected_work_item_id
                    )
                  }
                >
                  Open semantic inspection
                </.link>
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

              <div
                :if={workspace_binding_repair_visible?(@memory_inspection.notice)}
                id="project-detail-memory-repair-workspace"
                class="flex"
              >
                <.link
                  patch={
                    project_detail_section_path(
                      @project_detail,
                      @return_to_path,
                      section: :overview,
                      work_item_id: @selected_work_item_id,
                      anchor: "project-detail-workspace-binding-panel"
                    )
                  }
                  class="btn btn-sm btn-outline"
                >
                  Repair workspace binding
                </.link>
              </div>

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

            <div :if={@selected_detail_section == :workflows} id="project-detail-workflows-panel" class="space-y-4">
              <section class="space-y-2">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold">Workflow launch and defaults</h2>
                  <p class="text-sm text-base-content/70">
                    Keep repo-scoped workspace binding, readiness remediation, and governed workflow kickoff together so this route stays an action surface instead of generic repository tooling.
                  </p>
                </div>

                <article
                  id="project-detail-workflow-readiness-summary"
                  class="rounded-lg border border-base-300/70 bg-base-200/20 p-4 space-y-3"
                >
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="space-y-1">
                      <h3 class="font-semibold">Governed launch posture</h3>
                      <p
                        id="project-detail-workflow-readiness-detail"
                        class="text-sm text-base-content/70"
                      >
                        {workflow_family_summary(@project_detail)}
                      </p>
                    </div>
                    <span
                      id="project-detail-workflow-readiness-badge"
                      class={[
                        "badge border font-medium",
                        workflow_family_badge_class(@project_detail)
                      ]}
                    >
                      {workflow_family_badge_label(@project_detail)}
                    </span>
                  </div>
                </article>
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
                <div
                  :if={workspace_binding_repair_visible?(project_readiness(@project_detail))}
                  class="pt-2"
                >
                  <.link
                    id="project-detail-launch-disabled-repair"
                    patch={
                      project_detail_section_path(
                        @project_detail,
                        @return_to_path,
                        section: :overview,
                        work_item_id: @selected_work_item_id,
                        anchor: "project-detail-workspace-binding-panel"
                      )
                    }
                    class="btn btn-sm btn-outline"
                  >
                    Repair workspace binding
                  </.link>
                </div>
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
            </div>
          </.subject_pane>
        </.subject_tree_shell>
      </section>
    </Layouts.app>
    """
  end

  defp detail_section_items(assigns) do
    [
      %{section: :overview, label: "Overview"},
      %{section: :conversations, label: "Conversations"},
      %{section: :semantic, label: "Semantic"},
      %{section: :memory, label: "Memory"},
      %{section: :workflows, label: "Workflows"}
    ]
    |> Enum.map(fn section ->
      OperatorShell.child_subject(%{
        id: section.section,
        label: section.label,
        selected?: assigns.selected_detail_section == section.section,
        summary: detail_section_summary(section.section, assigns),
        badge: detail_section_badge(section.section, assigns),
        pane_id: "project-detail-pane-#{section.section}",
        patch:
          project_detail_section_path(
            assigns.project_detail,
            assigns.return_to_path,
            section: section.section,
            work_item_id: assigns.selected_work_item_id
          )
      })
      |> Map.put(:section, section.section)
    end)
  end

  defp project_detail_breadcrumbs(assigns) do
    [
      OperatorShell.breadcrumb(%{
        id: "project-detail-breadcrumb-return",
        label: return_to_label(assigns.return_to_path),
        navigate: assigns.return_to_path
      }),
      OperatorShell.breadcrumb(%{
        id: "project-detail-breadcrumb-current",
        label: assigns.project_detail.github_full_name,
        current?: true
      })
    ]
  end

  defp project_detail_parent_subjects do
    [
      OperatorShell.parent_subject(%{
        id: :repo,
        label: "Repo",
        description: "Canonical repository workspace for governed work, knowledge, and execution posture.",
        selected?: true
      })
    ]
  end

  defp project_detail_selected_pane(assigns) do
    section = assigns.selected_detail_section

    OperatorShell.pane(%{
      id: "project-detail-pane-#{section}",
      title: project_detail_pane_title(section),
      summary: project_detail_pane_summary(section)
    })
  end

  defp overview_family_guides(assigns) do
    assigns
    |> detail_section_items()
    |> Enum.reject(&(&1.section == :overview))
  end

  defp detail_section_summary(:overview, _assigns),
    do: "Repository identity, launch posture, and the next place to drill in."

  defp detail_section_summary(:conversations, assigns) do
    governed_count = length(Map.get(assigns, :conversation_roster, []))
    repo_intake_open? = is_map(Map.get(Map.get(assigns, :repo_intake_surface, %{}), :conversation))

    cond do
      repo_intake_open? and governed_count > 0 ->
        "Repo intake plus #{governed_count} governed conversation threads."

      repo_intake_open? ->
        "Repo intake is open for bounded clarification before work settles."

      governed_count > 0 ->
        "#{governed_count} governed work-item conversations remain active here."

      true ->
        "Repo intake and governed work stay hosted on this route."
    end
  end

  defp detail_section_summary(:semantic, _assigns),
    do: "Source-code graph freshness, recovery, and bounded structural inspection."

  defp detail_section_summary(:memory, _assigns),
    do: "Durable coding memory, workflow provenance, and freshness validation."

  defp detail_section_summary(:workflows, assigns) do
    if project_ready_for_launch?(Map.get(assigns, :project_detail)) do
      "Launch defaults and governed workflow kickoff are ready."
    else
      "Workflow launch posture is blocked and needs remediation."
    end
  end

  defp project_detail_pane_title(:overview), do: "Repository overview"
  defp project_detail_pane_title(:conversations), do: "Repository conversation"
  defp project_detail_pane_title(:semantic), do: "Semantic inspection"
  defp project_detail_pane_title(:memory), do: "Repository memory"
  defp project_detail_pane_title(:workflows), do: "Workflow launch"

  defp project_detail_pane_summary(:overview),
    do:
      "Repository identity, launch posture, and workflow readiness stay together here before you drill into work, knowledge, or execution detail."

  defp project_detail_pane_summary(:conversations),
    do:
      "Repo intake, governed work-item conversations, and degraded continuity stay product-owned on this managed-repository route."

  defp project_detail_pane_summary(:semantic),
    do:
      "Freshness, recovery, and bounded graph exploration stay explicit here before semantic context informs operator follow-up."

  defp project_detail_pane_summary(:memory),
    do:
      "Durable coding memory, workflow provenance, and validation remain product-owned here before memory influences operator decisions."

  defp project_detail_pane_summary(:workflows),
    do:
      "Builtin workflow launch stays governed and repository-scoped here so blocked remediation and run traceability stay together."

  defp return_to_label("/dashboard"), do: "Dashboard"
  defp return_to_label("/repos"), do: "Repositories"
  defp return_to_label("/workbench"), do: "Workbench"
  defp return_to_label("/settings"), do: "Settings"
  defp return_to_label(path) when is_binary(path), do: "Back"

  defp detail_section_badge(:overview, _assigns), do: nil

  defp detail_section_badge(:conversations, assigns) do
    governed_count = length(Map.get(assigns, :conversation_roster, []))
    repo_intake_open? = is_map(Map.get(Map.get(assigns, :repo_intake_surface, %{}), :conversation))
    runtime_status = Map.get(Map.get(assigns, :conversation_runtime, %{}), :status)
    snapshot = Map.get(assigns, :conversation_snapshot)
    stream_mode = Map.get(assigns, :conversation_stream_mode)

    cond do
      runtime_status == :blocked -> %{label: "Blocked", tone: :error}
      conversation_pending_clarification(snapshot) -> %{label: "Input", tone: :warning}
      stream_mode == :degraded -> %{label: "Snapshot", tone: :warning}
      governed_count > 0 -> %{label: Integer.to_string(governed_count), tone: :info}
      repo_intake_open? -> %{label: "Intake", tone: :info}
      true -> %{label: "Idle", tone: :neutral}
    end
  end

  defp detail_section_badge(:semantic, assigns) do
    detail_section_graph_badge(
      Map.get(assigns, :semantic_inspection),
      &semantic_notice_visible?/1
    )
  end

  defp detail_section_badge(:memory, assigns) do
    detail_section_graph_badge(
      Map.get(assigns, :memory_inspection),
      &memory_notice_visible?/1
    )
  end

  defp detail_section_badge(:workflows, assigns) do
    if project_ready_for_launch?(Map.get(assigns, :project_detail)) do
      %{label: "Ready", tone: :success}
    else
      %{label: "Blocked", tone: :warning}
    end
  end

  defp detail_section_graph_badge(%{} = inspection, notice_visible?) when is_function(notice_visible?, 1) do
    state =
      inspection
      |> Map.get(:graph, %{})
      |> Map.get(:state, :unavailable)

    tone =
      cond do
        notice_visible?.(inspection) -> :warning
        state in [:ready, "ready"] -> :success
        state in [:stale, "stale"] -> :warning
        true -> :neutral
      end

    %{label: detail_section_state_label(state), tone: tone}
  end

  defp detail_section_graph_badge(_inspection, _notice_visible?),
    do: %{label: "Unavailable", tone: :neutral}

  defp detail_section_state_label(state) when is_atom(state) do
    state
    |> Atom.to_string()
    |> detail_section_state_label()
  end

  defp detail_section_state_label(state) when is_binary(state) do
    case String.trim(state) do
      "" -> "Unavailable"
      value -> value |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp detail_section_state_label(_state), do: "Unavailable"

  defp detail_section_badge_class(:success), do: "border-success/50 bg-success/10 text-success"
  defp detail_section_badge_class(:warning), do: "border-warning/50 bg-warning/10 text-warning-content"
  defp detail_section_badge_class(:error), do: "border-error/50 bg-error/10 text-error"
  defp detail_section_badge_class(:info), do: "border-info/50 bg-info/10 text-info"
  defp detail_section_badge_class(:neutral), do: "border-base-300 bg-base-200/70 text-base-content/75"

  defp workflow_family_badge_label(project_detail) do
    if project_ready_for_launch?(project_detail), do: "Ready", else: "Blocked"
  end

  defp workflow_family_badge_class(project_detail) do
    if project_ready_for_launch?(project_detail) do
      detail_section_badge_class(:success)
    else
      detail_section_badge_class(:warning)
    end
  end

  defp workflow_family_summary(project_detail) do
    if project_ready_for_launch?(project_detail) do
      "Launch defaults are ready and workflow kickoff from this route preserves governed run traceability."
    else
      readiness = project_readiness(project_detail)

      [Map.get(readiness, :detail), Map.get(readiness, :remediation)]
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
      |> Enum.join(" ")
      |> case do
        "" ->
          "Workflow launch is currently blocked for this managed repository."

        summary ->
          summary
      end
    end
  end

  defp conversation_workspace_focus_label(selected_work_item_id, conversation_surface, repo_intake_surface) do
    cond do
      is_binary(selected_work_item_id) and is_map(Map.get(conversation_surface, :work_item)) ->
        Map.get(Map.get(conversation_surface, :work_item), :summary) || selected_work_item_id

      is_map(Map.get(repo_intake_surface, :conversation)) ->
        "Repo intake"

      true ->
        "No active selection"
    end
  end

  defp conversation_workspace_focus_summary(selected_work_item_id, _conversation_surface, repo_intake_surface) do
    cond do
      is_binary(selected_work_item_id) ->
        "Following the productive conversation, transcript, and runtime posture for the selected governed work item."

      is_map(Map.get(repo_intake_surface, :conversation)) ->
        "Repo-scoped intake remains available for pre-work clarification and demand shaping."

      true ->
        "Open or resume a repository conversation here to coordinate work without leaving the managed-repository route."
    end
  end

  defp conversation_governed_summary(conversation_roster) when is_list(conversation_roster) do
    case length(conversation_roster) do
      0 -> "No governed work-item conversations are active on this repository yet."
      1 -> "One governed work-item thread is currently active and resumable from this route."
      count -> "#{count} governed work-item threads are currently active and resumable from this route."
    end
  end

  defp conversation_workspace_runtime_label(conversation_runtime, :degraded),
    do: "#{conversation_runtime_status_label(conversation_runtime)} / snapshot only"

  defp conversation_workspace_runtime_label(conversation_runtime, _stream_mode),
    do: conversation_runtime_status_label(conversation_runtime)

  defp conversation_workspace_runtime_summary(conversation_runtime, stream_mode) do
    cond do
      Map.get(conversation_runtime, :status) == :blocked ->
        "Runtime prerequisites are blocked, but the latest durable conversation state remains visible on this route."

      stream_mode == :degraded ->
        "Live delivery is degraded, so the conversation family is showing the latest durable snapshot."

      true ->
        "Runtime posture, selected model, and continuity remain legible while work continues."
    end
  end

  defp empty_conversation_surface do
    %{
      available?: false,
      managed_repo_id: nil,
      conversation: nil,
      historical_conversation: nil,
      work_item: nil,
      snapshot: nil,
      recent_events: [],
      notice: nil,
      action_label: "Open repo conversation"
    }
  end

  defp empty_conversation_runtime do
    %{
      status: :idle,
      notice: nil,
      llm_selection: nil,
      workspace_path: nil
    }
  end

  defp assign_conversation_runtime(socket, project_detail) do
    assign(socket, :conversation_runtime, load_conversation_runtime(project_detail))
  end

  defp load_conversation_runtime(%{} = project_detail) do
    managed_repo_id =
      project_detail
      |> Map.get(:managed_repo_id)
      |> present_optional_string()

    llm_selection = resolve_runtime_llm_selection(project_detail)
    workspace_path = project_detail |> runtime_workspace_path() |> present_optional_string()

    case managed_repo_id do
      nil ->
        %{
          status: :blocked,
          notice: %{
            error_type: "conversation_runtime_repo_scope_invalid",
            detail: "Managed repository scope is missing for real conversation runtime.",
            remediation: "Open the repository from a managed-repository route and retry the conversation."
          },
          llm_selection: llm_selection,
          workspace_path: workspace_path
        }

      _managed_repo_id ->
        case RuntimeReadiness.resolve(managed_repo_id) do
          {:ok, readiness} ->
            %{
              status: :ready,
              notice: nil,
              llm_selection: LLMSelection.summary(readiness.llm_selection),
              workspace_path: readiness.workspace_path
            }

          {:error, %{} = notice} ->
            %{
              status: :blocked,
              notice: notice,
              llm_selection: llm_selection,
              workspace_path: workspace_path
            }
        end
    end
  end

  defp load_conversation_runtime(_project_detail), do: empty_conversation_runtime()

  defp resolve_runtime_llm_selection(project_detail) do
    case LLMSelection.resolve_from_project_detail(project_detail) do
      {:ok, selection} -> LLMSelection.summary(selection)
      _other -> nil
    end
  end

  defp runtime_workspace_path(%{} = project_detail) do
    ProjectDetail.workspace_path(project_detail)
  end

  defp runtime_workspace_path(_project_detail), do: nil

  defp refresh_project_detail_surface(socket) do
    case socket.assigns.project_detail do
      %{id: project_id} when is_binary(project_id) ->
        case ProjectDetail.load(project_id) do
          {:ok, project_detail} ->
            socket
            |> assign(:project_detail, project_detail)
            |> assign(:project_load_error, nil)
            |> assign(:semantic_inspection, ProjectSemanticInspection.load_repo_detail(project_detail))
            |> assign(:memory_inspection, ProjectMemoryInspection.load_repo_detail(project_detail))
            |> assign_workspace_binding_form(project_detail)
            |> assign_project_conversation(project_detail, socket.assigns.selected_work_item_id)

          {:error, project_load_error} ->
            socket
            |> assign(:project_load_error, project_load_error)
            |> assign(:semantic_inspection, nil)
            |> assign(:memory_inspection, nil)
            |> clear_project_conversation()
        end

      _other ->
        socket
    end
  end

  defp assign_workspace_binding_form(socket, %{} = source) do
    form_values = workspace_binding_form_values(source)

    socket
    |> assign(:workspace_binding_form_values, form_values)
    |> assign(:workspace_binding_form, to_form(form_values, as: :workspace_binding))
  end

  defp assign_workspace_binding_form(socket, source) do
    assign_workspace_binding_form(socket, workspace_binding_form_values(source))
  end

  defp workspace_binding_form_values(%{} = source) do
    binding = workspace_binding_form_source(source)

    %{
      "workspace_environment" =>
        binding
        |> Map.get("workspace_environment", Map.get(binding, :workspace_environment))
        |> workspace_binding_form_environment(),
      "workspace_path" =>
        binding
        |> Map.get("workspace_path", Map.get(binding, :workspace_path))
        |> normalize_optional_string() || ""
    }
  end

  defp workspace_binding_form_values(_source),
    do: %{"workspace_environment" => "sprite", "workspace_path" => ""}

  defp workspace_binding_form_source(%{workspace_environment: _workspace_environment} = binding),
    do: normalize_workspace_binding_form_params(binding)

  defp workspace_binding_form_source(%{"workspace_environment" => _workspace_environment} = binding),
    do: normalize_workspace_binding_form_params(binding)

  defp workspace_binding_form_source(%{workspace_path: _workspace_path} = binding),
    do: normalize_workspace_binding_form_params(binding)

  defp workspace_binding_form_source(%{"workspace_path" => _workspace_path} = binding),
    do: normalize_workspace_binding_form_params(binding)

  defp workspace_binding_form_source(source), do: ProjectDetail.workspace_binding(source)

  defp normalize_workspace_binding_form_params(params) when is_map(params) do
    %{
      "workspace_environment" =>
        params
        |> map_get(:workspace_environment, "workspace_environment")
        |> workspace_binding_form_environment(),
      "workspace_path" =>
        params
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_optional_string()
    }
  end

  defp normalize_workspace_binding_form_params(_params),
    do: %{"workspace_environment" => "sprite", "workspace_path" => nil}

  defp workspace_binding_form_environment(:local), do: "local"
  defp workspace_binding_form_environment("local"), do: "local"
  defp workspace_binding_form_environment(_workspace_environment), do: "sprite"

  defp workspace_binding_form_local?(%{} = form_values) do
    form_values
    |> Map.get("workspace_environment")
    |> workspace_binding_form_environment() == "local"
  end

  defp workspace_binding_form_local?(_form_values), do: false

  defp workspace_binding_derived_root_note(%{} = form_values) do
    case form_values |> Map.get("workspace_path") |> normalize_optional_string() do
      nil ->
        "Choose the absolute path for this repository. The parent directory shown below is derived from that saved path."

      workspace_path ->
        if Path.type(workspace_path) == :absolute do
          "Derived parent directory: #{Path.dirname(Path.expand(workspace_path))}"
        else
          "Choose an absolute path for this repository. The parent directory shown below is derived from that saved path."
        end
    end
  end

  defp workspace_binding_derived_root_note(_form_values) do
    "Choose the absolute path for this repository. The parent directory shown below is derived from that saved path."
  end

  defp workspace_binding_save_button_label(%{} = form_values) do
    if workspace_binding_form_local?(form_values) do
      "Save repo workspace path"
    else
      "Save cloud-default binding"
    end
  end

  defp workspace_binding_save_button_label(_form_values), do: "Save repo workspace binding"

  defp workspace_binding_badge_label(project_detail) do
    binding = ProjectDetail.workspace_binding(project_detail)

    cond do
      binding.bound? -> "Bound"
      binding.local? -> "Needs path"
      true -> "Cloud default only"
    end
  end

  defp workspace_binding_badge_tone(project_detail) do
    binding = ProjectDetail.workspace_binding(project_detail)

    cond do
      binding.bound? -> :success
      binding.local? -> :warning
      true -> :neutral
    end
  end

  defp workspace_binding_environment_label(project_detail) do
    case ProjectDetail.workspace_binding(project_detail).workspace_environment do
      :local -> "Local"
      _other -> "Cloud default only"
    end
  end

  defp workspace_binding_path_label(project_detail) do
    case ProjectDetail.workspace_binding(project_detail).workspace_path do
      workspace_path when is_binary(workspace_path) -> workspace_path
      _other -> "No repo-scoped local workspace path saved"
    end
  end

  defp workspace_binding_root_label(project_detail) do
    case ProjectDetail.workspace_binding(project_detail).workspace_root do
      workspace_root when is_binary(workspace_root) -> workspace_root
      _other -> "Derived after a local path is saved"
    end
  end

  defp workspace_binding_route_readiness_label(project_detail) do
    case project_readiness(project_detail) do
      %{status: :ready} -> "Ready"
      _other -> "Blocked"
    end
  end

  defp workspace_binding_repair_visible?(%{} = state) do
    state
    |> Map.get(:error_type, Map.get(state, "error_type"))
    |> normalize_optional_string()
    |> case do
      "conversation_runtime_workspace_binding_missing" -> true
      "conversation_runtime_workspace_binding_unavailable" -> true
      "managed_repo_workspace_binding_missing" -> true
      "managed_repo_workspace_binding_unavailable" -> true
      "semantic_workspace_binding_unavailable" -> true
      "memory_workspace_binding_unavailable" -> true
      _other -> false
    end
  end

  defp workspace_binding_repair_visible?(_state), do: false

  defp assign_project_conversation(socket, project_detail, selected_work_item_id) do
    previous_conversation_id = conversation_id(socket)
    actor = initiating_actor(socket)

    repo_intake_surface =
      ProjectConversation.load_repo_detail(project_detail, actor: actor)

    roster_result = ProjectConversation.load_active_work_item_roster(project_detail, actor: actor)

    effective_selected_work_item_id =
      resolve_selected_work_item_id(
        selected_work_item_id,
        repo_intake_surface,
        roster_result.entries
      )

    selected_surface =
      case effective_selected_work_item_id do
        work_item_id when is_binary(work_item_id) ->
          ProjectConversation.load_work_item_linkage(work_item_id, actor: actor)

        _other ->
          repo_intake_surface
      end

    socket
    |> assign(:repo_intake_surface, repo_intake_surface)
    |> assign(:conversation_roster, roster_result.entries)
    |> assign(:conversation_roster_notice, roster_result.notice)
    |> assign(:selected_work_item_id, effective_selected_work_item_id)
    |> assign_conversation_runtime(project_detail)
    |> assign_conversation_surface(selected_surface)
    |> sync_conversation_subscription(previous_conversation_id)
  end

  defp clear_project_conversation(socket) do
    socket
    |> assign(:repo_intake_surface, empty_conversation_surface())
    |> assign(:conversation_roster, [])
    |> assign(:conversation_roster_notice, nil)
    |> assign(:conversation_surface, empty_conversation_surface())
    |> assign(:conversation_snapshot, nil)
    |> assign(:conversation_events, [])
    |> assign(:conversation_runtime, empty_conversation_runtime())
    |> assign(:conversation_last_event_sequence, 0)
    |> assign(:conversation_input, "")
    |> assign(:conversation_action_feedback, nil)
    |> assign(:conversation_action_feedback_kind, :info)
    |> assign(:conversation_stream_mode, :idle)
    |> assign(:conversation_stream_degraded_reason, nil)
    |> assign(:conversation_stream_discontinuity_count, 0)
  end

  defp assign_conversation_surface(socket, projection) do
    snapshot = Map.get(projection, :snapshot)
    recent_events = Map.get(projection, :recent_events, [])

    socket
    |> assign(:conversation_surface, projection)
    |> assign(:conversation_snapshot, snapshot)
    |> assign(:conversation_events, recent_events)
    |> assign(:conversation_last_event_sequence, (snapshot && snapshot.last_event_sequence) || 0)
    |> assign(:conversation_stream_mode, conversation_stream_mode(projection))
    |> assign(:conversation_stream_degraded_reason, conversation_stream_reason(projection))
    |> assign(:conversation_stream_discontinuity_count, 0)
  end

  defp assign_conversation_snapshot(socket, snapshot) do
    next_selected_work_item_id =
      socket.assigns.selected_work_item_id ||
        present_optional_string(Map.get(snapshot, :work_item_id))

    assign_project_conversation(
      socket,
      socket.assigns.project_detail,
      next_selected_work_item_id
    )
  end

  defp sync_conversation_subscription(socket, previous_conversation_id) do
    current_conversation_id = conversation_id(socket)

    if is_binary(previous_conversation_id) and previous_conversation_id != current_conversation_id do
      _ = ConversationPubSub.unsubscribe_conversation(previous_conversation_id)
    end

    maybe_subscribe_conversation(socket)
  end

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

  defp conversation_input_command(socket, input, params) do
    payload =
      %{}
      |> Map.put("instruction", input)
      |> maybe_put("workflow", normalize_optional_string(Map.get(params, "workflow")))
      |> maybe_put("workflow_name", normalize_optional_string(Map.get(params, "workflow_name")))

    case socket.assigns.conversation_snapshot do
      %{active_turn_id: turn_id} = snapshot when is_binary(turn_id) ->
        if conversation_awaiting_input?(snapshot) do
          %{
            type: "turn.resume",
            payload:
              payload
              |> Map.take(["workflow", "workflow_name"])
              |> Map.put("turn_id", turn_id)
              |> Map.put("response", input)
          }
        else
          %{type: "turn.submit", payload: payload}
        end

      _other ->
        %{type: "turn.submit", payload: payload}
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

  defp conversation_work_resolution_action(%{conversation: %{work_resolution: %{} = work_resolution}}) do
    Map.get(work_resolution, "action", "repo_scoped")
  end

  defp conversation_work_resolution_action(_surface), do: "repo_scoped"

  defp conversation_work_resolution_detail(%{conversation: %{work_resolution: %{} = work_resolution}}) do
    Map.get(work_resolution, "detail")
  end

  defp conversation_work_resolution_detail(_surface), do: nil

  defp conversation_workbench_path(%{id: project_id}) when is_binary(project_id) do
    "/workbench?" <> URI.encode_query(%{"project_id" => project_id})
  end

  defp conversation_workbench_path(_project_detail), do: nil

  defp repo_intake_summary(%{} = surface) do
    repo_intake_handoff_detail(surface) ||
      conversation_surface_summary(surface) ||
      "Repo intake is available from this managed-repository route."
  end

  defp repo_intake_summary(_surface),
    do: "Repo intake is available from this managed-repository route."

  defp repo_intake_handoff_work_item_id(%{} = surface) do
    surface
    |> Map.get(:conversation)
    |> Kernel.||(%{})
    |> Map.get(:intake_handoff)
    |> Kernel.||(%{})
    |> Map.get("work_item_id")
    |> present_optional_string()
  end

  defp repo_intake_handoff_work_item_id(_surface), do: nil

  defp repo_intake_handoff_detail(%{} = surface) do
    handoff =
      surface
      |> Map.get(:conversation)
      |> Kernel.||(%{})
      |> Map.get(:intake_handoff)
      |> Kernel.||(%{})

    case handoff do
      %{"handoff_kind" => "repo_intake_to_work_item", "work_item_id" => work_item_id}
      when is_binary(work_item_id) ->
        "Repo intake handed off to governed WorkItem #{work_item_id} and preserved the intake continuity here."

      _other ->
        nil
    end
  end

  defp repo_intake_handoff_detail(_surface), do: nil

  defp conversation_surface_summary(%{conversation: %{} = conversation} = surface) do
    normalize_optional_string(conversation_work_resolution_detail(surface)) ||
      normalize_optional_string(Map.get(conversation, :objective)) ||
      normalize_optional_string(Map.get(conversation, :title)) ||
      case Map.get(surface, :work_item) do
        %{} = work_item ->
          "Governed conversation is attached to #{Map.get(work_item, :summary) || Map.get(work_item, "summary") || "the selected work item"}."

        _other ->
          "Conversation detail is available on this route."
      end
  end

  defp conversation_surface_summary(%{work_item: %{} = work_item}) do
    "Governed work item #{Map.get(work_item, :summary) || Map.get(work_item, "summary") || Map.get(work_item, :id)} is ready for conversation detail."
  end

  defp conversation_surface_summary(_surface), do: nil

  defp conversation_latest_activity_label(%{} = surface) do
    surface
    |> Map.get(:conversation)
    |> Kernel.||(%{})
    |> Map.get(:last_activity_at)
    |> format_activity_time()
    |> Kernel.||(
      surface
      |> Map.get(:work_item)
      |> Kernel.||(%{})
      |> Map.get(:updated_at)
      |> format_activity_time()
    )
  end

  defp conversation_latest_activity_label(_surface), do: nil

  defp conversation_runtime_notice_visible?(%{notice: %{} = _notice}), do: true
  defp conversation_runtime_notice_visible?(_runtime), do: false

  defp conversation_runtime_preserves_state?(%{status: :blocked}, %{snapshot: %{} = _snapshot}), do: true
  defp conversation_runtime_preserves_state?(%{status: :blocked}, %{work_item: %{} = _work_item}), do: true
  defp conversation_runtime_preserves_state?(_runtime, _surface), do: false

  defp conversation_runtime_status_label(%{status: :ready}), do: "Ready"
  defp conversation_runtime_status_label(%{status: :blocked}), do: "Blocked"
  defp conversation_runtime_status_label(_runtime), do: "Idle"

  defp conversation_runtime_status_class(%{status: :ready}), do: "badge-success"
  defp conversation_runtime_status_class(%{status: :blocked}), do: "badge-error"
  defp conversation_runtime_status_class(_runtime), do: "badge-ghost"

  defp conversation_runtime_llm_label(%{llm_selection: %{model_spec: model_spec}})
       when is_binary(model_spec),
       do: model_spec

  defp conversation_runtime_llm_label(_runtime), do: "No provider/model selected"

  defp conversation_runtime_source_label(%{llm_selection: %{source: source}}) when is_atom(source) do
    case source do
      :explicit -> "Explicit override"
      :conversation -> "Conversation metadata"
      :repo_default -> "Managed repo default"
      :system_default -> "System default"
      other -> other |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp conversation_runtime_source_label(_runtime), do: "Unavailable"

  defp conversation_runtime_workspace_label(%{workspace_path: path}) when is_binary(path), do: path
  defp conversation_runtime_workspace_label(_runtime), do: ProjectWorkspaceBindingNotice.missing_path_label()

  defp conversation_continuity_detail(:live, 0), do: "Live events are arriving without detected gaps."

  defp conversation_continuity_detail(:live, discontinuity_count) when discontinuity_count > 0 do
    "Live delivery recovered from #{discontinuity_count} continuity gap(s)."
  end

  defp conversation_continuity_detail(:degraded, discontinuity_count) when discontinuity_count > 0 do
    "Showing the durable snapshot after #{discontinuity_count} continuity gap(s)."
  end

  defp conversation_continuity_detail(:degraded, _discontinuity_count) do
    "Showing the durable snapshot while live delivery is unavailable."
  end

  defp conversation_continuity_detail(_stream_mode, _discontinuity_count) do
    "Conversation continuity metadata will appear once a route-owned transcript is available."
  end

  defp conversation_turn_summary(snapshot) do
    cond do
      conversation_awaiting_input?(snapshot) ->
        "Clarification required"

      conversation_active_turn?(snapshot) ->
        "Turn in progress"

      conversation_paused?(snapshot) ->
        "Conversation paused"

      true ->
        "No active turn"
    end
  end

  defp conversation_sequence_summary(last_event_sequence, discontinuity_count)
       when is_integer(last_event_sequence) do
    "Sequence #{last_event_sequence}. Continuity gaps #{discontinuity_count}."
  end

  defp conversation_sequence_summary(_last_event_sequence, discontinuity_count) do
    "Sequence unavailable. Continuity gaps #{discontinuity_count}."
  end

  defp conversation_roster_selected?(selected_work_item_id, %{} = entry) when is_binary(selected_work_item_id) do
    entry_work_item_id =
      entry
      |> Map.get(:work_item)
      |> Kernel.||(%{})
      |> Map.get(:id)
      |> present_optional_string()

    entry_work_item_id == selected_work_item_id
  end

  defp conversation_roster_selected?(_selected_work_item_id, _entry), do: false

  defp selected_conversation_title(selected_work_item_id, _surface) when is_binary(selected_work_item_id),
    do: "Governed conversation detail"

  defp selected_conversation_title(_selected_work_item_id, _surface), do: "Repo intake detail"

  defp selected_conversation_summary(selected_work_item_id, %{} = surface)
       when is_binary(selected_work_item_id) do
    case Map.get(surface, :work_item) do
      %{} = work_item ->
        "Active or historical governed conversation detail for #{Map.get(work_item, :summary) || Map.get(work_item, "summary") || selected_work_item_id}."

      _other ->
        "Governed conversation detail stays attached to the selected work item."
    end
  end

  defp selected_conversation_summary(_selected_work_item_id, %{} = surface) do
    repo_intake_summary(surface)
  end

  defp selected_conversation_summary(_selected_work_item_id, _surface),
    do: "Repo intake detail stays on this managed-repository route."

  defp format_activity_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp format_activity_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_activity_time(datetime)
      _other -> nil
    end
  end

  defp format_activity_time(_value), do: nil

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
    case map_get(event, :name, "name", "") do
      "conversation.message_added" ->
        "input"

      "conversation.status_changed" ->
        "status"

      "turn.awaiting_input" ->
        "clarification"

      "turn.delta" ->
        "progress"

      "tool.progress" ->
        "progress"

      "tool.stdout" ->
        "tool output"

      "tool.failed" ->
        "failure"

      "tool.cancel_failed" ->
        "failure"

      "" ->
        "event"

      name when is_binary(name) ->
        cond do
          String.starts_with?(name, "tool.") -> "tool"
          String.starts_with?(name, "turn.") -> "turn"
          true -> name |> String.split(".", parts: 2) |> List.first()
        end

      _other ->
        "event"
    end
  end

  defp conversation_event_tone(event) do
    case map_get(event, :name, "name", "") do
      "conversation.message_added" ->
        :input

      "conversation.status_changed" ->
        :status

      "turn.awaiting_input" ->
        :warning

      "turn.completed" ->
        :success

      "turn.cancelled" ->
        :warning

      "turn.cancelling" ->
        :warning

      "turn.delta" ->
        :progress

      "tool.progress" ->
        :progress

      "tool.stdout" ->
        :tool

      "tool.started" ->
        :tool

      "tool.completed" ->
        :success

      "tool.cancelled" ->
        :warning

      "tool.failed" ->
        :error

      "tool.cancel_failed" ->
        :error

      name when is_binary(name) ->
        if String.starts_with?(name, "turn."), do: :turn, else: :neutral

      _other ->
        :neutral
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

  defp resolve_selected_work_item_id(selected_work_item_id, repo_intake_surface, roster_entries) do
    selected_work_item_id ||
      repo_intake_surface
      |> case do
        %{} = intake_surface ->
          intake_surface
          |> Map.get(:conversation)
          |> Kernel.||(%{})
          |> Map.get(:work_item_id)

        _other ->
          nil
      end
      |> present_optional_string() ||
      roster_entries
      |> List.first()
      |> case do
        %{} = entry ->
          entry
          |> Map.get(:work_item)
          |> Kernel.||(%{})
          |> Map.get(:id)
          |> present_optional_string()

        _other ->
          nil
      end
  end

  defp project_detail_conversation_path(project_detail, return_to_path, work_item_id) do
    project_detail_section_path(
      project_detail,
      return_to_path,
      section: :conversations,
      work_item_id: work_item_id,
      anchor: "project-detail-conversation-panel"
    )
  end

  defp project_detail_section_path(project_detail, return_to_path, opts) do
    project_id =
      project_detail
      |> Map.get(:id)
      |> present_optional_string()

    section =
      opts
      |> Keyword.get(:section, :overview)
      |> normalize_detail_section()

    work_item_id =
      opts
      |> Keyword.get(:work_item_id)
      |> present_optional_string()

    anchor =
      opts
      |> Keyword.get(:anchor)
      |> present_optional_string()

    query =
      %{}
      |> maybe_put("return_to", normalized_return_to_param(return_to_path))
      |> maybe_put("section", detail_section_param(section))
      |> maybe_put("work_item_id", work_item_id)

    query_suffix =
      case query do
        empty when empty == %{} -> ""
        params -> "?" <> URI.encode_query(params)
      end

    anchor_suffix =
      case anchor do
        nil -> ""
        value -> "##{value}"
      end

    case project_id do
      nil -> "/repos"
      id -> "/repos/#{id}#{query_suffix}#{anchor_suffix}"
    end
  end

  defp detail_section_param(:overview), do: nil
  defp detail_section_param(section), do: Atom.to_string(section)

  defp normalize_detail_section(section) when is_atom(section) and section in @detail_sections,
    do: section

  defp normalize_detail_section(section) when is_binary(section) do
    section
    |> normalize_optional_string()
    |> case do
      "overview" -> :overview
      "conversations" -> :conversations
      "semantic" -> :semantic
      "memory" -> :memory
      "workflows" -> :workflows
      _other -> :overview
    end
  end

  defp normalize_detail_section(_section), do: :overview

  defp normalized_return_to_param("/workbench"), do: nil
  defp normalized_return_to_param(value), do: present_optional_string(value)

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

  defp memory_notice_visible?(%{notice: notice}) when is_map(notice), do: true
  defp memory_notice_visible?(_inspection), do: false

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

  defp present_optional_string(value) do
    case normalize_optional_string(value) do
      "nil" -> nil
      normalized -> normalized
    end
  end
end
