defmodule JidoCodeWeb.HomeLive do
  # covers: baseline.surface.auth_entrypoints_visible
  # covers: baseline.surface.welcome_surface_consolidated
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.registration_guardrails
  # covers: setup.onboarding.deployment_mode_auto_detected
  # covers: auth.provider_login_flow.entrypoint_visible
  # covers: auth.provider_login_flow.local_auth_fallback_visible
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
  alias JidoCode.Setup.BootstrapStatus
  alias JidoCode.Setup.DeploymentMode
  alias JidoCode.Setup.OwnerBootstrap
  alias JidoCode.Setup.OwnerRecovery
  alias JidoCode.Setup.PrerequisiteChecks
  alias JidoCode.Setup.SystemConfig

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
        |> assign(:deployment_mode, DeploymentMode.current())
        |> assign(:prereq_status, initial_prereq_status(bootstrap_status))
        |> assign(:prereq_report, nil)
        |> assign(:owner_mode, owner_status.mode)
        |> assign(:owner_email, owner_status.owner_email)
        |> assign(:owner_form, build_owner_form(owner_status.owner_email))
        |> assign(:owner_recovery_form, build_recovery_form(owner_status.owner_email))
        |> assign(:save_error, owner_status.error || bootstrap_status.diagnostic)
        |> assign(
          github_login_path: github_login_path(),
          github_login_enabled?: github_login_enabled?()
        )

      if connected?(socket) && bootstrap_status.state == :bootstrap_required do
        send(self(), :run_prereqs)
      end

      {:ok, socket}
    end
  end

  @impl true
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
    <div class="min-h-screen bg-gradient-to-br from-base-200 via-base-100 to-base-200">
      <div class={[
        "mx-auto flex w-full px-6",
        (@bootstrap_status.state == :ready and @current_user) && "max-w-6xl py-12",
        (@bootstrap_status.state != :ready or !@current_user) && "min-h-screen max-w-4xl items-center justify-center py-16"
      ]}>
        <div class={["w-full", (@bootstrap_status.state != :ready or !@current_user) && "max-w-xl"]}>
          <%= case @bootstrap_status.state do %>
            <% :bootstrap_required -> %>
              <div class="space-y-6 rounded-3xl border border-base-300 bg-base-100 p-10 shadow-2xl">
                <div class="space-y-3 text-center">
                  <p class="text-xs font-bold uppercase tracking-[0.24em] text-base-content/50">
                    First-Run Setup
                  </p>
                  <h1 class="text-4xl font-bold text-base-content">Create your admin account</h1>
                  <p class="text-base leading-7 text-base-content/70">
                    {bootstrap_intro_copy(@deployment_mode)}
                  </p>
                </div>

                <div id="system-check" class="space-y-2">
                  <div
                    :if={@prereq_status == :checking}
                    class="flex items-center justify-center gap-2 py-3 text-base-content/60"
                  >
                    <.icon name="hero-arrow-path" class="size-5 animate-spin" />
                    <span>Checking your system…</span>
                  </div>

                  <div :if={@prereq_status == :pass} class="flex items-center justify-center gap-2 py-2">
                    <span class="badge badge-success gap-1">
                      <.icon name="hero-check-circle-mini" class="size-4" /> System ready
                    </span>
                  </div>

                  <div :if={@prereq_status in [:fail, :timeout]} class="space-y-2">
                    <div class={[
                      "alert",
                      if(@prereq_status == :timeout, do: "alert-warning", else: "alert-error")
                    ]}>
                      <.icon name="hero-exclamation-triangle-mini" class="size-5" />
                      <span>{prerequisite_banner_message(@prereq_status)}</span>
                    </div>

                    <details :if={@prereq_report} class="rounded-lg border border-base-300 bg-base-100 p-3">
                      <summary class="cursor-pointer text-sm font-medium text-base-content/80">
                        Show technical details
                      </summary>
                      <ul class="mt-2 space-y-1 text-sm">
                        <li :for={check <- @prereq_report.checks} class="flex items-start gap-2">
                          <span class={["badge badge-sm mt-0.5", prereq_badge_class(check.status)]}>
                            {prereq_status_label(check.status)}
                          </span>
                          <div>
                            <span class="font-medium">{check.name}</span>
                            <span class="text-base-content/60">{[" — ", check.detail]}</span>
                            <p :if={check.status != :pass} class="text-warning text-xs">
                              {check.remediation}
                            </p>
                          </div>
                        </li>
                      </ul>
                    </details>

                    <div class="flex justify-center">
                      <button phx-click="recheck_prereqs" class="btn btn-sm btn-outline">
                        <.icon name="hero-arrow-path-mini" class="size-4" /> Re-check
                      </button>
                    </div>
                  </div>
                </div>

                <div :if={@save_error} id="welcome-save-error" class="alert alert-error">
                  <.icon name="hero-x-circle-mini" class="size-5" />
                  <span>{@save_error}</span>
                </div>

                <div id="owner-form-section" class="space-y-4">
                  <div :if={@prereq_status != :pass} class="text-center text-sm text-base-content/50 py-2">
                    <.icon name="hero-lock-closed-mini" class="size-4 inline" /> Complete system check first
                  </div>

                  <div :if={@prereq_status == :pass} class="space-y-4">
                    <.form for={@owner_form} id="welcome-owner-form" phx-submit="bootstrap_owner" class="space-y-4">
                      <.input field={@owner_form[:email]} type="email" label="Email" required autocomplete="email" />
                      <div>
                        <.input
                          field={@owner_form[:password]}
                          type="password"
                          label="Password"
                          minlength="8"
                          required
                          autocomplete="new-password"
                        />
                        <p class="mt-1 text-xs text-base-content/50">Minimum 8 characters</p>
                      </div>
                      <.input
                        field={@owner_form[:password_confirmation]}
                        type="password"
                        label="Confirm password"
                        minlength="8"
                        required
                        autocomplete="new-password"
                      />
                      <button type="submit" class="btn btn-primary btn-block">
                        Create Account & Continue
                      </button>
                    </.form>
                  </div>
                </div>
              </div>
            <% :continue_setup -> %>
              <div class="space-y-6 rounded-3xl border border-base-300 bg-base-100 p-10 shadow-2xl">
                <div class="space-y-3 text-center">
                  <p class="text-xs font-bold uppercase tracking-[0.24em] text-base-content/50">
                    Continue Setup
                  </p>
                  <h1 class="text-4xl font-bold text-base-content">Sign in to finish onboarding</h1>
                  <p class="text-base leading-7 text-base-content/70">
                    Use the existing admin account to continue setup. Public account creation is closed after the first install.
                  </p>
                </div>

                <div class="rounded-2xl border border-base-300 bg-base-200/60 p-4 text-center text-sm text-base-content/70">
                  Existing admin: <span class="font-semibold text-base-content">{@owner_email || "Unavailable"}</span>
                </div>

                <div :if={@save_error} id="welcome-save-error" class="alert alert-error">
                  <.icon name="hero-x-circle-mini" class="size-5" />
                  <span>{@save_error}</span>
                </div>

                <.form for={@owner_form} id="continue-setup-owner-form" phx-submit="bootstrap_owner" class="space-y-4">
                  <.input field={@owner_form[:email]} type="email" label="Email" required autocomplete="email" />
                  <.input
                    field={@owner_form[:password]}
                    type="password"
                    label="Admin password"
                    required
                    autocomplete="current-password"
                  />
                  <button type="submit" class="btn btn-primary btn-block">
                    Sign In & Continue
                  </button>
                </.form>

                <div class="rounded-2xl border border-warning/30 bg-warning/10 p-5">
                  <h2 class="text-lg font-semibold text-base-content">Need to recover access?</h2>
                  <p class="mt-2 text-sm leading-6 text-base-content/75">
                    Recovery is only for the existing bootstrap admin and requires explicit verification before credentials are changed.
                  </p>

                  <.form
                    for={@owner_recovery_form}
                    id="continue-setup-recovery-form"
                    phx-submit="recover_owner"
                    class="mt-4 space-y-4"
                  >
                    <.input field={@owner_recovery_form[:email]} type="email" label="Admin email" required />
                    <.input
                      field={@owner_recovery_form[:password]}
                      type="password"
                      label="New password"
                      required
                      minlength="8"
                    />
                    <.input
                      field={@owner_recovery_form[:password_confirmation]}
                      type="password"
                      label="Confirm new password"
                      required
                      minlength="8"
                    />
                    <.input
                      field={@owner_recovery_form[:verification_phrase]}
                      type="text"
                      label="Verification phrase"
                      required
                      value={OwnerRecovery.verification_phrase()}
                    />
                    <.input
                      field={@owner_recovery_form[:verification_ack]}
                      type="checkbox"
                      label="I understand this resets the existing bootstrap admin credentials"
                    />
                    <button type="submit" class="btn btn-warning btn-block">
                      Recover Admin Access
                    </button>
                  </.form>
                </div>
              </div>
            <% :invalid_state -> %>
              <div class="space-y-6 rounded-3xl border border-error/30 bg-base-100 p-10 shadow-2xl">
                <div class="space-y-3 text-center">
                  <p class="text-xs font-bold uppercase tracking-[0.24em] text-error/80">
                    Bootstrap Repair Needed
                  </p>
                  <h1 class="text-4xl font-bold text-base-content">The install needs attention</h1>
                  <p class="text-base leading-7 text-base-content/70">
                    The public bootstrap flow is paused because the local account state is inconsistent.
                  </p>
                </div>

                <div id="welcome-save-error" class="alert alert-error">
                  <.icon name="hero-x-circle-mini" class="size-5" />
                  <span>{@save_error || "Repair the bootstrap state before continuing."}</span>
                </div>
              </div>
            <% :ready -> %>
              <div class="space-y-6 rounded-3xl border border-base-300 bg-base-100 p-10 shadow-2xl">
                <div class="space-y-3 text-center">
                  <%!-- covers: baseline.surface.welcome_landing_copy --%>
                  <p class="text-xs font-bold uppercase tracking-[0.24em] text-base-content/50">
                    {if @current_user, do: "Ready", else: "Bootstrap Complete"}
                  </p>
                  <h1 class="text-4xl font-bold text-base-content">Welcome to Jido Code</h1>
                  <p class="text-base leading-7 text-base-content/70">
                    {if(@current_user,
                      do: ready_signed_in_intro_copy(@deployment_mode),
                      else: ready_intro_copy(@deployment_mode)
                    )}
                  </p>
                </div>

                <div class="space-y-4">
                  <%= if @current_user do %>
                    <div class="rounded-2xl border border-success/30 bg-success/10 p-5 text-left">
                      <p class="text-sm uppercase tracking-[0.16em] text-success">Signed In</p>
                      <p class="mt-2 text-lg font-semibold text-base-content">{@current_user.email}</p>
                      <p class="mt-3 text-sm leading-6 text-base-content/75">
                        Bootstrap is complete. Use dashboard for normal product work, and use settings when you need to manage provider login or deployment-local Git automation.
                      </p>
                    </div>

                    <div class="grid gap-3 sm:grid-cols-2">
                      <.link id="welcome-open-dashboard" navigate={~p"/dashboard"} class="btn btn-primary btn-block">
                        Open Dashboard
                      </.link>
                      <.link id="welcome-open-settings" navigate={~p"/settings/auth"} class="btn btn-outline btn-block">
                        Open Auth & Integrations
                      </.link>
                    </div>

                    <div class="grid gap-3">
                      <a href="/sign-out" class="btn btn-ghost btn-block">Sign Out</a>
                    </div>

                    <div
                      id="welcome-ready-handoff-note"
                      class="rounded-2xl border border-base-300 bg-base-200/60 p-4 text-left text-sm text-base-content/70"
                    >
                      Local email auth remains the fallback path even when hosted provider sign-in is enabled. Dashboard is the default authenticated entry, and Settings owns durable provider and Git integration management.
                    </div>
                  <% else %>
                    <div class="grid gap-3">
                      <a href="/sign-in" class="btn btn-primary btn-block">Sign In</a>
                    </div>

                    <%= if @github_login_enabled? do %>
                      <div class="grid gap-3">
                        <a href={@github_login_path} class="btn btn-neutral btn-block">
                          Sign In with GitHub
                        </a>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
          <% end %>
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

  defp bootstrap_intro_copy(:desktop),
    do:
      "This is a brand-new desktop install. We’ll verify the local runtime, create your first admin account, and then continue into setup."

  defp bootstrap_intro_copy(_deployment_mode),
    do:
      "This is a brand-new install. We’ll verify the runtime, create the first admin account, and then continue into the rest of setup."

  defp ready_intro_copy(:desktop),
    do:
      "Sign in to this desktop install. The first-run bootstrap is complete, and public account creation is now disabled."

  defp ready_intro_copy(_deployment_mode),
    do: "Sign in to this install. The first-run bootstrap is complete, and public account creation is now disabled."

  defp ready_signed_in_intro_copy(:desktop),
    do:
      "This desktop install is ready. Continue into dashboard for product work, and use settings when you need auth or Git integration management."

  defp ready_signed_in_intro_copy(_deployment_mode),
    do:
      "This install is ready. Continue into dashboard for product work, and use settings when you need auth or Git integration management."

  defp prerequisite_banner_message(:timeout),
    do: "Some checks timed out. Your system may not be fully ready."

  defp prerequisite_banner_message(_status),
    do: "Some system requirements aren't met yet."

  defp prereq_badge_class(:pass), do: "badge-success"
  defp prereq_badge_class(:fail), do: "badge-error"
  defp prereq_badge_class(:timeout), do: "badge-warning"
  defp prereq_badge_class(_status), do: "badge-neutral"

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
    "/auth/providers/github/start?provider_host=github.com"
  end
end
