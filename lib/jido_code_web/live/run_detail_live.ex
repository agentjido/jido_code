defmodule JidoCodeWeb.RunDetailLive do
  # covers: package.jido_code.primary_implementation_repo
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.governed_run_memory_context_does_not_displace_posture_state
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  # covers: architecture.runtime_service_overlay.runtime_narratives_can_coexist_with_bounded_memory_context
  # covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  # covers: architecture.run_governance.run_detail_can_host_bounded_memory_context
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.governed_run_routes_host_work_conversations
  # covers: architecture.source_code_graph_product_adoption.governed_surfaces_may_cohost_semantic_cross_links
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  use JidoCodeWeb, :live_view

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Conversations.PubSub, as: ConversationPubSub
  alias JidoCode.Governance.{ChangeRequest, Decision, Evidence, RepoPosture}
  alias JidoCode.MemoryGraph.{FollowUpSurface, GovernedSurfaceContext, OperatorService, ProductService, SurfaceFeedback}
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.{Run, RunPubSub}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.RunConversation

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
  @conversation_progress_delay_ms 60
  @conversation_stdout_delay_ms 100
  @conversation_clarification_delay_ms 140
  @conversation_delta_delay_ms 180
  @conversation_completion_delay_ms 240
  @conversation_resume_delta_delay_ms 80
  @conversation_resume_completion_delay_ms 160
  @conversation_cancellation_settle_delay_ms 80
  @conversation_degraded_mode_message "Live conversation stream unavailable. Showing the latest governed work conversation snapshot only."

  @impl true
  def mount(%{"id" => project_id, "run_id" => run_id}, _session, socket) do
    socket =
      socket
      |> clear_run_conversation()
      |> assign(:project_id, project_id)
      |> assign(:run_id, run_id)
      |> assign(:memory_action_feedback, nil)
      |> assign(:approval_action_error, nil)
      |> assign(:retry_action_error, nil)

    socket =
      case load_run_state(project_id, run_id) do
        {:ok, run_state} ->
          socket
          |> assign_run_state(run_state)

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
  def handle_info({:conversation_event, event}, socket) do
    if conversation_event_applies?(socket, event) do
      event_sequence = map_get(event, :sequence, "sequence")

      cond do
        not is_integer(event_sequence) ->
          {:noreply, socket}

        event_sequence <= socket.assigns.conversation_last_event_sequence ->
          {:noreply, socket}

        event_sequence == socket.assigns.conversation_last_event_sequence + 1 ->
          {:noreply, append_conversation_event(socket, event)}

        true ->
          {:noreply, recover_run_conversation_gap(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:run_detail_conversation_tool_result, conversation_id, child_work_id, payload}, socket) do
    if conversation_id(socket) == conversation_id do
      case JidoCode.AgentWorkspace.conversation_snapshot(conversation_id) do
        {:ok, snapshot} ->
          if child_work_open?(snapshot, child_work_id) or child_work_cancelling?(snapshot, child_work_id) do
            case JidoCode.AgentWorkspace.handle_conversation_command(
                   conversation_id,
                   %{
                     type: "tool_result.submit",
                     payload: Map.put(payload, :child_work_id, child_work_id)
                   },
                   actor: approving_actor(socket)
                 ) do
              {:ok, updated_snapshot} ->
                {:noreply, assign_conversation_snapshot(socket, updated_snapshot)}

              {:error, _reason} ->
                {:noreply, socket}
            end
          else
            {:noreply, socket}
          end

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("approve_run", _params, %{assigns: %{run: %Run{} = run}} = socket) do
    case Run.approve(run, %{
           actor: approving_actor(socket),
           current_step: "resume_execution"
         }) do
      {:ok, %Run{} = _approved_run} ->
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
  def handle_event("reject_run", params, %{assigns: %{run: %Run{} = run}} = socket) do
    rationale =
      params
      |> map_get(:rationale, "rationale")
      |> normalize_optional_string()

    case Run.reject(run, %{
           actor: approving_actor(socket),
           rationale: rationale
         }) do
      {:ok, %Run{} = _rejected_run} ->
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
  def handle_event("retry_run", _params, %{assigns: %{run: %Run{} = run}} = socket) do
    case Run.retry(run, %{actor: approving_actor(socket)}) do
      {:ok, %Run{} = retried_run} ->
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
  def handle_event("retry_step", _params, %{assigns: %{run: %Run{} = run}} = socket) do
    case Run.retry_step(run, %{actor: approving_actor(socket)}) do
      {:ok, %Run{} = retried_run} ->
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
  def handle_event("open_run_conversation", _params, socket) do
    case RunConversation.open_run_detail(
           run_conversation_scope(socket.assigns.run, socket.assigns.work_item),
           actor: approving_actor(socket)
         ) do
      {:ok, %{conversation: conversation, snapshot: snapshot}} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, nil)
         |> assign(:conversation_action_feedback_kind, :info)
         |> assign(:conversation_input, "")
         |> assign_opened_conversation(conversation, snapshot)}

      {:error, notice} ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, notice)
         |> assign(:conversation_action_feedback_kind, :error)}
    end
  end

  @impl true
  def handle_event("update_conversation_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, :conversation_input, value)}
  end

  @impl true
  def handle_event("send_conversation", params, socket) do
    input =
      params
      |> Map.get("input", socket.assigns.conversation_input)
      |> normalize_optional_string()
      |> Kernel.||("")

    submit_as_resume? = conversation_awaiting_input?(socket.assigns.conversation_snapshot)
    conversation_id = conversation_id(socket)

    cond do
      input == "" ->
        {:noreply, socket}

      not is_binary(conversation_id) ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, %{
           error_type: "run_detail_conversation_missing",
           detail: "Open the governed work conversation before submitting more work.",
           remediation: "Use the governed work conversation action above and then retry the request."
         })
         |> assign(:conversation_action_feedback_kind, :error)}

      socket.assigns.conversation_snapshot &&
          socket.assigns.conversation_snapshot.status == :paused ->
        {:noreply,
         socket
         |> assign(:conversation_action_feedback, %{
           error_type: "run_detail_conversation_paused",
           detail: "Resume the governed work conversation before submitting new work.",
           remediation: "Use the Resume control and then retry the request."
         })
         |> assign(:conversation_action_feedback_kind, :error)}

      true ->
        case JidoCode.AgentWorkspace.handle_conversation_command(
               conversation_id,
               conversation_input_command(socket, input),
               actor: approving_actor(socket)
             ) do
          {:ok, snapshot} ->
            updated_socket =
              socket
              |> assign(:conversation_input, "")
              |> assign(:conversation_action_feedback, nil)
              |> assign(:conversation_action_feedback_kind, :info)
              |> assign_conversation_snapshot(snapshot)
              |> maybe_schedule_conversation_runtime_flow(input, submit_as_resume?)

            {:noreply, updated_socket}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:conversation_action_feedback, %{
               error_type: "run_detail_conversation_submit_failed",
               detail: "Governed work conversation input could not be submitted (#{inspect(reason)}).",
               remediation: "Retry the request or reopen the governed work conversation if the prior turn cannot continue."
             })
             |> assign(:conversation_action_feedback_kind, :error)}
        end
    end
  end

  @impl true
  def handle_event("pause_conversation", _params, socket) do
    dispatch_conversation_control(socket, "session.pause", %{
      reason: "Operator paused the governed work conversation."
    })
  end

  @impl true
  def handle_event("resume_conversation", _params, socket) do
    dispatch_conversation_control(socket, "session.resume", %{})
  end

  @impl true
  def handle_event("stop_conversation_turn", _params, socket) do
    if is_binary(active_child_work_id(socket.assigns.conversation_snapshot)) do
      case JidoCode.AgentWorkspace.handle_conversation_command(
             conversation_id(socket),
             %{type: "turn.stop", payload: %{reason: "Operator requested a stop."}},
             actor: approving_actor(socket)
           ) do
        {:ok, snapshot} ->
          {:noreply,
           socket
           |> assign(:conversation_action_feedback, nil)
           |> assign(:conversation_action_feedback_kind, :info)
           |> assign_conversation_snapshot(snapshot)
           |> maybe_schedule_conversation_cancellation()}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:conversation_action_feedback, %{
             error_type: "run_detail_conversation_stop_failed",
             detail: "The active governed work conversation turn could not be stopped (#{inspect(reason)}).",
             remediation: "Retry the stop request or let the active turn settle before continuing."
           })
           |> assign(:conversation_action_feedback_kind, :error)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("recover_memory_graph", _params, socket) do
    with %{managed_repo_id: managed_repo_id, workspace_path: workspace_path} <- socket.assigns.memory_context,
         managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id,
         workspace_path when is_binary(workspace_path) <- workspace_path do
      case ProductService.recover(managed_repo_id, workspace_path) do
        {:ok, _recovery_result} ->
          refreshed_socket = refresh_run_assigns(socket)

          {:noreply,
           assign(
             refreshed_socket,
             :memory_action_feedback,
             SurfaceFeedback.recovery_result(
               memory_context_graph(refreshed_socket),
               surface_label: "this governed run surface"
             )
           )}

        {:error, reason, diagnostics} ->
          refreshed_socket = refresh_run_assigns(socket)

          {:noreply,
           assign(
             refreshed_socket,
             :memory_action_feedback,
             SurfaceFeedback.recovery_error(
               reason,
               diagnostics,
               graph: memory_context_graph(refreshed_socket),
               surface_label: "this governed run surface"
             )
           )}
      end
    else
      _other ->
        refreshed_socket = refresh_run_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.recovery_error(
             :memory_governed_scope_unavailable,
             nil,
             graph: memory_context_graph(refreshed_socket),
             surface_label: "this governed run surface"
           )
         )}
    end
  end

  @impl true
  def handle_event(
        "validate_memory",
        %{"memory_iri" => memory_iri},
        %{assigns: %{memory_context: %{memories: projection}, run: %Run{} = run}} = socket
      ) do
    case OperatorService.validate(projection, memory_iri, memory_operator_opts(socket, run)) do
      {:ok, _result} ->
        refreshed_socket = refresh_run_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.action_result(
             :validate,
             graph: memory_context_graph(refreshed_socket),
             surface_label: "this governed run surface"
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
        %{assigns: %{memory_context: %{memories: projection}, run: %Run{} = run}} = socket
      ) do
    case OperatorService.invalidate(projection, memory_iri, memory_operator_opts(socket, run)) do
      {:ok, _result} ->
        refreshed_socket = refresh_run_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.action_result(
             :invalidate,
             graph: memory_context_graph(refreshed_socket),
             surface_label: "this governed run surface"
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
        %{assigns: %{memory_context: %{memories: projection}, run: %Run{} = run}} = socket
      ) do
    case OperatorService.promote_follow_up(projection, memory_iri, memory_operator_opts(socket, run)) do
      {:ok, %{result: %{work_item: work_item}, target: :work_item}} ->
        refreshed_socket = refresh_run_assigns(socket)

        {:noreply,
         assign(
           refreshed_socket,
           :memory_action_feedback,
           SurfaceFeedback.action_result(
             :promote_follow_up,
             graph: memory_context_graph(refreshed_socket),
             surface_label: "this governed run surface",
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
        %{assigns: %{memory_context: %{memories: projection}, decisions: decisions, run: %Run{} = run}} = socket
      ) do
    with %{} = decision <-
           Enum.find(decisions, &(normalize_optional_string(map_get(&1, :id, "id")) == decision_id)),
         {:ok, _result} <-
           OperatorService.supersede_with_governed_decision(
             projection,
             memory_iri,
             decision,
             memory_operator_opts(socket, run, decision_id: decision_id)
           ) do
      refreshed_socket = refresh_run_assigns(socket)

      {:noreply,
       assign(
         refreshed_socket,
         :memory_action_feedback,
         SurfaceFeedback.action_result(
           :supersede_with_governed_decision,
           graph: memory_context_graph(refreshed_socket),
           surface_label: "this governed run surface"
         )
       )}
    else
      nil ->
        {:noreply, assign_memory_action_error(socket, :governed_decision_not_found)}

      {:error, reason} ->
        {:noreply, assign_memory_action_error(socket, reason)}
    end
  end

  @impl true
  def handle_event("supersede_memory", _params, socket), do: {:noreply, socket}

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

            <section id="run-detail-work-item" class="space-y-2">
              <p class="text-sm font-medium">Work item</p>

              <%= if @work_item do %>
                <div
                  id="run-detail-work-item-entry"
                  class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
                >
                  <p id="run-detail-work-item-summary" class="text-sm font-medium">
                    {Map.get(@work_item, :summary)}
                  </p>
                  <p id="run-detail-work-item-status" class="text-xs text-base-content/80">
                    Status: {Map.get(@work_item, :status) |> status_label()}
                  </p>
                  <p id="run-detail-work-item-category" class="text-xs text-base-content/80">
                    Category: {Map.get(@work_item, :category)}
                  </p>
                </div>
              <% else %>
                <p id="run-detail-work-item-empty" class="text-xs text-base-content/70">
                  No governed work item is linked to this run yet.
                </p>
              <% end %>
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
                    id={
                      "run-detail-evidence-entry-#{governed_record_dom_token(Map.get(evidence, :id) || index)}"
                    }
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
                    id={
                      "run-detail-decision-entry-#{governed_record_dom_token(Map.get(decision, :id) || index)}"
                    }
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

            <section
              :if={@memory_context}
              id="run-detail-memory-context"
              class="space-y-3 rounded border border-base-300/70 bg-base-200/20 p-3"
            >
              <div class="space-y-1">
                <p class="text-sm font-medium">Repository memory context</p>
                <p id="run-detail-memory-context-state" class="text-xs text-base-content/70">
                  Memory state: {Map.get(@memory_context.graph, :state, :unavailable)}
                </p>
                <.operator_state_notice
                  :if={@memory_action_feedback}
                  id="run-detail-memory-action-feedback"
                  title="Run memory update"
                  state={@memory_action_feedback}
                  kind={memory_feedback_kind(@memory_action_feedback)}
                  compact={true}
                />
                <.memory_status_notice
                  :if={@memory_context.notice}
                  id="run-detail-memory-context-notice"
                  title="Run memory status"
                  state={@memory_context.notice}
                  kind={Map.get(@memory_context, :notice_kind, :warning)}
                  recovery={Map.get(@memory_context, :recovery)}
                  recover_event="recover_memory_graph"
                  recover_id="run-detail-memory-recover"
                />
              </div>

              <div
                :if={
                  (@memory_context.governed_history.work_item != nil ||
                     @memory_context.governed_history.evidence != []) or
                    @memory_context.governed_history.decisions != []
                }
                id="run-detail-memory-history"
                class="grid gap-3 md:grid-cols-2"
              >
                <section :if={@memory_context.governed_history.work_item} class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Work item history
                  </p>
                  <div
                    id="run-detail-memory-work-item-history"
                    class="rounded border border-base-300/50 bg-base-100 p-2"
                  >
                    <p class="text-xs font-medium">{@memory_context.governed_history.work_item.label}</p>
                    <p class="text-xs text-base-content/70">
                      Memory: {@memory_context.governed_history.work_item.memory_count} | Provenance: {@memory_context.governed_history.work_item.provenance_count}
                    </p>
                  </div>
                </section>

                <section :if={@memory_context.governed_history.evidence != []} class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Evidence history
                  </p>
                  <ol id="run-detail-memory-evidence-history" class="space-y-2">
                    <li
                      :for={{entry, index} <- Enum.with_index(@memory_context.governed_history.evidence, 1)}
                      id={"run-detail-memory-evidence-history-#{index}"}
                      class="rounded border border-base-300/50 bg-base-100 p-2"
                    >
                      <p class="text-xs font-medium">{entry.label}</p>
                      <p class="text-xs text-base-content/70">
                        Memory: {entry.memory_count} | Provenance: {entry.provenance_count}
                      </p>
                    </li>
                  </ol>
                </section>

                <section :if={@memory_context.governed_history.decisions != []} class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Decision history
                  </p>
                  <ol id="run-detail-memory-decision-history" class="space-y-2">
                    <li
                      :for={{entry, index} <- Enum.with_index(@memory_context.governed_history.decisions, 1)}
                      id={"run-detail-memory-decision-history-#{index}"}
                      class="rounded border border-base-300/50 bg-base-100 p-2"
                    >
                      <p class="text-xs font-medium">{entry.label}</p>
                      <p class="text-xs text-base-content/70">
                        Memory: {entry.memory_count} | Provenance: {entry.provenance_count}
                      </p>
                    </li>
                  </ol>
                </section>
              </div>

              <div
                :if={
                  (@memory_context.governed_surfaces.work_item != nil ||
                     @memory_context.governed_surfaces.evidence != []) or
                    @memory_context.governed_surfaces.decisions != []
                }
                id="run-detail-governed-memory-contexts"
                class="space-y-3"
              >
                <section
                  :if={@memory_context.governed_surfaces.work_item}
                  id="run-detail-work-item-memory"
                  class="space-y-2 rounded border border-base-300/50 bg-base-100 p-3"
                >
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Work item memory context
                  </p>
                  <.governed_memory_surface
                    dom_prefix="run-detail-work-item-memory"
                    context={@memory_context.governed_surfaces.work_item}
                  />
                </section>

                <section
                  :if={@memory_context.governed_surfaces.evidence != []}
                  id="run-detail-evidence-memory-contexts"
                  class="space-y-2"
                >
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Evidence memory context
                  </p>
                  <ol class="space-y-2">
                    <li
                      :for={context <- @memory_context.governed_surfaces.evidence}
                      id={"run-detail-evidence-memory-context-#{governed_record_dom_token(context.id)}"}
                      class="rounded border border-base-300/50 bg-base-100 p-2"
                    >
                      <.governed_memory_surface
                        dom_prefix={"run-detail-evidence-memory-#{governed_record_dom_token(context.id)}"}
                        context={context}
                      />
                    </li>
                  </ol>
                </section>

                <section
                  :if={@memory_context.governed_surfaces.decisions != []}
                  id="run-detail-decision-memory-contexts"
                  class="space-y-2"
                >
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Decision memory context
                  </p>
                  <ol class="space-y-2">
                    <li
                      :for={context <- @memory_context.governed_surfaces.decisions}
                      id={"run-detail-decision-memory-context-#{governed_record_dom_token(context.id)}"}
                      class="rounded border border-base-300/50 bg-base-100 p-2"
                    >
                      <.governed_memory_surface
                        dom_prefix={"run-detail-decision-memory-#{governed_record_dom_token(context.id)}"}
                        context={context}
                      />
                      <button
                        :if={decision_memory_iri(@memory_context.memories.items)}
                        type="button"
                        id={"run-detail-decision-memory-supersede-#{governed_record_dom_token(context.id)}"}
                        phx-click="supersede_memory"
                        phx-value-memory_iri={decision_memory_iri(@memory_context.memories.items)}
                        phx-value-decision_id={context.id}
                        class="btn btn-xs btn-outline"
                      >
                        Supersede with decision
                      </button>
                    </li>
                  </ol>
                </section>
              </div>

              <section id="run-detail-memory-items" class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Durable memories
                </p>

                <%= if @memory_context.memories.items == [] do %>
                  <p id="run-detail-memory-empty" class="text-xs text-base-content/70">
                    No durable memories currently point at this governed history.
                  </p>
                <% else %>
                  <ol id="run-detail-memory-list" class="space-y-2">
                    <li
                      :for={{item, index} <- Enum.with_index(@memory_context.memories.items, 1)}
                      id={"run-detail-memory-item-#{index}"}
                      class="rounded border border-base-300/50 bg-base-100 p-3 space-y-1"
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
                          id={"run-detail-memory-validate-#{index}"}
                          phx-click="validate_memory"
                          phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                          class="btn btn-xs btn-outline"
                        >
                          Validate
                        </button>
                        <button
                          type="button"
                          id={"run-detail-memory-invalidate-#{index}"}
                          phx-click="invalidate_memory"
                          phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                          class="btn btn-xs btn-outline btn-warning"
                        >
                          Invalidate
                        </button>
                        <button
                          type="button"
                          id={"run-detail-memory-promote-#{index}"}
                          phx-click="promote_memory_follow_up"
                          phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                          class="btn btn-xs btn-primary"
                        >
                          Create follow-up
                        </button>
                      </div>
                      <.memory_link_groups dom_prefix={"run-detail-memory-#{index}"} item={item} />
                    </li>
                  </ol>
                <% end %>
              </section>

              <section
                :if={@memory_follow_up_preview && @memory_follow_up_preview.available?}
                id="run-detail-memory-follow-up-preview"
                class="space-y-2 rounded border border-base-300/50 bg-base-100 p-3"
              >
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Memory-aware follow-up
                </p>
                <p id="run-detail-memory-follow-up-preview-summary" class="text-sm font-medium">
                  {@memory_follow_up_preview.summary}
                </p>
                <p id="run-detail-memory-follow-up-preview-metadata" class="text-xs text-base-content/70">
                  Recommended action: {@memory_follow_up_preview.recommended_action_label} | Priority: {@memory_follow_up_preview.priority} | Urgency: {@memory_follow_up_preview.urgency}
                </p>
                <p id="run-detail-memory-follow-up-preview-kinds" class="text-xs text-base-content/70">
                  Selected memory kinds: {Enum.join(@memory_follow_up_preview.memory_kinds, ", ")}
                </p>
                <.link
                  :if={@memory_follow_up_preview.route}
                  id="run-detail-memory-follow-up-preview-route"
                  class="link link-primary text-xs"
                  navigate={@memory_follow_up_preview.route}
                >
                  {@memory_follow_up_preview.route_label}
                </.link>
              </section>

              <section id="run-detail-memory-provenance" class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Workflow provenance
                </p>

                <%= if @memory_context.provenance.items == [] do %>
                  <p id="run-detail-memory-provenance-empty" class="text-xs text-base-content/70">
                    No workflow provenance currently points at this governed history.
                  </p>
                <% else %>
                  <ol id="run-detail-memory-provenance-list" class="space-y-2">
                    <li
                      :for={{item, index} <- Enum.with_index(@memory_context.provenance.items, 1)}
                      id={"run-detail-memory-provenance-item-#{index}"}
                      class="rounded border border-base-300/50 bg-base-100 p-3 space-y-1"
                    >
                      <p class="text-sm font-medium">
                        {provenance_item_kind(item)}: {provenance_item_label(item)}
                      </p>
                      <p class="text-xs text-base-content/70">
                        Revision: {provenance_item_revision(item)}
                      </p>
                      <.memory_link_groups dom_prefix={"run-detail-memory-provenance-#{index}"} item={item} />
                    </li>
                  </ol>
                <% end %>
              </section>
            </section>
          </section>

          <section id="run-detail-conversation-panel" class="space-y-4 rounded border border-base-300 bg-base-100 p-4">
            <div class="space-y-1">
              <h2 class="text-lg font-semibold">Governed work conversation</h2>
              <p class="text-sm text-base-content/70">
                Continue the run's governed work from this route through the product-owned conversation stream, with durable snapshot recovery when live delivery degrades.
              </p>
            </div>

            <.operator_state_notice
              :if={@conversation_action_feedback}
              id="run-detail-conversation-feedback"
              title="Governed work conversation update"
              state={@conversation_action_feedback}
              kind={@conversation_action_feedback_kind}
            />

            <.operator_state_notice
              :if={conversation_notice_visible?(@conversation_surface)}
              id="run-detail-conversation-notice"
              title="Governed work conversation status"
              state={@conversation_surface.notice}
              kind={:warning}
            />

            <div
              :if={@conversation_stream_mode == :degraded}
              id="run-detail-conversation-degraded"
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
                          id="run-detail-conversation-id"
                          class="text-xs font-mono text-base-content/60"
                        >
                          {@conversation_surface.conversation.id}
                        </p>
                      </div>

                      <div class="flex flex-wrap items-center gap-2 text-xs">
                        <span
                          id="run-detail-conversation-stream-mode"
                          class="rounded-full bg-base-200 px-3 py-1 font-medium"
                        >
                          {@conversation_stream_mode}
                        </span>
                        <span
                          id="run-detail-conversation-sequence"
                          class="rounded-full bg-base-200 px-3 py-1 font-medium"
                        >
                          seq {@conversation_last_event_sequence}
                        </span>
                        <span
                          id="run-detail-conversation-discontinuities"
                          class="rounded-full bg-base-200 px-3 py-1 font-medium"
                        >
                          discontinuities: {@conversation_stream_discontinuity_count}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div id="run-detail-conversation-events" class="max-h-96 space-y-3 overflow-y-auto px-4 py-4">
                    <%= for event <- @conversation_events do %>
                      <article
                        id={"run-detail-conversation-event-#{map_get(event, :id, "id")}"}
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
                      id="run-detail-conversation-pending-clarification"
                      class="mb-3 rounded-lg border border-warning/60 bg-warning/10 p-3 text-sm"
                    >
                      <p class="font-semibold">Input required</p>
                      <p class="mt-1">
                        {conversation_clarification_prompt(@conversation_snapshot) ||
                          "The active turn is waiting on clarification."}
                      </p>
                    </div>

                    <form id="run-detail-conversation-form" phx-submit="send_conversation" class="flex flex-col gap-3 sm:flex-row">
                      <input
                        id="run-detail-conversation-input"
                        type="text"
                        name="input"
                        value={@conversation_input}
                        phx-change="update_conversation_input"
                        placeholder={
                          if conversation_awaiting_input?(@conversation_snapshot) do
                            conversation_clarification_prompt(@conversation_snapshot) ||
                              "Provide the missing clarification…"
                          else
                            "Describe the governed work this conversation should coordinate…"
                          end
                        }
                        class="input input-bordered flex-1"
                        autocomplete="off"
                      />
                      <button
                        id="run-detail-conversation-submit"
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
                        <dd id="run-detail-conversation-status" class="font-medium">
                          {Map.get(@conversation_surface.conversation, :status)}
                        </dd>
                      </div>
                      <div class="flex justify-between gap-3">
                        <dt class="text-base-content/70">Scope</dt>
                        <dd id="run-detail-conversation-scope" class="font-medium">
                          {Map.get(@conversation_surface.conversation, :scope)}
                        </dd>
                      </div>
                      <div class="flex justify-between gap-3">
                        <dt class="text-base-content/70">Attachment</dt>
                        <dd id="run-detail-conversation-attachment" class="font-medium">
                          {Map.get(@conversation_surface.conversation, :attachment_mode)}
                        </dd>
                      </div>
                      <div class="flex justify-between gap-3">
                        <dt class="text-base-content/70">Work item</dt>
                        <dd id="run-detail-conversation-work-item" class="font-medium">
                          {Map.get(@conversation_snapshot, :work_item_id) || "run-scoped"}
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
                      id="run-detail-conversation-progress"
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
                      id="run-detail-conversation-stdout"
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
                        id="run-detail-conversation-pause"
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
                        id="run-detail-conversation-resume"
                        type="button"
                        class="btn btn-sm btn-outline"
                        phx-click="resume_conversation"
                        disabled={!conversation_paused?(@conversation_snapshot)}
                      >
                        Resume
                      </button>
                      <button
                        id="run-detail-conversation-stop-turn"
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
                  Open a governed work conversation to continue this run's canonical work without leaving the run detail route.
                </p>
                <button
                  id="run-detail-conversation-open"
                  type="button"
                  class="btn btn-primary btn-sm"
                  phx-click="open_run_conversation"
                  disabled={!@conversation_surface.available?}
                >
                  {@conversation_surface.action_label}
                </button>
              </div>
            <% end %>
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
    |> assign(:work_item, nil)
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
    |> assign(:memory_context, nil)
    |> assign(:memory_follow_up_preview, nil)
    |> assign(:step_retry_state, step_retry_state(nil))
    |> assign(:memory_action_feedback, nil)
    |> assign(:approval_action_error, nil)
    |> assign(:retry_action_error, nil)
    |> clear_run_conversation()
  end

  defp timeline_entries(%Run{} = run) do
    run
    |> workflow_audit_status_transitions()
    |> normalize_timeline_entries()
  end

  defp timeline_entries(_run), do: []

  defp assign_run_state(
         socket,
         %{
           run: run,
           work_item: work_item,
           evidence_records: evidence_records,
           change_request: change_request,
           decisions: decisions,
           repo_posture: repo_posture,
           memory_context: memory_context,
           memory_follow_up_preview: memory_follow_up_preview
         }
       ) do
    socket
    |> assign(:run, run)
    |> assign(:work_item, work_item)
    |> assign(:evidence_records, evidence_records)
    |> assign(:change_request, change_request)
    |> assign(:decisions, decisions)
    |> assign(:runtime_evidence_summary, runtime_evidence_summary(run, evidence_records, repo_posture))
    |> assign(:memory_context, memory_context)
    |> assign(:memory_follow_up_preview, memory_follow_up_preview)
    |> assign(:timeline_entries, timeline_entries(run))
    |> assign(:retry_lineage_entries, retry_lineage_entries(run))
    |> assign(:artifact_categories, artifact_categories(run))
    |> assign(:failure_context, failure_context(run))
    |> assign(:issue_triage_artifacts, issue_triage_artifacts(run))
    |> assign(:approval_context, approval_context(run))
    |> assign(:approval_context_blocker, approval_context_blocker(run))
    |> assign(:step_retry_state, step_retry_state(run))
    |> assign_run_conversation(run, work_item)
  end

  defp refresh_run_assigns(%{assigns: %{project_id: project_id, run_id: run_id}} = socket) do
    case load_run_state(project_id, run_id) do
      {:ok, run_state} -> assign_run_state(socket, run_state)
      _other -> assign_missing_run(socket, project_id, run_id)
    end
  end

  defp assign_memory_action_error(socket, reason) do
    refreshed_socket = refresh_run_assigns(socket)

    assign(
      refreshed_socket,
      :memory_action_feedback,
      SurfaceFeedback.action_error(
        reason,
        graph: memory_context_graph(refreshed_socket),
        surface_label: "this governed run surface"
      )
    )
  end

  defp memory_context_graph(%{assigns: %{memory_context: %{graph: graph}}}) when is_map(graph), do: graph
  defp memory_context_graph(_socket), do: nil

  defp load_run_state(project_id, run_id) do
    with {:ok, project_scope} <- RepoBridge.repo_scope(project_id),
         {:ok, run} <- load_governed_run(project_scope, run_id) do
      evidence_records = load_evidence_records(run)
      decisions = load_decisions(run)
      work_item = load_work_item(run, evidence_records, decisions)

      managed_repo_id = memory_context_managed_repo_id(project_scope, run)
      workspace_path = load_project_workspace_path(project_id)

      memory_context =
        GovernedSurfaceContext.load_run_detail(
          project_scope,
          run,
          evidence_records,
          decisions,
          work_item: work_item,
          managed_repo_id: managed_repo_id,
          workspace_path: workspace_path
        )

      {:ok,
       %{
         run: run,
         work_item: work_item,
         evidence_records: evidence_records,
         change_request: load_change_request(run),
         decisions: decisions,
         repo_posture: load_repo_posture(run),
         memory_context: memory_context,
         memory_follow_up_preview:
           load_memory_follow_up_preview(
             memory_context,
             run,
             managed_repo_id
           )
       }}
    else
      {:error, :governed_run_not_found} ->
        {:error, :not_found}

      {:error, :repo_scope_not_found} ->
        {:error, :not_found}

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

  defp load_work_item(%Run{} = run, evidence_records, decisions) do
    work_item_id =
      normalize_optional_string(Map.get(run, :work_item_id)) ||
        work_item_id_from_records(evidence_records) ||
        work_item_id_from_records(decisions)

    case work_item_id do
      work_item_id when is_binary(work_item_id) ->
        case WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: Actor.operator_actor()) do
          {:ok, [work_item | _rest]} -> work_item
          _other -> placeholder_work_item(work_item_id)
        end

      _other ->
        nil
    end
  end

  defp load_work_item(_run, _evidence_records, _decisions), do: nil

  defp work_item_id_from_records(records) when is_list(records) do
    records
    |> Enum.find_value(fn record ->
      normalize_optional_string(Map.get(record, :work_item_id) || Map.get(record, "work_item_id"))
    end)
  end

  defp work_item_id_from_records(_records), do: nil

  defp placeholder_work_item(work_item_id) when is_binary(work_item_id) do
    %{
      id: work_item_id,
      summary: "Governed work item #{work_item_id}",
      status: :unknown,
      category: "governed_follow_up"
    }
  end

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

  defp load_project_workspace_path(project_id) do
    with {:ok, [project]} <-
           Project.read(query: [filter: [id: project_id], limit: 1], actor: Actor.operator_actor()) do
      project
      |> map_get(:settings, "settings", %{})
      |> map_get(:workspace, "workspace", %{})
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_optional_string()
    else
      _other -> nil
    end
  end

  defp empty_conversation_surface do
    %{
      available?: false,
      managed_repo_id: nil,
      work_item_id: nil,
      run_id: nil,
      conversation: nil,
      snapshot: nil,
      recent_events: [],
      notice: nil,
      action_label: "Open work conversation"
    }
  end

  defp assign_run_conversation(socket, run, work_item) do
    projection =
      RunConversation.load_run_detail(
        run_conversation_scope(run, work_item),
        actor: approving_actor(socket)
      )

    assign_conversation_surface(socket, projection)
  end

  defp clear_run_conversation(socket) do
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
    |> assign(:conversation_degraded_mode_message, @conversation_degraded_mode_message)
    |> sync_conversation_subscription()
  end

  defp assign_opened_conversation(socket, conversation, snapshot) do
    projection = %{
      available?: true,
      managed_repo_id: conversation.managed_repo_id,
      work_item_id: conversation.work_item_id,
      run_id: route_run_id(socket),
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
      action_label: "Continue work conversation"
    }

    assign_conversation_surface(socket, projection)
  end

  defp assign_conversation_surface(socket, projection) do
    snapshot = Map.get(projection, :snapshot)
    recent_events = Map.get(projection, :recent_events, [])
    previous_id = conversation_id(socket)
    next_id = projection |> Map.get(:conversation, %{}) |> map_get(:id, "id")

    socket
    |> assign(:conversation_surface, projection)
    |> assign(:conversation_snapshot, snapshot)
    |> assign(:conversation_events, recent_events)
    |> assign(:conversation_last_event_sequence, snapshot && snapshot.last_event_sequence || 0)
    |> assign(:conversation_stream_mode, conversation_stream_mode(projection))
    |> assign(:conversation_stream_degraded_reason, conversation_stream_reason(projection))
    |> assign(:conversation_stream_discontinuity_count, 0)
    |> maybe_reset_conversation_input(previous_id, next_id)
    |> maybe_reset_conversation_feedback(previous_id, next_id)
    |> sync_conversation_subscription()
  end

  defp maybe_reset_conversation_input(socket, conversation_id, conversation_id)
       when is_binary(conversation_id),
       do: socket

  defp maybe_reset_conversation_input(socket, _previous_id, _next_id) do
    assign(socket, :conversation_input, "")
  end

  defp maybe_reset_conversation_feedback(socket, conversation_id, conversation_id)
       when is_binary(conversation_id),
       do: socket

  defp maybe_reset_conversation_feedback(socket, _previous_id, _next_id) do
    socket
    |> assign(:conversation_action_feedback, nil)
    |> assign(:conversation_action_feedback_kind, :info)
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

  defp sync_conversation_subscription(socket) do
    if connected?(socket) do
      subscribed_id = Map.get(socket.assigns, :conversation_subscription_id)
      current_id = conversation_id(socket)

      cond do
        subscribed_id == current_id ->
          socket

        is_binary(subscribed_id) ->
          _ = ConversationPubSub.unsubscribe_conversation(subscribed_id)
          subscribe_to_conversation(socket, current_id)

        true ->
          subscribe_to_conversation(socket, current_id)
      end
    else
      socket
    end
  end

  defp subscribe_to_conversation(socket, conversation_id) when is_binary(conversation_id) do
    case ConversationPubSub.subscribe_conversation(conversation_id) do
      :ok ->
        socket
        |> assign(:conversation_subscription_id, conversation_id)
        |> assign(:conversation_stream_mode, :live)
        |> assign(:conversation_stream_degraded_reason, nil)

      {:error, reason} ->
        socket
        |> assign(:conversation_subscription_id, nil)
        |> assign(:conversation_stream_mode, :degraded)
        |> assign(:conversation_stream_degraded_reason, inspect(reason))

      other ->
        socket
        |> assign(:conversation_subscription_id, nil)
        |> assign(:conversation_stream_mode, :degraded)
        |> assign(:conversation_stream_degraded_reason, inspect(other))
    end
  end

  defp subscribe_to_conversation(socket, _conversation_id) do
    assign(socket, :conversation_subscription_id, nil)
  end

  defp dispatch_conversation_control(socket, command_type, payload) do
    case JidoCode.AgentWorkspace.handle_conversation_command(
           conversation_id(socket),
           %{type: command_type, payload: payload},
           actor: approving_actor(socket)
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
           error_type: "run_detail_conversation_control_failed",
           detail: "The governed work conversation could not be updated (#{inspect(reason)}).",
           remediation: "Retry the control action after the active conversation state is available again."
         })
         |> assign(:conversation_action_feedback_kind, :error)}
    end
  end

  defp maybe_schedule_conversation_runtime_flow(socket, input, true) do
    case active_child_work_id(socket.assigns.conversation_snapshot) do
      child_work_id when is_binary(child_work_id) ->
        Process.send_after(
          self(),
          {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
           %{
             kind: "delta",
             text: "Continuing with the clarified governed work instruction: #{input}"
           }},
          @conversation_resume_delta_delay_ms
        )

        Process.send_after(
          self(),
          {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
           %{
             kind: "completed",
             result: %{summary: "Completed the clarified governed work: #{input}"}
           }},
          @conversation_resume_completion_delay_ms
        )

        socket

      _other ->
        socket
    end
  end

  defp maybe_schedule_conversation_runtime_flow(socket, instruction, false) do
    case active_child_work_id(socket.assigns.conversation_snapshot) do
      child_work_id when is_binary(child_work_id) ->
        Process.send_after(
          self(),
          {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
           %{
             kind: "progress",
             summary: "Inspecting the governed run context.",
             percent: 35
           }},
          @conversation_progress_delay_ms
        )

        Process.send_after(
          self(),
          {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
           %{kind: "stdout", text: simulated_conversation_stdout(instruction)}},
          @conversation_stdout_delay_ms
        )

        if conversation_requires_clarification?(instruction) do
          Process.send_after(
            self(),
            {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
             %{kind: "needs_input", prompt: "Which step or file should I inspect first?"}},
            @conversation_clarification_delay_ms
          )
        else
          Process.send_after(
            self(),
            {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
             %{kind: "delta", text: "Applying the requested governed work scope: #{instruction}"}},
            @conversation_delta_delay_ms
          )

          Process.send_after(
            self(),
            {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
             %{
               kind: "completed",
               result: %{summary: "Completed the requested governed work: #{instruction}"}
             }},
            @conversation_completion_delay_ms
          )
        end

        socket

      _other ->
        socket
    end
  end

  defp maybe_schedule_conversation_cancellation(socket) do
    case active_child_work_id(socket.assigns.conversation_snapshot) do
      child_work_id when is_binary(child_work_id) ->
        Process.send_after(
          self(),
          {:run_detail_conversation_tool_result, conversation_id(socket), child_work_id,
           %{
             kind: "cancelled",
             result: %{reason: "The active governed work conversation was cancelled before completion."}
           }},
          @conversation_cancellation_settle_delay_ms
        )

        socket

      _other ->
        socket
    end
  end

  defp recover_run_conversation_gap(socket) do
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

  defp route_run_id(socket) do
    socket.assigns
    |> Map.get(:run)
    |> case do
      %Run{} = run -> map_get(run, :run_id, "run_id")
      _other -> Map.get(socket.assigns, :run_id)
    end
  end

  defp run_conversation_scope(%Run{} = run, work_item) do
    %{
      managed_repo_id: normalize_optional_string(map_get(run, :managed_repo_id, "managed_repo_id")),
      work_item_id:
        (work_item
         |> map_get(:id, "id")
         |> normalize_optional_string()) ||
          normalize_optional_string(map_get(run, :work_item_id, "work_item_id")),
      run_id: normalize_optional_string(map_get(run, :run_id, "run_id"))
    }
  end

  defp run_conversation_scope(_run, _work_item), do: %{}

  defp conversation_input_command(socket, input) do
    case socket.assigns.conversation_snapshot do
      %{active_turn_id: turn_id} = snapshot
      when is_binary(turn_id) and conversation_awaiting_input?(snapshot) ->
        %{type: "turn.resume", payload: %{turn_id: turn_id, response: input}}

      _other ->
        %{type: "turn.submit", payload: %{instruction: input}}
    end
  end

  defp active_child_work_id(nil), do: nil
  defp active_child_work_id(snapshot), do: snapshot.active_child_work_id

  defp child_work_open?(snapshot, child_work_id) do
    snapshot.child_works
    |> Enum.find(&(&1.id == child_work_id))
    |> case do
      %{state: state} when state in [:running, :cancel_requested, :cancel_acknowledged] -> true
      _other -> false
    end
  end

  defp child_work_cancelling?(snapshot, child_work_id) do
    snapshot.child_works
    |> Enum.find(&(&1.id == child_work_id))
    |> case do
      %{state: state} when state in [:cancel_requested, :cancel_acknowledged] -> true
      _other -> false
    end
  end

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

  defp conversation_requires_clarification?(instruction) when is_binary(instruction) do
    normalized = String.downcase(instruction)

    String.contains?(normalized, "clarify") or String.contains?(normalized, "input") or
      String.contains?(normalized, "question")
  end

  defp conversation_requires_clarification?(_instruction), do: false

  defp simulated_conversation_stdout(instruction) do
    "rg --context 2 #{String.slice(instruction, 0, 32)}"
  end

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
          "Recorded governed work conversation input."

      "conversation.status_changed" ->
        "Conversation status is now #{map_get(conversation_event_payload(event), :status, "status") || "active"}."

      "turn.intent_announced" ->
        map_get(conversation_event_payload(event), :text, "text") || "Intent announced."

      "turn.queued" ->
        "Queued a new governed work turn."

      "turn.started" ->
        "Started the active governed work turn."

      "turn.awaiting_input" ->
        map_get(conversation_event_payload(event), :prompt, "prompt") ||
          "Waiting for clarification before continuing."

      "turn.delta" ->
        map_get(conversation_event_payload(event), :text, "text") ||
          "Streaming turn update received."

      "turn.cancelling" ->
        "Stopping the active governed work turn."

      "turn.completed" ->
        "The active governed work turn completed."

      "turn.cancelled" ->
        "The active governed work turn was cancelled."

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_time(nil), do: "n/a"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_value), do: "n/a"

  defp memory_context_managed_repo_id(project_scope, %Run{} = run) do
    normalize_optional_string(map_get(run, :managed_repo_id, "managed_repo_id")) ||
      normalize_optional_string(map_get(project_scope, :managed_repo_id, "managed_repo_id")) ||
      project_scope
      |> map_get(:managed_repo, "managed_repo", %{})
      |> map_get(:id, "id")
      |> normalize_optional_string()
  end

  defp governed_record_dom_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized -> normalized
    end
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  attr :dom_prefix, :string, required: true
  attr :context, :map, required: true

  defp governed_memory_surface(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="space-y-1">
          <p id={"#{@dom_prefix}-label"} class="text-sm font-medium">{@context.label}</p>
          <p id={"#{@dom_prefix}-counts"} class="text-xs text-base-content/70">
            Memory: {@context.memory_count} | Provenance: {@context.provenance_count}
          </p>
        </div>
        <.link
          :if={@context.route}
          id={"#{@dom_prefix}-route"}
          class="link link-primary text-xs"
          navigate={@context.route}
        >
          Open governed record
        </.link>
      </div>

      <%= if @context.memories.items == [] do %>
        <p id={"#{@dom_prefix}-memory-empty"} class="text-xs text-base-content/70">
          No durable memories currently point at this governed record.
        </p>
      <% else %>
        <ol id={"#{@dom_prefix}-memory-list"} class="space-y-2">
          <li
            :for={{item, index} <- Enum.with_index(@context.memories.items, 1)}
            id={"#{@dom_prefix}-memory-item-#{index}"}
            class="rounded border border-base-300/50 bg-base-200/20 p-2 space-y-1"
          >
            <p class="text-xs font-medium">
              {memory_item_kind(item)}: {memory_item_content(item)}
            </p>
            <p class="text-xs text-base-content/70">
              Freshness: {memory_item_freshness(item)} | Decision status: {memory_item_decision_status(item)}
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                id={"#{@dom_prefix}-memory-validate-#{index}"}
                phx-click="validate_memory"
                phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                class="btn btn-xs btn-outline"
              >
                Validate
              </button>
              <button
                type="button"
                id={"#{@dom_prefix}-memory-invalidate-#{index}"}
                phx-click="invalidate_memory"
                phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                class="btn btn-xs btn-outline btn-warning"
              >
                Invalidate
              </button>
              <button
                type="button"
                id={"#{@dom_prefix}-memory-promote-#{index}"}
                phx-click="promote_memory_follow_up"
                phx-value-memory_iri={map_get(item, :memory_iri, "memory_iri")}
                class="btn btn-xs btn-primary"
              >
                Create follow-up
              </button>
            </div>
            <.memory_link_groups dom_prefix={"#{@dom_prefix}-memory-#{index}"} item={item} />
          </li>
        </ol>
      <% end %>

      <%= if @context.provenance.items == [] do %>
        <p id={"#{@dom_prefix}-provenance-empty"} class="text-xs text-base-content/70">
          No workflow provenance currently points at this governed record.
        </p>
      <% else %>
        <ol id={"#{@dom_prefix}-provenance-list"} class="space-y-2">
          <li
            :for={{item, index} <- Enum.with_index(@context.provenance.items, 1)}
            id={"#{@dom_prefix}-provenance-item-#{index}"}
            class="rounded border border-base-300/50 bg-base-200/20 p-2 space-y-1"
          >
            <p class="text-xs font-medium">
              {provenance_item_kind(item)}: {provenance_item_label(item)}
            </p>
            <p class="text-xs text-base-content/70">
              Revision: {provenance_item_revision(item)}
            </p>
            <.memory_link_groups dom_prefix={"#{@dom_prefix}-provenance-#{index}"} item={item} />
          </li>
        </ol>
      <% end %>
    </div>
    """
  end

  defp decision_memory_iri(items) when is_list(items) do
    items
    |> Enum.find(&(memory_item_kind(&1) == "Decision"))
    |> case do
      nil -> nil
      item -> memory_item_iri(item)
    end
  end

  defp decision_memory_iri(_items), do: nil

  defp memory_feedback_kind(%{kind: kind}) when is_atom(kind), do: kind
  defp memory_feedback_kind(_feedback), do: :info

  defp memory_item_iri(item) do
    present_string(map_get(item, :memory_iri, "memory_iri"))
  end

  defp memory_item_kind(item) do
    present_string(map_get(item, :memory_kind, "memory_kind")) ||
      kind_from_resource_iri(memory_item_iri(item)) ||
      "Memory"
  end

  defp memory_item_content(item) do
    present_string(map_get(item, :content, "content")) || "bounded durable memory"
  end

  defp memory_item_freshness(item) do
    map_get(item, :freshness_score, "freshness_score") || "unknown"
  end

  defp memory_item_decision_status(item) do
    present_string(map_get(item, :decision_status, "decision_status")) || "n/a"
  end

  defp provenance_item_kind(item) do
    present_string(map_get(item, :provenance_kind, "provenance_kind")) ||
      kind_from_resource_iri(present_string(map_get(item, :resource_iri, "resource_iri"))) ||
      "Provenance"
  end

  defp provenance_item_label(item) do
    present_string(map_get(item, :label, "label")) ||
      present_string(map_get(item, :content, "content")) ||
      "bounded provenance"
  end

  defp provenance_item_revision(item) do
    present_string(map_get(item, :revision_iri, "revision_iri")) || "unknown"
  end

  defp kind_from_resource_iri(nil), do: nil

  defp kind_from_resource_iri(value) when is_binary(value) do
    value
    |> String.split("#")
    |> List.last()
    |> case do
      nil -> nil
      fragment -> fragment |> String.split("/") |> List.first()
    end
    |> present_string()
    |> case do
      nil -> nil
      segment -> segment |> String.replace("-", "_") |> Macro.camelize()
    end
  end

  defp load_memory_follow_up_preview(memory_context, %Run{} = run, managed_repo_id) when is_map(memory_context) do
    FollowUpSurface.preview(
      Map.get(memory_context, :memories),
      route: follow_up_preview_route(run, managed_repo_id),
      category: "governed_follow_up"
    )
  end

  defp load_memory_follow_up_preview(_memory_context, _run, _managed_repo_id), do: nil

  defp follow_up_preview_route(%Run{} = run, managed_repo_id) do
    managed_repo_id = present_string(managed_repo_id)
    run_id = present_string(run.run_id)

    if is_binary(managed_repo_id) and is_binary(run_id) do
      "/repos/#{managed_repo_id}/runs/#{run_id}#run-detail-memory-context"
    else
      nil
    end
  end

  defp present_string(value) do
    case normalize_optional_string(value) do
      "nil" -> nil
      normalized -> normalized
    end
  end

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

  defp workflow_audit(%Run{} = run) do
    run_metadata =
      run
      |> Map.get(:run_metadata, %{})
      |> normalize_map()

    run_metadata
    |> Map.get("workflow_audit", %{})
    |> normalize_map()
  end

  defp workflow_audit(_run), do: %{}

  defp workflow_audit_status_transitions(%Run{} = run) do
    workflow_audit = workflow_audit(run)

    case Map.get(workflow_audit, "status_transitions") do
      transitions when is_list(transitions) ->
        transitions

      _other ->
        run
        |> Map.get(:run_metadata, %{})
        |> normalize_map()
        |> Map.get("status_transitions", [])
    end
  end

  defp workflow_audit_status_transitions(_run), do: []

  defp workflow_audit_step_results(%Run{} = run) do
    run
    |> workflow_audit()
    |> Map.get("step_results", %{})
    |> normalize_map()
  end

  defp workflow_audit_step_results(_run), do: %{}

  defp workflow_audit_error(%Run{} = run) do
    run
    |> workflow_audit()
    |> Map.get("error", %{})
    |> normalize_map()
  end

  defp workflow_audit_error(_run), do: %{}

  defp failure_context(%Run{} = run) do
    if failed_status?(Map.get(run, :status)) do
      error = workflow_audit_error(run)

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

  defp issue_triage_artifacts(%Run{} = run) do
    workflow_name =
      run
      |> Map.get(:workflow_name)
      |> normalize_optional_string()

    if workflow_name == "issue_triage" do
      step_results =
        workflow_audit_step_results(run)

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

  defp artifact_categories(%Run{} = run) do
    step_results = workflow_audit_step_results(run)

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

  defp approval_context(%Run{} = run) do
    step_results = workflow_audit_step_results(run)

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

  defp approval_context_blocker(%Run{} = run) do
    diagnostics =
      run
      |> workflow_audit_error()
      |> Map.get("approval_context_diagnostics", [])
      |> normalize_diagnostics()

    diagnostics
    |> List.last()
    |> normalize_approval_context_diagnostic()
  end

  defp approval_context_blocker(_run), do: nil

  defp retry_lineage_entries(%Run{} = run) do
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

  defp step_retry_state(%Run{} = run) do
    case Run.step_retry_contract(run) do
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

  defp memory_operator_opts(socket, %Run{} = run, extra_opts \\ []) do
    actor = approving_actor(socket)

    [
      actor: actor,
      workspace_path: memory_operator_workspace_path(socket),
      revision: memory_operator_revision(socket),
      run_id: map_get(run, :run_id, "run_id"),
      work_item_id: map_get(run, :work_item_id, "work_item_id")
    ] ++ extra_opts
  end

  defp memory_operator_workspace_path(socket) do
    socket.assigns
    |> Map.get(:memory_context, %{})
    |> Map.get(:workspace_path)
  end

  defp memory_operator_revision(socket) do
    socket.assigns
    |> Map.get(:memory_context, %{})
    |> Map.get(:graph, %{})
    |> Map.get(:current_revision)
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
