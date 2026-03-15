defmodule JidoCodeWeb.FolioLive do
  @moduledoc """
  Folio - GTD Task Manager

  Brain dump thoughts via chat, process them into actions/projects,
  and work from your next actions list.
  """
  use JidoCodeWeb, :live_view

  alias JidoCode.Folio.FolioAgent
  alias JidoCode.Folio
  alias JidoCode.Folio.{InboxItem, Action, Project}

  @poll_interval 80

  defmodule Trace do
    @moduledoc false
    defstruct last_iteration: 0,
              text: "",
              thinking: "",
              seen_tool_ids: MapSet.new(),
              completed_tool_ids: MapSet.new(),
              awaiting_start?: true
  end

  @impl true
  def mount(_params, _session, socket) do
    actor = %{id: Ash.UUID.generate(), role: :user}

    socket =
      socket
      |> assign(:agent_pid, nil)
      |> assign(:running?, false)
      |> assign(:input, "")
      |> assign(:error, nil)
      |> assign(:trace, %Trace{})
      |> assign(:messages, [])
      |> assign(:poll_ref, nil)
      |> assign(:actor, actor)
      |> assign(:active_tab, :inbox)
      |> assign(:inbox_items, [])
      |> assign(:next_actions, [])
      |> assign(:projects, [])

    if connected?(socket) do
      case start_agent() do
        {:ok, pid} ->
          Process.monitor(pid)
          socket = fetch_all_data(socket)
          {:ok, assign(socket, :agent_pid, pid)}

        {:error, reason} ->
          {:ok, assign(socket, :error, "Failed to start agent: #{inspect(reason)}")}
      end
    else
      {:ok, socket}
    end
  end

  defp start_agent do
    Jido.AgentServer.start_link(
      agent: FolioAgent,
      id: "folio-#{System.unique_integer([:positive])}",
      jido: JidoCode.Jido
    )
  end

  defp fetch_all_data(socket) do
    context = ash_context(socket.assigns.actor)

    inbox =
      case InboxItem.Jido.Inbox.run(%{}, context) do
        {:ok, items} when is_list(items) -> items
        {:ok, item} -> [item]
        _ -> []
      end

    next =
      case Action.Jido.Next.run(%{}, context) do
        {:ok, items} when is_list(items) -> items
        {:ok, item} -> [item]
        _ -> []
      end

    projects =
      case Project.Jido.Active.run(%{}, context) do
        {:ok, items} when is_list(items) -> items
        {:ok, item} -> [item]
        _ -> []
      end

    socket
    |> assign(:inbox_items, inbox)
    |> assign(:next_actions, next)
    |> assign(:projects, projects)
  end

  defp ash_context(actor) do
    %{domain: Folio, actor: actor}
  end

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    :ok
  end

  @impl true
  def handle_event("update_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, tab_atom)}
  end

  def handle_event("send", _params, socket) do
    input = String.trim(socket.assigns.input)

    if input == "" or socket.assigns.running? or is_nil(socket.assigns.agent_pid) do
      {:noreply, socket}
    else
      case FolioAgent.ask(socket.assigns.agent_pid, input) do
        {:ok, _request} ->
          user_msg = %{id: gen_id(), role: :user, content: input}
          pending_msg = %{id: gen_id(), role: :assistant, content: "", pending: true}

          {:noreply,
           socket
           |> assign(:input, "")
           |> assign(:running?, true)
           |> assign(:trace, %Trace{})
           |> assign(:messages, socket.assigns.messages ++ [user_msg, pending_msg])
           |> schedule_poll()}

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Failed to send message: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("restart_agent", _params, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    case start_agent() do
      {:ok, pid} ->
        Process.monitor(pid)
        socket = fetch_all_data(socket)

        {:noreply,
         socket
         |> assign(:agent_pid, pid)
         |> assign(:error, nil)
         |> assign(:running?, false)
         |> assign(:messages, [])
         |> assign(:trace, %Trace{})}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to restart: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:poll, ref}, %{assigns: %{poll_ref: ref}} = socket) do
    socket = assign(socket, :poll_ref, nil)

    if socket.assigns.running? and socket.assigns.agent_pid do
      case get_snapshot(socket.assigns.agent_pid) do
        {:ok, snap} ->
          {trace, messages} =
            process_snapshot(socket.assigns.trace, socket.assigns.messages, snap)

          socket =
            socket
            |> assign(:trace, trace)
            |> assign(:messages, messages)

          if snap.done? and not trace.awaiting_start? do
            socket = fetch_all_data(socket)
            {:noreply, assign(socket, :running?, false)}
          else
            {:noreply, schedule_poll(socket)}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:running?, false)
           |> assign(:error, "Snapshot error: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll, _old_ref}, socket) do
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, socket) do
    if pid == socket.assigns.agent_pid do
      {:noreply,
       socket
       |> assign(:agent_pid, nil)
       |> assign(:running?, false)
       |> assign(:poll_ref, nil)
       |> assign(:error, "Agent crashed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  defp schedule_poll(socket) do
    ref = make_ref()
    Process.send_after(self(), {:poll, ref}, @poll_interval)
    assign(socket, :poll_ref, ref)
  end

  defp get_snapshot(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, server_state} ->
        {:ok, FolioAgent.strategy_snapshot(server_state.agent)}

      error ->
        error
    end
  end

  defp process_snapshot(trace, messages, snap) do
    details = snap.details || %{}

    current_iteration = details[:iteration] || 0
    streaming_text = details[:streaming_text] || ""
    streaming_thinking = details[:streaming_thinking] || ""
    tool_calls = details[:tool_calls] || []

    trace =
      if trace.awaiting_start? and snap.status == :running do
        %{trace | awaiting_start?: false}
      else
        trace
      end

    if trace.awaiting_start? do
      {trace, messages}
    else
      trace =
        if current_iteration > trace.last_iteration and trace.last_iteration > 0 do
          %{trace | last_iteration: current_iteration, text: "", thinking: ""}
        else
          %{trace | last_iteration: max(current_iteration, trace.last_iteration)}
        end

      {messages, trace} = sync_tool_calls(messages, tool_calls, trace)

      messages = update_pending_content(messages, streaming_text)

      {messages, trace} =
        if snap.done? do
          final_content = snap.result || streaming_text
          messages = finalize_pending(messages, final_content, trace.thinking)
          {messages, trace}
        else
          trace = %{trace | text: streaming_text, thinking: streaming_thinking}
          {messages, trace}
        end

      {trace, messages}
    end
  end

  defp sync_tool_calls(messages, [], trace), do: {messages, trace}

  defp sync_tool_calls(messages, tool_calls, trace) do
    {messages, seen, completed} =
      Enum.reduce(tool_calls, {messages, trace.seen_tool_ids, trace.completed_tool_ids}, fn tc,
                                                                                            {msgs, seen, completed} ->
        if MapSet.member?(seen, tc.id) do
          msgs = update_tool_call_status(msgs, tc)

          completed =
            if tc.status in [:completed, :failed],
              do: MapSet.put(completed, tc.id),
              else: completed

          {msgs, seen, completed}
        else
          tool_msg = %{
            id: tc.id,
            role: :tool_call,
            tool_name: tc.name,
            arguments: tc.arguments,
            status: tc.status,
            result: tc.result
          }

          msgs = insert_before_pending(msgs, tool_msg)
          seen = MapSet.put(seen, tc.id)

          completed =
            if tc.status in [:completed, :failed],
              do: MapSet.put(completed, tc.id),
              else: completed

          {msgs, seen, completed}
        end
      end)

    {messages, %{trace | seen_tool_ids: seen, completed_tool_ids: completed}}
  end

  defp update_tool_call_status(messages, tc) do
    Enum.map(messages, fn msg ->
      if msg[:id] == tc.id do
        %{msg | status: tc.status, result: tc.result}
      else
        msg
      end
    end)
  end

  defp insert_before_pending(messages, new_msg) do
    case Enum.split_while(messages, &(!&1[:pending])) do
      {before, [pending | rest]} -> before ++ [new_msg, pending | rest]
      {all, []} -> all ++ [new_msg]
    end
  end

  defp update_pending_content(messages, content) do
    Enum.map(messages, fn msg ->
      if msg[:pending], do: %{msg | content: content}, else: msg
    end)
  end

  defp finalize_pending(messages, content, reasoning) do
    Enum.map(messages, fn msg ->
      if msg[:pending] do
        msg
        |> Map.put(:content, content)
        |> Map.put(:reasoning, reasoning)
        |> Map.delete(:pending)
      else
        msg
      end
    end)
  end

  defp gen_id, do: System.unique_integer([:positive]) |> Integer.to_string()

  defp render_markdown(content) when is_binary(content) and content != "" do
    case MDEx.to_html(content) do
      {:ok, html} -> html
      {:error, _} -> content
    end
  end

  defp render_markdown(_), do: ""

  defp format_args(nil), do: ""

  defp format_args(args) when is_map(args) do
    args
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
    |> String.slice(0, 80)
  end

  defp format_args(args), do: inspect(args) |> String.slice(0, 80)

  defp format_result(nil), do: nil
  defp format_result({:ok, result}), do: inspect(result, limit: 5, printable_limit: 100)
  defp format_result({:error, reason}), do: "Error: #{inspect(reason)}"
  defp format_result(result), do: inspect(result, limit: 5, printable_limit: 100)

  defp truncate_id(nil), do: "—"

  defp truncate_id(id) when is_binary(id) do
    String.slice(id, 0, 8) <> "..."
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="space-y-6 max-w-7xl mx-auto">
        <.header>
          Folio - GTD Task Manager
          <:subtitle>Brain dump thoughts, process them into actions and projects</:subtitle>
        </.header>

        <%= if @error do %>
          <div class="alert alert-error">
            <span>{@error}</span>
            <button phx-click="restart_agent" class="btn btn-sm">Restart Agent</button>
          </div>
        <% end %>

        <div class="space-y-6">
          <div class="card bg-base-200 shadow-lg">
            <div class="card-body">
              <h3 class="font-semibold mb-3">Brain Dump</h3>

              <div
                id="folio-messages"
                class="h-[300px] overflow-y-auto space-y-3 mb-4"
                phx-hook="ScrollBottom"
              >
                <%= if @messages == [] do %>
                  <div class="text-center text-base-content/50 py-8">
                    <p class="text-sm">
                      Try: "I need to call mom about the birthday party and also pick up groceries"
                    </p>
                    <p class="text-xs mt-1 opacity-70">
                      or "Show me my inbox" or "What are my next actions?"
                    </p>
                  </div>
                <% else %>
                  <%= for msg <- @messages do %>
                    <%= if msg.role == :tool_call do %>
                      <div class="flex items-center gap-2 px-3 py-2 bg-base-300 rounded-lg text-xs">
                        <span class={[
                          "badge badge-xs",
                          msg.status == :running && "badge-warning",
                          msg.status == :completed && "badge-success",
                          msg.status == :failed && "badge-error"
                        ]}>
                          <%= case msg.status do %>
                            <% :running -> %>
                              <span class="loading loading-spinner loading-xs"></span>
                            <% :completed -> %>
                              ✓
                            <% _ -> %>
                              ✗
                          <% end %>
                        </span>
                        <span class="font-mono font-semibold text-primary">{msg.tool_name}</span>
                        <span class="opacity-60 truncate max-w-32">
                          ({format_args(msg.arguments)})
                        </span>
                        <%= if msg.result do %>
                          <span class="opacity-70 truncate max-w-24">
                            → {format_result(msg.result)}
                          </span>
                        <% end %>
                      </div>
                    <% end %>

                    <%= if msg.role in [:user, :assistant] do %>
                      <div class={["chat", (msg.role == :user && "chat-end") || "chat-start"]}>
                        <div class="chat-header text-xs opacity-70 mb-1">
                          {if msg.role == :user, do: "You", else: "Folio"}
                        </div>
                        <div class={[
                          "chat-bubble text-sm",
                          (msg.role == :user && "chat-bubble-primary") || "chat-bubble-neutral"
                        ]}>
                          <%= if msg[:pending] == true and msg.content == "" do %>
                            <span class="loading loading-dots loading-sm"></span>
                          <% else %>
                            <div class="prose prose-sm max-w-none">
                              {raw(render_markdown(msg.content))}
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                <% end %>
              </div>

              <form phx-submit="send" class="flex gap-2">
                <input
                  type="text"
                  name="input"
                  value={@input}
                  phx-change="update_input"
                  placeholder="Dump your thoughts here..."
                  class="input input-bordered input-sm flex-1"
                  disabled={@running? or is_nil(@agent_pid)}
                  autocomplete="off"
                  id="folio-chat-input"
                />
                <button
                  type="submit"
                  class="btn btn-primary btn-sm"
                  disabled={@running? or is_nil(@agent_pid) or String.trim(@input) == ""}
                >
                  <%= if @running? do %>
                    <span class="loading loading-spinner loading-xs"></span>
                  <% else %>
                    Capture
                  <% end %>
                </button>
              </form>
            </div>
          </div>

          <div class="card bg-base-200 shadow-lg">
            <div class="card-body p-4">
              <div role="tablist" class="tabs tabs-bordered mb-4">
                <button
                  role="tab"
                  class={["tab", @active_tab == :inbox && "tab-active"]}
                  phx-click="switch_tab"
                  phx-value-tab="inbox"
                >
                  Inbox ({length(@inbox_items)})
                </button>
                <button
                  role="tab"
                  class={["tab", @active_tab == :next_actions && "tab-active"]}
                  phx-click="switch_tab"
                  phx-value-tab="next_actions"
                >
                  Next Actions ({length(@next_actions)})
                </button>
                <button
                  role="tab"
                  class={["tab", @active_tab == :projects && "tab-active"]}
                  phx-click="switch_tab"
                  phx-value-tab="projects"
                >
                  Projects ({length(@projects)})
                </button>
              </div>

              <div class="overflow-x-auto max-h-[400px] overflow-y-auto">
                <%= case @active_tab do %>
                  <% :inbox -> %>
                    <table class="table table-xs table-zebra">
                      <thead class="sticky top-0 bg-base-200">
                        <tr>
                          <th>ID</th>
                          <th>Content</th>
                          <th>Source</th>
                          <th>Captured</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= if @inbox_items == [] do %>
                          <tr>
                            <td colspan="4" class="text-center opacity-50 py-8">
                              Inbox zero! Brain dump something to get started.
                            </td>
                          </tr>
                        <% else %>
                          <%= for item <- @inbox_items do %>
                            <tr>
                              <td class="font-mono text-xs">{truncate_id(item.id)}</td>
                              <td class="max-w-md truncate">{item.content}</td>
                              <td>{item.source || "—"}</td>
                              <td class="text-xs opacity-70">
                                {if item.captured_at,
                                  do: Calendar.strftime(item.captured_at, "%m/%d %H:%M"),
                                  else: "—"}
                              </td>
                            </tr>
                          <% end %>
                        <% end %>
                      </tbody>
                    </table>
                  <% :next_actions -> %>
                    <table class="table table-xs table-zebra">
                      <thead class="sticky top-0 bg-base-200">
                        <tr>
                          <th>ID</th>
                          <th>Title</th>
                          <th>Due</th>
                          <th>Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= if @next_actions == [] do %>
                          <tr>
                            <td colspan="4" class="text-center opacity-50 py-8">
                              No next actions. Process your inbox or create actions directly.
                            </td>
                          </tr>
                        <% else %>
                          <%= for action <- @next_actions do %>
                            <tr>
                              <td class="font-mono text-xs">{truncate_id(action.id)}</td>
                              <td class="max-w-md truncate">{action.title}</td>
                              <td class="text-xs">
                                {if action.due_on,
                                  do: Calendar.strftime(action.due_on, "%m/%d"),
                                  else: "—"}
                              </td>
                              <td>
                                <span class={[
                                  "badge badge-xs",
                                  action.status == :next && "badge-success",
                                  action.status == :waiting && "badge-warning",
                                  action.status == :someday && "badge-ghost"
                                ]}>
                                  {action.status}
                                </span>
                              </td>
                            </tr>
                          <% end %>
                        <% end %>
                      </tbody>
                    </table>
                  <% :projects -> %>
                    <table class="table table-xs table-zebra">
                      <thead class="sticky top-0 bg-base-200">
                        <tr>
                          <th>ID</th>
                          <th>Title</th>
                          <th>Outcome</th>
                          <th>Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= if @projects == [] do %>
                          <tr>
                            <td colspan="4" class="text-center opacity-50 py-8">
                              No active projects. Multi-step outcomes will appear here.
                            </td>
                          </tr>
                        <% else %>
                          <%= for project <- @projects do %>
                            <tr>
                              <td class="font-mono text-xs">{truncate_id(project.id)}</td>
                              <td class="max-w-md truncate">{project.title}</td>
                              <td class="max-w-sm truncate text-xs opacity-70">
                                {project.outcome || "—"}
                              </td>
                              <td>
                                <span class={[
                                  "badge badge-xs",
                                  project.status == :active && "badge-success",
                                  project.status == :someday && "badge-ghost",
                                  project.status == :done && "badge-info"
                                ]}>
                                  {project.status}
                                </span>
                              </td>
                            </tr>
                          <% end %>
                        <% end %>
                      </tbody>
                    </table>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
