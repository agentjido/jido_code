import Config
config :live_vue, ssr: false, enable_props_diff: false
config :jido_code, token_signing_secret: "HzvQA7aDEqgO64zKrIKG0mZWQ1bIBZLQ"
config :jido_code, secret_ref_encryption_key: "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="
config :bcrypt_elixir, log_rounds: 1

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :jido_code, JidoCodeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "a4QGmxFAnlnqwKUFp79OE/prjOWIbcL4d0ydTDHj3XH9fRKN1VxSI3oy2+6pxRUQ",
  server: false

# In test we don't send emails
config :jido_code, JidoCode.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Use in-memory SystemConfig for tests (no DB persistence)
config :jido_code,
  system_config_loader: &JidoCode.Setup.SystemConfig.default_loader/0,
  system_config_saver: &JidoCode.Setup.SystemConfig.default_saver/1,
  control_plane_store_path: nil,
  control_plane_store_reset_policy: :reset_on_start,
  control_plane_store_open_timeout_ms: 5_000

config :jido_code,
  source_code_graph_file_watcher_enabled: false,
  source_code_graph_file_watcher_debounce_ms: 5,
  source_code_graph_file_watcher_max_pending_paths: 100,
  source_code_graph_auto_refresh_enabled: false,
  source_code_graph_refresh_debounce_ms: 5,
  source_code_graph_refresh_max_coalesce_ms: 50,
  source_code_graph_refresh_max_pending_paths: 100,
  source_code_graph_auto_refresh_missing_graph_policy: :skip,
  source_code_graph_auto_refresh_max_attempts: 1

config :jido_code, :llm_selection, %{default: %{provider: "deterministic", model: "deterministic"}}

# Ontology configuration (optional - requires elixir_ontologies package)
config :jido_code, :ontology_enabled, false

# AgentOS configuration for testing
config :jido_code,
  agent_os_kernel_supervisor: JidoCode.AgentOS.Manager.Supervisor,
  agent_os_registry: JidoCode.AgentOS.Manager.Registry,
  agent_workspace_specialist_runner: JidoCode.AgentWorkspace.DeterministicSpecialistRunner
