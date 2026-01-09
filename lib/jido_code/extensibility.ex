defmodule JidoCode.Extensibility do
  @moduledoc """
  Extensibility system for JidoCode.

  This module provides the public API for the extensibility system including:
  - Configuration management (channels, settings)
  - Permissions (allow/deny/ask patterns with configurable defaults)
  - Hooks (future phases)
  - Agents (future phases)
  - Plugins (future phases)

  ## Overview

  The extensibility system allows JidoCode to be configured and extended
  through JSON settings files, enabling runtime customization without code changes.

  ## Architecture

  The extensibility system is organized into:
  - `JidoCode.Extensibility.ChannelConfig` - Phoenix channel configuration
  - `JidoCode.Extensibility.Permissions` - Permission patterns and checks
  - `JidoCode.Extensibility.Error` - Structured error types

  Future phases will add:
  - `JidoCode.Extensibility.Hooks` - Event hook configuration
  - `JidoCode.Extensibility.Agents` - Agent configuration
  - `JidoCode.Extensibility.Plugins` - Plugin management
  - `JidoCode.Extensibility.Component` - Component lifecycle behavior

  ## Public API

      # Load extensions from settings
      {:ok, extensions} = JidoCode.Extensibility.load_extensions(settings)

      # Validate configuration
      {:ok, config} = JidoCode.Extensibility.validate_channel_config(channel_map)

      # Check permissions
      :deny = JidoCode.Extensibility.check_permission(permissions, "Delete", "file.txt")

      # Get default configuration
      defaults = JidoCode.Extensibility.defaults()

  ## Security

  The permission system defaults to **fail-closed** (`:deny`) for security.
  Unmatched actions are denied by default unless explicitly allowed.

  To enable backward-compatibility mode (fail-open), set `"default_mode": "allow"`
  in your permissions configuration.

  ## Examples

      # Load and validate extensions from settings
      settings = JidoCode.Settings.load()
      {:ok, ext} = JidoCode.Extensibility.load_extensions(settings)

      # Access channel configuration
      ext.channels["ui_state"].topic
      #=> "jido:ui"

      # Check a permission
      JidoCode.Extensibility.check_permission(ext.permissions, "Read", "file.txt")
      #=> :allow

  """

  alias JidoCode.Extensibility.{ChannelConfig, Permissions, Error}
  alias JidoCode.{Settings, Error}

  @typedoc """
  Aggregate extensibility configuration.

  ## Fields

  - `:channels` - Map of channel name to ChannelConfig.t()
  - `:permissions` - Permissions struct or nil
  """
  @type t :: %__MODULE__{
          channels: %{String.t() => ChannelConfig.t()},
          permissions: Permissions.t() | nil
        }

  defstruct channels: %{}, permissions: nil

  @doc """
  Loads and validates extensibility configuration from settings.

  This is the main entry point for loading extensibility configuration.
  It validates channel configs and permissions from the settings.

  ## Parameters

  - `settings` - JidoCode.Settings struct containing extensibility fields

  ## Returns

  - `{:ok, extensibility}` - Successfully loaded configuration
  - `{:error, %JidoCode.Extensibility.Error{}}` - Validation failed

  ## Examples

      iex> settings = %{
      ...>   channels: %{"ui" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:ui"}},
      ...>   permissions: nil
      ...> }
      iex> {:ok, ext} = JidoCode.Extensibility.load_extensions(settings)
      iex> is_map(ext.channels)
      true

  """
  @spec load_extensions(map()) :: {:ok, t()} | {:error, Error.t()}
  def load_extensions(settings) when is_map(settings) do
    with {:ok, channels} <- load_channels(settings),
         {:ok, permissions} <- load_permissions(settings) do
      {:ok, %__MODULE__{channels: channels, permissions: permissions}}
    end
  end

  @doc """
  Validates a channel configuration map.

  Delegates to `ChannelConfig.validate/1` with error wrapping.

  ## Parameters

  - `config` - Map with channel configuration keys

  ## Returns

  - `{:ok, ChannelConfig.t()}` - Valid configuration
  - `{:error, %Error{}}` - Validation failed

  ## Examples

      iex> {:ok, config} = JidoCode.Extensibility.validate_channel_config(%{
      ...>   "socket" => "ws://localhost:4000/socket",
      ...>   "topic" => "jido:ui"
      ...> })
      iex> config.topic
      "jido:ui"

  """
  @spec validate_channel_config(map()) :: {:ok, ChannelConfig.t()} | {:error, Error.t()}
  def validate_channel_config(config) when is_map(config) do
    ChannelConfig.validate(config)
  end

  @doc """
  Validates a permissions configuration map.

  Delegates to `Permissions.from_json/1` with error wrapping.

  ## Parameters

  - `json` - Map with string keys containing "allow", "deny", "ask", "default_mode"

  ## Returns

  - `{:ok, Permissions.t()}` - Valid configuration
  - `{:error, %Error{}}` - Validation failed

  ## Examples

      iex> {:ok, perms} = JidoCode.Extensibility.validate_permissions(%{
      ...>   "allow" => ["Read:*"],
      ...>   "deny" => ["*delete*"]
      ...> })
      iex> perms.default_mode
      :deny

  """
  @spec validate_permissions(map()) :: {:ok, Permissions.t()} | {:error, Error.t()}
  def validate_permissions(json) when is_map(json) do
    Permissions.from_json(json)
  end

  @doc """
  Checks if a permission is granted.

  Delegates to `Permissions.check_permission/3`.

  ## Parameters

  - `permissions` - The Permissions struct to check against
  - `category` - The category of the action (e.g., "Read", "Edit", "run_command")
  - `action` - The specific action to check (e.g., "file.txt", "delete", "make")

  ## Returns

  - `:allow` - The action is permitted
  - `:deny` - The action is blocked
  - `:ask` - User confirmation is required

  ## Examples

      iex> perms = %JidoCode.Extensibility.Permissions{
      ...>   allow: ["Read:*"],
      ...>   deny: ["*delete*"],
      ...>   ask: [],
      ...>   default_mode: :deny
      ...> }
      iex> JidoCode.Extensibility.check_permission(perms, "Read", "file.txt")
      :allow

      iex> JidoCode.Extensibility.check_permission(perms, "Edit", "delete_file")
      :deny

  """
  @spec check_permission(Permissions.t(), String.t() | atom(), String.t() | atom()) ::
          Permissions.decision()
  def check_permission(%Permissions{} = perms, category, action) do
    Permissions.check_permission(perms, category, action)
  end

  @doc """
  Returns default extensibility configuration.

  Provides sensible defaults for channels and permissions.

  ## Returns

  - `t()` - Default extensibility configuration

  ## Examples

      iex> defaults = JidoCode.Extensibility.defaults()
      iex> Map.keys(defaults.channels)
      ["ui_state", "agent", "hooks"]

      iex> defaults.permissions.default_mode
      :deny

  """
  @spec defaults() :: t()
  def defaults do
    %__MODULE__{
      channels: ChannelConfig.defaults(),
      permissions: Permissions.defaults()
    }
  end

  # Private Functions

  @doc false
  @spec load_channels(map()) :: {:ok, %{String.t() => ChannelConfig.t()}} | {:error, Error.t()}
  defp load_channels(%{channels: channels}) when is_map(channels) do
    Enum.reduce_while(channels, {:ok, %{}}, fn {name, config}, {:ok, acc} ->
      case validate_channel_config(config) do
        {:ok, channel} -> {:cont, {:ok, Map.put(acc, name, channel)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp load_channels(%{channels: nil}), do: {:ok, ChannelConfig.defaults()}

  defp load_channels(settings) when is_map(settings) do
    # channels is not a map and not nil - check if channels key exists
    case Map.get(settings, :channels) do
      nil -> {:ok, ChannelConfig.defaults()}
      val when is_map(val) ->
        Enum.reduce_while(val, {:ok, %{}}, fn {name, config}, {:ok, acc} ->
          case validate_channel_config(config) do
            {:ok, channel} -> {:cont, {:ok, Map.put(acc, name, channel)}}
            {:error, _} = error -> {:halt, error}
          end
        end)
      _ ->
        {:error, Error.channel_config_invalid("channels must be a map")}
    end
  end

  @doc false
  @spec load_permissions(map()) :: {:ok, Permissions.t() | nil} | {:error, Error.t()}
  defp load_permissions(%{permissions: perms}) when is_map(perms) do
    validate_permissions(perms)
  end

  defp load_permissions(%{permissions: nil}), do: {:ok, nil}

  defp load_permissions(settings) when is_map(settings) do
    # permissions may be at string key
    case Map.get(settings, :permissions) do
      nil -> {:ok, nil}
      perms when is_map(perms) -> validate_permissions(perms)
      _ -> {:error, Error.permissions_invalid("permissions must be a map")}
    end
  end
end
