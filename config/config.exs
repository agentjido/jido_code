# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# General application configuration
config :jido_code,
  # PubSub configuration
  pubsub: [name: JidoCode.PubSub, adapter: Phoenix.PubSub.PG2]

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :agent]

# Import environment specific config
import_config "#{config_env()}.exs"
