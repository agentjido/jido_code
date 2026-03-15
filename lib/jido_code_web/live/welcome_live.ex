defmodule JidoCodeWeb.WelcomeLive do
  use JidoCodeWeb, :live_view

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Setup.OwnerBootstrap
  alias JidoCode.Setup.PrerequisiteChecks
  alias JidoCode.Setup.RuntimeMode
  alias JidoCode.Setup.SystemConfig

  @impl true
  def mount(_params, _session, socket) do
    {onboarding_step, onboarding_state} =
      case SystemConfig.load() do
        {:ok, %SystemConfig{onboarding_completed: true}} ->
          {:redirect, :dashboard}

        {:ok, %SystemConfig{onboarding_step: step}} when step >= 3 ->
          {:redirect, :setup}

        {:ok, %SystemConfig{onboarding_step: step, onboarding_state: state}} ->
          {step, state}

        {:error, _reason} ->
          {1, %{}}
      end

    case onboarding_step do
      :redirect ->
        target = if onboarding_state == :dashboard, do: ~p"/dashboard", else: ~p"/setup"
        {:ok, push_navigate(socket, to: target)}

      step ->
        owner_status = resolve_owner_status()

        socket =
          socket
          |> assign(:onboarding_step, step)
          |> assign(:onboarding_state, onboarding_state)
          |> assign(:prereq_status, :checking)
          |> assign(:prereq_report, nil)
          |> assign(:owner_mode, owner_status.mode)
          |> assign(:owner_email, owner_status.owner_email)
          |> assign(
            :owner_form,
            to_form(%{"email" => owner_status.owner_email || "", "password" => "", "password_confirmation" => ""},
              as: :owner
            )
          )
          |> assign(:save_error, owner_status.error)

        if connected?(socket) do
          send(self(), :run_prereqs)
        end

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.onboarding flash={@flash}>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body space-y-6">
          <%!-- Welcome header --%>
          <div class="text-center">
            <h1 class="text-3xl font-bold">Welcome to Jido Code</h1>
            <p class="mt-2 text-base-content/70">
              Let's get your AI coding assistant set up. This will only take a minute.
            </p>
          </div>

          <%!-- System check section --%>
          <div id="system-check" class="space-y-2">
            <div :if={@prereq_status == :checking} class="flex items-center justify-center gap-2 py-3 text-base-content/60">
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
                <span>
                  {if @prereq_status == :timeout,
                    do: "Some checks timed out. Your system may not be fully ready.",
                    else: "Some system requirements aren't met yet."}
                </span>
              </div>

              <details :if={@prereq_report} class="rounded-lg border border-base-300 bg-base-100 p-3">
                <summary class="cursor-pointer text-sm font-medium text-base-content/80">
                  Show technical details
                </summary>
                <ul class="mt-2 space-y-1 text-sm">
                  <li :for={check <- @prereq_report.checks} class="flex items-start gap-2">
                    <span class={[
                      "badge badge-sm mt-0.5",
                      prereq_badge_class(check.status)
                    ]}>
                      {prereq_status_label(check.status)}
                    </span>
                    <div>
                      <span class="font-medium">{check.name}</span>
                      <span class="text-base-content/60"> —       {check.detail}</span>
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

          <%!-- Registration / Sign-in form --%>
          <div id="owner-form-section" class="space-y-4">
            <div :if={@prereq_status != :pass} class="text-center text-sm text-base-content/50 py-2">
              <.icon name="hero-lock-closed-mini" class="size-4 inline" /> Complete system check first
            </div>

            <div :if={@prereq_status == :pass} class="space-y-4">
              <h2 class="text-lg font-semibold text-center">
                {if @owner_mode == :create,
                  do: "Create your admin account",
                  else: "Welcome back! Sign in to continue setup."}
              </h2>

              <div :if={@save_error} id="welcome-save-error" class="alert alert-error">
                <.icon name="hero-x-circle-mini" class="size-5" />
                <span>{@save_error}</span>
              </div>

              <.form for={@owner_form} id="welcome-owner-form" phx-submit="bootstrap_owner" class="space-y-4">
                <.input
                  field={@owner_form[:email]}
                  type="email"
                  label="Email"
                  required
                  autocomplete="email"
                />
                <div>
                  <.input
                    field={@owner_form[:password]}
                    type="password"
                    label="Password"
                    minlength={if @owner_mode == :create, do: 8, else: nil}
                    required
                    autocomplete="new-password"
                  />
                  <p class="mt-1 text-xs text-base-content/50">Minimum 8 characters</p>
                </div>
                <.input
                  :if={@owner_mode == :create}
                  field={@owner_form[:password_confirmation]}
                  type="password"
                  label="Confirm password"
                  minlength="8"
                  required
                  autocomplete="new-password"
                />
                <button type="submit" class="btn btn-primary btn-block">
                  {if @owner_mode == :create, do: "Create Account & Continue", else: "Sign In & Continue"}
                </button>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.onboarding>
    """
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
  def handle_event("recheck_prereqs", _params, socket) do
    send(self(), :run_prereqs)

    {:noreply,
     socket
     |> assign(:prereq_status, :checking)
     |> assign(:prereq_report, nil)}
  end

  def handle_event("bootstrap_owner", %{"owner" => owner_params}, socket) do
    if socket.assigns.prereq_status != :pass do
      {:noreply, assign(socket, :save_error, "System checks must pass before creating an account.")}
    else
      case OwnerBootstrap.bootstrap(owner_params) do
        {:ok, result} ->
          save_result =
            if socket.assigns.onboarding_step == 1 do
              step_1_state =
                %{
                  "validated_note" => "System prerequisites verified (welcome flow).",
                  "prerequisite_checks" => PrerequisiteChecks.serialize_for_state(socket.assigns.prereq_report)
                }

              case SystemConfig.save_step_progress(step_1_state) do
                {:ok, _config} -> save_step_2(result)
                {:error, %{diagnostic: diagnostic}} -> {:error, diagnostic}
              end
            else
              save_step_2(result)
            end

          case save_result do
            {:ok, _config} ->
              {:noreply,
               socket
               |> assign(:save_error, nil)
               |> redirect(to: owner_sign_in_with_token_path(result.token))}

            {:error, diagnostic} ->
              {:noreply, assign(socket, :save_error, diagnostic)}
          end

        {:error, {_error_type, diagnostic}} ->
          owner_status = resolve_owner_status()

          {:noreply,
           socket
           |> assign(:owner_mode, owner_status.mode)
           |> assign(:owner_email, owner_status.owner_email)
           |> assign(:save_error, diagnostic)
           |> assign(
             :owner_form,
             to_form(
               %{
                 "email" => owner_params["email"] || "",
                 "password" => "",
                 "password_confirmation" => ""
               },
               as: :owner
             )
           )}
      end
    end
  end

  defp save_step_2(result) do
    step_state =
      %{
        "validated_note" => result.validated_note,
        "owner_email" => to_string(result.owner.email),
        "owner_mode" => Atom.to_string(result.owner_mode)
      }
      |> maybe_mark_registration_lockout()

    case SystemConfig.save_step_progress(step_state) do
      {:ok, config} -> {:ok, config}
      {:error, %{diagnostic: diagnostic}} -> {:error, diagnostic}
    end
  end

  defp resolve_owner_status do
    case OwnerBootstrap.status() do
      {:ok, %{mode: :create}} ->
        %{mode: :create, owner_email: nil, error: nil}

      {:ok, %{mode: :confirm, owner: owner}} ->
        %{mode: :confirm, owner_email: to_string(owner.email), error: nil}

      {:error, {_error_type, diagnostic}} ->
        %{mode: :create, owner_email: nil, error: diagnostic}
    end
  end

  defp maybe_mark_registration_lockout(step_state) do
    if RuntimeMode.production?() do
      Map.put(step_state, "registration_actions_disabled", true)
    else
      step_state
    end
  end

  defp owner_sign_in_with_token_path(token) do
    strategy = Info.strategy!(User, :password)

    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _ -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})

    "#{path}?#{query}"
  end

  defp prereq_badge_class(:pass), do: "badge-success"
  defp prereq_badge_class(:fail), do: "badge-error"
  defp prereq_badge_class(:timeout), do: "badge-warning"
  defp prereq_badge_class(_), do: "badge-ghost"

  defp prereq_status_label(:pass), do: "Pass"
  defp prereq_status_label(:fail), do: "Fail"
  defp prereq_status_label(:timeout), do: "Timeout"
  defp prereq_status_label(_), do: "Unknown"
end
