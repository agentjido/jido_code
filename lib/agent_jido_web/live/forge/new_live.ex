defmodule AgentJidoWeb.Forge.NewLive do
  use AgentJidoWeb, :live_view

  alias AgentJido.Forge

  @runners [
    {"Shell", "shell"},
    {"Claude Code", "claude_code"},
    {"Workflow", "workflow"},
    {"Custom", "custom"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    form =
      to_form(%{
        "session_id" => generate_session_id(),
        "runner" => "shell",
        "runner_config" => "{}",
        "env" => "{}",
        "bootstrap" => "[]"
      })

    {:ok,
     socket
     |> assign(:page_title, "New Forge Session")
     |> assign(:runners, @runners)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"session_id" => _} = params, socket) do
    form = to_form(params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", params, socket) do
    session_id = params["session_id"]
    runner = params["runner"]

    with {:ok, runner_config} <- Jason.decode(params["runner_config"] || "{}"),
         {:ok, env} <- Jason.decode(params["env"] || "{}"),
         {:ok, bootstrap} <- Jason.decode(params["bootstrap"] || "[]") do
      spec = %{
        runner: String.to_existing_atom(runner),
        runner_config: runner_config,
        env: env,
        bootstrap: bootstrap
      }

      case Forge.start_session(session_id, spec) do
        {:ok, _pid} ->
          {:noreply,
           socket
           |> put_flash(:info, "Session started")
           |> push_navigate(to: ~p"/forge/#{session_id}")}

        {:error, {:already_started, _}} ->
          {:noreply, put_flash(socket, :error, "Session ID already exists")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    else
      {:error, %Jason.DecodeError{}} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON in config fields")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-2xl mx-auto py-8 px-4">
        <div class="mb-6">
          <.link navigate={~p"/forge"} class="text-sm opacity-60 hover:opacity-100">
            ← Back to Sessions
          </.link>
          <h1 class="text-2xl font-bold mt-2">New Forge Session</h1>
        </div>

        <.form for={@form} id="new-session-form" phx-change="validate" phx-submit="submit" class="space-y-6">
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Session ID</span>
            </label>
            <input
              type="text"
              name="session_id"
              value={@form[:session_id].value}
              class="input input-bordered w-full font-mono"
              required
            />
            <label class="label">
              <span class="label-text-alt opacity-60">Unique identifier for this session</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Runner</span>
            </label>
            <select name="runner" class="select select-bordered w-full">
              <option :for={{label, value} <- @runners} value={value} selected={@form[:runner].value == value}>
                {label}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Runner Config (JSON)</span>
            </label>
            <textarea
              name="runner_config"
              class="textarea textarea-bordered w-full font-mono h-24"
              placeholder="{}"
            >{@form[:runner_config].value}</textarea>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Environment Variables (JSON)</span>
            </label>
            <textarea
              name="env"
              class="textarea textarea-bordered w-full font-mono h-24"
              placeholder="{}"
            >{@form[:env].value}</textarea>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Bootstrap Steps (JSON Array)</span>
            </label>
            <textarea
              name="bootstrap"
              class="textarea textarea-bordered w-full font-mono h-24"
              placeholder="[]"
            >{@form[:bootstrap].value}</textarea>
            <label class="label">
              <span class="label-text-alt opacity-60" phx-no-curly-interpolation>
                Example: [{"type": "exec", "command": "mkdir -p /app"}]
              </span>
            </label>
          </div>

          <div class="flex gap-4">
            <button type="submit" class="btn btn-primary">
              Create Session
            </button>
            <.link navigate={~p"/forge"} class="btn btn-ghost">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp generate_session_id do
    "forge-#{:erlang.unique_integer([:positive])}"
  end
end
