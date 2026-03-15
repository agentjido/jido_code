defmodule JidoCodeWeb.ProjectDetailLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.CodeServer
  alias JidoCode.Workbench.ProjectDetail
  alias JidoCode.Workbench.ProjectDetailWorkflowKickoff

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:project_detail, nil)
     |> assign(:project_load_error, nil)
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, "/workbench")
     |> assign(:conversation_ready?, false)
     |> assign(:conversation_id, nil)
     |> assign(:conversation_messages, [])
     |> assign(:conversation_input, "")
     |> assign(:conversation_status, :idle)
     |> assign(:conversation_error, nil)
     |> assign(:supported_workflows, ProjectDetailWorkflowKickoff.supported_workflows())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = Map.get(params, "id")
    return_to_path = normalize_return_to_path(Map.get(params, "return_to"))

    socket = cleanup_conversation(socket, stop?: false)

    socket =
      case ProjectDetail.load(project_id) do
        {:ok, project_detail} ->
          socket
          |> assign(:project_detail, project_detail)
          |> assign(:project_load_error, nil)

        {:error, project_load_error} ->
          socket
          |> assign(:project_detail, nil)
          |> assign(:project_load_error, project_load_error)
      end

    {:noreply,
     socket
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, return_to_path)
     |> reset_conversation_state()}
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
  def handle_event("start_conversation", _params, socket) do
    case conversation_start_block_reason(socket.assigns.project_detail) do
      %{} = readiness_error ->
        {:noreply,
         socket
         |> assign(:conversation_status, :error)
         |> assign(:conversation_error, normalize_conversation_error(readiness_error))
         |> assign(:conversation_ready?, false)
         |> assign(:conversation_id, nil)}

      nil ->
        case current_project_id(socket) do
          {:ok, project_id} ->
            case CodeServer.start_conversation(project_id) do
              {:ok, conversation_id} ->
                case CodeServer.subscribe(project_id, conversation_id, self()) do
                  :ok ->
                    {:noreply,
                     socket
                     |> assign(:conversation_ready?, true)
                     |> assign(:conversation_id, conversation_id)
                     |> assign(:conversation_messages, [])
                     |> assign(:conversation_status, :active)
                     |> assign(:conversation_error, nil)}

                  {:error, typed_error} ->
                    _ = CodeServer.stop_conversation(project_id, conversation_id)

                    {:noreply,
                     socket
                     |> assign(:conversation_status, :error)
                     |> assign(:conversation_error, normalize_conversation_error(typed_error))}
                end

              {:error, typed_error} ->
                {:noreply,
                 socket
                 |> assign(:conversation_status, :error)
                 |> assign(:conversation_error, normalize_conversation_error(typed_error))}
            end

          {:error, typed_error} ->
            {:noreply,
             socket
             |> assign(:conversation_status, :error)
             |> assign(:conversation_error, normalize_conversation_error(typed_error))}
        end
    end
  end

  @impl true
  def handle_event("conversation_input_change", params, socket) do
    {:noreply,
     assign(socket, :conversation_input, conversation_input_from_params(params, socket.assigns.conversation_input))}
  end

  @impl true
  def handle_event("send_conversation_message", params, socket) do
    input = conversation_input_from_params(params, socket.assigns.conversation_input)

    case normalize_optional_string(input) do
      nil ->
        {:noreply, assign(socket, :conversation_input, input || "")}

      content ->
        with {:ok, project_id} <- current_project_id(socket),
             {:ok, conversation_id} <- current_conversation_id(socket, project_id),
             :ok <- CodeServer.send_user_message(project_id, conversation_id, content) do
          {:noreply,
           socket
           |> assign(:conversation_input, "")
           |> assign(:conversation_status, :active)
           |> assign(:conversation_error, nil)}
        else
          {:error, typed_error} ->
            {:noreply,
             socket
             |> assign(:conversation_status, :error)
             |> assign(:conversation_error, normalize_conversation_error(typed_error))
             |> assign(:conversation_input, input || "")}
        end
    end
  end

  @impl true
  def handle_event("stop_conversation", _params, socket) do
    socket = cleanup_conversation(socket, stop?: true)

    {:noreply,
     socket
     |> reset_conversation_state()
     |> assign(:conversation_status, :stopped)}
  end

  @impl true
  def handle_info({:conversation_event, conversation_id, payload}, socket) do
    if active_conversation?(socket, conversation_id) do
      {:noreply, apply_conversation_event(socket, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:conversation_delta, _conversation_id, _payload}, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    _ = cleanup_conversation(socket, stop?: true)
    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-2">
        <h1 id="project-detail-title" class="text-2xl font-bold">Project detail</h1>
        <p class="text-base-content/70">
          Launch builtin workflows with project defaults from repository context.
        </p>
      </section>

      <section
        :if={@project_load_error}
        id="project-detail-load-error"
        class="rounded-lg border border-warning/60 bg-warning/10 p-4 space-y-2"
      >
        <p id="project-detail-load-error-label" class="font-semibold">
          Project detail is unavailable
        </p>
        <p id="project-detail-load-error-type" class="text-sm">
          Typed error: {@project_load_error.error_type}
        </p>
        <p id="project-detail-load-error-detail" class="text-sm">{@project_load_error.detail}</p>
        <p id="project-detail-load-error-remediation" class="text-sm">
          {@project_load_error.remediation}
        </p>
      </section>

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

        <section
          id="project-detail-workflow-defaults"
          class="rounded-lg border border-base-300 bg-base-200/40 p-3 space-y-1"
        >
          <p class="text-sm font-medium">Project launch defaults</p>
          <p id="project-detail-default-branch" class="text-sm text-base-content/80">
            Default branch: {@project_detail.default_branch}
          </p>
          <p id="project-detail-default-repository" class="text-sm text-base-content/80">
            Repository: {@project_detail.github_full_name}
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

        <section
          id="project-detail-conversation-panel"
          class="space-y-3 rounded-lg border border-base-300 bg-base-200/30 p-4"
        >
          <% conversation_start_block = conversation_start_block_reason(@project_detail) %>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 id="project-detail-conversation-title" class="font-semibold">Project conversation</h2>
              <p class="text-xs text-base-content/70">
                Runs through `jido_code_server` for this project workspace.
              </p>
            </div>
            <span
              id="project-detail-conversation-status"
              class={["badge badge-sm", conversation_status_badge_class(@conversation_status)]}
            >
              {conversation_status_label(@conversation_status)}
            </span>
          </div>

          <section
            :if={conversation_start_block}
            id="project-detail-conversation-disabled-guidance"
            class="rounded-lg border border-warning/60 bg-warning/10 p-3 space-y-1"
          >
            <p id="project-detail-conversation-disabled-label" class="font-semibold">
              Conversation controls are disabled
            </p>
            <p id="project-detail-conversation-disabled-type" class="text-xs">
              Typed readiness state: {conversation_start_block.error_type}
            </p>
            <p id="project-detail-conversation-disabled-detail" class="text-sm">
              {conversation_start_block.detail}
            </p>
            <p id="project-detail-conversation-disabled-remediation" class="text-sm">
              {conversation_start_block.remediation}
            </p>
          </section>

          <section
            :if={@conversation_error}
            id="project-detail-conversation-error"
            class="rounded border border-warning/60 bg-warning/10 p-3 space-y-1"
          >
            <p id="project-detail-conversation-error-type" class="text-xs">
              Typed conversation error: {@conversation_error.error_type}
            </p>
            <p id="project-detail-conversation-error-detail" class="text-sm">
              {@conversation_error.detail}
            </p>
            <p id="project-detail-conversation-error-remediation" class="text-sm">
              {@conversation_error.remediation}
            </p>
          </section>

          <div class="flex flex-wrap items-center gap-2">
            <button
              id="project-detail-conversation-start"
              type="button"
              class="btn btn-sm btn-primary"
              phx-click="start_conversation"
              disabled={@conversation_ready? or conversation_start_block != nil}
            >
              Start conversation
            </button>
            <button
              id="project-detail-conversation-stop"
              type="button"
              class="btn btn-sm btn-outline"
              phx-click="stop_conversation"
              disabled={!@conversation_ready?}
            >
              Stop conversation
            </button>
          </div>

          <form
            id="project-detail-conversation-form"
            phx-submit="send_conversation_message"
            phx-change="conversation_input_change"
            class="flex flex-col gap-2 md:flex-row md:items-end"
          >
            <div class="w-full">
              <.input
                id="project-detail-conversation-input"
                name="conversation[input]"
                label="Message"
                value={@conversation_input}
                placeholder="Ask about this repository..."
                autocomplete="off"
              />
            </div>
            <button
              id="project-detail-conversation-send"
              type="submit"
              class="btn btn-sm btn-secondary md:self-end"
              disabled={!@conversation_ready?}
            >
              Send
            </button>
          </form>

          <section id="project-detail-conversation-messages" class="space-y-2">
            <p
              :if={@conversation_messages == []}
              id="project-detail-conversation-empty"
              class="text-sm text-base-content/70"
            >
              No conversation messages yet.
            </p>

            <article
              :for={message <- @conversation_messages}
              id={"project-detail-conversation-message-#{message.id}"}
              class={["rounded border p-2 space-y-1", conversation_message_class(message)]}
            >
              <p id={"project-detail-conversation-role-#{message.id}"} class="text-xs font-medium">
                {conversation_role_label(message)}
              </p>
              <p id={"project-detail-conversation-content-#{message.id}"} class="text-sm whitespace-pre-wrap">
                {message.content}
              </p>
            </article>
          </section>
        </section>
      </section>
    </Layouts.app>
    """
  end

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

  defp reset_conversation_state(socket) do
    socket
    |> assign(:conversation_ready?, false)
    |> assign(:conversation_id, nil)
    |> assign(:conversation_messages, [])
    |> assign(:conversation_input, "")
    |> assign(:conversation_status, :idle)
    |> assign(:conversation_error, nil)
  end

  defp cleanup_conversation(socket, opts) do
    stop? = Keyword.get(opts, :stop?, true)

    project_id =
      socket.assigns
      |> Map.get(:project_detail)
      |> map_get(:id, "id")
      |> normalize_optional_string()

    conversation_id =
      socket.assigns
      |> Map.get(:conversation_id)
      |> normalize_optional_string()

    if is_binary(project_id) and is_binary(conversation_id) do
      _ = CodeServer.unsubscribe(project_id, conversation_id, self())

      if stop? do
        _ = CodeServer.stop_conversation(project_id, conversation_id)
      end
    end

    socket
  end

  defp current_project_id(socket) do
    case socket.assigns |> Map.get(:project_detail) |> map_get(:id, "id") |> normalize_optional_string() do
      nil ->
        {:error,
         conversation_error(
           "code_server_project_not_found",
           "Project context is unavailable.",
           "Open an imported project and retry the conversation action."
         )}

      project_id ->
        {:ok, project_id}
    end
  end

  defp current_conversation_id(socket, project_id) do
    case socket.assigns |> Map.get(:conversation_id) |> normalize_optional_string() do
      nil ->
        {:error,
         conversation_error(
           "code_server_message_send_failed",
           "Conversation has not been started yet.",
           "Start a conversation before sending messages.",
           project_id: project_id
         )}

      conversation_id ->
        {:ok, conversation_id}
    end
  end

  defp active_conversation?(socket, incoming_conversation_id) do
    current_conversation_id =
      socket.assigns
      |> Map.get(:conversation_id)
      |> normalize_optional_string()

    normalized_incoming_conversation_id = normalize_optional_string(incoming_conversation_id)

    socket.assigns.conversation_ready? == true and
      is_binary(current_conversation_id) and
      current_conversation_id == normalized_incoming_conversation_id
  end

  defp apply_conversation_event(socket, payload) when is_map(payload) do
    event_type = payload |> map_get(:type, "type") |> normalize_optional_string()
    event_data = payload |> map_get(:data, "data", %{}) |> normalize_map()

    case event_type do
      "user.message" ->
        append_conversation_message(socket, :user, extract_event_content(event_data), :final)

      "assistant.delta" ->
        update(socket, :conversation_messages, &append_assistant_delta(&1, extract_event_content(event_data)))

      "assistant.message" ->
        update(socket, :conversation_messages, &finalize_assistant_message(&1, extract_event_content(event_data)))

      "tool.failed" ->
        append_failure_message(socket, "tool.failed", event_data)

      "llm.failed" ->
        append_failure_message(socket, "llm.failed", event_data)

      _other ->
        socket
    end
  end

  defp apply_conversation_event(socket, _payload), do: socket

  defp append_failure_message(socket, failure_type, event_data) do
    detail =
      event_data
      |> extract_failure_detail()
      |> case do
        nil -> "Conversation runtime reported #{failure_type}."
        value -> "#{failure_type}: #{value}"
      end

    append_conversation_message(socket, :system, detail, :warning)
  end

  defp append_conversation_message(socket, role, content, status) do
    normalized_content = normalize_optional_string(content) || default_message_content(role, status)

    update(socket, :conversation_messages, fn messages ->
      messages ++ [%{id: conversation_message_id(), role: role, status: status, content: normalized_content}]
    end)
  end

  defp append_assistant_delta(messages, nil), do: messages

  defp append_assistant_delta(messages, delta_content) do
    normalized_delta = normalize_optional_string(delta_content)

    if is_nil(normalized_delta) do
      messages
    else
      case List.last(messages) do
        %{role: :assistant, status: :streaming} = last_message ->
          List.replace_at(messages, -1, %{last_message | content: "#{last_message.content}#{normalized_delta}"})

        _other ->
          messages ++
            [%{id: conversation_message_id(), role: :assistant, status: :streaming, content: normalized_delta}]
      end
    end
  end

  defp finalize_assistant_message(messages, final_content) do
    normalized_final_content = normalize_optional_string(final_content)

    case List.last(messages) do
      %{role: :assistant, status: :streaming} = last_message ->
        content =
          normalized_final_content || normalize_optional_string(last_message.content) || "Assistant response completed."

        List.replace_at(messages, -1, %{last_message | status: :final, content: content})

      _other when is_binary(normalized_final_content) ->
        messages ++
          [%{id: conversation_message_id(), role: :assistant, status: :final, content: normalized_final_content}]

      _other ->
        messages
    end
  end

  defp extract_event_content(event_data) do
    event_data
    |> map_get(:content, "content")
    |> normalize_optional_string()
    |> case do
      nil ->
        event_data
        |> map_get(:text, "text")
        |> normalize_optional_string()

      value ->
        value
    end
  end

  defp extract_failure_detail(event_data) do
    event_data
    |> map_get(:detail, "detail")
    |> normalize_optional_string()
    |> case do
      nil ->
        event_data
        |> map_get(:reason, "reason")
        |> normalize_optional_string()

      value ->
        value
    end
    |> case do
      nil ->
        event_data
        |> map_get(:message, "message")
        |> normalize_optional_string()

      value ->
        value
    end
  end

  defp conversation_input_from_params(params, fallback) when is_map(params) do
    params
    |> map_get(:conversation, "conversation", %{})
    |> normalize_map()
    |> map_get(:input, "input", fallback)
    |> normalize_optional_string()
    |> case do
      nil -> ""
      value -> value
    end
  end

  defp conversation_input_from_params(_params, fallback), do: normalize_optional_string(fallback) || ""

  defp normalize_conversation_error(error) when is_map(error) do
    %{
      error_type:
        normalize_optional_string(map_get(error, :error_type, "error_type")) || "code_server_unexpected_error",
      detail: normalize_optional_string(map_get(error, :detail, "detail")) || "Conversation request failed.",
      remediation:
        normalize_optional_string(map_get(error, :remediation, "remediation")) ||
          "Retry the conversation action after verifying project workspace readiness.",
      project_id: normalize_optional_string(map_get(error, :project_id, "project_id")),
      conversation_id: normalize_optional_string(map_get(error, :conversation_id, "conversation_id"))
    }
  end

  defp normalize_conversation_error(_error) do
    conversation_error(
      "code_server_unexpected_error",
      "Conversation request failed.",
      "Retry the conversation action after verifying project workspace readiness."
    )
  end

  defp conversation_error(error_type, detail, remediation, opts \\ []) do
    %{
      error_type: normalize_optional_string(error_type) || "code_server_unexpected_error",
      detail: normalize_optional_string(detail) || "Conversation request failed.",
      remediation:
        normalize_optional_string(remediation) ||
          "Retry the conversation action after verifying project workspace readiness.",
      project_id: normalize_optional_string(Keyword.get(opts, :project_id)),
      conversation_id: normalize_optional_string(Keyword.get(opts, :conversation_id))
    }
  end

  defp conversation_status_label(:idle), do: "Idle"
  defp conversation_status_label(:active), do: "Active"
  defp conversation_status_label(:stopped), do: "Stopped"
  defp conversation_status_label(:error), do: "Error"
  defp conversation_status_label(_status), do: "Idle"

  defp conversation_status_badge_class(:active), do: "badge-success"
  defp conversation_status_badge_class(:stopped), do: "badge-warning"
  defp conversation_status_badge_class(:error), do: "badge-error"
  defp conversation_status_badge_class(_status), do: "badge-ghost"

  defp conversation_message_class(%{role: :user}), do: "border-primary/40 bg-primary/5"
  defp conversation_message_class(%{role: :assistant, status: :streaming}), do: "border-secondary/40 bg-secondary/5"
  defp conversation_message_class(%{role: :assistant}), do: "border-base-300 bg-base-100"
  defp conversation_message_class(%{role: :system}), do: "border-warning/60 bg-warning/10"
  defp conversation_message_class(_message), do: "border-base-300 bg-base-100"

  defp conversation_role_label(%{role: :user}), do: "User"
  defp conversation_role_label(%{role: :assistant, status: :streaming}), do: "Assistant (streaming)"
  defp conversation_role_label(%{role: :assistant}), do: "Assistant"
  defp conversation_role_label(%{role: :system}), do: "System warning"
  defp conversation_role_label(_message), do: "Message"

  defp default_message_content(:user, _status), do: "(empty user message)"
  defp default_message_content(:assistant, :streaming), do: "(streaming assistant response)"
  defp default_message_content(:assistant, _status), do: "(empty assistant response)"
  defp default_message_content(:system, _status), do: "(conversation warning)"
  defp default_message_content(_role, _status), do: "(empty message)"

  defp conversation_message_id do
    "conversation-message-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp conversation_start_block_reason(project_detail) when is_map(project_detail) do
    project_id =
      project_detail
      |> map_get(:id, "id")
      |> normalize_optional_string()

    cond do
      not project_ready_for_launch?(project_detail) ->
        readiness = project_readiness(project_detail)

        conversation_error(
          normalize_optional_string(map_get(readiness, :error_type, "error_type")) ||
            "code_server_workspace_unavailable",
          normalize_optional_string(map_get(readiness, :detail, "detail")) ||
            "Project workspace prerequisites are incomplete for conversation runtime.",
          normalize_optional_string(map_get(readiness, :remediation, "remediation")) ||
            "Complete project import and baseline sync, then retry the conversation action.",
          project_id: project_id
        )

      true ->
        workspace_settings = conversation_workspace_settings(project_detail)

        case normalize_workspace_environment(
               map_get(workspace_settings, :workspace_environment, "workspace_environment")
             ) do
          :local ->
            conversation_workspace_path_block_reason(workspace_settings, project_id)

          :sprite ->
            conversation_error(
              "code_server_workspace_environment_unsupported",
              "Project workspace environment is sprite/cloud and cannot run local conversations.",
              "Switch the project workspace environment to local and rerun baseline sync before starting a conversation.",
              project_id: project_id
            )

          :unknown ->
            conversation_error(
              "code_server_workspace_environment_unsupported",
              "Project workspace environment is unavailable or unsupported.",
              "Switch the project workspace environment to local and rerun baseline sync before starting a conversation.",
              project_id: project_id
            )
        end
    end
  end

  defp conversation_start_block_reason(_project_detail) do
    conversation_error(
      "code_server_project_not_found",
      "Project context is unavailable.",
      "Open an imported project and retry the conversation action."
    )
  end

  defp conversation_workspace_settings(project_detail) do
    project_detail
    |> map_get(:settings, "settings", %{})
    |> normalize_map()
    |> map_get(:workspace, "workspace", %{})
    |> normalize_map()
  end

  defp conversation_workspace_path_block_reason(workspace_settings, project_id) do
    case workspace_settings
         |> map_get(:workspace_path, "workspace_path")
         |> normalize_optional_string() do
      nil ->
        conversation_error(
          "code_server_workspace_unavailable",
          "Local workspace path is missing from project settings.",
          "Complete project import and baseline sync, then ensure a local absolute workspace path is available.",
          project_id: project_id
        )

      workspace_path ->
        cond do
          Path.type(workspace_path) != :absolute ->
            conversation_error(
              "code_server_workspace_unavailable",
              "Workspace path must be absolute: #{workspace_path}.",
              "Update project workspace settings to use an absolute local path, then retry.",
              project_id: project_id
            )

          not File.dir?(workspace_path) ->
            conversation_error(
              "code_server_workspace_unavailable",
              "Workspace path does not exist on disk: #{workspace_path}.",
              "Re-import the project workspace or correct the workspace path, then retry.",
              project_id: project_id
            )

          true ->
            nil
        end
    end
  end

  defp normalize_workspace_environment(:local), do: :local
  defp normalize_workspace_environment("local"), do: :local
  defp normalize_workspace_environment(:sprite), do: :sprite
  defp normalize_workspace_environment("sprite"), do: :sprite
  defp normalize_workspace_environment(:cloud), do: :sprite
  defp normalize_workspace_environment("cloud"), do: :sprite
  defp normalize_workspace_environment(_other), do: :unknown

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

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}
end
