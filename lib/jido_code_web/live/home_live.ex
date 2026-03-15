defmodule JidoCodeWeb.HomeLive do
  # covers: auth.provider_login_flow.entrypoint_visible
  # covers: auth.provider_login_flow.local_auth_fallback_visible
  use JidoCodeWeb, :live_view

  require Ash.Query

  alias JidoCode.AuthProviders
  alias JidoCode.AuthProviders.ProviderConfig

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       github_login_path: github_login_path(),
       github_login_enabled?: github_login_enabled?()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-base-200 via-base-100 to-base-200">
      <div class="mx-auto flex min-h-screen w-full max-w-4xl items-center justify-center px-6 py-16">
        <div class="w-full max-w-xl">
          <div class="space-y-6 rounded-3xl border border-base-300 bg-base-100 p-10 shadow-2xl">
            <div class="space-y-3 text-center">
              <%!-- covers: baseline.surface.welcome_landing_copy --%>
              <p class="text-xs font-bold uppercase tracking-[0.24em] text-base-content/50">
                Spec Led Baseline
              </p>
              <h1 class="text-4xl font-bold text-base-content">Welcome to Jido Code</h1>
              <p class="text-base leading-7 text-base-content/70">
                The application is intentionally trimmed to a minimal landing page plus authentication while the baseline is being re-established.
              </p>
            </div>

            <%!-- covers: baseline.surface.auth_entrypoints_visible --%>
            <div class="space-y-4">
              <%= if @current_user do %>
                <div class="rounded-2xl border border-success/30 bg-success/10 p-4 text-center">
                  <p class="text-sm uppercase tracking-[0.16em] text-success">Signed In</p>
                  <p class="mt-2 text-lg font-semibold text-base-content">{@current_user.email}</p>
                </div>

                <div class="grid gap-3">
                  <a href="/sign-out" class="btn btn-primary btn-block">Sign Out</a>
                </div>
              <% else %>
                <div class="grid gap-3 sm:grid-cols-2">
                  <a href="/sign-in" class="btn btn-primary btn-block">Sign In</a>
                  <a href="/register" class="btn btn-outline btn-block">Create Account</a>
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

            <div class="rounded-2xl border border-dashed border-base-300 bg-base-200/60 p-4 text-sm text-base-content/60">
              Product routes, demos, setup flows, APIs, and workbench surfaces are commented out until the new spec-led baseline is validated.
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp github_login_enabled? do
    ProviderConfig
    |> Ash.Query.filter(provider == ^:github and provider_host == ^"github.com")
    |> Ash.read_one(domain: AuthProviders, authorize?: false)
    |> case do
      {:ok, %ProviderConfig{enabled: true, login_enabled: true}} -> true
      _other -> false
    end
  end

  defp github_login_path do
    "/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome"
  end
end
