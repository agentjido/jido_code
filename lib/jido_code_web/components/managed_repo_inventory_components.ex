defmodule JidoCodeWeb.ManagedRepoInventoryComponents do
  @moduledoc false

  use JidoCodeWeb, :html

  alias JidoCode.Workbench.InventorySurface

  attr :row, :map, required: true
  attr :dom_prefix, :string, required: true
  attr :detail_path, :string, default: nil

  def managed_repo_hint_stack(assigns) do
    ~H"""
    <div
      :if={
        InventorySurface.semantic_graph_hint(@row) ||
          InventorySurface.memory_graph_hint(@row) ||
          InventorySurface.conversation_supervision_projection(@row) ||
          InventorySurface.conversation_supervision_notice(@row)
      }
      class="space-y-2 pt-2"
    >
      <div
        :if={InventorySurface.semantic_graph_hint(@row)}
        id={"#{@dom_prefix}-semantic-hint-#{@row.id}"}
        class="space-y-1"
      >
        <span
          id={"#{@dom_prefix}-semantic-hint-badge-#{@row.id}"}
          class={InventorySurface.semantic_graph_hint_badge_class(InventorySurface.semantic_graph_hint(@row))}
        >
          {InventorySurface.semantic_graph_hint(@row).label}
        </span>
        <p
          id={"#{@dom_prefix}-semantic-hint-detail-#{@row.id}"}
          class="text-[11px] text-base-content/65"
        >
          {InventorySurface.semantic_graph_hint(@row).detail}
        </p>
        <.link
          :if={InventorySurface.semantic_graph_hint_recovery_path(@row, @detail_path)}
          id={"#{@dom_prefix}-semantic-hint-recovery-#{@row.id}"}
          class="link link-primary text-[11px]"
          href={InventorySurface.semantic_graph_hint_recovery_path(@row, @detail_path)}
        >
          {InventorySurface.semantic_graph_hint(@row).remediation}
        </.link>
      </div>

      <div
        :if={InventorySurface.memory_graph_hint(@row)}
        id={"#{@dom_prefix}-memory-hint-#{@row.id}"}
        class="space-y-1"
      >
        <span
          id={"#{@dom_prefix}-memory-hint-badge-#{@row.id}"}
          class={InventorySurface.memory_graph_hint_badge_class(InventorySurface.memory_graph_hint(@row))}
        >
          {InventorySurface.memory_graph_hint(@row).label}
        </span>
        <p
          id={"#{@dom_prefix}-memory-hint-detail-#{@row.id}"}
          class="text-[11px] text-base-content/65"
        >
          {InventorySurface.memory_graph_hint(@row).detail}
        </p>
        <.link
          :if={InventorySurface.memory_graph_hint_recovery_path(@row, @detail_path)}
          id={"#{@dom_prefix}-memory-hint-recovery-#{@row.id}"}
          class="link link-primary text-[11px]"
          href={InventorySurface.memory_graph_hint_recovery_path(@row, @detail_path)}
        >
          {InventorySurface.memory_graph_hint(@row).remediation}
        </.link>
      </div>

      <div
        :if={InventorySurface.conversation_supervision_projection(@row)}
        id={"#{@dom_prefix}-conversation-hint-#{@row.id}"}
        class="space-y-2"
      >
        <div class="flex flex-wrap items-center gap-2">
          <.conversation_role_badge
            id={"#{@dom_prefix}-conversation-role-#{@row.id}"}
            scope={InventorySurface.conversation_supervision_role_scope(@row)}
            attachment_mode={InventorySurface.conversation_supervision_role_attachment_mode(@row)}
            work_item_id={InventorySurface.conversation_supervision_role_work_item_id(@row)}
          />
          <.conversation_status_badge
            :if={InventorySurface.conversation_supervision_status(@row)}
            id={"#{@dom_prefix}-conversation-status-#{@row.id}"}
            status={InventorySurface.conversation_supervision_status(@row)}
          />
          <span
            :if={InventorySurface.conversation_supervision_active_count(@row) > 0}
            id={"#{@dom_prefix}-conversation-hint-badge-#{@row.id}"}
            class="badge badge-sm badge-primary badge-outline font-medium"
          >
            {InventorySurface.conversation_supervision_active_count_label(@row)}
          </span>
          <span
            :if={InventorySurface.conversation_supervision_clarification_count(@row) > 0}
            id={"#{@dom_prefix}-conversation-clarification-#{@row.id}"}
            class="badge badge-sm badge-warning badge-outline font-medium"
          >
            {InventorySurface.conversation_supervision_clarification_count_label(@row)}
          </span>
        </div>
        <p
          id={"#{@dom_prefix}-conversation-hint-detail-#{@row.id}"}
          class="text-[11px] text-base-content/65"
        >
          {InventorySurface.conversation_supervision_detail(@row)}
        </p>
        <p
          :if={InventorySurface.conversation_supervision_work_item(@row)}
          id={"#{@dom_prefix}-conversation-work-item-#{@row.id}"}
          class="text-[11px] text-base-content/70"
        >
          Latest governed work: {InventorySurface.conversation_supervision_work_item(@row).summary} ( {conversation_status_label(
            InventorySurface.conversation_supervision_work_item(@row).status
          )})
        </p>
        <.link
          id={"#{@dom_prefix}-conversation-link-#{@row.id}"}
          class="link link-primary text-[11px]"
          href={@detail_path}
        >
          {InventorySurface.conversation_supervision_action_label(@row)}
        </.link>
      </div>

      <div
        :if={InventorySurface.conversation_supervision_notice(@row)}
        id={"#{@dom_prefix}-conversation-notice-#{@row.id}"}
        class="space-y-1"
      >
        <span
          id={"#{@dom_prefix}-conversation-notice-label-#{@row.id}"}
          class="badge badge-warning badge-outline"
        >
          Conversation state unavailable
        </span>
        <p
          id={"#{@dom_prefix}-conversation-notice-detail-#{@row.id}"}
          class="text-[11px] text-base-content/65"
        >
          {InventorySurface.conversation_supervision_notice(@row).detail}
        </p>
        <.link
          id={"#{@dom_prefix}-conversation-notice-link-#{@row.id}"}
          class="link link-primary text-[11px]"
          href={@detail_path}
        >
          Open repo detail
        </.link>
      </div>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :dom_prefix, :string, required: true
  attr :detail_path, :string, default: nil
  attr :kind, :atom, required: true
  attr :recent_run_outcome, :map, default: nil
  attr :triage_policy_state, :map, default: nil
  attr :issue_triage_feedback, :map, default: nil
  attr :fix_feedback, :map, default: nil

  def managed_repo_action_cluster(assigns) do
    assigns =
      assigns
      |> assign(:link_target, action_link_target(assigns.row, assigns.detail_path, assigns.kind))
      |> assign(:github_target, github_target(assigns.row, assigns.kind))
      |> assign(:heading, if(assigns.kind == :issue, do: "Issues", else: "PRs"))
      |> assign(:context_item_type, if(assigns.kind == :issue, do: "issue", else: "pull_request"))

    ~H"""
    <div id={"#{@dom_prefix}-links-#{@row.id}"}>
      <p class="font-medium text-base-content/80">{@heading}</p>
      <div class="flex flex-col gap-0.5">
        <.inventory_row_link
          link_id={"#{@dom_prefix}-github-link-#{@row.id}"}
          disabled_id={"#{@dom_prefix}-github-disabled-#{@row.id}"}
          reason_id={"#{@dom_prefix}-github-disabled-reason-#{@row.id}"}
          label={"GitHub #{@heading}"}
          target={@github_target}
          disabled_reason="GitHub repository URL is unavailable for this row."
          external
        />
        <.inventory_row_link
          link_id={"#{@dom_prefix}-project-link-#{@row.id}"}
          disabled_id={"#{@dom_prefix}-project-disabled-#{@row.id}"}
          reason_id={"#{@dom_prefix}-project-disabled-reason-#{@row.id}"}
          label="Repo detail"
          target={@link_target}
          disabled_reason="Repo detail link is unavailable for this row."
        />
        <.inventory_recent_run_outcome
          outcome={@recent_run_outcome}
          dom_prefix={"#{@dom_prefix}-run-outcome-#{@row.id}"}
        />

        <%= if @kind == :issue do %>
          <%= if Map.get(@triage_policy_state || %{}, :enabled, true) do %>
            <button
              id={"#{@dom_prefix}-triage-action-#{@row.id}"}
              type="button"
              class="btn btn-xs btn-outline btn-accent w-fit mt-1"
              phx-click="kickoff_issue_triage_workflow"
              phx-value-project_id={@row.id}
              phx-value-context_item_type="issue"
            >
              Kick off issue triage workflow
            </button>
          <% else %>
            <.inventory_issue_triage_policy_blocked_feedback
              policy_state={@triage_policy_state}
              dom_prefix={"#{@dom_prefix}-triage-disabled-#{@row.id}"}
            />
          <% end %>

          <.inventory_workflow_feedback
            feedback={@issue_triage_feedback}
            dom_prefix={"#{@dom_prefix}-triage-#{@row.id}"}
          />
        <% end %>

        <button
          id={"#{@dom_prefix}-fix-action-#{@row.id}"}
          type="button"
          class="btn btn-xs btn-outline btn-primary w-fit mt-1"
          phx-click="kickoff_fix_workflow"
          phx-value-project_id={@row.id}
          phx-value-context_item_type={@context_item_type}
        >
          Kick off fix workflow
        </button>

        <.inventory_workflow_feedback
          feedback={@fix_feedback}
          dom_prefix={"#{@dom_prefix}-fix-#{@row.id}"}
        />
      </div>
    </div>
    """
  end

  attr :feedback, :map, default: nil
  attr :dom_prefix, :string, required: true

  def inventory_workflow_feedback(assigns) do
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

  attr :outcome, :map, default: nil
  attr :dom_prefix, :string, required: true

  def inventory_recent_run_outcome(assigns) do
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
            {outcome.guidance || "Refresh managed-repository inventory to resolve recent run status."}
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
            <span class={InventorySurface.run_outcome_status_badge_class(outcome.status)}>
              {InventorySurface.run_outcome_status_label(outcome.status)}
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

  attr :policy_state, :map, required: true
  attr :dom_prefix, :string, required: true

  def inventory_issue_triage_policy_blocked_feedback(assigns) do
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

  attr :link_id, :string, required: true
  attr :disabled_id, :string, required: true
  attr :reason_id, :string, required: true
  attr :label, :string, required: true
  attr :target, :string, default: nil
  attr :disabled_reason, :string, required: true
  attr :external, :boolean, default: false

  def inventory_row_link(assigns) do
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

  defp action_link_target(row, detail_path, _kind) do
    if is_binary(detail_path) do
      detail_path
    else
      InventorySurface.project_detail_path(row)
    end
  end

  defp github_target(row, :issue), do: InventorySurface.issue_github_url(row)
  defp github_target(row, :pull_request), do: InventorySurface.pull_request_github_url(row)

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

  defp conversation_status_label(status) when is_binary(status), do: status
  defp conversation_status_label(status) when is_atom(status), do: Atom.to_string(status)
  defp conversation_status_label(_status), do: "unknown"
end
