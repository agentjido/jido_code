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

  defstruct [:socket, :topic, :auth, :broadcast_events]

  @type t :: %__MODULE__{
          socket: String.t() | nil,
          topic: String.t() | nil,
          auth: map() | nil,
          broadcast_events: [String.t()] | nil
        }

  @doc """
  Validates a channel configuration map.

  ## Parameters

  - `config` - Map with channel configuration keys

  ## Returns

  - `{:ok, ChannelConfig.t()}` - Valid configuration
  - `{:error, String.t()}` - Validation error with reason

  ## Examples

      iex> ChannelConfig.validate(%{
      ...>   "socket" => "ws://localhost:4000/socket",
      ...>   "topic" => "jido:ui"
      ...> })
      {:ok, %ChannelConfig{socket: "ws://localhost:4000/socket", topic: "jido:ui", auth: nil, broadcast_events: nil}}

      iex> ChannelConfig.validate(%{"socket" => "invalid-url"})
      {:error, "socket must be a valid WebSocket URL (ws:// or wss://)"}
  """
  @spec validate(map()) :: {:ok, t()} | {:error, String.t()}
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

  - Expanded string with environment variables resolved

  ## Examples

      iex> System.put_env("TEST_VAR", "value")
      iex> ChannelConfig.expand_env_vars("${TEST_VAR}")
      "value"

      iex> ChannelConfig.expand_env_vars("${MISSING:-default}")
      "default"

      iex> ChannelConfig.expand_env_vars("no_vars")
      "no_vars"
  """
  @spec expand_env_vars(String.t()) :: String.t()
  def expand_env_vars(value) when is_binary(value) do
    # Match ${VAR} or ${VAR:-default} pattern
    Regex.replace(
      ~r/\$\{([^}:}]+)(?::-([^}]*))?\}/,
      value,
      fn _whole, var_name, default ->
        case System.fetch_env(var_name) do
          {:ok, value} -> value
          :error when is_nil(default) or default == "" ->
            raise RuntimeError, "environment variable #{var_name} is not set"
          :error ->
            default
        end
      end
    )
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
  defp validate_socket(nil), do: :ok
  defp validate_socket("") do
    {:error, "socket cannot be empty string"}
  end
  defp validate_socket(socket) when is_binary(socket) do
    if String.starts_with?(socket, ["ws://", "wss://"]) do
      :ok
    else
      {:error, "socket must be a valid WebSocket URL (ws:// or wss://)"}
    end
  end

  @doc false
  defp validate_topic(nil) do
    {:error, "topic is required"}
  end
  defp validate_topic("") do
    {:error, "topic cannot be empty"}
  end
  defp validate_topic(topic) when is_binary(topic) do
    if Regex.match?(~r/^[a-zA-Z0-9:_\-\.]+$/, topic) do
      :ok
    else
      {:error, "topic must contain only alphanumeric characters, colons, underscores, hyphens, or dots"}
    end
  end

  @doc false
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
  defp validate_auth(nil), do: :ok
  defp validate_auth(auth) when is_map(auth) do
    case Map.get(auth, "type") do
      nil -> {:error, "auth.type is required when auth is provided"}
      type when type in ["token", "basic", "custom"] -> :ok
      type -> {:error, "auth.type must be one of: token, basic, custom. Got: #{type}"}
    end
  end

  @doc false
  defp validate_broadcast_events(nil), do: :ok
  defp validate_broadcast_events(events) when is_list(events) do
    if Enum.all?(events, &is_binary/1) and Enum.all?(events, &(&1 != "")) do
      :ok
    else
      {:error, "broadcast_events must be a list of non-empty strings"}
    end
  end

  defp validate_broadcast_events(_), do: {:error, "broadcast_events must be a list of non-empty strings"}

  @doc false
  defp maybe_expand_auth(nil), do: nil
  defp maybe_expand_auth(auth) when is_map(auth) do
    Map.update(auth, "token", nil, fn token -> expand_token(token) end)
  end

  @doc false
  defp expand_token(nil), do: nil
  defp expand_token(token) when is_binary(token), do: expand_env_vars(token)

  @doc false
  defp expand_token(_), do: nil
end
