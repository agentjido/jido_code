defmodule JidoCodeWeb.Router do
  # covers: baseline.surface.public_entry_routes
  # covers: baseline.surface.product_routes_declared
  # covers: baseline.surface.root_redirects_to_welcome
  use JidoCodeWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {JidoCodeWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:load_from_session)
    plug(JidoCodeWeb.Plugs.PublicBootstrapAuthGate)
  end

  pipeline :api do
    plug(:accepts, ["json"])

    plug(AshAuthentication.Strategy.ApiKey.Plug,
      resource: JidoCode.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false
    )

    plug(:load_from_bearer)
    plug(:set_actor, :user)
  end

  pipeline :github_webhook do
    plug(:accepts, ["json"])
  end

  scope "/", JidoCodeWeb do
    pipe_through(:browser)

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{JidoCodeWeb.LiveUserAuth, :live_user_required}] do
      live("/dashboard", DashboardLive, :index)
      live("/workbench", WorkbenchLive, :index)
      live("/workflows", WorkflowsLive, :index)
      live("/agents", AgentsLive, :index)
      live("/repos", ProjectInventoryLive, :index)
      live("/repos/:id", ProjectDetailLive, :show)
      live("/repos/:id/runs/:run_id", RunDetailLive, :show)
      live("/settings", SettingsLive, :index)
      live("/settings/:tab", SettingsLive, :index)

      live("/forge", Forge.IndexLive, :index)
      live("/forge/new", Forge.NewLive, :new)
      live("/forge/:session_id", Forge.ShowLive, :show)

      live("/folio", FolioLive, :index)

      live("/demos/chat", Demos.ChatLive, :index)
    end
  end

  scope "/api", JidoCodeWeb do
    pipe_through(:github_webhook)

    post("/github/webhooks", GitHubWebhookController, :create)
  end

  scope "/api/json" do
    pipe_through([:api])

    forward("/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4
    )

    forward("/", JidoCodeWeb.AshJsonApiRouter)
  end

  scope "/", JidoCodeWeb do
    pipe_through(:browser)

    get("/auth/providers/:provider/start", ProviderAuthController, :start)
    get("/auth/providers/:provider/complete", ProviderAuthController, :complete)

    ash_authentication_live_session :public_routes,
      on_mount: [{JidoCodeWeb.LiveUserAuth, :live_user_optional}] do
      live("/welcome", HomeLive, :index)
      live("/setup", SetupLive, :index)
    end

    get("/", PageController, :home)
    get("/register", PageController, :register_redirect)

    auth_routes(AuthController, JidoCode.Accounts.User, path: "/auth")
    sign_out_route(AuthController)

    # Remove these if you'd like to use your own authentication views
    sign_in_route(
      reset_path: "/reset",
      auth_routes_prefix: "/auth",
      on_mount: [{JidoCodeWeb.LiveUserAuth, :live_no_user}],
      overrides: [
        JidoCodeWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )

    # Remove this if you do not want to use the reset password feature
    reset_route(
      auth_routes_prefix: "/auth",
      overrides: [
        JidoCodeWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )

    # Remove this if you do not use the confirmation strategy
    confirm_route(JidoCode.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [JidoCodeWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(JidoCode.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [JidoCodeWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
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

  if Application.compile_env(:jido_code, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through(:browser)

      ash_admin("/")
    end
  end
end
