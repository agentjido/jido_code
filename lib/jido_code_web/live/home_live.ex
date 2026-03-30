defmodule JidoCodeWeb.HomeLive do
  # covers: baseline.surface.auth_entrypoints_visible
  # covers: baseline.surface.welcome_surface_consolidated
  # covers: baseline.surface.welcome_landing_copy
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.registration_guardrails
  # covers: auth.provider_login_flow.entrypoint_visible
  # covers: auth.provider_login_flow.local_auth_fallback_visible
  # covers: auth.operator_settings.sections_separated
  # covers: auth.operator_settings.broker_trust_configuration_ui
  # covers: auth.operator_settings.github_service_validation_feedback
  # covers: auth.operator_settings.integration_boundary_visible
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  # covers: auth.self_hosted_provider_integration.login_and_service_ready
  # covers: auth.self_hosted_provider_integration.service_independent_of_login_toggle
  # covers: auth.self_hosted_provider_integration.local_auth_fallback_on_broker_failure
  # covers: auth.self_hosted_provider_integration.allowlist_rejection_without_service_regression
  # covers: auth.self_hosted_provider_integration.bootstrap_precedes_provider_login
  use JidoCodeWeb, :live_view

  require Ash.Query

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.AuthProviders
  alias JidoCode.AuthProviders.ProviderConfig
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Setup.BootstrapStatus
  alias JidoCode.Setup.GitHubCredentialChecks
  alias JidoCode.Setup.OwnerBootstrap
  alias JidoCode.Setup.OwnerRecovery
  alias JidoCode.Setup.PrerequisiteChecks
  alias JidoCode.Setup.SystemConfig

  @provider_catalog [
    %{
      provider: :github,
      display_name: "GitHub",
      provider_host: "github.com",
      login_entrypoint_visible?: true,
      service_integration_status: :implemented
    },
    %{
      provider: :gitlab,
      display_name: "GitLab",
      provider_host: "gitlab.com",
      login_entrypoint_visible?: false,
      service_integration_status: :placeholder
    },
    %{
      provider: :bitbucket,
      display_name: "Bitbucket",
      provider_host: "bitbucket.org",
      login_entrypoint_visible?: false,
      service_integration_status: :placeholder
    }
  ]

  @allowlist_options [
    {"None", "none"},
    {"Users", "users"},
    {"Organizations", "organizations"},
    {"Teams", "teams"},
    {"Groups", "groups"},
    {"Workspaces", "workspaces"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    bootstrap_status = BootstrapStatus.current()
    owner_status = resolve_owner_status(bootstrap_status)

    if socket.assigns[:current_user] && bootstrap_status.state == :continue_setup do
      {:ok, push_navigate(socket, to: ~p"/setup")}
    else
      socket =
        socket
        |> assign(:bootstrap_status, bootstrap_status)
        |> assign(:desktop_runtime?, desktop_runtime?())
        |> assign(:prereq_status, initial_prereq_status(bootstrap_status))
        |> assign(:prereq_report, nil)
        |> assign(:owner_mode, owner_status.mode)
        |> assign(:owner_email, owner_status.owner_email)
        |> assign(:owner_form, build_owner_form(owner_status.owner_email))
        |> assign(:owner_recovery_form, build_recovery_form(owner_status.owner_email))
        |> assign(:save_error, owner_status.error || bootstrap_status.diagnostic)
        |> assign(
          github_login_path: github_login_path(),
          github_login_enabled?: github_login_enabled?(),
          allowlist_options: @allowlist_options
        )
        |> refresh_operator_settings()

      if connected?(socket) && bootstrap_status.state == :bootstrap_required do
        send(self(), :run_prereqs)
      end

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("save_provider_login", %{"provider_login" => params}, socket) do
    with {:ok, provider} <- normalize_provider(Map.get(params, "provider")),
         {:ok, provider_host} <- provider_host_for(provider),
         {:ok, _config} <- save_provider_login(provider, provider_host, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Saved #{provider_display_name(provider)} provider login settings.")
       |> refresh_operator_settings()}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, format_error(error))}
    end
  end

  def handle_event("refresh_github_service_checks", _params, socket) do
    {:noreply,
     socket
     |> assign(:github_service_report, github_service_report(socket.assigns[:current_user]))}
  end

  def handle_event("recheck_prereqs", _params, socket) do
    send(self(), :run_prereqs)

    {:noreply,
     socket
     |> assign(:prereq_status, :checking)
     |> assign(:prereq_report, nil)}
  end

  def handle_event("bootstrap_owner", %{"owner" => owner_params}, socket) do
    cond do
      socket.assigns.bootstrap_status.state == :bootstrap_required and socket.assigns.prereq_status != :pass ->
        {:noreply, assign(socket, :save_error, "System checks must pass before creating an account.")}

      socket.assigns.bootstrap_status.state not in [:bootstrap_required, :continue_setup] ->
        {:noreply, assign(socket, :save_error, "Bootstrap is unavailable from the current public state.")}

      true ->
        case OwnerBootstrap.bootstrap(owner_params) do
          {:ok, result} ->
            prerequisite_report = current_prerequisite_report(socket)

            case persist_bootstrap_progress(socket.assigns.bootstrap_status, prerequisite_report, result) do
              {:ok, _config} ->
                {:noreply,
                 socket
                 |> assign(:save_error, nil)
                 |> redirect(to: owner_sign_in_with_token_path(result.token))}

              {:error, %{diagnostic: diagnostic}} ->
                {:noreply, assign(socket, :save_error, diagnostic)}
            end

          {:error, {_error_type, diagnostic}} ->
            owner_status = resolve_owner_status(BootstrapStatus.current())

            {:noreply,
             socket
             |> assign(:bootstrap_status, BootstrapStatus.current())
             |> assign(:owner_mode, owner_status.mode)
             |> assign(:owner_email, owner_status.owner_email)
             |> assign(:save_error, diagnostic)
             |> assign(:owner_form, build_owner_form(owner_params["email"] || owner_status.owner_email))}
        end
    end
  end

  def handle_event("recover_owner", %{"owner_recovery" => recovery_params}, socket) do
    if socket.assigns.bootstrap_status.state == :continue_setup and socket.assigns.owner_mode == :confirm do
      case OwnerRecovery.recover(recovery_params) do
        {:ok, result} ->
          prerequisite_report = current_prerequisite_report(socket)

          case persist_recovery_progress(socket.assigns.bootstrap_status, prerequisite_report, result) do
            {:ok, _config} ->
              {:noreply,
               socket
               |> assign(:save_error, nil)
               |> redirect(to: owner_sign_in_with_token_path(result.token))}

            {:error, %{diagnostic: diagnostic}} ->
              {:noreply, assign(socket, :save_error, diagnostic)}
          end

        {:error, {_error_type, diagnostic}} ->
          owner_status = resolve_owner_status(BootstrapStatus.current())

          {:noreply,
           socket
           |> assign(:bootstrap_status, BootstrapStatus.current())
           |> assign(:owner_mode, owner_status.mode)
           |> assign(:owner_email, owner_status.owner_email)
           |> assign(:save_error, diagnostic)
           |> assign(
             :owner_recovery_form,
             build_recovery_form(recovery_params["email"] || owner_status.owner_email, recovery_params)
           )}
      end
    else
      {:noreply, assign(socket, :save_error, "Owner recovery is only available while setup is still incomplete.")}
    end
  end

  @impl true
  def handle_info(:run_prereqs, socket) do
    report = PrerequisiteChecks.run()

    {:noreply,
     socket
     |> assign(:prereq_status, report.status)
     |> assign(:prereq_report, report)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="welcome-shell">
      <div class={[
        "mx-auto w-full px-6 py-12 sm:px-8 lg:px-12",
        (@bootstrap_status.state == :ready and @current_user) && "max-w-[1240px]",
        (@bootstrap_status.state != :ready or !@current_user) && "max-w-[1160px]"
      ]}>
        <div class={[
          "w-full",
          (@bootstrap_status.state == :ready and @current_user) && "space-y-16"
        ]}>
          <div class={[
            "grid gap-14 lg:grid-cols-[minmax(0,360px)_minmax(0,400px)] lg:gap-24",
            (@bootstrap_status.state == :ready and @current_user) && "lg:items-start",
            (@bootstrap_status.state != :ready or !@current_user) && "lg:min-h-[calc(100vh-6rem)] lg:items-center"
          ]}>
            <section class="w-full max-w-[360px] space-y-10">
              <div class="flex items-center gap-3">
                <div class="welcome-shell__logo-mark">
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                    <path
                      d="M2 10L6 7L2 4"
                      stroke="currentColor"
                      stroke-width="1.5"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                    <path
                      d="M7 10H12"
                      stroke="currentColor"
                      stroke-width="1.5"
                      stroke-linecap="round"
                    />
                  </svg>
                </div>

                <div class="space-y-0.5">
                  <p class="text-[15px] font-semibold tracking-[-0.02em] text-base-content">
                    Jido Code
                  </p>
                  <p :if={@desktop_runtime?} class="font-mono text-[11px] text-base-content/28">
                    desktop install
                  </p>
                </div>
              </div>

              <div class="space-y-4">
                <p class="font-mono text-[11px] uppercase tracking-[0.18em] text-base-content/42">
                  {welcome_eyebrow(@bootstrap_status, @current_user)}
                </p>
                <h1 class="text-[42px] font-semibold tracking-[-0.05em] leading-[0.98] text-base-content">
                  {welcome_headline(@bootstrap_status, @current_user)}
                </h1>
                <p class="max-w-[32rem] text-[15px] leading-7 text-base-content/58">
                  {welcome_description(@bootstrap_status, @desktop_runtime?, @current_user)}
                </p>
              </div>

              <%= case @bootstrap_status.state do %>
                <% :bootstrap_required -> %>
                  <div class="space-y-4">
                    <div
                      id="system-check"
                      class="flex flex-wrap items-center gap-x-4 gap-y-2 text-[14px] text-base-content/62"
                    >
                      <span class={["inline-flex items-center gap-2", welcome_status_text_class(@prereq_status)]}>
                        <%= case @prereq_status do %>
                          <% :checking -> %>
                            <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                            <span>Checking your system…</span>
                          <% :pass -> %>
                            <.icon name="hero-check-circle-mini" class="size-4" />
                            <span>System ready</span>
                          <% :timeout -> %>
                            <.icon name="hero-exclamation-triangle-mini" class="size-4" />
                            <span>{prerequisite_banner_message(@prereq_status)}</span>
                          <% _other -> %>
                            <.icon name="hero-x-circle-mini" class="size-4" />
                            <span>{prerequisite_banner_message(@prereq_status)}</span>
                        <% end %>
                      </span>

                      <button
                        type="button"
                        phx-click="recheck_prereqs"
                        class="text-[12px] font-medium text-base-content/36 transition-colors hover:text-base-content/58"
                      >
                        Re-check
                      </button>
                    </div>

                    <details
                      :if={@prereq_status in [:fail, :timeout] and @prereq_report}
                      class="max-w-[340px] border-t border-base-300/25 pt-4"
                    >
                      <summary class="cursor-pointer list-none text-[12px] font-medium text-base-content/36 transition-colors hover:text-base-content/58">
                        Technical details
                      </summary>

                      <ul class="mt-4 space-y-3 text-[13px] leading-6 text-base-content/52">
                        <li :for={check <- @prereq_report.checks} class="space-y-1">
                          <div class="flex items-center justify-between gap-4">
                            <span class="font-medium text-base-content/74">{check.name}</span>
                            <span class={[
                              "font-mono text-[11px] uppercase tracking-[0.16em]",
                              welcome_check_text_class(check.status)
                            ]}>
                              {prereq_status_label(check.status)}
                            </span>
                          </div>
                          <p>{check.detail}</p>
                          <p :if={check.status != :pass} class="text-warning/90">{check.remediation}</p>
                        </li>
                      </ul>
                    </details>
                  </div>
                <% :continue_setup -> %>
                  <div class="space-y-2">
                    <p class="font-mono text-[11px] uppercase tracking-[0.16em] text-base-content/28">
                      Admin email
                    </p>
                    <p class="text-[14px] text-base-content/62">{@owner_email || "Unavailable"}</p>
                  </div>
                <% :invalid_state -> %>
                  <p class="max-w-[28rem] text-[14px] leading-6 text-error/80">
                    {bootstrap_diagnostic(@save_error)}
                  </p>
                <% :ready -> %>
                  <div class="space-y-2">
                    <p
                      :if={@current_user}
                      class="font-mono text-[12px] text-base-content/32"
                    >
                      {@current_user.email}
                    </p>
                    <p :if={!@current_user} class="text-[14px] leading-6 text-base-content/52">
                      Public account creation is disabled.
                    </p>
                    <p
                      :if={@current_user}
                      class="text-[14px] leading-6 text-base-content/52"
                    >
                      Local email auth remains the fallback path even when provider sign-in is enabled.
                    </p>
                  </div>
              <% end %>
            </section>

            <section class="w-full max-w-[400px] lg:border-l lg:border-base-300/28 lg:pl-24">
              <%= case @bootstrap_status.state do %>
                <% :bootstrap_required -> %>
                  <div class={["space-y-6 transition-all duration-300", @prereq_status != :pass && "opacity-70"]}>
                    <div class="space-y-1">
                      <h2 class="text-[15px] font-medium tracking-[-0.01em] text-base-content">
                        Admin account
                      </h2>
                      <p class="text-[13px] leading-6 text-base-content/44">
                        This will be the only admin account.
                      </p>
                    </div>

                    <div
                      :if={@save_error}
                      id="welcome-save-error"
                      class="rounded-md border border-error/25 bg-error/10 px-4 py-3 text-[13px] leading-6 text-error"
                    >
                      {@save_error}
                    </div>

                    <.form for={@owner_form} id="welcome-owner-form" phx-submit="bootstrap_owner" class="space-y-4">
                      <div class="space-y-1.5">
                        <label for={@owner_form[:email].id} class="text-[12px] font-medium text-base-content/50">
                          Email
                        </label>
                        <input
                          id={@owner_form[:email].id}
                          name={@owner_form[:email].name}
                          type="email"
                          value={field_value(@owner_form[:email])}
                          required
                          disabled={@prereq_status != :pass}
                          autocomplete="email"
                          placeholder="admin@yourorg.com"
                          class={welcome_input_classes()}
                        />
                      </div>

                      <div class="space-y-1.5">
                        <label for={@owner_form[:password].id} class="text-[12px] font-medium text-base-content/50">
                          Password
                        </label>
                        <input
                          id={@owner_form[:password].id}
                          name={@owner_form[:password].name}
                          type="password"
                          value=""
                          required
                          minlength="8"
                          disabled={@prereq_status != :pass}
                          autocomplete="new-password"
                          placeholder="••••••••••••"
                          class={welcome_input_classes()}
                        />
                      </div>

                      <div class="space-y-1.5">
                        <label
                          for={@owner_form[:password_confirmation].id}
                          class="text-[12px] font-medium text-base-content/50"
                        >
                          Confirm password
                        </label>
                        <input
                          id={@owner_form[:password_confirmation].id}
                          name={@owner_form[:password_confirmation].name}
                          type="password"
                          value=""
                          required
                          minlength="8"
                          disabled={@prereq_status != :pass}
                          autocomplete="new-password"
                          placeholder="••••••••••••"
                          class={welcome_input_classes()}
                        />
                      </div>

                      <div class="pt-3">
                        <button
                          type="submit"
                          disabled={@prereq_status != :pass}
                          class={welcome_button_classes(:primary)}
                        >
                          <span>
                            {if @prereq_status == :pass,
                              do: "Create Account & Continue",
                              else: "Complete system check first"}
                          </span>
                          <.icon
                            :if={@prereq_status == :pass}
                            name="hero-arrow-right-mini"
                            class="size-4"
                          />
                        </button>
                      </div>
                    </.form>
                  </div>
                <% :continue_setup -> %>
                  <div class="space-y-8">
                    <div class="space-y-1">
                      <h2 class="text-[15px] font-medium tracking-[-0.01em] text-base-content">
                        Admin sign-in
                      </h2>
                      <p class="text-[13px] leading-6 text-base-content/44">
                        Use the existing admin account to continue.
                      </p>
                    </div>

                    <div
                      :if={@save_error}
                      id="welcome-save-error"
                      class="rounded-md border border-error/25 bg-error/10 px-4 py-3 text-[13px] leading-6 text-error"
                    >
                      {@save_error}
                    </div>

                    <.form for={@owner_form} id="continue-setup-owner-form" phx-submit="bootstrap_owner" class="space-y-4">
                      <div class="space-y-1.5">
                        <label for={@owner_form[:email].id} class="text-[12px] font-medium text-base-content/50">
                          Email
                        </label>
                        <input
                          id={@owner_form[:email].id}
                          name={@owner_form[:email].name}
                          type="email"
                          value={field_value(@owner_form[:email])}
                          required
                          autocomplete="email"
                          placeholder="admin@yourorg.com"
                          class={welcome_input_classes()}
                        />
                      </div>

                      <div class="space-y-1.5">
                        <label for={@owner_form[:password].id} class="text-[12px] font-medium text-base-content/50">
                          Password
                        </label>
                        <input
                          id={@owner_form[:password].id}
                          name={@owner_form[:password].name}
                          type="password"
                          value=""
                          required
                          autocomplete="current-password"
                          placeholder="••••••••••••"
                          class={welcome_input_classes()}
                        />
                      </div>

                      <div class="pt-3">
                        <button type="submit" class={welcome_button_classes(:primary)}>
                          <span>Sign In & Continue</span>
                          <.icon name="hero-arrow-right-mini" class="size-4" />
                        </button>
                      </div>
                    </.form>

                    <details class="border-t border-base-300/20 pt-5">
                      <summary class="cursor-pointer list-none text-[12px] font-medium text-base-content/36 transition-colors hover:text-base-content/58">
                        Reset admin password
                      </summary>

                      <div class="mt-5 space-y-4">
                        <p class="max-w-[24rem] text-[12px] leading-6 text-base-content/48">
                          Only use this if you cannot sign in. This replaces the current admin password.
                        </p>

                        <.form
                          for={@owner_recovery_form}
                          id="continue-setup-recovery-form"
                          phx-submit="recover_owner"
                          class="space-y-4"
                        >
                          <div class="space-y-1.5">
                            <label
                              for={@owner_recovery_form[:email].id}
                              class="text-[12px] font-medium text-base-content/50"
                            >
                              Admin email
                            </label>
                            <input
                              id={@owner_recovery_form[:email].id}
                              name={@owner_recovery_form[:email].name}
                              type="email"
                              value={field_value(@owner_recovery_form[:email])}
                              required
                              autocomplete="email"
                              placeholder="admin@yourorg.com"
                              class={welcome_input_classes()}
                            />
                          </div>

                          <div class="space-y-1.5">
                            <label
                              for={@owner_recovery_form[:password].id}
                              class="text-[12px] font-medium text-base-content/50"
                            >
                              New password
                            </label>
                            <input
                              id={@owner_recovery_form[:password].id}
                              name={@owner_recovery_form[:password].name}
                              type="password"
                              value=""
                              required
                              minlength="8"
                              placeholder="••••••••••••"
                              class={welcome_input_classes()}
                            />
                          </div>

                          <div class="space-y-1.5">
                            <label
                              for={@owner_recovery_form[:password_confirmation].id}
                              class="text-[12px] font-medium text-base-content/50"
                            >
                              Confirm password
                            </label>
                            <input
                              id={@owner_recovery_form[:password_confirmation].id}
                              name={@owner_recovery_form[:password_confirmation].name}
                              type="password"
                              value=""
                              required
                              minlength="8"
                              placeholder="••••••••••••"
                              class={welcome_input_classes()}
                            />
                          </div>

                          <div class="space-y-1.5">
                            <label
                              for={@owner_recovery_form[:verification_phrase].id}
                              class="text-[12px] font-medium text-base-content/50"
                            >
                              Type this phrase
                            </label>
                            <input
                              id={@owner_recovery_form[:verification_phrase].id}
                              name={@owner_recovery_form[:verification_phrase].name}
                              type="text"
                              value={field_value(@owner_recovery_form[:verification_phrase])}
                              required
                              placeholder={OwnerRecovery.verification_phrase()}
                              class={welcome_input_classes()}
                            />
                          </div>

                          <label class="flex items-start gap-3 pt-1 text-[12px] leading-6 text-base-content/52">
                            <input
                              type="hidden"
                              name={@owner_recovery_form[:verification_ack].name}
                              value="false"
                            />
                            <input
                              id={@owner_recovery_form[:verification_ack].id}
                              name={@owner_recovery_form[:verification_ack].name}
                              type="checkbox"
                              value="true"
                              checked={normalize_checkbox(@owner_recovery_form[:verification_ack].value)}
                              class="mt-1 size-4 rounded border border-base-300 bg-transparent text-warning focus:ring-0"
                            />
                            <span>I understand this replaces the current admin password.</span>
                          </label>

                          <div class="pt-3">
                            <button type="submit" class={welcome_button_classes(:warning)}>
                              <span>Reset Admin Password</span>
                              <.icon name="hero-arrow-right-mini" class="size-4" />
                            </button>
                          </div>
                        </.form>
                      </div>
                    </details>
                  </div>
                <% :invalid_state -> %>
                  <div class="space-y-6">
                    <div class="space-y-1">
                      <h2 class="text-[15px] font-medium tracking-[-0.01em] text-base-content">
                        Diagnostic report
                      </h2>
                      <p class="text-[13px] leading-6 text-base-content/44">
                        Repair the bootstrap state before continuing.
                      </p>
                    </div>

                    <div
                      id="welcome-save-error"
                      class="rounded-md border border-error/25 bg-error/10 px-4 py-3 text-[13px] leading-6 text-error"
                    >
                      {@save_error || "Repair the bootstrap state before continuing."}
                    </div>
                  </div>
                <% :ready -> %>
                  <%= if @current_user do %>
                    <div class="space-y-6">
                      <div class="space-y-1">
                        <h2 class="text-[15px] font-medium tracking-[-0.01em] text-base-content">
                          Signed in
                        </h2>
                        <p class="text-[13px] leading-6 text-base-content/44">{@current_user.email}</p>
                      </div>

                      <a href="/sign-out" class={welcome_button_classes(:primary)}>
                        <span>Sign Out</span>
                        <.icon name="hero-arrow-right-mini" class="size-4" />
                      </a>
                    </div>
                  <% else %>
                    <div class="space-y-6">
                      <div class="space-y-1">
                        <h2 class="text-[15px] font-medium tracking-[-0.01em] text-base-content">
                          Sign in
                        </h2>
                        <p class="text-[13px] leading-6 text-base-content/44">
                          Local email sign-in stays available even when provider login is enabled.
                        </p>
                      </div>

                      <div class="space-y-3">
                        <a href="/sign-in" class={welcome_button_classes(:primary)}>
                          <span>Sign In</span>
                          <.icon name="hero-arrow-right-mini" class="size-4" />
                        </a>

                        <a
                          :if={@github_login_enabled?}
                          href={@github_login_path}
                          class={welcome_button_classes(:secondary)}
                        >
                          <span>Sign In with GitHub</span>
                        </a>
                      </div>
                    </div>
                  <% end %>
              <% end %>
            </section>
          </div>

          <div :if={@bootstrap_status.state == :ready and @current_user} class="space-y-8">
            <%!-- covers: auth.operator_settings.sections_separated --%>
            <section
              id="provider-login-settings"
              class="rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
            >
              <div class="mb-6 flex items-start justify-between gap-6">
                <div class="space-y-2">
                  <p class="text-xs font-bold uppercase tracking-[0.22em] text-base-content/45">
                    Operator Settings
                  </p>
                  <h2 class="text-2xl font-semibold text-base-content">Provider Login</h2>
                  <p class="max-w-3xl text-sm leading-6 text-base-content/70">
                    Configure broker trust and allowlist policy separately from deployment-local Git automation credentials.
                  </p>
                </div>
                <div class="rounded-2xl border border-base-300 bg-base-200/70 px-4 py-3 text-sm text-base-content/70">
                  Local email sign-in stays available even if every provider card below is disabled.
                </div>
              </div>

              <div class="grid gap-6 xl:grid-cols-3">
                <article
                  :for={card <- @provider_login_cards}
                  id={"provider-login-card-#{card.provider}"}
                  class="rounded-2xl border border-base-300 bg-base-200/40 p-5"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="text-lg font-semibold text-base-content">{card.display_name}</h3>
                      <p class="text-sm text-base-content/60">{card.provider_host}</p>
                    </div>
                    <span class={provider_status_badge_class(card.status.tone)}>
                      {card.status.label}
                    </span>
                  </div>

                  <p class="mt-4 text-sm leading-6 text-base-content/70">{card.status.detail}</p>

                  <p
                    :if={card.status.missing_fields != []}
                    class="mt-3 text-xs font-medium uppercase tracking-[0.18em] text-warning"
                  >
                    Missing: {Enum.join(card.status.missing_fields, ", ")}
                  </p>

                  <p class="mt-3 text-xs leading-5 text-base-content/55">{card.entrypoint_note}</p>

                  <.form
                    for={%{}}
                    as={:provider_login}
                    id={"provider-login-form-#{card.provider}"}
                    phx-submit="save_provider_login"
                    class="mt-5 space-y-3"
                  >
                    <input type="hidden" name="provider_login[provider]" value={card.provider} />

                    <%!-- covers: auth.operator_settings.broker_trust_configuration_ui --%>
                    <div class="grid gap-3 sm:grid-cols-2">
                      <.input
                        type="checkbox"
                        name="provider_login[enabled]"
                        checked={card.enabled}
                        label="Enable provider host"
                      />
                      <.input
                        type="checkbox"
                        name="provider_login[login_enabled]"
                        checked={card.login_enabled}
                        label="Allow browser sign-in"
                      />
                    </div>

                    <.input
                      type="select"
                      name="provider_login[allowlist_mode]"
                      label="Allowlist Mode"
                      value={card.allowlist_mode}
                      options={@allowlist_options}
                    />

                    <.input
                      type="textarea"
                      name="provider_login[allowlist_values]"
                      label="Allowlist Values"
                      value={card.allowlist_values_text}
                      rows="4"
                      placeholder="One value per line or comma separated"
                    />

                    <div class="rounded-2xl border border-base-300 bg-base-100/70 p-4">
                      <p class="text-xs font-bold uppercase tracking-[0.18em] text-base-content/45">
                        Broker Trust
                      </p>
                      <div class="mt-3 space-y-3">
                        <.input
                          type="url"
                          name="provider_login[broker_base_url]"
                          label="Broker Base URL"
                          value={card.broker_base_url}
                          placeholder="https://broker.example.com"
                        />
                        <.input
                          type="text"
                          name="provider_login[broker_issuer]"
                          label="Broker Issuer"
                          value={card.broker_issuer}
                          placeholder="https://broker.example.com"
                        />
                        <.input
                          type="text"
                          name="provider_login[broker_audience]"
                          label="Broker Audience"
                          value={card.broker_audience}
                          placeholder="jido-code"
                        />
                      </div>
                    </div>

                    <button type="submit" class="btn btn-primary btn-block">
                      Save {card.display_name} Login Settings
                    </button>
                  </.form>
                </article>
              </div>
            </section>

            <section
              id="git-provider-integrations"
              class="rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
            >
              <div class="mb-6 flex items-start justify-between gap-6">
                <div class="space-y-2">
                  <h2 class="text-2xl font-semibold text-base-content">Git Provider Integrations</h2>
                  <%!-- covers: auth.operator_settings.integration_boundary_visible --%>
                  <p class="max-w-3xl text-sm leading-6 text-base-content/70">
                    Deployment-local Git automation credentials stay separate from provider-login broker trust. GitHub App is preferred, PAT is fallback, and GitLab or Bitbucket remain placeholders for now.
                  </p>
                </div>
                <button
                  id="refresh-github-service-checks"
                  type="button"
                  phx-click="refresh_github_service_checks"
                  class="btn btn-outline btn-sm"
                >
                  Refresh GitHub Validation
                </button>
              </div>

              <div class="grid gap-6 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
                <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="text-lg font-semibold text-base-content">GitHub Service Integration</h3>
                      <p class="text-sm text-base-content/60">
                        Deployment-local automation credentials and repository access validation
                      </p>
                    </div>
                    <span class={integration_status_badge_class(@github_service_report.status)}>
                      {integration_status_label(@github_service_report.status)}
                    </span>
                  </div>

                  <%!-- covers: auth.operator_settings.github_service_validation_feedback --%>
                  <div id="github-service-status" class="mt-4 space-y-4">
                    <p class="text-sm leading-6 text-base-content/70">
                      {github_service_summary(@github_service_report)}
                    </p>

                    <p class="text-xs uppercase tracking-[0.18em] text-base-content/45">
                      Last checked: {format_datetime(@github_service_report.checked_at)}
                    </p>

                    <div class="space-y-3">
                      <div
                        :for={path_result <- @github_service_report.paths}
                        id={"github-service-path-#{path_result.path}"}
                        class="rounded-2xl border border-base-300 bg-base-100/70 p-4"
                      >
                        <div class="flex items-start justify-between gap-4">
                          <div>
                            <p class="font-medium text-base-content">{path_result.name}</p>
                            <p class="mt-1 text-sm text-base-content/65">{path_result.detail}</p>
                          </div>
                          <span class={integration_status_badge_class(path_result.status)}>
                            {integration_status_label(path_result.status)}
                          </span>
                        </div>

                        <p class="mt-3 text-xs uppercase tracking-[0.18em] text-base-content/45">
                          Repository access: {repository_access_label(path_result.repository_access)}
                        </p>

                        <p
                          :if={path_result.missing_repositories != []}
                          class="mt-2 text-sm text-warning"
                        >
                          Missing repositories: {Enum.join(path_result.missing_repositories, ", ")}
                        </p>

                        <p class="mt-2 text-sm text-base-content/70">
                          Remediation: {path_result.remediation}
                        </p>
                      </div>
                    </div>
                  </div>
                </article>

                <div class="space-y-6">
                  <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
                    <h3 class="text-lg font-semibold text-base-content">Deployment-Local Secrets</h3>
                    <p class="mt-2 text-sm leading-6 text-base-content/70">
                      These secret refs back GitHub automation. They are not stored in the provider-login broker config.
                    </p>

                    <div class="mt-4 space-y-2 text-sm text-base-content/75">
                      <p :for={{credential, secret_ref} <- @github_service_secret_refs}>
                        <span class="font-medium">{service_credential_label(credential)}:</span>
                        <code class="ml-2 rounded bg-base-300/70 px-2 py-1 text-xs">{secret_ref}</code>
                      </p>
                    </div>
                  </article>

                  <article class="rounded-2xl border border-base-300 bg-base-200/40 p-5">
                    <h3 class="text-lg font-semibold text-base-content">Future Providers</h3>
                    <div class="mt-3 space-y-3 text-sm text-base-content/70">
                      <div class="rounded-2xl border border-base-300 bg-base-100/70 p-4">
                        <p class="font-medium text-base-content">GitLab</p>
                        <p class="mt-1">
                          Login config is modeled, but GitLab service automation is still a named placeholder adapter.
                        </p>
                      </div>
                      <div class="rounded-2xl border border-base-300 bg-base-100/70 p-4">
                        <p class="font-medium text-base-content">Bitbucket</p>
                        <p class="mt-1">
                          Login config is modeled, but Bitbucket service automation is still a named placeholder adapter.
                        </p>
                      </div>
                    </div>
                  </article>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp resolve_owner_status(%{state: state}) when state in [:bootstrap_required, :continue_setup] do
    case OwnerBootstrap.status() do
      {:ok, %{mode: :create}} ->
        %{mode: :create, owner_email: nil, error: nil}

      {:ok, %{mode: :confirm, owner: owner}} ->
        %{mode: :confirm, owner_email: to_string(owner.email), error: nil}

      {:error, {_error_type, diagnostic}} ->
        %{mode: :error, owner_email: nil, error: diagnostic}
    end
  end

  defp resolve_owner_status(_status), do: %{mode: :inactive, owner_email: nil, error: nil}

  defp initial_prereq_status(%{state: :bootstrap_required}), do: :checking
  defp initial_prereq_status(_status), do: :idle

  defp current_prerequisite_report(socket) do
    socket.assigns[:prereq_report] || PrerequisiteChecks.run()
  end

  defp persist_bootstrap_progress(%{config: %SystemConfig{} = config}, prerequisite_report, result) do
    cond do
      config.onboarding_step == 1 ->
        with {:ok, _config} <- SystemConfig.save_step_progress(bootstrap_step_1_state(prerequisite_report)),
             {:ok, saved_config} <- SystemConfig.save_step_progress(bootstrap_step_2_state(result)) do
          {:ok, saved_config}
        end

      config.onboarding_step == 2 ->
        SystemConfig.save_step_progress(bootstrap_step_2_state(result))

      true ->
        {:ok, config}
    end
  end

  defp persist_recovery_progress(%{config: %SystemConfig{} = config}, prerequisite_report, result) do
    cond do
      config.onboarding_step == 1 ->
        with {:ok, _config} <- SystemConfig.save_step_progress(bootstrap_step_1_state(prerequisite_report)),
             {:ok, saved_config} <- SystemConfig.save_step_progress(recovery_step_2_state(result)) do
          {:ok, saved_config}
        end

      config.onboarding_step == 2 ->
        SystemConfig.save_step_progress(recovery_step_2_state(result))

      true ->
        {:ok, config}
    end
  end

  defp bootstrap_step_1_state(prerequisite_report) do
    %{
      "validated_note" => "System prerequisites verified (welcome flow).",
      "prerequisite_checks" => PrerequisiteChecks.serialize_for_state(prerequisite_report)
    }
  end

  defp bootstrap_step_2_state(result) do
    %{
      "validated_note" => result.validated_note,
      "owner_email" => to_string(result.owner.email),
      "owner_mode" => Atom.to_string(result.owner_mode),
      "registration_actions_disabled" => true
    }
  end

  defp recovery_step_2_state(result) do
    %{
      "validated_note" => result.validated_note,
      "owner_email" => to_string(result.owner.email),
      "owner_mode" => Atom.to_string(result.owner_mode),
      "registration_actions_disabled" => true,
      "owner_recovery_audit" => OwnerRecovery.serialize_audit_for_state(result.audit)
    }
  end

  defp build_owner_form(owner_email) do
    to_form(%{"email" => owner_email || "", "password" => "", "password_confirmation" => ""}, as: :owner)
  end

  defp build_recovery_form(owner_email, params \\ %{}) do
    to_form(
      %{
        "email" => params["email"] || owner_email || "",
        "password" => "",
        "password_confirmation" => "",
        "verification_phrase" => params["verification_phrase"] || "",
        "verification_ack" => normalize_checkbox(params["verification_ack"])
      },
      as: :owner_recovery
    )
  end

  defp normalize_checkbox(true), do: true
  defp normalize_checkbox("true"), do: true
  defp normalize_checkbox("on"), do: true
  defp normalize_checkbox(_value), do: false

  defp field_value(%Phoenix.HTML.FormField{value: nil}), do: ""
  defp field_value(%Phoenix.HTML.FormField{value: value}), do: value

  defp welcome_eyebrow(%{state: :bootstrap_required}, _current_user), do: "First-Run Setup"
  defp welcome_eyebrow(%{state: :continue_setup}, _current_user), do: "Continue Setup"
  defp welcome_eyebrow(%{state: :invalid_state}, _current_user), do: "Bootstrap Repair Needed"
  defp welcome_eyebrow(%{state: :ready}, nil), do: "Jido Code"
  defp welcome_eyebrow(%{state: :ready}, _current_user), do: "Signed In"

  defp welcome_headline(%{state: :bootstrap_required}, _current_user), do: "Create your admin account"
  defp welcome_headline(%{state: :continue_setup}, _current_user), do: "Sign in to finish onboarding"
  defp welcome_headline(%{state: :invalid_state}, _current_user), do: "The install needs attention"
  defp welcome_headline(%{state: :ready}, nil), do: "Welcome back"
  defp welcome_headline(%{state: :ready}, _current_user), do: "Manage your install"

  defp welcome_description(%{state: :bootstrap_required}, true, _current_user),
    do: "This is a brand-new desktop install. Create the first admin to begin."

  defp welcome_description(%{state: :bootstrap_required}, false, _current_user),
    do: "No accounts exist yet. Create the first admin to begin."

  defp welcome_description(%{state: :continue_setup}, _desktop_runtime?, _current_user),
    do: "An admin account already exists. Sign in to continue."

  defp welcome_description(%{state: :invalid_state}, _desktop_runtime?, _current_user),
    do: "The public bootstrap flow is paused because the local account state is inconsistent."

  defp welcome_description(%{state: :ready}, _desktop_runtime?, nil),
    do: "Sign in to continue."

  defp welcome_description(%{state: :ready}, _desktop_runtime?, _current_user),
    do: "Your install is ready. Review provider login and git integration settings below."

  defp bootstrap_diagnostic(nil), do: "Repair the bootstrap state before continuing."
  defp bootstrap_diagnostic(diagnostic), do: diagnostic

  defp welcome_status_text_class(:pass), do: "text-accent-green"
  defp welcome_status_text_class(:timeout), do: "text-warning/90"
  defp welcome_status_text_class(:fail), do: "text-error"
  defp welcome_status_text_class(_status), do: "text-base-content/62"

  defp welcome_check_text_class(:pass), do: "text-accent-green"
  defp welcome_check_text_class(:timeout), do: "text-warning/90"
  defp welcome_check_text_class(:fail), do: "text-error"
  defp welcome_check_text_class(_status), do: "text-base-content/38"

  defp welcome_input_classes do
    "h-11 w-full rounded-md border border-base-300/70 bg-base-100/20 px-3 text-[15px] text-base-content placeholder:text-base-content/24 transition-colors focus:border-accent-green/60 focus:outline-none disabled:cursor-not-allowed disabled:opacity-45"
  end

  defp welcome_button_classes(:primary) do
    "inline-flex h-11 w-full items-center justify-center gap-2 rounded-md bg-primary px-4 text-[14px] font-medium text-primary-content transition hover:brightness-[1.03] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/45 disabled:cursor-not-allowed disabled:opacity-40"
  end

  defp welcome_button_classes(:secondary) do
    "inline-flex h-11 w-full items-center justify-center gap-2 rounded-md border border-base-300/65 bg-transparent px-4 text-[14px] font-medium text-base-content/82 transition hover:border-base-300 hover:bg-base-100/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-base-content/15"
  end

  defp welcome_button_classes(:warning) do
    "inline-flex h-11 w-full items-center justify-center gap-2 rounded-md bg-warning px-4 text-[14px] font-medium text-warning-content transition hover:brightness-[1.02] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-warning/45"
  end

  defp prerequisite_banner_message(:timeout),
    do: "Some checks timed out. Your system may not be fully ready."

  defp prerequisite_banner_message(_status),
    do: "Some system requirements aren't met yet."

  defp prereq_status_label(:pass), do: "Pass"
  defp prereq_status_label(:fail), do: "Fail"
  defp prereq_status_label(:timeout), do: "Timeout"
  defp prereq_status_label(status), do: status |> to_string() |> String.capitalize()

  defp owner_sign_in_with_token_path(token) do
    strategy = Info.strategy!(User, :password)

    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end

  defp desktop_runtime? do
    System.get_env("BURRITO_TARGET") not in [nil, ""]
  end

  defp refresh_operator_settings(%{assigns: %{current_user: nil}} = socket) do
    assign(socket,
      provider_login_cards: [],
      github_service_report: github_service_report(nil),
      github_service_secret_refs: service_secret_refs()
    )
  end

  defp refresh_operator_settings(socket) do
    assign(socket,
      provider_login_cards: provider_login_cards(),
      github_service_report: github_service_report(socket.assigns[:current_user]),
      github_service_secret_refs: service_secret_refs()
    )
  end

  defp provider_login_cards do
    Enum.map(@provider_catalog, fn provider_definition ->
      config =
        case ProviderConfig.get_by_provider_host(
               provider_definition.provider,
               provider_definition.provider_host,
               authorize?: false
             ) do
          {:ok, %ProviderConfig{} = provider_config} -> provider_config
          _other -> nil
        end

      allowlist_mode =
        (config || %{})
        |> Map.get(:allowlist_mode, :none)
        |> Atom.to_string()

      allowlist_values = Map.get(config || %{}, :allowlist_values, [])

      card =
        Map.merge(provider_definition, %{
          enabled: Map.get(config || %{}, :enabled, false),
          login_enabled: Map.get(config || %{}, :login_enabled, false),
          allowlist_mode: allowlist_mode,
          allowlist_values: allowlist_values,
          allowlist_values_text: Enum.join(allowlist_values, "\n"),
          broker_base_url: Map.get(config || %{}, :broker_base_url, nil),
          broker_issuer: Map.get(config || %{}, :broker_issuer, nil),
          broker_audience: Map.get(config || %{}, :broker_audience, nil)
        })

      card
      |> Map.put(:status, provider_login_status(card))
      |> Map.put(:entrypoint_note, provider_entrypoint_note(card))
    end)
  end

  defp provider_login_status(card) do
    missing_fields =
      []
      |> maybe_add_missing(blank?(card.broker_base_url), "broker base URL")
      |> maybe_add_missing(blank?(card.broker_issuer), "broker issuer")
      |> maybe_add_missing(blank?(card.broker_audience), "broker audience")
      |> maybe_add_missing(card.allowlist_mode != "none" and card.allowlist_values == [], "allowlist values")

    cond do
      not card.enabled ->
        %{
          tone: :muted,
          label: "Disabled",
          detail: "Provider host is disabled. Local email authentication remains the only sign-in path.",
          missing_fields: []
        }

      not card.login_enabled ->
        %{
          tone: :warning,
          label: "Host Enabled",
          detail: "Provider host is configured, but browser sign-in is still turned off.",
          missing_fields: missing_fields
        }

      missing_fields == [] ->
        %{
          tone: :success,
          label: "Ready",
          detail: "Broker trust is configured and this provider host is ready for hosted sign-in.",
          missing_fields: []
        }

      true ->
        %{
          tone: :warning,
          label: "Needs Broker Trust",
          detail: "Provider login is enabled, but broker trust or allowlist details are still incomplete.",
          missing_fields: missing_fields
        }
    end
  end

  defp provider_entrypoint_note(%{provider: :github, enabled: true, login_enabled: true}) do
    "Anonymous visitors can use the GitHub sign-in entrypoint on the landing page when this host stays enabled."
  end

  defp provider_entrypoint_note(%{provider: :github}) do
    "The landing page hides the GitHub sign-in entrypoint until both provider host and browser sign-in are enabled."
  end

  defp provider_entrypoint_note(_card) do
    "The provider login contract is modeled here, but the landing page still exposes only the GitHub browser entrypoint today."
  end

  defp save_provider_login(provider, provider_host, params) do
    ProviderConfig.upsert(
      %{
        provider: provider,
        provider_host: provider_host,
        enabled: truthy?(Map.get(params, "enabled")),
        login_enabled: truthy?(Map.get(params, "login_enabled")),
        allowlist_mode: normalize_allowlist_mode(Map.get(params, "allowlist_mode")),
        allowlist_values: parse_allowlist_values(Map.get(params, "allowlist_values")),
        broker_base_url: normalize_optional_string(Map.get(params, "broker_base_url")),
        broker_issuer: normalize_optional_string(Map.get(params, "broker_issuer")),
        broker_audience: normalize_optional_string(Map.get(params, "broker_audience"))
      },
      authorize?: false
    )
  end

  defp github_service_report(nil) do
    GitHubCredentialChecks.run(nil, nil)
  rescue
    _exception ->
      GitHubCredentialChecks.run(nil, nil)
  end

  defp github_service_report(current_user) do
    owner_context =
      current_user
      |> Map.get(:email)
      |> to_string()

    GitHubCredentialChecks.run(nil, owner_context)
  rescue
    _exception ->
      GitHubCredentialChecks.run(nil, nil)
  end

  defp service_secret_refs do
    ServiceCredentials.service_secret_ref_names()
    |> Enum.sort_by(fn {credential, _secret_ref} -> credential end)
  end

  defp github_service_summary(%{status: :ready, integration_health: integration_health}) do
    "GitHub automation is ready. GitHub App status is #{integration_status_label(integration_health.github_app_status)} with repository access #{repository_access_label(integration_health.github_app_repository_access)}."
  end

  defp github_service_summary(%{integration_health: integration_health}) do
    "GitHub automation is blocked. GitHub App status is #{integration_status_label(integration_health.github_app_status)} and the service path needs operator attention before automation should run."
  end

  defp github_service_summary(_report) do
    "GitHub automation readiness could not be determined."
  end

  defp provider_status_badge_class(:success),
    do:
      "rounded-full border border-success/40 bg-success/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-success"

  defp provider_status_badge_class(:warning),
    do:
      "rounded-full border border-warning/40 bg-warning/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-warning"

  defp provider_status_badge_class(_tone),
    do:
      "rounded-full border border-base-300 bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-base-content/60"

  defp integration_status_badge_class(:ready),
    do:
      "rounded-full border border-success/40 bg-success/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-success"

  defp integration_status_badge_class(:blocked),
    do:
      "rounded-full border border-warning/40 bg-warning/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-warning"

  defp integration_status_badge_class(:invalid),
    do:
      "rounded-full border border-warning/40 bg-warning/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-warning"

  defp integration_status_badge_class(:not_configured),
    do:
      "rounded-full border border-base-300 bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-base-content/60"

  defp integration_status_badge_class(_status),
    do:
      "rounded-full border border-base-300 bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-base-content/60"

  defp integration_status_label(:ready), do: "Ready"
  defp integration_status_label(:blocked), do: "Blocked"
  defp integration_status_label(:invalid), do: "Invalid"
  defp integration_status_label(:not_configured), do: "Not Configured"
  defp integration_status_label(:confirmed), do: "Confirmed"
  defp integration_status_label(:unconfirmed), do: "Unconfirmed"

  defp integration_status_label(status) when is_atom(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp integration_status_label(status), do: status |> to_string() |> String.capitalize()

  defp repository_access_label(:confirmed), do: "Confirmed"
  defp repository_access_label(:unconfirmed), do: "Unconfirmed"
  defp repository_access_label(_status), do: "Unknown"

  defp service_credential_label(:app_id), do: "GitHub App ID"
  defp service_credential_label(:app_private_key), do: "GitHub App Private Key"
  defp service_credential_label(:webhook_secret), do: "GitHub Webhook Secret"
  defp service_credential_label(:pat), do: "PAT Fallback"

  defp service_credential_label(credential),
    do: credential |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp provider_display_name(:github), do: "GitHub"
  defp provider_display_name(:gitlab), do: "GitLab"
  defp provider_display_name(:bitbucket), do: "Bitbucket"

  defp provider_display_name(provider) when is_binary(provider) do
    case normalize_provider(provider) do
      {:ok, normalized_provider} -> provider_display_name(normalized_provider)
      {:error, _message} -> "Provider"
    end
  end

  defp provider_display_name(_provider), do: "Provider"

  defp provider_host_for(provider) do
    case Enum.find(@provider_catalog, fn definition -> definition.provider == provider end) do
      %{provider_host: provider_host} -> {:ok, provider_host}
      nil -> {:error, "Unsupported provider."}
    end
  end

  defp normalize_provider("github"), do: {:ok, :github}
  defp normalize_provider("gitlab"), do: {:ok, :gitlab}
  defp normalize_provider("bitbucket"), do: {:ok, :bitbucket}
  defp normalize_provider(:github), do: {:ok, :github}
  defp normalize_provider(:gitlab), do: {:ok, :gitlab}
  defp normalize_provider(:bitbucket), do: {:ok, :bitbucket}
  defp normalize_provider(_provider), do: {:error, "Unsupported provider."}

  defp normalize_allowlist_mode("users"), do: :users
  defp normalize_allowlist_mode("organizations"), do: :organizations
  defp normalize_allowlist_mode("teams"), do: :teams
  defp normalize_allowlist_mode("groups"), do: :groups
  defp normalize_allowlist_mode("workspaces"), do: :workspaces
  defp normalize_allowlist_mode(_mode), do: :none

  defp parse_allowlist_values(nil), do: []

  defp parse_allowlist_values(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_allowlist_values(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_allowlist_values(_value), do: []

  defp maybe_add_missing(fields, true, value), do: fields ++ [value]
  defp maybe_add_missing(fields, false, _value), do: fields

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp blank?(value), do: normalize_optional_string(value) == nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(_datetime), do: "Not checked"

  defp format_error(error) when is_exception(error), do: Exception.message(error)
  defp format_error(%{errors: errors}) when is_list(errors), do: Enum.map_join(errors, "; ", &inspect/1)
  defp format_error(error), do: inspect(error)

  defp github_login_enabled? do
    if not BootstrapStatus.provider_login_available?() do
      false
    else
      ProviderConfig
      |> Ash.Query.filter(provider == ^:github and provider_host == ^"github.com")
      |> Ash.read_one(domain: AuthProviders, authorize?: false)
      |> case do
        {:ok, %ProviderConfig{enabled: true, login_enabled: true}} -> true
        _other -> false
      end
    end
  end

  defp github_login_path do
    "/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome"
  end
end
