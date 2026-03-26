defmodule JidoCodeWeb.SetupLive do
  # covers: baseline.surface.public_entry_routes
  # covers: setup.onboarding.post_bootstrap_start_surface
  # covers: setup.onboarding.deployment_mode_auto_detected
  # covers: setup.onboarding.deferred_integrations
  # covers: setup.onboarding.start_path_preference_persisted
  use JidoCodeWeb, :live_view

  alias JidoCode.Setup.DeploymentMode
  alias JidoCode.Setup.SystemConfig

  @start_paths [:local_repo, :github, :later]

  @type start_path :: :local_repo | :github | :later

  @impl true
  def mount(params, _session, socket) do
    diagnostic = normalize_optional_string(params["diagnostic"])

    case SystemConfig.load() do
      {:ok, %SystemConfig{} = config} ->
        route_setup(socket, config, diagnostic, false)

      {:error, %{diagnostic: load_diagnostic, onboarding_step: onboarding_step}} ->
        fallback_config = %SystemConfig{
          onboarding_completed: false,
          onboarding_step: max(onboarding_step, 3),
          onboarding_state: %{},
          default_environment: :sprite,
          workspace_root: nil
        }

        route_setup(socket, fallback_config, diagnostic || load_diagnostic, true)
    end
  end

  @impl true
  def handle_event("choose_start_path", %{"choice" => choice}, socket) do
    normalized_choice = normalize_start_path(choice)
    allowed_choices = Enum.map(socket.assigns.start_options, & &1.id)

    cond do
      socket.assigns.buttons_disabled? ->
        {:noreply, assign(socket, :save_error, "Resolve the setup state issue before saving a start path.")}

      normalized_choice not in allowed_choices ->
        {:noreply, assign(socket, :save_error, "Choose a valid way to start.")}

      true ->
        case persist_start_path(socket.assigns.deployment_mode, normalized_choice) do
          {:ok, %SystemConfig{} = config} ->
            {:noreply,
             socket
             |> assign_start_surface(config, socket.assigns.diagnostic, false)
             |> put_flash(:info, "#{start_path_title(normalized_choice)} saved as your default start path.")}

          {:error, %{diagnostic: diagnostic}} ->
            {:noreply, assign(socket, :save_error, diagnostic)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="setup-start-surface" class="mx-auto w-full max-w-6xl px-6 py-10">
        <div class="grid gap-8 lg:grid-cols-[minmax(0,20rem)_minmax(0,1fr)] lg:gap-12">
          <div class="space-y-6">
            <div class="space-y-3">
              <p id="setup-eyebrow" class="text-xs font-medium uppercase tracking-[0.3em] text-base-content/60">
                Setup
              </p>
              <h1 id="setup-title" class="text-4xl font-semibold tracking-tight sm:text-5xl">
                Choose how to start
              </h1>
              <p id="setup-description" class="max-w-md text-base text-base-content/70">
                {setup_description(@deployment_mode)}
              </p>
            </div>

            <dl class="space-y-4 rounded-2xl border border-base-300 bg-base-100/80 p-5">
              <div class="space-y-1">
                <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                  Deployment mode
                </dt>
                <dd id="setup-deployment-mode" class="text-sm font-medium">
                  {deployment_mode_label(@deployment_mode)}
                </dd>
              </div>

              <div class="space-y-1">
                <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                  Admin email
                </dt>
                <dd id="setup-owner-email" class="text-sm font-medium">
                  {@owner_email}
                </dd>
              </div>

              <div class="space-y-1">
                <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">
                  Saved choice
                </dt>
                <dd id="setup-selected-start-path" class="text-sm font-medium">
                  {selected_start_path_label(@selected_start_path)}
                </dd>
              </div>
            </dl>

            <p id="setup-selected-start-note" class="max-w-md text-sm text-base-content/60">
              {selected_start_path_note(@selected_start_path, @deployment_mode)}
            </p>
          </div>

          <div class="space-y-4">
            <div :if={@diagnostic} id="setup-diagnostic" class="alert alert-warning">
              <.icon name="hero-exclamation-triangle-mini" class="size-5" />
              <span>{@diagnostic}</span>
            </div>

            <div :if={@save_error} id="setup-save-error" class="alert alert-error">
              <.icon name="hero-x-circle-mini" class="size-5" />
              <span>{@save_error}</span>
            </div>

            <article
              :for={option <- @start_options}
              id={"setup-start-choice-#{option.id}"}
              class={[
                "rounded-2xl border p-5 transition",
                @selected_start_path == option.id && "border-primary/50 bg-base-100 shadow-sm",
                @selected_start_path != option.id && "border-base-300 bg-base-100/80"
              ]}
            >
              <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2">
                    <h2 class="text-xl font-semibold">{option.title}</h2>
                    <span
                      :if={choice_badge_label(option.id, @selected_start_path, option.recommended?)}
                      id={"setup-start-choice-#{option.id}-badge"}
                      class="badge badge-outline text-xs"
                    >
                      {choice_badge_label(option.id, @selected_start_path, option.recommended?)}
                    </span>
                  </div>
                  <p class="text-sm font-medium text-base-content/80">{option.summary}</p>
                  <p class="max-w-2xl text-sm text-base-content/60">{option.detail}</p>
                </div>

                <button
                  id={"setup-start-choice-#{option.id}-save"}
                  type="button"
                  phx-click="choose_start_path"
                  phx-value-choice={option.id}
                  disabled={@buttons_disabled? or @selected_start_path == option.id}
                  class={[
                    "btn btn-sm w-full sm:w-auto",
                    option.button_class,
                    (@buttons_disabled? or @selected_start_path == option.id) && "btn-disabled"
                  ]}
                >
                  {choice_button_label(option.id, @selected_start_path)}
                </button>
              </div>
            </article>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp route_setup(socket, %SystemConfig{} = config, diagnostic, config_load_error?) do
    cond do
      config.onboarding_step < 3 ->
        {:ok, push_navigate(socket, to: ~p"/welcome")}

      is_nil(socket.assigns[:current_user]) ->
        {:ok, push_navigate(socket, to: ~p"/welcome")}

      config.onboarding_completed ->
        {:ok, push_navigate(socket, to: ~p"/dashboard")}

      true ->
        {:ok, assign_start_surface(socket, config, diagnostic, config_load_error?)}
    end
  end

  defp assign_start_surface(socket, %SystemConfig{} = config, diagnostic, buttons_disabled?) do
    deployment_mode = DeploymentMode.current()
    selected_start_path = selected_start_path(config.onboarding_state)

    socket
    |> assign(:deployment_mode, deployment_mode)
    |> assign(:onboarding_state, config.onboarding_state)
    |> assign(:owner_email, owner_email(config.onboarding_state, socket.assigns[:current_user]))
    |> assign(:selected_start_path, selected_start_path)
    |> assign(:start_options, start_options(deployment_mode))
    |> assign(:diagnostic, diagnostic)
    |> assign(:buttons_disabled?, buttons_disabled?)
    |> assign(:save_error, nil)
  end

  defp start_options(:desktop) do
    [
      %{
        id: :local_repo,
        title: "Add local repo",
        summary: "Start from a folder on this machine.",
        detail: "Use this when your source of truth already lives on your desktop.",
        recommended?: true,
        button_class: "btn-primary"
      },
      %{
        id: :github,
        title: "Connect GitHub",
        summary: "Use a hosted repository and GitHub-backed workflows.",
        detail: "Choose this if GitHub should stay your primary source-control path.",
        recommended?: false,
        button_class: "btn-outline"
      },
      %{
        id: :later,
        title: "Do this later",
        summary: "Keep moving and come back when you are ready to attach a repo.",
        detail: "This keeps the setup path simple while you finish the rest of the product wiring.",
        recommended?: false,
        button_class: "btn-ghost"
      }
    ]
  end

  defp start_options(:cloud) do
    [
      %{
        id: :github,
        title: "Connect GitHub",
        summary: "Use GitHub as the first source-control path for this install.",
        detail: "This is the cleanest starting point for a hosted deployment.",
        recommended?: true,
        button_class: "btn-primary"
      },
      %{
        id: :later,
        title: "Do this later",
        summary: "Keep moving and connect source control when you need it.",
        detail: "You can defer GitHub setup until the first feature that depends on it.",
        recommended?: false,
        button_class: "btn-outline"
      }
    ]
  end

  defp persist_start_path(deployment_mode, start_path) do
    SystemConfig.update_onboarding_state(fn current_state ->
      current_state = normalize_keyed_map(current_state)
      existing_step_state = current_state |> fetch_step_state(3) |> normalize_keyed_map()

      updated_step_state =
        existing_step_state
        |> Map.put("start_path", Atom.to_string(start_path))
        |> Map.put("deployment_mode", Atom.to_string(deployment_mode))
        |> Map.put("validated_note", start_path_note(start_path))

      {:ok, Map.put(current_state, "3", updated_step_state)}
    end)
  end

  defp selected_start_path(onboarding_state) do
    onboarding_state
    |> fetch_step_state(3)
    |> map_get(:start_path, "start_path")
    |> normalize_start_path()
  end

  defp owner_email(onboarding_state, current_user) do
    onboarding_state
    |> fetch_step_state(2)
    |> map_get(:owner_email, "owner_email")
    |> normalize_optional_string()
    |> case do
      nil -> current_user_email(current_user)
      owner_email -> owner_email
    end
  end

  defp current_user_email(%{email: email}), do: email
  defp current_user_email(_current_user), do: "Admin account"

  defp setup_description(:desktop),
    do: "Your admin account is ready. Pick the first path you want this desktop install to guide next."

  defp setup_description(:cloud),
    do: "Your admin account is ready. Pick the first path you want this install to guide next."

  defp deployment_mode_label(:desktop), do: "Desktop"
  defp deployment_mode_label(:cloud), do: "Cloud"

  defp selected_start_path_label(nil), do: "Not chosen yet"
  defp selected_start_path_label(start_path), do: start_path_title(start_path)

  defp selected_start_path_note(nil, :desktop),
    do: "Pick a default path now. You can still change it later once more setup moves into the app."

  defp selected_start_path_note(nil, :cloud),
    do: "Pick a default path now. You can still change it later once more setup moves into the app."

  defp selected_start_path_note(:local_repo, _deployment_mode),
    do: "Local repositories are the default path for this install until you choose something else."

  defp selected_start_path_note(:github, _deployment_mode),
    do: "GitHub is saved as the default source-control path for this install."

  defp selected_start_path_note(:later, _deployment_mode),
    do: "Repo setup is deferred for now. You can come back and choose a source-control path later."

  defp choice_badge_label(option_id, selected_start_path, _recommended?) when option_id == selected_start_path,
    do: "Saved"

  defp choice_badge_label(_option_id, _selected_start_path, true), do: "Recommended"
  defp choice_badge_label(_option_id, _selected_start_path, _recommended?), do: nil

  defp choice_button_label(option_id, selected_start_path) when option_id == selected_start_path,
    do: "Saved"

  defp choice_button_label(option_id, _selected_start_path), do: start_path_title(option_id)

  defp start_path_title(:local_repo), do: "Add local repo"
  defp start_path_title(:github), do: "Connect GitHub"
  defp start_path_title(:later), do: "Do this later"

  defp start_path_note(:local_repo), do: "Local repo path selected."
  defp start_path_note(:github), do: "GitHub path selected."
  defp start_path_note(:later), do: "Repo setup deferred for now."

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key, Map.get(map, string_key, default))
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_start_path(start_path) when start_path in @start_paths, do: start_path

  defp normalize_start_path(start_path) when is_binary(start_path) do
    case String.trim(start_path) do
      "local_repo" -> :local_repo
      "github" -> :github
      "later" -> :later
      _other -> nil
    end
  end

  defp normalize_start_path(_start_path), do: nil

  defp normalize_keyed_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, Atom.to_string(key), value)

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      {key, value}, acc ->
        Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_keyed_map(_map), do: %{}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(_value), do: nil
end
