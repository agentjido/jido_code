import Config
config :jido_code, token_signing_secret: "HzvQA7aDEqgO64zKrIKG0mZWQ1bIBZLQ"
config :jido_code, secret_ref_encryption_key: "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :jido_code, JidoCode.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "jido_code_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

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
  system_config_saver: &JidoCode.Setup.SystemConfig.default_saver/1

config :jido_code_server, :llm_adapter, :deterministic
