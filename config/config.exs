# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :live_vue, ssr: true

config :phoenix_vite, PhoenixVite.Npm,
  assets: [args: [], cd: Path.expand("..", __DIR__)],
  vite: [
    args: ~w(exec -- vite),
    cd: Path.expand("../assets", __DIR__),
    env: %{"MIX_BUILD_PATH" => Mix.Project.build_path()}
  ]

config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

config :git_hooks,
  auto_install: false,
  project_path: Path.expand("..", __DIR__)

config :jido_code,
  system_config_loader: &JidoCode.Setup.SystemConfigPersistence.load/0,
  system_config_saver: &JidoCode.Setup.SystemConfigPersistence.save/1,
  control_plane_store_path: nil,
  control_plane_store_reset_policy: :bootstrap_if_empty,
  control_plane_store_open_timeout_ms: 5_000,
  mailer: [from_name: "Jido Code"],
  runtime_mode: config_env(),
  # Source-code graph save-triggered refresh defaults are conservative outside dev.
  source_code_graph_file_watcher_enabled: false,
  source_code_graph_file_watcher_debounce_ms: 500,
  source_code_graph_file_watcher_max_pending_paths: 500,
  source_code_graph_auto_refresh_enabled: false,
  source_code_graph_refresh_debounce_ms: 250,
  source_code_graph_refresh_max_coalesce_ms: 2_500,
  source_code_graph_refresh_max_pending_paths: 500,
  source_code_graph_auto_refresh_missing_graph_policy: :skip,
  source_code_graph_auto_refresh_max_attempts: 1

config :jido_code, :code_server,
  data_dir: ".jido",
  conversation_orchestration: true

config :jido_code, :conversation_context_memory,
  enabled?: false,
  provider: :basic,
  store: {Jido.Memory.Store.ETS, [table: :jido_code_prompt_memory]},
  store_opts: [],
  timeout_ms: 250,
  retrieval_limit: 6,
  max_instruction_lines: 6,
  max_instruction_bytes: 2_000,
  ttl_ms: 86_400_000

config :jido_code, :context_budget,
  id: "context-budget:v1",
  history: [
    max_messages: 24,
    token_budget: 8_000
  ],
  tool_output: [
    max_bytes: 10_000,
    max_lines: 500,
    max_results: 1_000
  ]

config :jido_code, :context_management,
  id: "context-management:v1",
  enabled?: true,
  compaction_enabled?: true,
  high_water_mark: 0.80,
  repeated_trim_threshold: 2,
  debounce_window_ms: 300_000,
  max_summary_tokens: 1_000,
  max_candidate_tokens: 4_000

# Configure the endpoint
config :jido_code, JidoCodeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: JidoCodeWeb.ErrorHTML, json: JidoCodeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JidoCode.PubSub,
  live_view: [signing_salt: "W6lKwmK0"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :jido_code, JidoCode.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
