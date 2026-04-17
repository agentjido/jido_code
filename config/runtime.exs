import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/jido_code start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :jido_code, JidoCodeWeb.Endpoint, server: true
end

config :jido_code, JidoCodeWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4100"))]

if config_env() == :prod do
  config :jido_code, JidoCodeWeb.Endpoint,
    cache_static_manifest_latest: PhoenixVite.cache_static_manifest_latest(:jido_code)
end

if secret_ref_encryption_key = System.get_env("JIDO_CODE_SECRET_REF_ENCRYPTION_KEY") do
  config :jido_code, secret_ref_encryption_key: secret_ref_encryption_key
end

llm_provider = System.get_env("JIDO_CODE_LLM_PROVIDER")
llm_model = System.get_env("JIDO_CODE_LLM_MODEL")
llm_model_spec = System.get_env("JIDO_CODE_LLM_MODEL_SPEC")

cond do
  is_binary(llm_provider) and String.trim(llm_provider) != "" and is_binary(llm_model) and
      String.trim(llm_model) != "" ->
    config :jido_code, :llm_selection, %{
      default: %{provider: String.trim(llm_provider), model: String.trim(llm_model)}
    }

  is_binary(llm_model_spec) and String.trim(llm_model_spec) != "" ->
    case String.split(String.trim(llm_model_spec), ":", parts: 2) do
      [provider, model] when provider != "" and model != "" ->
        config :jido_code, :llm_selection, %{default: %{provider: provider, model: model}}

      _other ->
        raise "JIDO_CODE_LLM_MODEL_SPEC must use provider:model format"
    end

  (is_binary(llm_provider) and String.trim(llm_provider) != "") or
      (is_binary(llm_model) and String.trim(llm_model) != "") ->
    raise "Set both JIDO_CODE_LLM_PROVIDER and JIDO_CODE_LLM_MODEL for the system LLM default"

  true ->
    :ok
end

# Source code graph configuration from environment
# These can be set to override defaults for production deployment
if source_code_graph_enabled = System.get_env("SOURCE_CODE_GRAPH_ENABLED") do
  config :jido_code, source_code_graph_enabled: source_code_graph_enabled == "true"
end

if analysis_timeout = System.get_env("SOURCE_CODE_GRAPH_ANALYSIS_TIMEOUT_MS") do
  config :jido_code, source_code_graph_analysis_timeout_ms: String.to_integer(analysis_timeout)
end

if load_timeout = System.get_env("SOURCE_CODE_GRAPH_LOAD_TIMEOUT_MS") do
  config :jido_code, source_code_graph_load_timeout_ms: String.to_integer(load_timeout)
end

if query_timeout = System.get_env("SOURCE_CODE_GRAPH_QUERY_TIMEOUT_MS") do
  config :jido_code, source_code_graph_query_timeout_ms: String.to_integer(query_timeout)
end

# Memory graph configuration from environment
# These can be set to override defaults for production deployment
# Default: memory_graph_enabled is false in production
if memory_graph_enabled = System.get_env("MEMORY_GRAPH_ENABLED") do
  config :jido_code, memory_graph_enabled: memory_graph_enabled == "true"
end

if store_timeout = System.get_env("MEMORY_GRAPH_STORE_TIMEOUT_MS") do
  config :jido_code, memory_graph_store_timeout_ms: String.to_integer(store_timeout)
end

if query_timeout = System.get_env("MEMORY_GRAPH_QUERY_TIMEOUT_MS") do
  config :jido_code, memory_graph_query_timeout_ms: String.to_integer(query_timeout)
end

if validation_timeout = System.get_env("MEMORY_GRAPH_VALIDATION_TIMEOUT_MS") do
  config :jido_code, memory_graph_validation_timeout_ms: String.to_integer(validation_timeout)
end

if recovery_timeout = System.get_env("MEMORY_GRAPH_RECOVERY_TIMEOUT_MS") do
  config :jido_code, memory_graph_recovery_timeout_ms: String.to_integer(recovery_timeout)
end

if max_retries = System.get_env("MEMORY_GRAPH_MAX_RETRIES") do
  config :jido_code, memory_graph_max_retries: String.to_integer(max_retries)
end

if max_write_retries = System.get_env("MEMORY_GRAPH_MAX_WRITE_RETRIES") do
  config :jido_code, memory_graph_max_write_retries: String.to_integer(max_write_retries)
end

if retry_backoff = System.get_env("MEMORY_GRAPH_RETRY_BACKOFF_MS") do
  config :jido_code, memory_graph_retry_backoff_ms: String.to_integer(retry_backoff)
end

if max_graph_size = System.get_env("MEMORY_GRAPH_MAX_GRAPH_SIZE_MB") do
  config :jido_code, memory_graph_max_graph_size_mb: String.to_integer(max_graph_size)
end

if max_query_results = System.get_env("MEMORY_GRAPH_MAX_QUERY_RESULTS") do
  config :jido_code, memory_graph_max_query_results: String.to_integer(max_query_results)
end

if max_concurrent = System.get_env("MEMORY_GRAPH_MAX_CONCURRENT_OPERATIONS") do
  config :jido_code, memory_graph_max_concurrent_operations: String.to_integer(max_concurrent)
end

# Desktop/Burrito mode: when BURRITO_TARGET is set (by Tauri sidecar or manually),
# override prod config for local desktop use. This block runs before the prod
# block below, providing defaults so the raises are never hit.
if config_env() == :prod and System.get_env("BURRITO_TARGET") != nil do
  port = String.to_integer(System.get_env("PORT") || "4100")

  config :jido_code, JidoCode.Repo,
    url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@localhost/jido_code_dev",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  config :jido_code, JidoCodeWeb.Endpoint,
    url: [host: "localhost", port: port, scheme: "http"],
    # Desktop sidecar only needs loopback access from the local webview.
    http: [ip: {127, 0, 0, 1}, port: port],
    secret_key_base:
      System.get_env("SECRET_KEY_BASE") ||
        "j1d0_c0d3_d3skt0p_s3cr3t_k3y_b4s3_th4t_1s_l0ng_3n0ugh_f0r_c00k13_st0r3_v4l1d4t10n_64b",
    server: true,
    check_origin: false,
    force_ssl: [
      rewrite_on: [:x_forwarded_proto],
      exclude: [hosts: ["localhost", "127.0.0.1"], paths: ["/status"]]
    ]

  config :jido_code,
    token_signing_secret: System.get_env("TOKEN_SIGNING_SECRET") || "jido_code_desktop_token_signing_secret"
end

if config_env() == :prod and System.get_env("BURRITO_TARGET") == nil do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :jido_code, JidoCode.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :jido_code, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :jido_code, JidoCodeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: [
      "https://#{host}",
      "https://jidoeboss-prod.fly.dev"
    ],
    force_ssl: [hsts: true, host: host, rewrite_on: [:x_forwarded_proto]],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :jido_code,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :jido_code, JidoCodeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :jido_code, JidoCodeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Using Resend for email delivery in production.
  # Set RESEND_API_KEY and MAILER_FROM_EMAIL in your environment.
  config :jido_code, JidoCode.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: System.get_env("RESEND_API_KEY"),
    from_email: System.get_env("MAILER_FROM_EMAIL", "noreply@example.com")
end
