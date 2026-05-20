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

config :ash_json_api,
  show_public_calculations_when_loaded?: false,
  authorize_update_destroy_with_error?: true

config :git_hooks,
  auto_install: false,
  project_path: Path.expand("..", __DIR__)

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :json_api,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [
        :admin,
        :json_api,
        :resources,
        :policies,
        :authorization,
        :domain,
        :execution
      ]
    ]
  ]

config :jido_code,
  ecto_repos: [JidoCode.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    JidoCode.Accounts,
    JidoCode.AuthProviders,
    JidoCode.GitHub,
    JidoCode.Projects,
    JidoCode.Conversations,
    JidoCode.Control,
    JidoCode.Governance,
    JidoCode.Operations,
    JidoCode.Orchestration,
    JidoCode.Forge.Domain,
    JidoCode.Security,
    JidoCode.Setup
  ],
  # covers: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
  system_config_loader: &JidoCode.Setup.SystemConfigPersistence.load/0,
  system_config_saver: &JidoCode.Setup.SystemConfigPersistence.save/1,
  ash_authentication: [return_error_on_invalid_magic_link_token?: true],
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
