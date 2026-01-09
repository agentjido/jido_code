defmodule JidoCode.Extensibility.Error do
  @moduledoc """
  Structured error types for the extensibility system.

  Follows the JidoCode.Error pattern for consistency across the codebase.

  ## Error Codes

  Configuration:
  - `:channel_config_invalid` - Channel configuration validation failed
  - `:socket_invalid` - Socket URL is not a valid WebSocket URL
  - `:topic_invalid` - Topic contains invalid characters
  - `:auth_invalid` - Authentication configuration is invalid
  - `:auth_type_invalid` - Auth type is not one of: token, basic, custom
  - `:token_invalid` - Auth token format is invalid
  - `:token_required` - Auth token is required for the given auth type
  - `:broadcast_events_invalid` - Broadcast events list is invalid

  Permissions:
  - `:permissions_invalid` - Permissions configuration validation failed
  - `:pattern_invalid` - Permission pattern has invalid syntax
  - `:permission_denied` - Permission check returned :deny
  - `:field_list_invalid` - Permission field must be a list

  Environment:
  - `:missing_env_var` - Required environment variable is not set

  General:
  - `:validation_failed` - Generic validation failure
  - `:not_found` - Resource not found
  - `:internal_error` - Unexpected internal error

  ## Usage

      error = Error.new(:channel_config_invalid, "socket must be a WebSocket URL")
      #=> %JidoCode.Extensibility.Error{code: :channel_config_invalid, message: "...", details: nil}

      {:error, error}
      #=> {:error, %JidoCode.Extensibility.Error{...}}

  ## Pattern Matching

      case result do
        {:ok, value} -> value
        {:error, %Error{code: :missing_env_var}} -> handle_missing_var()
        {:error, %Error{code: code, message: msg}} -> handle_error(code, msg)
      end
  """

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: map() | nil
        }

  defstruct [:code, :message, :details]

  @doc """
  Creates a new extensibility error.

  ## Parameters

  - `code` - Atom error code
  - `message` - Human-readable error message
  - `details` - Optional map with additional context

  ## Examples

      iex> Error.new(:socket_invalid, "socket must be a valid WebSocket URL (ws:// or wss://)")
      %JidoCode.Extensibility.Error{code: :socket_invalid, message: "socket must be a valid WebSocket URL (ws:// or wss://)", details: nil}

      iex> Error.new(:token_invalid, "Token too short", %{min_length: 20})
      %JidoCode.Extensibility.Error{code: :token_invalid, message: "Token too short", details: %{min_length: 20}}

  """
  @spec new(atom(), String.t(), map() | nil) :: t()
  def new(code, message, details \\ nil) when is_atom(code) and is_binary(message) do
    %__MODULE__{
      code: code,
      message: message,
      details: details
    }
  end

  @doc """
  Creates a validation error for a specific field.

  ## Examples

      iex> Error.validation_failed("channel config", "socket is required")
      %JidoCode.Extensibility.Error{code: :validation_failed, message: "channel config validation failed: socket is required", details: %{field: "channel config"}}

  """
  @spec validation_failed(String.t(), String.t()) :: t()
  def validation_failed(field, reason) do
    new(:validation_failed, "#{field} validation failed: #{reason}", %{field: field})
  end

  @doc """
  Creates a channel configuration error.

  ## Examples

      iex> Error.channel_config_invalid("socket must be a WebSocket URL")
      %JidoCode.Extensibility.Error{code: :channel_config_invalid, message: "socket must be a WebSocket URL", details: %{reason: "socket must be a WebSocket URL"}}

  """
  @spec channel_config_invalid(String.t()) :: t()
  def channel_config_invalid(reason) do
    new(:channel_config_invalid, reason, %{reason: reason})
  end

  @doc """
  Creates a socket validation error.

  ## Examples

      iex> Error.socket_invalid("invalid-url")
      %JidoCode.Extensibility.Error{code: :socket_invalid, message: "socket must be a valid WebSocket URL (ws:// or wss://)", details: nil}

  """
  @spec socket_invalid() :: t()
  def socket_invalid do
    new(:socket_invalid, "socket must be a valid WebSocket URL (ws:// or wss://)")
  end

  @doc """
  Creates a socket empty error.

  """
  @spec socket_empty() :: t()
  def socket_empty do
    new(:socket_invalid, "socket cannot be empty string")
  end

  @doc """
  Creates a topic validation error.

  ## Examples

      iex> Error.topic_required()
      %JidoCode.Extensibility.Error{code: :topic_invalid, message: "topic is required", details: nil}

  """
  @spec topic_required() :: t()
  def topic_required do
    new(:topic_invalid, "topic is required")
  end

  @doc """
  Creates a topic empty error.

  """
  @spec topic_empty() :: t()
  def topic_empty do
    new(:topic_invalid, "topic cannot be empty")
  end

  @doc """
  Creates a topic format error.

  """
  @spec topic_format_invalid() :: t()
  def topic_format_invalid do
    new(
      :topic_invalid,
      "topic must contain only alphanumeric characters, colons, underscores, hyphens, or dots"
    )
  end

  @doc """
  Creates an auth configuration error.

  ## Examples

      iex> Error.auth_type_required()
      %JidoCode.Extensibility.Error{code: :auth_invalid, message: "auth.type is required when auth is provided", details: nil}

  """
  @spec auth_type_required() :: t()
  def auth_type_required do
    new(:auth_invalid, "auth.type is required when auth is provided")
  end

  @doc """
  Creates an auth type invalid error.

  """
  @spec auth_type_invalid(String.t()) :: t()
  def auth_type_invalid(type) do
    new(
      :auth_type_invalid,
      "auth.type must be one of: token, basic, custom. Got: #{type}",
      %{got: type}
    )
  end

  @doc """
  Creates an auth token required error.

  """
  @spec token_required() :: t()
  def token_required do
    new(:token_required, "auth.token is required for token type")
  end

  @doc """
  Creates an auth token invalid error.

  """
  @spec token_invalid(String.t()) :: t()
  def token_invalid(reason) do
    new(:token_invalid, reason, %{reason: reason})
  end

  @doc """
  Creates a basic auth credentials required error.

  """
  @spec basic_credentials_required() :: t()
  def basic_credentials_required do
    new(:auth_invalid, "auth.username and auth.password are required for basic type")
  end

  @doc """
  Creates a broadcast events invalid error.

  """
  @spec broadcast_events_invalid() :: t()
  def broadcast_events_invalid do
    new(:broadcast_events_invalid, "broadcast_events must be a list of non-empty strings")
  end

  @doc """
  Creates a permissions error.

  ## Examples

      iex> Error.permissions_invalid("allow must be a list of strings")
      %JidoCode.Extensibility.Error{code: :permissions_invalid, message: "allow must be a list of strings", details: %{reason: "allow must be a list of strings"}}

  """
  @spec permissions_invalid(String.t()) :: t()
  def permissions_invalid(reason) do
    new(:permissions_invalid, reason, %{reason: reason})
  end

  @doc """
  Creates a permission field list invalid error.

  """
  @spec field_list_invalid(String.t()) :: t()
  def field_list_invalid(field) do
    new(:field_list_invalid, "#{field} must be a list of strings", %{field: field})
  end

  @doc """
  Creates a permission pattern invalid error.

  """
  @spec pattern_invalid(String.t()) :: t()
  def pattern_invalid(reason) do
    new(:pattern_invalid, reason, %{reason: reason})
  end

  @doc """
  Creates a missing environment variable error.

  Note: The error message does NOT include the environment variable value,
  only the variable name, to prevent leakage.

  ## Examples

      iex> Error.missing_env_var("API_TOKEN")
      %JidoCode.Extensibility.Error{code: :missing_env_var, message: "required environment variable not set: API_TOKEN", details: %{var_name: "API_TOKEN"}}

  """
  @spec missing_env_var(String.t()) :: t()
  def missing_env_var(var_name) do
    # Intentionally do NOT include the env var value in the error message
    # to prevent leakage of sensitive values
    new(:missing_env_var, "required environment variable not set: #{var_name}", %{var_name: var_name})
  end

  @doc """
  Wraps an error in a tuple for consistent return values.

  ## Examples

      iex> Error.wrap(:not_found, "Resource not found")
      {:error, %JidoCode.Extensibility.Error{code: :not_found, message: "Resource not found"}}

  """
  @spec wrap(atom(), String.t(), map() | nil) :: {:error, t()}
  def wrap(code, message, details \\ nil) do
    {:error, new(code, message, details)}
  end
end
