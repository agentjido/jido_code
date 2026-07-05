defmodule JidoCodeWeb.Router do
  # covers: baseline.surface.public_entry_routes
  # covers: baseline.surface.product_routes_declared
  # covers: baseline.surface.root_redirects_to_welcome
  use JidoCodeWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {JidoCodeWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(JidoCodeWeb.Plugs.PublicBootstrapAuthGate)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :github_webhook do
    plug(:accepts, ["json"])
  end

  scope "/", JidoCodeWeb do
    pipe_through(:browser)

    live_session :authenticated_routes,
      on_mount: [{JidoCodeWeb.LiveUserAuth, :live_user_required}] do
      live("/dashboard", DashboardLive, :index)
      live("/workbench", WorkbenchLive, :index)
      live("/workflows", WorkflowsLive, :index)
      live("/agents", AgentsLive, :index)
      live("/repos", ProjectInventoryLive, :index)
      live("/repos/:id", ProjectDetailLive, :show)
      live("/repos/:id/runs/:run_id", RunDetailLive, :show)
      live("/repos/:id/work-items/:work_item_id", WorkItemDetailLive, :show)
      live("/repos/:id/evidence/:evidence_id", EvidenceDetailLive, :show)
      live("/repos/:id/decisions/:decision_id", DecisionDetailLive, :show)
      live("/settings", SettingsLive, :index)
      live("/settings/:tab", SettingsLive, :index)
    end
  end

  scope "/api", JidoCodeWeb do
    pipe_through(:github_webhook)

    post("/github/webhooks", GitHubWebhookController, :create)
  end

  scope "/", JidoCodeWeb do
    pipe_through(:browser)

    get("/auth/providers/:provider/start", ProviderAuthController, :start)
    get("/auth/providers/:provider/complete", ProviderAuthController, :complete)
    get("/auth/setup/owner/sign-in", SetupAuthController, :sign_in)

    live_session :public_routes,
      on_mount: [{JidoCodeWeb.LiveUserAuth, :live_user_optional}] do
      live("/welcome", HomeLive, :index)
      live("/setup", SetupLive, :index)
    end

    get("/", PageController, :home)
    get("/register", PageController, :register_redirect)
    get("/sign-in", PageController, :home)
    get("/sign-out", AuthController, :sign_out)
    delete("/sign-out", AuthController, :sign_out)
  end

  if Mix.env() == :test do
    scope "/_test", JidoCodeWeb do
      pipe_through(:browser)

      get("/browser/scenario", TestBrowserScenarioController, :update)
      get("/browser/sign-in", TestBrowserSessionController, :create)
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", JidoCodeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jido_code, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: JidoCodeWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
