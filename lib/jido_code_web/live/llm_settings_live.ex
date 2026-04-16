defmodule JidoCodeWeb.LLMSettingsLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.LLM.Discovery
  alias JidoCode.Security.SecretRefs
  alias JidoCode.Control.Actor

  @impl true
  def mount(_params, _session, socket) do
    current_actor = current_actor(socket)

    socket =
      socket
      |> assign(:page_title, "LLM Settings")
      |> assign(:current_actor, current_actor)
      |> assign_providers()
      |> assign_credentials()
      |> assign(:test_results, %{})
      |> assign(:testing_provider, nil)

    {:ok, socket}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-6xl mx-auto py-8">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">LLM Provider Settings</h1>
        </div>

        <p class="text-base-content/70 mb-6">
          Configure API keys for different LLM providers. Keys are stored securely and can be used
          across all your repositories.
        </p>

        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <.live_component
            :for={provider <- @providers}
            module={JidoCodeWeb.LLMProviderCard}
            id={"provider-#{provider.id}"}
            provider={provider}
            configured={Map.has_key?(@credentials, provider.id)}
            credential_status={Map.get(@credentials, provider.id)}
            test_result={Map.get(@test_results, Atom.to_string(provider.id))}
            testing={@testing_provider == provider.id}
            current_actor={@current_actor}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:test_complete, provider_id, result}, socket) do
    socket =
      socket
      |> put_flash(
        if(result == :ok, do: :info, else: :error),
        if(result == :ok,
          do: "Connection test successful!",
          else: "Connection test failed. Please check your API key."
        )
      )
      |> update(:test_results, fn results -> Map.put(results, Atom.to_string(provider_id), result) end)
      |> assign(:testing_provider, nil)

    {:noreply, socket}
  end

  defp assign_providers(socket) do
    providers = Discovery.list_providers()
    assign(socket, :providers, providers)
  end

  defp assign_credentials(socket) do
    credentials =
      socket.assigns.providers
      |> Enum.filter(fn provider ->
        secret_name = "providers/#{Atom.to_string(provider.id)}_api_key"
        case SecretRefs.operational_secret_value(:integration, secret_name) do
          {:ok, _} -> true
          _ -> false
        end
      end)
      |> Map.new(fn provider ->
        {provider.id, :configured}
      end)

    assign(socket, :credentials, credentials)
  end
end
