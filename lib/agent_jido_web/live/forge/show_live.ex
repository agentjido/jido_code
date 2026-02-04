defmodule AgentJidoWeb.Forge.ShowLive do
  use AgentJidoWeb, :live_view

  alias AgentJido.Forge
  alias AgentJido.Forge.PubSub, as: ForgePubSub

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    result =
      try do
        Forge.status(session_id)
      catch
        :exit, _ -> {:error, :not_found}
        _, _ -> {:error, :not_found}
      end

    case result do
      {:ok, status} ->
        if connected?(socket) do
          ForgePubSub.subscribe_session(session_id)
          schedule_refresh()
        end

        {:ok,
         socket
         |> assign(:page_title, "Session: #{session_id}")
         |> assign(:session_id, session_id)
         |> assign(:status, status)
         |> assign(:input, "")
         |> assign(:input_prompt, nil)
         |> assign(:not_found, false)
         |> stream(:output, [])}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:page_title, "Session Not Found")
         |> assign(:session_id, session_id)
         |> assign(:not_found, true)}
    end
  end

  @impl true
  def handle_info({:status, status}, socket) do
    {:noreply, assign(socket, :status, status)}
  end

  def handle_info({:output, %{chunk: chunk, seq: seq}}, socket) do
    lines = String.split(chunk, "\n", trim: true)

    socket =
      Enum.with_index(lines)
      |> Enum.reduce(socket, fn {line, idx}, acc ->
        stream_insert(acc, :output, %{
          id: "line-#{seq}-#{idx}-#{System.unique_integer()}",
          kind: :out,
          text: line
        })
      end)

    {:noreply, socket}
  end

  def handle_info({:needs_input, %{prompt: prompt}}, socket) do
    {:noreply,
     socket
     |> assign(:status, Map.put(socket.assigns.status, :state, :needs_input))
     |> assign(:input_prompt, prompt)}
  end

  def handle_info({:stopped, reason}, socket) do
    {:noreply,
     socket
     |> assign(:status, Map.put(socket.assigns.status, :state, :stopped))
     |> put_flash(:info, "Session stopped: #{inspect(reason)}")}
  end

  def handle_info(:refresh, socket) do
    if socket.assigns[:not_found] do
      {:noreply, socket}
    else
      result =
        try do
          Forge.status(socket.assigns.session_id)
        catch
          :exit, _ -> {:error, :not_found}
          _, _ -> {:error, :not_found}
        end

      case result do
        {:ok, status} ->
          schedule_refresh()
          {:noreply, assign(socket, :status, status)}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> assign(:not_found, true)
           |> put_flash(:error, "Session no longer exists")}
      end
    end
  end

  def handle_info({:terminal_exec_result, {output, exit_code}}, socket)
      when is_binary(output) and is_integer(exit_code) do
    socket =
      output
      |> String.split("\n", trim: true)
      |> Enum.reduce(socket, fn line, acc ->
        stream_insert(acc, :output, %{id: uniq_line_id(), kind: :out, text: line})
      end)

    socket =
      if exit_code != 0 do
        stream_insert(socket, :output, %{
          id: uniq_line_id(),
          kind: :err,
          text: "[exit #{exit_code}]"
        })
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:terminal_exec_result, {:applied, _command}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:terminal_exec_result, {:error, reason}}, socket) do
    {:noreply,
     stream_insert(socket, :output, %{
       id: uniq_line_id(),
       kind: :err,
       text: "[error] #{inspect(reason)}"
     })}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("run_iteration", _, socket) do
    session_id = socket.assigns.session_id

    Task.start(fn ->
      Forge.run_iteration(session_id)
    end)

    {:noreply, socket}
  end

  def handle_event("stop", _, socket) do
    Forge.stop_session(socket.assigns.session_id)

    {:noreply,
     socket
     |> put_flash(:info, "Session stopped")
     |> push_navigate(to: ~p"/forge")}
  end

  def handle_event("submit_input", %{"input" => input}, socket) do
    Forge.apply_input(socket.assigns.session_id, input)

    {:noreply,
     socket
     |> assign(:input, "")
     |> assign(:input_prompt, nil)}
  end

  def handle_event("update_input", %{"input" => input}, socket) do
    {:noreply, assign(socket, :input, input)}
  end

  def handle_event("terminal_run", %{"command" => command}, socket) do
    command = String.trim(command)

    if command == "" do
      {:noreply, socket}
    else
      do_terminal_run(socket, command)
    end
  end

  defp do_terminal_run(socket, command) do
    socket =
      stream_insert(socket, :output, %{
        id: uniq_line_id(),
        kind: :cmd,
        text: "$ " <> command
      })

    session_id = socket.assigns.session_id
    is_needs_input = socket.assigns.status.state == :needs_input

    start_exec_task(session_id, command, is_needs_input)

    socket = if is_needs_input, do: assign(socket, :input_prompt, nil), else: socket
    {:noreply, socket}
  end

  defp start_exec_task(session_id, command, is_needs_input) do
    lv_pid = self()

    Task.start(fn ->
      result = execute_command(session_id, command, is_needs_input)
      send(lv_pid, {:terminal_exec_result, result})
    end)
  end

  defp execute_command(session_id, command, true = _is_needs_input) do
    case Forge.apply_input(session_id, command) do
      :ok -> {:applied, command}
      error -> error
    end
  end

  defp execute_command(session_id, command, false = _is_needs_input) do
    Forge.exec(session_id, command)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-6xl mx-auto py-8 px-4">
        <%= if @not_found do %>
          <div class="text-center py-12">
            <h1 class="text-xl font-bold mb-4">Session Not Found</h1>
            <p class="mb-4 opacity-60">Session "{@session_id}" does not exist or has been stopped.</p>
            <.link navigate={~p"/forge"} class="btn btn-primary">Back to Dashboard</.link>
          </div>
        <% else %>
          <div class="flex justify-between items-center mb-6">
            <div>
              <.link navigate={~p"/forge"} class="text-sm opacity-60 hover:opacity-100">
                ← Back to Sessions
              </.link>
              <h1 class="text-2xl font-bold font-mono">{@session_id}</h1>
            </div>
            <div class="flex gap-2">
              <button
                phx-click="run_iteration"
                disabled={@status.state not in [:ready]}
                class={[
                  "btn btn-primary",
                  @status.state not in [:ready] && "btn-disabled opacity-50"
                ]}
              >
                Run Iteration
              </button>
              <button phx-click="stop" class="btn btn-error btn-outline">
                Stop
              </button>
            </div>
          </div>

          <div class="grid grid-cols-4 gap-4 mb-6">
            <div class="bg-base-200 rounded-lg p-4">
              <div class="text-sm opacity-60 mb-1">State</div>
              <div class="text-lg font-semibold"><.state_badge state={@status.state} /></div>
            </div>
            <div class="bg-base-200 rounded-lg p-4">
              <div class="text-sm opacity-60 mb-1">Iteration</div>
              <div class="text-lg font-semibold">{@status.iteration}</div>
            </div>
            <div class="bg-base-200 rounded-lg p-4">
              <div class="text-sm opacity-60 mb-1">Sprite ID</div>
              <div class="text-sm font-mono truncate">{@status.sprite_id || "—"}</div>
            </div>
            <div class="bg-base-200 rounded-lg p-4">
              <div class="text-sm opacity-60 mb-1">Last Activity</div>
              <div class="text-sm">{format_time(@status.last_activity)}</div>
            </div>
          </div>

          <%= if @status.state == :needs_input do %>
            <div class="mb-6 p-4 border border-warning rounded-lg bg-warning/10">
              <div class="font-bold mb-2">Input Required</div>
              <p :if={@input_prompt} class="mb-2 opacity-70">{@input_prompt}</p>
              <form phx-submit="submit_input" class="flex gap-2">
                <input
                  type="text"
                  name="input"
                  value={@input}
                  phx-change="update_input"
                  class="input input-bordered flex-1"
                  placeholder="Enter response..."
                  autofocus
                />
                <button type="submit" class="btn btn-primary">Submit</button>
              </form>
            </div>
          <% end %>

          <div class="bg-base-300 rounded-lg overflow-hidden">
            <div class="px-4 py-2 bg-base-200 border-b border-base-100 flex justify-between items-center">
              <span class="font-bold text-sm">Terminal</span>
              <span class="text-xs opacity-60">
                <%= if @status.state == :needs_input do %>
                  <span class="text-warning">awaiting input</span>
                <% else %>
                  ready
                <% end %>
              </span>
            </div>
            <div
              id="terminal"
              phx-update="stream"
              phx-hook=".ForgeTerminal"
              class="h-96 overflow-y-auto p-4 font-mono text-sm bg-neutral text-neutral-content"
            >
              <div
                :for={{id, line} <- @streams.output}
                id={id}
                class={[
                  "whitespace-pre-wrap",
                  line.kind == :cmd && "text-primary opacity-90",
                  line.kind == :err && "text-error"
                ]}
              >
                {line.text}
              </div>
            </div>
            <div class="border-t border-base-100 bg-neutral text-neutral-content px-4 py-2">
              <div class="flex items-center gap-2 font-mono text-sm">
                <span class="opacity-70">$</span>
                <input
                  id="terminal-input"
                  type="text"
                  disabled={@status.state in [:stopped, :stopping]}
                  phx-hook=".ForgeTerminalInput"
                  class="w-full bg-transparent outline-none text-neutral-content placeholder-neutral-content/50"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder={
                    if @status.state == :needs_input, do: @input_prompt || "enter response...", else: "type command..."
                  }
                />
              </div>
            </div>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".ForgeTerminal">
            export default {
              mounted() {
                this.scrollToBottom();
              },
              updated() {
                this.scrollToBottom();
              },
              scrollToBottom() {
                this.el.scrollTop = this.el.scrollHeight;
              }
            }
          </script>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".ForgeTerminalInput">
            export default {
              mounted() {
                this.history = []
                this.idx = -1

                this.el.addEventListener("keydown", (e) => {
                  if (e.key === "Enter") {
                    e.preventDefault()
                    const cmd = this.el.value
                    if (cmd.trim().length === 0) return

                    this.pushEvent("terminal_run", { command: cmd })
                    this.history.push(cmd)
                    this.idx = this.history.length
                    this.el.value = ""
                  }

                  if (e.key === "ArrowUp") {
                    if (this.history.length === 0) return
                    e.preventDefault()
                    this.idx = Math.max(0, this.idx - 1)
                    this.el.value = this.history[this.idx] || ""
                    queueMicrotask(() => this.el.setSelectionRange(this.el.value.length, this.el.value.length))
                  }

                  if (e.key === "ArrowDown") {
                    if (this.history.length === 0) return
                    e.preventDefault()
                    this.idx = Math.min(this.history.length, this.idx + 1)
                    this.el.value = this.history[this.idx] || ""
                    queueMicrotask(() => this.el.setSelectionRange(this.el.value.length, this.el.value.length))
                  }

                  if (e.key === "Escape") {
                    this.el.value = ""
                    this.idx = this.history.length
                  }
                })
              }
            }
          </script>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, 5_000)
  end

  defp uniq_line_id do
    "line-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "—"

  defp state_badge(assigns) do
    {bg, text} = state_colors(assigns.state)
    assigns = assign(assigns, bg: bg, text: text)

    ~H"""
    <span class={["badge", @bg, @text]}>
      {@state}
    </span>
    """
  end

  defp state_colors(:starting), do: {"bg-info/20", "text-info"}
  defp state_colors(:bootstrapping), do: {"bg-info/20", "text-info"}
  defp state_colors(:initializing), do: {"bg-info/20", "text-info"}
  defp state_colors(:ready), do: {"bg-success/20", "text-success"}
  defp state_colors(:running), do: {"bg-warning/20", "text-warning"}
  defp state_colors(:needs_input), do: {"bg-error/20", "text-error"}
  defp state_colors(:stopping), do: {"bg-base-300", "text-base-content/60"}
  defp state_colors(:stopped), do: {"bg-base-300", "text-base-content/60"}
  defp state_colors(_), do: {"bg-base-300", "text-base-content"}
end
