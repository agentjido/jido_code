defmodule AgentJidoWeb.Demos.ChatLive do
  @moduledoc """
  Demo: AI Chat Agent with ReAct Loop

  Demonstrates Jido.AI ReActAgent with full observability:
  - Streaming text display with iteration tracking
  - Tool call lifecycle (planned → executing → completed)
  - Thinking/reasoning visibility
  - Conversation history and usage metrics
  - Toggleable panels for verbose debugging

  Uses polling of strategy_snapshot for real-time updates.
  """
  use AgentJidoWeb, :live_view

  alias AgentJido.Demos.ChatAgent

  @poll_interval 80

  defmodule Trace do
    @moduledoc "Pure state for tracking snapshot deltas between polls"
    defstruct last_iteration: 0,
              text: "",
              thinking: "",
              seen_tool_ids: MapSet.new(),
              completed_tool_ids: MapSet.new(),
              awaiting_start?: true
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:agent_pid, nil)
      |> assign(:running?, false)
      |> assign(:input, "")
      |> assign(:error, nil)
      |> assign(:trace, %Trace{})
      |> assign(:messages, [])
      |> assign(:panels, %{thinking: "", usage: %{}, conversation: [], config: %{}})
      |> assign(:conversation_history, [])
      |> assign(:poll_ref, nil)

    socket =
      if connected?(socket) do
        case start_agent() do
          {:ok, pid} ->
            Process.monitor(pid)
            assign(socket, :agent_pid, pid)

          {:error, reason} ->
            assign(socket, :error, "Failed to start agent: #{inspect(reason)}")
        end
      else
        socket
      end

    {:ok, socket}
  end

  defp start_agent do
    Jido.AgentServer.start_link(
      agent: ChatAgent,
      id: "chat-#{System.unique_integer([:positive])}",
      jido: AgentJido.Jido
    )
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

  def handle_event("send", _params, socket) do
    input = String.trim(socket.assigns.input)

    if input == "" or socket.assigns.running? or is_nil(socket.assigns.agent_pid) do
      {:noreply, socket}
    else
      :ok = ChatAgent.ask(socket.assigns.agent_pid, input)

      user_msg = %{id: gen_id(), role: :user, content: input}
      pending_msg = %{id: gen_id(), role: :assistant, content: "", pending: true}

      {:noreply,
       socket
       |> assign(:input, "")
       |> assign(:running?, true)
       |> assign(:trace, %Trace{})
       |> assign(:messages, socket.assigns.messages ++ [user_msg, pending_msg])
       |> assign(:panels, %{thinking: "", usage: %{}, conversation: [], config: %{}})
       |> schedule_poll()}
    end
  end

  def handle_event("restart_agent", _params, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    case start_agent() do
      {:ok, pid} ->
        Process.monitor(pid)

        {:noreply,
         socket
         |> assign(:agent_pid, pid)
         |> assign(:error, nil)
         |> assign(:running?, false)
         |> assign(:messages, [])
         |> assign(:conversation_history, [])
         |> assign(:trace, %Trace{})}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to restart: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:poll, ref}, %{assigns: %{poll_ref: ref}} = socket) do
    socket = assign(socket, :poll_ref, nil)

    if socket.assigns.running? and socket.assigns.agent_pid do
      handle_poll_snapshot(socket)
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

  defp handle_poll_snapshot(socket) do
    case get_snapshot(socket.assigns.agent_pid) do
      {:ok, snap} -> apply_snapshot(socket, snap)
      {:error, reason} -> handle_snapshot_error(socket, reason)
    end
  end

  defp apply_snapshot(socket, snap) do
    {trace, messages, panels} = process_snapshot(socket.assigns.trace, socket.assigns.messages, snap)
    conversation = (snap.details || %{})[:conversation] || []

    socket =
      socket
      |> assign(:trace, trace)
      |> assign(:messages, messages)
      |> assign(:panels, panels)
      |> assign(:conversation_history, conversation)

    if snap.done? and not trace.awaiting_start? do
      {:noreply, assign(socket, :running?, false)}
    else
      {:noreply, schedule_poll(socket)}
    end
  end

  defp handle_snapshot_error(socket, reason) do
    {:noreply,
     socket
     |> assign(:running?, false)
     |> assign(:error, "Snapshot error: #{inspect(reason)}")}
  end

  defp schedule_poll(socket) do
    ref = make_ref()
    Process.send_after(self(), {:poll, ref}, @poll_interval)
    assign(socket, :poll_ref, ref)
  end

  defp get_snapshot(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, server_state} ->
        {:ok, ChatAgent.strategy_snapshot(server_state.agent)}

      error ->
        error
    end
  end

  defp process_snapshot(trace, messages, snap) do
    details = snap.details || %{}
    trace = maybe_clear_awaiting_start(trace, snap.status)

    if trace.awaiting_start? do
      {trace, messages, idle_panels()}
    else
      process_active_snapshot(trace, messages, snap, details)
    end
  end

  defp maybe_clear_awaiting_start(trace, :running) when trace.awaiting_start?, do: %{trace | awaiting_start?: false}
  defp maybe_clear_awaiting_start(trace, _status), do: trace

  defp idle_panels do
    %{thinking: "", usage: %{}, conversation: [], config: %{status: :idle, iteration: 0}}
  end

  defp process_active_snapshot(trace, messages, snap, details) do
    current_iteration = details[:iteration] || 0
    streaming_text = details[:streaming_text] || ""
    streaming_thinking = details[:streaming_thinking] || ""
    tool_calls = details[:tool_calls] || []

    trace = update_trace_iteration(trace, current_iteration)
    {messages, trace} = sync_tool_calls(messages, tool_calls, trace)
    messages = update_pending_content(messages, streaming_text)
    {messages, trace} = finalize_if_done(messages, trace, snap, streaming_text, streaming_thinking)
    panels = build_panels(details, streaming_thinking, current_iteration, snap.status)

    {trace, messages, panels}
  end

  defp update_trace_iteration(trace, current_iteration) do
    if current_iteration > trace.last_iteration and trace.last_iteration > 0 do
      %{trace | last_iteration: current_iteration, text: "", thinking: ""}
    else
      %{trace | last_iteration: max(current_iteration, trace.last_iteration)}
    end
  end

  defp finalize_if_done(messages, trace, snap, streaming_text, streaming_thinking) do
    if snap.done? do
      final_content = snap.result || streaming_text
      {finalize_pending(messages, final_content, trace.thinking), trace}
    else
      {messages, %{trace | text: streaming_text, thinking: streaming_thinking}}
    end
  end

  defp build_panels(details, streaming_thinking, current_iteration, status) do
    %{
      thinking: streaming_thinking,
      usage: details[:usage] || %{},
      conversation: details[:conversation] || [],
      config: %{
        model: details[:model],
        max_iterations: details[:max_iterations],
        available_tools: details[:available_tools] || [],
        current_llm_call_id: details[:current_llm_call_id],
        iteration: current_iteration,
        duration_ms: details[:duration_ms],
        termination_reason: details[:termination_reason],
        status: status
      }
    }
  end

  defp sync_tool_calls(messages, [], trace), do: {messages, trace}

  defp sync_tool_calls(messages, tool_calls, trace) do
    {messages, seen, completed} =
      Enum.reduce(tool_calls, {messages, trace.seen_tool_ids, trace.completed_tool_ids}, &process_tool_call/2)

    trace = %{trace | seen_tool_ids: seen, completed_tool_ids: completed}
    {messages, trace}
  end

  defp process_tool_call(tc, {msgs, seen, completed}) do
    if MapSet.member?(seen, tc.id) do
      update_existing_tool_call(tc, msgs, seen, completed)
    else
      add_new_tool_call(tc, msgs, seen, completed)
    end
  end

  defp update_existing_tool_call(tc, msgs, seen, completed) do
    msgs = update_tool_call(msgs, tc)
    completed = maybe_mark_completed(completed, tc)
    {msgs, seen, completed}
  end

  defp add_new_tool_call(tc, msgs, seen, completed) do
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
    completed = maybe_mark_completed(completed, tc)
    {msgs, seen, completed}
  end

  defp maybe_mark_completed(completed, tc) do
    if tc.status == :completed, do: MapSet.put(completed, tc.id), else: completed
  end

  defp update_tool_call(messages, tc) do
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
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> String.slice(0, 80)
  end

  defp format_args(args), do: inspect(args) |> String.slice(0, 80)

  defp format_result(nil), do: nil
  defp format_result({:ok, result}), do: inspect(result, limit: 5, printable_limit: 100)
  defp format_result({:error, reason}), do: "Error: #{inspect(reason)}"
  defp format_result(result), do: inspect(result, limit: 5, printable_limit: 100)

  defp format_conversation_content(msg) do
    content = msg[:content] || ""

    cond do
      msg[:tool_calls] ->
        tool_names = Enum.map_join(msg[:tool_calls], ", ", & &1[:name])
        "Calling: #{tool_names}"

      msg[:role] == :tool ->
        name = msg[:name] || "unknown"
        "[#{name}] #{String.slice(to_string(content), 0, 200)}"

      msg[:role] == :system ->
        String.slice(to_string(content), 0, 150) <> "..."

      true ->
        to_string(content)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6 max-w-7xl mx-auto">
        <.header>
          AI Chat Agent Demo
          <:subtitle>ReActAgent with streaming, tool calls, and full observability</:subtitle>
        </.header>

        <%!-- Error Display --%>
        <%= if @error do %>
          <div class="rounded-lg bg-red-50 p-4 border border-red-200">
            <div class="flex items-center justify-between">
              <span class="text-red-800">{@error}</span>
              <button
                phx-click="restart_agent"
                class="rounded-md bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 transition-colors"
              >
                Restart Agent
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Full Width Chat Section --%>
        <div class="rounded-xl bg-zinc-50 dark:bg-zinc-900 shadow-lg border border-zinc-200 dark:border-zinc-800">
          <div class="p-6">
            <%!-- Messages --%>
            <div
              id="chat-messages"
              class="h-[400px] overflow-y-auto space-y-3 mb-4"
              phx-hook=".ScrollBottom"
            >
              <%= if @messages == [] do %>
                <div class="text-center text-zinc-500 py-8">
                  <p class="text-lg font-medium">Start a conversation</p>
                  <p class="text-sm mt-2">
                    Try: "What is 15 * 23?" or "What's the weather in Chicago?"
                  </p>
                </div>
              <% else %>
                <%= for msg <- @messages do %>
                  <%= if msg.role == :tool_call do %>
                    <div class="flex items-center gap-2 px-4 py-2 bg-zinc-200 dark:bg-zinc-800 rounded-lg text-sm max-w-2xl mx-auto">
                      <span class={[
                        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                        msg.status == :running && "bg-amber-100 text-amber-800",
                        msg.status == :completed && "bg-green-100 text-green-800",
                        msg.status == :failed && "bg-red-100 text-red-800"
                      ]}>
                        <%= case msg.status do %>
                          <% :running -> %>
                            <span class="mr-1 inline-block h-2 w-2 animate-pulse rounded-full bg-amber-500"></span>
                          <% :completed -> %>
                            ✓
                          <% _ -> %>
                            ✗
                        <% end %>
                      </span>
                      <span class="font-mono font-semibold text-indigo-600 dark:text-indigo-400">{msg.tool_name}</span>
                      <span class="opacity-60">({format_args(msg.arguments)})</span>
                      <%= if msg.result do %>
                        <span class="opacity-70">→ {format_result(msg.result)}</span>
                      <% end %>
                    </div>
                  <% end %>

                  <%= if msg.role in [:user, :assistant] do %>
                    <div class={[
                      "flex",
                      if(msg.role == :user, do: "justify-end", else: "justify-start")
                    ]}>
                      <div class="max-w-2xl">
                        <div class="text-xs text-zinc-500 mb-1">
                          {if msg.role == :user, do: "You", else: "Assistant"}
                        </div>
                        <div class={[
                          "rounded-2xl px-4 py-3",
                          if(msg.role == :user,
                            do: "bg-indigo-600 text-white",
                            else: "bg-white dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700"
                          )
                        ]}>
                          <%= if msg[:pending] == true and msg.content == "" do %>
                            <span class="inline-flex gap-1">
                              <span class="h-2 w-2 rounded-full bg-zinc-400 animate-bounce"></span>
                              <span class="h-2 w-2 rounded-full bg-zinc-400 animate-bounce delay-100"></span>
                              <span class="h-2 w-2 rounded-full bg-zinc-400 animate-bounce delay-200"></span>
                            </span>
                          <% else %>
                            <%= if msg[:reasoning] && msg.reasoning != "" do %>
                              <details class="mb-2 rounded bg-zinc-100 dark:bg-zinc-700/50">
                                <summary class="cursor-pointer text-xs font-medium px-2 py-1">
                                  💭 Reasoning
                                </summary>
                                <pre class="text-xs whitespace-pre-wrap opacity-70 px-2 pb-2">{msg.reasoning}</pre>
                              </details>
                            <% end %>
                            <div class="prose prose-sm max-w-none dark:prose-invert">
                              {raw(render_markdown(msg.content))}
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              <% end %>
            </div>

            <%!-- Input Form --%>
            <form phx-submit="send" class="flex gap-2" id="chat-form">
              <input
                type="text"
                name="input"
                value={@input}
                phx-change="update_input"
                placeholder="Type a message..."
                class="flex-1 rounded-lg border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 px-4 py-2 text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                disabled={@running? or is_nil(@agent_pid)}
                autocomplete="off"
                id="chat-input"
              />
              <button
                type="submit"
                class={[
                  "rounded-lg px-6 py-2 font-medium text-white transition-colors",
                  if(@running? or is_nil(@agent_pid) or String.trim(@input) == "",
                    do: "bg-zinc-400 cursor-not-allowed",
                    else: "bg-indigo-600 hover:bg-indigo-700"
                  )
                ]}
                disabled={@running? or is_nil(@agent_pid) or String.trim(@input) == ""}
              >
                <%= if @running? do %>
                  <span class="inline-block h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent">
                  </span>
                <% else %>
                  Send
                <% end %>
              </button>
            </form>
          </div>
        </div>

        <%!-- Debug Panels Grid --%>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <%!-- Agent Status Panel --%>
          <div class="rounded-lg bg-white dark:bg-zinc-800 shadow border border-zinc-200 dark:border-zinc-700 p-4">
            <h3 class="font-semibold text-sm mb-2">Agent Status</h3>
            <dl class="text-xs space-y-1">
              <div class="flex justify-between">
                <dt class="text-zinc-500">Status</dt>
                <dd class={[
                  "font-medium",
                  @panels.config[:status] == :success && "text-green-600",
                  @panels.config[:status] == :failure && "text-red-600",
                  @panels.config[:status] == :running && "text-amber-600"
                ]}>
                  {@panels.config[:status] || "idle"}
                </dd>
              </div>
              <%= if @panels.config[:iteration] do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Iteration</dt>
                  <dd>{@panels.config[:iteration]} / {@panels.config[:max_iterations] || "?"}</dd>
                </div>
              <% end %>
              <%= if @panels.config[:model] do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Model</dt>
                  <dd class="font-mono text-xs truncate max-w-32">{@panels.config[:model]}</dd>
                </div>
              <% end %>
              <%= if @panels.config[:duration_ms] do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Duration</dt>
                  <dd>{@panels.config[:duration_ms]}ms</dd>
                </div>
              <% end %>
              <%= if @panels.config[:termination_reason] do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Termination</dt>
                  <dd>{@panels.config[:termination_reason]}</dd>
                </div>
              <% end %>
            </dl>
          </div>

          <%!-- Token Usage Panel --%>
          <div class="rounded-lg bg-white dark:bg-zinc-800 shadow border border-zinc-200 dark:border-zinc-700 p-4">
            <h3 class="font-semibold text-sm mb-2">Token Usage</h3>
            <dl class="text-xs space-y-1">
              <div class="flex justify-between">
                <dt class="text-zinc-500">Input</dt>
                <dd>{@panels.usage[:input_tokens] || 0}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-500">Output</dt>
                <dd>{@panels.usage[:output_tokens] || 0}</dd>
              </div>
              <%= if @panels.usage[:cache_read_input_tokens] do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Cache Read</dt>
                  <dd>{@panels.usage[:cache_read_input_tokens]}</dd>
                </div>
              <% end %>
            </dl>
          </div>

          <%!-- Available Tools Panel --%>
          <div class="rounded-lg bg-white dark:bg-zinc-800 shadow border border-zinc-200 dark:border-zinc-700 p-4">
            <h3 class="font-semibold text-sm mb-2">Available Tools</h3>
            <div class="flex flex-wrap gap-1">
              <%= for tool <- @panels.config[:available_tools] || [] do %>
                <span class="inline-flex items-center rounded-full border border-zinc-300 dark:border-zinc-600 px-2 py-0.5 text-xs font-mono">
                  {tool}
                </span>
              <% end %>
              <%= if (@panels.config[:available_tools] || []) == [] do %>
                <span class="text-xs text-zinc-400">No tools loaded</span>
              <% end %>
            </div>
          </div>

          <%!-- Thinking Panel --%>
          <div class="rounded-lg bg-white dark:bg-zinc-800 shadow border border-zinc-200 dark:border-zinc-700 p-4">
            <h3 class="font-semibold text-sm mb-2 flex items-center gap-2">
              Thinking
              <%= if @panels.thinking != "" do %>
                <span class="inline-flex gap-0.5">
                  <span class="h-1.5 w-1.5 rounded-full bg-zinc-400 animate-pulse"></span>
                  <span class="h-1.5 w-1.5 rounded-full bg-zinc-400 animate-pulse delay-75"></span>
                  <span class="h-1.5 w-1.5 rounded-full bg-zinc-400 animate-pulse delay-150"></span>
                </span>
              <% end %>
            </h3>
            <%= if @panels.thinking != "" do %>
              <pre class="text-xs whitespace-pre-wrap text-zinc-600 dark:text-zinc-400 max-h-32 overflow-y-auto">{@panels.thinking}</pre>
            <% else %>
              <span class="text-xs text-zinc-400">No active thinking</span>
            <% end %>
          </div>
        </div>

        <%!-- Full Width Conversation History --%>
        <div class="rounded-lg bg-white dark:bg-zinc-800 shadow border border-zinc-200 dark:border-zinc-700 p-4">
          <h3 class="font-semibold text-sm mb-2">
            Full Conversation History ({length(@conversation_history)} messages)
          </h3>
          <div class="text-xs space-y-2 max-h-64 overflow-y-auto">
            <%= if @conversation_history == [] do %>
              <span class="text-zinc-400">No conversation yet</span>
            <% else %>
              <%= for msg <- @conversation_history do %>
                <div class={[
                  "p-2 rounded",
                  msg[:role] == :system && "bg-zinc-100 dark:bg-zinc-700",
                  msg[:role] == :user && "bg-indigo-50 dark:bg-indigo-900/20",
                  msg[:role] == :assistant && "bg-zinc-50 dark:bg-zinc-800",
                  msg[:role] == :tool && "bg-cyan-50 dark:bg-cyan-900/20"
                ]}>
                  <div class="font-semibold text-zinc-600 dark:text-zinc-400 flex justify-between">
                    <span>{msg[:role]}</span>
                    <%= if msg[:tool_calls] do %>
                      <span class="inline-flex items-center rounded-full bg-zinc-200 dark:bg-zinc-600 px-2 py-0.5 text-xs">
                        tool_calls
                      </span>
                    <% end %>
                  </div>
                  <pre class="whitespace-pre-wrap text-xs mt-1 text-zinc-700 dark:text-zinc-300">{format_conversation_content(msg)}</pre>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Colocated JS Hook for auto-scroll --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollBottom">
        export default {
          mounted() {
            this.scrollToBottom()
            this.observer = new MutationObserver(() => this.scrollToBottom())
            this.observer.observe(this.el, { childList: true, subtree: true })
          },
          updated() {
            this.scrollToBottom()
          },
          destroyed() {
            if (this.observer) this.observer.disconnect()
          },
          scrollToBottom() {
            this.el.scrollTop = this.el.scrollHeight
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
