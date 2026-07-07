defmodule JidoCodeWeb.AgentsLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.Agents.SupportAgentConfigs
  alias JidoCodeWeb.OperatorShell

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:issue_bot_error, nil)
      |> assign(
        :issue_bot_supported_webhook_events,
        SupportAgentConfigs.supported_issue_bot_webhook_events()
      )
      |> assign(
        :issue_bot_supported_approval_modes,
        SupportAgentConfigs.supported_issue_bot_approval_modes()
      )
      |> assign(:project_count, 0)
      |> stream(:project_configs, [], reset: true)
      |> load_project_configs()

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "set_issue_bot_enabled",
        %{"project_id" => project_id, "enabled" => enabled},
        socket
      ) do
    case SupportAgentConfigs.set_issue_bot_enabled(project_id, enabled) do
      {:ok, project_config} ->
        {:noreply,
         socket
         |> assign(:issue_bot_error, nil)
         |> stream_insert(:project_configs, project_config)}

      {:error, typed_error} ->
        {:noreply, assign(socket, :issue_bot_error, typed_error)}
    end
  end

  def handle_event("set_issue_bot_enabled", _params, socket) do
    {:noreply,
     assign(socket, :issue_bot_error, %{
       error_type: "support_agent_config_validation_failed",
       detail: "Issue Bot toggle request is missing required parameters.",
       remediation: "Select Enable or Disable from a valid project row and retry."
     })}
  end

  @impl true
  def handle_event(
        "set_issue_bot_webhook_events",
        %{"project_id" => project_id} = params,
        socket
      ) do
    webhook_events = Map.get(params, "webhook_events", [])

    case SupportAgentConfigs.set_issue_bot_webhook_events(project_id, webhook_events) do
      {:ok, project_config} ->
        {:noreply,
         socket
         |> assign(:issue_bot_error, nil)
         |> stream_insert(:project_configs, project_config)}

      {:error, typed_error} ->
        {:noreply, assign(socket, :issue_bot_error, typed_error)}
    end
  end

  def handle_event("set_issue_bot_webhook_events", _params, socket) do
    {:noreply,
     assign(socket, :issue_bot_error, %{
       error_type: "support_agent_config_validation_failed",
       detail: "Issue Bot webhook event update is missing a project identifier.",
       remediation: "Submit webhook event selections from a valid project row and retry."
     })}
  end

  @impl true
  def handle_event(
        "set_issue_bot_approval_mode",
        %{"project_id" => project_id, "approval_mode" => approval_mode},
        socket
      ) do
    case SupportAgentConfigs.set_issue_bot_approval_mode(project_id, approval_mode) do
      {:ok, project_config} ->
        {:noreply,
         socket
         |> assign(:issue_bot_error, nil)
         |> stream_insert(:project_configs, project_config)}

      {:error, typed_error} ->
        {:noreply, assign(socket, :issue_bot_error, typed_error)}
    end
  end

  def handle_event("set_issue_bot_approval_mode", _params, socket) do
    {:noreply,
     assign(socket, :issue_bot_error, %{
       error_type: "support_agent_config_validation_failed",
       detail: "Issue Bot approval mode update is missing required parameters.",
       remediation: "Select an approval mode from a valid project row and retry."
     })}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      active_area={:agents}
      area_panel={JidoCodeWeb.AreaPanels.panel_for(:agents)}
    >
      <.single_pane_shell id="agents-shell" breadcrumbs={agents_breadcrumbs()} pane={agents_pane()}>
        <.operator_state_notice
          :if={@issue_bot_error}
          id="agents-issue-bot-error"
          title="Issue Bot configuration update failed"
          state={@issue_bot_error}
          kind={:error}
        />

        <section class="rounded-lg border border-border bg-card overflow-x-auto">
          <table id="agents-project-table" class="w-full caption-bottom text-sm">
            <thead>
              <tr>
                <th>Repository</th>
                <th>Issue Bot status</th>
                <th>Webhook events</th>
                <th>Approval policy</th>
                <th>Controls</th>
              </tr>
            </thead>
            <tbody id="agents-project-rows" phx-update="stream">
              <tr :if={@project_count == 0} id="agents-project-empty">
                <td colspan="5" class="py-8 text-center text-sm text-muted-foreground">
                  No repositories are available for Issue Bot configuration.
                </td>
              </tr>

              <tr :for={{dom_id, project_config} <- @streams.project_configs} id={dom_id}>
                <td>
                  <p id={"agents-project-github-full-name-#{project_config.id}"} class="font-medium">
                    {project_config.github_full_name}
                  </p>
                  <p id={"agents-project-name-#{project_config.id}"} class="text-xs text-muted-foreground">
                    {project_config.name}
                  </p>
                </td>
                <td id={"agents-issue-bot-status-#{project_config.id}"}>
                  <span class={issue_bot_status_class(project_config.enabled)}>
                    {issue_bot_status_label(project_config.enabled)}
                  </span>
                </td>
                <td>
                  <form
                    id={"agents-issue-bot-events-form-#{project_config.id}"}
                    phx-submit="set_issue_bot_webhook_events"
                    class="space-y-2"
                  >
                    <input type="hidden" name="project_id" value={project_config.id} />
                    <div class="grid gap-1">
                      <label
                        :for={event <- @issue_bot_supported_webhook_events}
                        id={
                          "agents-issue-bot-event-option-#{project_config.id}-#{issue_bot_webhook_event_dom_id(event)}"
                        }
                        class="inline-flex cursor-pointer items-center justify-start gap-2 py-0 text-xs"
                      >
                        <input
                          id={
                            "agents-issue-bot-event-checkbox-#{project_config.id}-#{issue_bot_webhook_event_dom_id(event)}"
                          }
                          type="checkbox"
                          name="webhook_events[]"
                          value={event}
                          checked={issue_bot_webhook_event_selected?(project_config.webhook_events, event)}
                          class="ui-checkbox ui-checkbox-sm"
                        />
                        <span class="text-xs">{event}</span>
                      </label>
                    </div>
                    <button
                      id={"agents-issue-bot-events-save-#{project_config.id}"}
                      type="submit"
                      class="ui-button ui-button-xs ui-button-outline"
                    >
                      Save events
                    </button>
                  </form>
                </td>
                <td>
                  <p id={"agents-issue-bot-approval-mode-#{project_config.id}"} class="text-xs text-muted-foreground">
                    {issue_bot_approval_mode_label(project_config.approval_policy)}
                  </p>
                  <form
                    id={"agents-issue-bot-approval-form-#{project_config.id}"}
                    phx-submit="set_issue_bot_approval_mode"
                    class="mt-2 space-y-2"
                  >
                    <input type="hidden" name="project_id" value={project_config.id} />
                    <select
                      id={"agents-issue-bot-approval-select-#{project_config.id}"}
                      name="approval_mode"
                      class="w-full max-w-[14rem] ui-select text-xs"
                    >
                      <option
                        :for={approval_mode <- @issue_bot_supported_approval_modes}
                        value={approval_mode}
                        selected={issue_bot_approval_mode_selected?(project_config.approval_policy, approval_mode)}
                      >
                        {issue_bot_approval_mode_option_label(approval_mode)}
                      </option>
                    </select>
                    <button
                      id={"agents-issue-bot-approval-save-#{project_config.id}"}
                      type="submit"
                      class="ui-button ui-button-xs ui-button-outline"
                    >
                      Save policy
                    </button>
                  </form>
                  <p id={"agents-issue-bot-last-updated-#{project_config.id}"} class="text-[11px] text-muted-foreground">
                    Last updated: {issue_bot_last_updated_label(project_config.last_updated)}
                  </p>
                </td>
                <td>
                  <div class="flex flex-wrap gap-2">
                    <button
                      id={"agents-issue-bot-enable-#{project_config.id}"}
                      type="button"
                      class="ui-button ui-button-xs ui-button-secondary"
                      phx-click="set_issue_bot_enabled"
                      phx-value-project_id={project_config.id}
                      phx-value-enabled="true"
                      disabled={project_config.enabled}
                    >
                      Enable
                    </button>
                    <button
                      id={"agents-issue-bot-disable-#{project_config.id}"}
                      type="button"
                      class="ui-button ui-button-xs ui-button-warning"
                      phx-click="set_issue_bot_enabled"
                      phx-value-project_id={project_config.id}
                      phx-value-enabled="false"
                      disabled={!project_config.enabled}
                    >
                      Disable
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </.single_pane_shell>
    </Layouts.app>
    """
  end

  defp agents_breadcrumbs do
    [
      OperatorShell.breadcrumb(%{
        id: "agents-breadcrumb-current",
        label: "Agents",
        current?: true
      })
    ]
  end

  defp agents_pane do
    OperatorShell.pane(%{
      id: "agents-pane",
      title: "Support agent controls",
      summary: "Configure per-project Issue Bot automation controls."
    })
  end

  defp load_project_configs(socket) do
    case SupportAgentConfigs.list_issue_bot_configs() do
      {:ok, project_configs} ->
        socket
        |> assign(:issue_bot_error, nil)
        |> assign(:project_count, length(project_configs))
        |> stream(:project_configs, project_configs, reset: true)

      {:error, typed_error} ->
        socket
        |> assign(:issue_bot_error, typed_error)
        |> assign(:project_count, 0)
        |> stream(:project_configs, [], reset: true)
    end
  end

  defp issue_bot_status_label(true), do: "Enabled"
  defp issue_bot_status_label(false), do: "Disabled"

  defp issue_bot_status_class(true), do: "ui-badge ui-badge-success"
  defp issue_bot_status_class(false), do: "ui-badge ui-badge-warning"

  defp issue_bot_webhook_event_selected?(webhook_events, event) when is_list(webhook_events) do
    event in webhook_events
  end

  defp issue_bot_webhook_event_selected?(_webhook_events, _event), do: false

  defp issue_bot_webhook_event_dom_id(event) when is_binary(event) do
    event
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      dom_id -> dom_id
    end
  end

  defp issue_bot_webhook_event_dom_id(_event), do: "unknown"

  defp issue_bot_approval_mode_label(%{} = approval_policy) do
    case map_get(approval_policy, :mode, "mode") do
      "auto_post" -> "Auto-post"
      "approval_required" -> "Approval required"
      _other -> "Approval required"
    end
  end

  defp issue_bot_approval_mode_label(_approval_policy), do: "Approval required"

  defp issue_bot_approval_mode_option_label("auto_post"), do: "Auto-post"
  defp issue_bot_approval_mode_option_label("approval_required"), do: "Approval required"
  defp issue_bot_approval_mode_option_label(_approval_mode), do: "Approval required"

  defp issue_bot_approval_mode_selected?(approval_policy, approval_mode)
       when is_map(approval_policy) do
    map_get(approval_policy, :mode, "mode", "approval_required") == approval_mode
  end

  defp issue_bot_approval_mode_selected?(_approval_policy, approval_mode),
    do: approval_mode == "approval_required"

  defp issue_bot_last_updated_label(last_updated) when is_map(last_updated) do
    case map_get(last_updated, :updated_at, "updated_at") do
      updated_at when is_binary(updated_at) -> updated_at
      _other -> "unavailable"
    end
  end

  defp issue_bot_last_updated_label(_last_updated), do: "unavailable"

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
