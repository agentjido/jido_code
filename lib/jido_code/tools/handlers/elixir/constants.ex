defmodule JidoCode.Tools.Handlers.Elixir.Constants do
  @moduledoc """
  Shared constants for Elixir tool handlers.

  This module provides centralized definitions for blocked prefixes and sensitive
  fields used by ProcessState, SupervisorTree, and EtsInspect handlers.
  """

  @doc """
  Returns the shared list of blocked process prefixes.

  System processes and JidoCode internals that should not be inspected.
  """
  @spec blocked_prefixes() :: [String.t()]
  def blocked_prefixes do
    [
      # JidoCode internal processes
      "JidoCode.Tools",
      "JidoCode.Session",
      "JidoCode.Registry",
      "Elixir.JidoCode.Tools",
      "Elixir.JidoCode.Session",
      "Elixir.JidoCode.Registry",
      # Erlang kernel and runtime
      ":kernel",
      ":stdlib",
      ":init",
      ":code_server",
      ":user",
      ":application_controller",
      ":error_logger",
      ":logger",
      # Distribution and networking
      ":global_name_server",
      ":global_group",
      ":net_kernel",
      ":auth",
      ":inet_db",
      ":erl_epmd",
      # Code loading and file system
      ":erl_prim_loader",
      ":file_server_2",
      ":erts_code_purger",
      # Remote execution and signals
      ":rex",
      ":erl_signal_server",
      # SSL/TLS processes
      ":ssl_manager",
      ":ssl_pem_cache",
      # Disk logging
      ":disk_log_server",
      ":disk_log_sup",
      # Standard server processes
      ":standard_error",
      ":standard_error_sup"
    ]
  end

  @doc """
  Returns the shared list of sensitive field names for redaction.
  """
  @spec sensitive_fields() :: [String.t()]
  def sensitive_fields do
    [
      # Authentication
      "password",
      "passwd",
      "pwd",
      "passphrase",
      # Tokens and keys
      "secret",
      "token",
      "api_key",
      "apikey",
      "private_key",
      "secret_key",
      "signing_key",
      "encryption_key",
      # Credentials
      "credentials",
      "auth",
      "bearer",
      "authorization",
      # Session and client secrets
      "session_secret",
      "client_secret",
      "consumer_secret",
      # Database and connection
      "database_url",
      "connection_string",
      "db_password",
      # Cryptographic materials
      "salt",
      "nonce",
      "iv",
      "hmac"
    ]
  end
end
