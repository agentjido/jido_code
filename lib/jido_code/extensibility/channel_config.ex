defmodule JidoCode.Extensibility.ChannelConfig do
  @moduledoc """
  Configuration for Phoenix channel connections in the extensibility system.

  ## Fields

  - `:socket` - WebSocket URL (e.g., "ws://localhost:4000/socket")
  - `:topic` - Channel topic (e.g., "jido:agent")
  - `:auth` - Authentication configuration map
  - `:broadcast_events` - List of events to broadcast on this channel

  ## Examples

      # Default UI state channel
      %ChannelConfig{
        socket: "ws://localhost:4000/socket",
        topic: "jido:ui",
        auth: nil,
        broadcast_events: ["state_change", "progress", "error"]
      }

      # Channel with token authentication
      %ChannelConfig{
        socket: "wss://example.com/socket",
        topic: "jido:agent",
        auth: %{
          "type" => "token",
          "token" => "${JIDO_CHANNEL_TOKEN:-default_token}"
        },
        broadcast_events: nil
      }

  ## Environment Variable Expansion

  Auth tokens support environment variable expansion:

      ${VAR_NAME}         - Expand variable, error if not set
      ${VAR:-default}     - Expand variable, use default if not set

  ## Validation

  Use `validate/1` to ensure configuration is valid:

      {:ok, config} = ChannelConfig.validate(%{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido:ui"
      })
  """

  alias JidoCode.Extensibility.Error

  # Module attributes for validation constants
  @valid_auth_types ~w(token basic custom)
  @valid_socket_schemes ~w(ws wss)
  @topic_regex ~r/^[a-zA-Z0-9:_\-\.]+$/

  defstruct [:socket, :topic, :auth, :broadcast_events]

  @typedoc """
  Channel configuration struct.

  ## Fields

  - `:socket` - WebSocket URL (e.g., "ws://localhost:4000/socket")
  - `:topic` - Channel topic (e.g., "jido:agent")
  - `:auth` - Authentication configuration map
  - `:broadcast_events` - List of events to broadcast on this channel
  """
  @type t :: %__MODULE__{
          socket: String.t() | nil,
          topic: String.t() | nil,
          auth: map() | nil,
          broadcast_events: [String.t()] | nil
        }

  @typedoc """
  Authentication configuration map.

  Supported types:
  - `token`: Bearer token or JWT
  - `basic`: Basic auth with username/password
  - `custom`: Custom authentication scheme
  """
  @type auth_config :: %{
          String.t() => String.t() | nil
        }

  @typedoc """
  Broadcast events list (nil means use defaults)
  """
  @type broadcast_events :: [String.t()] | nil

  @doc """
  Validates a channel configuration map.

  ## Parameters

  - `config` - Map with channel configuration keys

  ## Returns

  - `{:ok, ChannelConfig.t()}` - Valid configuration
  - `{:error, %Error{}}` - Validation error with structured error

  ## Examples

      iex> ChannelConfig.validate(%{
      ...>   "socket" => "ws://localhost:4000/socket",
      ...>   "topic" => "jido:ui"
      ...> })
      {:ok, %ChannelConfig{socket: "ws://localhost:4000/socket", topic: "jido:ui", auth: nil, broadcast_events: nil}}

      iex> ChannelConfig.validate(%{"socket" => "invalid-url"})
      {:error, %JidoCode.Extensibility.Error{code: :socket_invalid, message: "socket must be a valid WebSocket URL (ws:// or wss://)", details: nil}}

  """
  @spec validate(map()) :: {:ok, t()} | {:error, Error.t()}
  def validate(config) when is_map(config) do
    with :ok <- validate_socket(Map.get(config, "socket")),
         :ok <- validate_topic(Map.get(config, "topic")),
         :ok <- validate_auth(Map.get(config, "auth")),
         :ok <- validate_broadcast_events(Map.get(config, "broadcast_events")) do
      # Convert string keys to atoms for struct
      atom_config = convert_to_atom_keys(config)

      config_struct = struct(__MODULE__, atom_config)

      # Expand environment variables in auth
      auth = maybe_expand_auth(config_struct.auth)

      {:ok, %__MODULE__{config_struct | auth: auth}}
    end
  end

  @doc """
  Expands environment variables in a configuration value.

  Supports two syntaxes:
  - `${VAR_NAME}` - Expand variable, error if not set
  - `${VAR:-default}` - Expand variable, use default if not set

  ## Parameters

  - `value` - String potentially containing environment variables

  ## Returns

  - `{:ok, expanded}` - Successfully expanded string
  - `{:error, %Error{}}` - Missing required environment variable

  ## Examples

      iex> System.put_env("TEST_VAR", "value")
      iex> ChannelConfig.expand_env_vars("${TEST_VAR}")
      {:ok, "value"}

      iex> ChannelConfig.expand_env_vars("${MISSING:-default}")
      {:ok, "default"}

      iex> ChannelConfig.expand_env_vars("no_vars")
      {:ok, "no_vars"}

      iex> ChannelConfig.expand_env_vars("${MISSING_REQUIRED}")
      {:error, %JidoCode.Extensibility.Error{code: :missing_env_var, message: "required environment variable not set: MISSING_REQUIRED", details: %{var_name: "MISSING_REQUIRED"}}}

  """
  @spec expand_env_vars(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def expand_env_vars(value) when is_binary(value) do
    try do
      expanded = do_expand_env_vars(value)
      {:ok, expanded}
    rescue
      e in RuntimeError ->
        # Extract var_name from the error message or use a safe default
        # The error message format is: "environment variable VAR_NAME is not set"
        var_name =
          case Regex.run(~r/environment variable (.+) is not set/, e.message) do
            [_, name] -> name
            _ -> "UNKNOWN"
          end

        {:error, Error.missing_env_var(var_name)}
    end
  end

  @doc """
  Returns default channel configurations for standard channels.

  ## Returns

  Map of channel name to ChannelConfig.t()

  ## Examples

      iex> ChannelConfig.defaults() |> Map.keys() |> MapSet.new()
      MapSet.new(["ui_state", "agent", "hooks"])

      iex> ChannelConfig.defaults()["ui_state"].topic
      "jido:ui"

  """
  @spec defaults() :: %{String.t() => t()}
  def defaults do
    %{
      "ui_state" => %__MODULE__{
        socket: "ws://localhost:4000/socket",
        topic: "jido:ui",
        auth: nil,
        broadcast_events: ["state_change", "progress", "error"]
      },
      "agent" => %__MODULE__{
        socket: "ws://localhost:4000/socket",
        topic: "jido:agent",
        auth: nil,
        broadcast_events: ["started", "stopped", "state_changed"]
      },
      "hooks" => %__MODULE__{
        socket: "ws://localhost:4000/socket",
        topic: "jido:hooks",
        auth: nil,
        broadcast_events: ["triggered", "completed", "failed"]
      }
    }
  end

  # Private helpers

  @doc false
  @spec validate_socket(nil | String.t()) :: :ok | {:error, Error.t()}
  defp validate_socket(nil), do: :ok
  defp validate_socket(""), do: {:error, Error.socket_empty()}

  defp validate_socket(socket) when is_binary(socket) do
    if String.starts_with?(socket, ["ws://", "wss://"]) do
      :ok
    else
      {:error, Error.socket_invalid()}
    end
  end

  @doc false
  @spec validate_topic(nil | String.t()) :: :ok | {:error, Error.t()}
  defp validate_topic(nil), do: {:error, Error.topic_required()}
  defp validate_topic(""), do: {:error, Error.topic_empty()}

  defp validate_topic(topic) when is_binary(topic) do
    if Regex.match?(@topic_regex, topic) do
      :ok
    else
      {:error, Error.topic_format_invalid()}
    end
  end

  @doc false
  @spec convert_to_atom_keys(map()) :: map()
  defp convert_to_atom_keys(config) when is_map(config) do
    valid_keys = [:socket, :topic, :auth, :broadcast_events]

    Enum.reduce(config, %{}, fn {k, v}, acc ->
      # Try to convert string key to atom, skip if not a valid struct field
      try do
        atom_key = String.to_existing_atom(k)
        if atom_key in valid_keys do
          Map.put(acc, atom_key, v)
        else
          acc
        end
      rescue
        ArgumentError -> acc
      end
    end)
  end

  @doc false
  @spec validate_auth(nil | map()) :: :ok | {:error, Error.t()}
  defp validate_auth(nil), do: :ok

  defp validate_auth(auth) when is_map(auth) do
    with {:ok, type} <- validate_auth_type(Map.get(auth, "type")),
         :ok <- validate_auth_credentials(type, auth) do
      :ok
    end
  end

  @doc false
  @spec validate_auth_type(nil | String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  defp validate_auth_type(nil), do: {:error, Error.auth_type_required()}

  defp validate_auth_type(type) when type in @valid_auth_types do
    {:ok, type}
  end

  defp validate_auth_type(type) do
    {:error, Error.auth_type_invalid(type)}
  end

  @doc false
  @spec validate_auth_credentials(String.t(), map()) :: :ok | {:error, Error.t()}
  defp validate_auth_credentials("token", auth) do
    token = Map.get(auth, "token")

    cond do
      is_nil(token) ->
        {:error, Error.token_required()}

      is_binary(token) ->
        # First expand environment variables in the token
        case expand_env_vars(token) do
          {:ok, expanded_token} -> validate_token_format(expanded_token)
          {:error, _} = error -> error
        end

      true ->
        {:error, Error.token_required()}
    end
  end

  defp validate_auth_credentials("basic", auth) do
    username = Map.get(auth, "username")
    password = Map.get(auth, "password")

    if is_nil(username) or is_nil(password) do
      {:error, Error.basic_credentials_required()}
    else
      :ok
    end
  end

  defp validate_auth_credentials("custom", _auth), do: :ok

  @doc false
  @spec validate_token_format(String.t()) :: :ok | {:error, Error.t()}
  defp validate_token_format(token) do
    cond do
      # Bearer token format (prefix "Bearer " + at least 20 chars)
      String.starts_with?(token, "Bearer ") and String.length(token) > 27 ->
        :ok

      # JWT format (header.payload.signature - 3 parts separated by dots)
      is_jwt_format?(token) ->
        :ok

      # Generic token (at least 20 chars)
      String.length(token) >= 20 ->
        :ok

      true ->
        {:error,
         Error.token_invalid(
           "token format invalid (must be Bearer token with >= 20 chars, JWT, or >= 20 chars)"
         )}
    end
  end

  @doc false
  @spec is_jwt_format?(String.t()) :: boolean()
  defp is_jwt_format?(token) do
    # JWT has exactly 2 dots separating 3 parts
    parts = String.split(token, ".")
    length(parts) == 3 and Enum.all?(parts, &(&1 != ""))
  end

  @doc false
  @spec validate_broadcast_events(nil | list()) :: :ok | {:error, Error.t()}
  defp validate_broadcast_events(nil), do: :ok

  defp validate_broadcast_events(events) when is_list(events) do
    if Enum.all?(events, &is_binary/1) and Enum.all?(events, &(&1 != "")) do
      :ok
    else
      {:error, Error.broadcast_events_invalid()}
    end
  end

  defp validate_broadcast_events(_), do: {:error, Error.broadcast_events_invalid()}

  @doc false
  @spec maybe_expand_auth(nil | map()) :: nil | map()
  defp maybe_expand_auth(nil), do: nil

  defp maybe_expand_auth(auth) when is_map(auth) do
    Map.update(auth, "token", nil, fn token -> expand_token(token) end)
  end

  @doc false
  @spec expand_token(nil | String.t()) :: nil | String.t()
  defp expand_token(nil), do: nil

  defp expand_token(token) when is_binary(token) do
    case expand_env_vars(token) do
      {:ok, expanded} -> expanded
      # If expansion fails, keep original token for validation to catch
      {:error, _} -> token
    end
  end

  @doc false
  defp expand_token(_), do: nil

  @doc false
  @spec do_expand_env_vars(String.t()) :: String.t()
  defp do_expand_env_vars(value) when is_binary(value) do
    # Match ${VAR} or ${VAR:-default} pattern
    Regex.replace(
      ~r/\$\{([^}:}]+)(?::-([^}]*))?\}/,
      value,
      fn _whole, var_name, default ->
        case System.fetch_env(var_name) do
          {:ok, value} -> value
          :error when is_nil(default) or default == "" ->
            raise RuntimeError, "environment variable #{var_name} is not set"
          :error -> default
        end
      end
    )
  end
end
