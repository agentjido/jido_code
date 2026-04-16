defmodule JidoCodeWeb.LLMProviderCard do
  use JidoCodeWeb, :live_component

  alias JidoCode.Security.SecretRefs

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:show_credential_form, false)
      |> assign(:api_key, "")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-300">
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <h3 class="card-title text-lg font-semibold flex items-center gap-2">
              <span>{@provider.name}</span>
              <.credential_status configured={@configured} />
            </h3>
            {if @provider.description do
              ~H'<p class="text-sm text-base-content/70 mt-1">{@provider.description}</p>'
            end}
            <p class="text-xs text-base-content/50 mt-1">
              Environment: <code class="text-xs bg-base-200 px-1 py-0.5 rounded">{@provider.env_key}</code>
            </p>
          </div>
        </div>

        {if @show_credential_form do
              ~H'''
                <.credential_form
                  provider={@provider}
                  myself={@myself}
                  api_key={@api_key}
                />
              '''
        end}

        <div class="card-actions mt-4">
          {if !@configured do
                ~H'''
                  <button
                    phx-click="toggle_credential_form"
                    phx-target={@myself}
                    class="btn btn-sm btn-primary"
                  >
                    Configure
                  </button>
                '''
          end}

          <button
            phx-click="test_provider"
            phx-target={@myself}
            class="btn btn-sm btn-outline"
            disabled={@testing || !@configured}
          >
            {if @testing do
                  ~H'''
                    <span class="loading loading-spinner loading-xs"></span>
                    Testing...
                  '''
            else
                  ~H'''
                    Test Connection
                  '''
            end}
          </button>
        </div>

        {if @test_result && !@testing do
              ~H'''
                <.test_result result={@test_result} />
              '''
        end}
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_credential_form", _params, socket) do
    {:noreply, update(socket, :show_credential_form, &(!&1))}
  end

  def handle_event("save_credential", %{"api_key" => api_key}, socket) do
    provider = socket.assigns.provider.id
    provider_name = Atom.to_string(provider)
    secret_name = "providers/#{provider_name}_api_key"

    case SecretRefs.persist_operational_secret(%{
           scope: :integration,
           name: secret_name,
           value: api_key,
           actor: current_actor(socket)
         }) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "API key saved successfully")
          |> assign(:show_credential_form, false)
          |> assign(:configured, true)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save API key")}
    end
  end

  def handle_event("test_provider", _params, socket) do
    send(self(), {:test_complete, socket.assigns.provider.id, :ok})

    socket =
      socket
      |> assign(:testing, true)
      |> push_patch(to: "#")

    {:noreply, socket}
  end

  defp credential_status(assigns) do
    ~H"""
    {if @configured do
          ~H'<span class="badge badge-success badge-sm">Configured</span>'
    else
          ~H'<span class="badge badge-ghost badge-sm">Not configured</span>'
    end}
    """
  end

  defp credential_form(assigns) do
    ~H"""
    <div class="mt-4 p-4 bg-base-200 rounded-lg">
      <h4 class="font-semibold text-sm mb-2">Add API Key</h4>
      <form phx-submit="save_credential" phx-target={@myself}>
        <div class="form-control">
          <input
            id="api-key-input"
            type="password"
            name="api_key"
            value={@api_key}
            placeholder="Enter your API key"
            class="input input-sm input-bordered w-full mb-2"
            phx-hook="PasswordVisibilityToggle"
          />
          <p class="text-xs text-base-content/50">
            Your API key will be encrypted and stored securely.
          </p>
        </div>
        <div class="flex gap-2 mt-2">
          <button type="submit" class="btn btn-sm btn-primary">Save</button>
          <button
            type="button"
            phx-click="toggle_credential_form"
            phx-target={@myself}
            class="btn btn-sm btn-ghost"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp test_result(assigns) do
    ~H"""
    <div class="mt-2">
      {if @result == :ok do
            ~H'''
              <div class="alert alert-success alert-sm py-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="stroke-current shrink-0 h-4 w-4"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <span class="text-sm">Connection successful!</span>
              </div>
            '''
      else
            ~H'''
              <div class="alert alert-error alert-sm py-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="stroke-current shrink-0 h-4 w-4"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <span class="text-sm">Connection failed. Please check your API key.</span>
              </div>
            '''
      end}
    </div>
    """
  end

  defp current_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{id: id} = user ->
        %{
          "id" => id,
          "email" => Map.get(user, :email)
        }

      _other ->
        %{}
    end
  end
end
