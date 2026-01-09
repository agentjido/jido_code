defmodule JidoCode.Extensibility.Skills.ConfigLoader do
  @moduledoc """
  Helper for loading extensibility configuration into Jido Skills.

  This module provides functions to load extensibility configuration from
  JidoCode.Settings and convert it to a format suitable for use in Skills.

  ## Usage

      # In a Skill's mount/2 callback
      def mount(_agent, config) do
        ext_config = ConfigLoader.load_for_agent("my_agent")
        {:ok, %{permissions: ext_config.permissions, channels: ext_config.channels}}
      end

  ## Agent-Specific Configuration

  Configuration can be overridden per-agent by including an `:agents` map
  in the extensibility settings:

      {
        "extensibility": {
          "permissions": {...},
          "agents": {
            "llm_agent": {
              "permissions": {
                "allow": ["run_command:*"]
              }
            }
          }
        }
      }

  """

  alias JidoCode.{Settings, Extensibility}
  alias JidoCode.Extensibility.{Error, ChannelConfig, Permissions}

  @typedoc """
  Agent configuration output format.

  ## Fields

  - `:permissions` - Permission configuration struct
  - `:channels` - Map of channel name to ChannelConfig struct
  """
  @type agent_config :: %{
          permissions: Permissions.t() | nil,
          channels: %{String.t() => ChannelConfig.t()}
        }

  @doc """
  Load extensibility configuration for an agent.

  This function loads the extensibility configuration from settings and applies
  any agent-specific overrides if an agent_name is provided.

  ## Parameters

  - `agent_name` - Optional atom or string name of the agent for agent-specific overrides

  ## Returns

  Map with `:permissions` and `:channels` keys. If loading fails, returns
  default configuration.

  ## Examples

      # Load defaults
      ConfigLoader.load_for_agent()
      # => %{permissions: %Permissions{...}, channels: %{...}}

      # Load with agent-specific overrides
      ConfigLoader.load_for_agent(:llm_agent)
      # => %{permissions: %Permissions{allow: ["run_command:*"], ...}, channels: %{...}}

  """
  @spec load_for_agent(atom() | String.t() | nil) :: agent_config()
  def load_for_agent(agent_name \\ nil) do
    case Settings.load() do
      {:ok, settings} ->
        case load_and_merge_config(settings, agent_name) do
          {:ok, config} ->
            config

          {:error, %Error{}} ->
            # Fall back to defaults if loading fails
            defaults()
        end

      {:error, _reason} ->
        # Settings not available, use defaults
        defaults()
    end
  end

  @doc """
  Load configuration from a settings map directly.

  Useful for testing or when you have a settings map but don't want to
  query the global Settings.

  ## Parameters

  - `settings` - Map containing extensibility configuration
  - `agent_name` - Optional agent name for agent-specific overrides

  ## Returns

  - `{:ok, agent_config()}` - Successfully loaded configuration
  - `{:error, %Error{}}` - Validation failed

  ## Examples

      settings = %{"extensibility" => %{"permissions" => {"allow": ["Read:*"]}}}
      ConfigLoader.load_from_settings(settings, :my_agent)
      # => {:ok, %{permissions: %Permissions{allow: ["Read:*"], ...}, channels: %{...}}}

  """
  @spec load_from_settings(map(), atom() | String.t() | nil) ::
          {:ok, agent_config()} | {:error, Error.t()}
  def load_from_settings(settings, agent_name \\ nil) do
    load_and_merge_config(settings, agent_name)
  end

  @doc """
  Returns default extensibility configuration.

  This is the fallback configuration used when settings cannot be loaded
  or are invalid.

  ## Examples

      ConfigLoader.defaults()
      # => %{permissions: %Permissions{allow: ["Read:*", ...], ...}, channels: %{...}}

  """
  @spec defaults() :: agent_config()
  def defaults do
    ext_defaults = Extensibility.defaults()

    %{
      permissions: ext_defaults.permissions,
      channels: ext_defaults.channels
    }
  end

  # Private Functions

  # Load and merge configuration from settings with agent-specific overrides
  defp load_and_merge_config(settings, agent_name) do
    with {:ok, base_config} <- load_base_config(settings),
         {:ok, merged_config} <- maybe_apply_agent_overrides(base_config, settings, agent_name) do
      {:ok, merged_config}
    end
  end

  # Load base configuration from settings
  defp load_base_config(settings) do
    # Extensibility config may be at top level or nested under "extensibility" key
    ext_settings =
      case Map.get(settings, "extensibility") do
        nil when is_map(settings) ->
          # Check for atom keys as well
          case Map.get(settings, :extensibility) do
            nil -> settings
            val -> val
          end

        val when is_map(val) ->
          val

        _ ->
          settings
      end

    # Convert string keys to atoms for Extensibility.load_extensions
    atomized_ext_settings = atomize_keys(ext_settings)

    case Extensibility.load_extensions(atomized_ext_settings) do
      {:ok, ext_config} ->
        # Fill in defaults for nil values
        permissions = ext_config.permissions || Permissions.defaults()
        channels = ext_config.channels || ChannelConfig.defaults()
        {:ok, %{permissions: permissions, channels: channels}}

      {:error, %Error{}} = error ->
        error
    end
  end

  # Convert string keys to known atom keys
  defp atomize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {"channels", val}, acc when is_map(val) ->
        Map.put(acc, :channels, val)

      {"permissions", val}, acc when is_map(val) ->
        Map.put(acc, :permissions, val)

      {"agents", val}, acc when is_map(val) ->
        Map.put(acc, :agents, val)

      {key, val}, acc when is_atom(key) ->
        Map.put(acc, key, val)

      {_key, _val}, acc ->
        acc
    end)
  end

  # Apply agent-specific overrides if agent_name is provided and overrides exist
  defp maybe_apply_agent_overrides(base_config, _settings, nil) do
    # No agent name, return base config
    {:ok, base_config}
  end

  defp maybe_apply_agent_overrides(base_config, settings, agent_name) do
    agent_key = to_string(agent_name)

    # Check if there are agent-specific overrides in settings
    agent_overrides = get_in(settings, ["extensibility", "agents", agent_key])

    cond do
      is_nil(agent_overrides) ->
        # No overrides for this agent
        {:ok, base_config}

      is_map(agent_overrides) ->
        # Apply overrides
        apply_agent_overrides(base_config, agent_overrides)

      true ->
        # Invalid overrides format, log warning and return base
        require Logger
        Logger.warning(
          "Invalid agent overrides format for #{agent_key}, expected map but got: #{inspect(agent_overrides)}"
        )

        {:ok, base_config}
    end
  end

  # Apply agent-specific overrides to base configuration
  defp apply_agent_overrides(base_config, overrides) do
    # Merge permissions if provided
    permissions =
      case Map.get(overrides, "permissions") do
        nil -> base_config.permissions
        perms when is_map(perms) -> merge_permissions(base_config.permissions, perms)
      end

    # Merge channels if provided
    channels =
      case Map.get(overrides, "channels") do
        nil -> base_config.channels
        chans when is_map(chans) -> merge_channels(base_config.channels, chans)
      end

    {:ok, %{permissions: permissions, channels: channels}}
  end

  # Merge permissions: base permissions are overridden by agent-specific ones
  defp merge_permissions(base_permissions, override_perms) do
    # Check if override specifies default_mode, otherwise inherit from base
    has_override_default_mode = Map.has_key?(override_perms, "default_mode")

    # Parse override permissions
    case Permissions.from_json(override_perms) do
      {:ok, override} ->
        # Merge: override lists replace base lists
        # For default_mode: use override's if explicitly set, otherwise inherit from base
        default_mode =
          if has_override_default_mode do
            override.default_mode
          else
            base_permissions.default_mode
          end

        %Permissions{
          allow: override.allow || base_permissions.allow,
          deny: override.deny || base_permissions.deny,
          ask: override.ask || base_permissions.ask,
          default_mode: default_mode
        }

      {:error, %Error{}} ->
        # If override is invalid, use base
        base_permissions
    end
  end

  # Merge channels: base channels are overridden by agent-specific ones
  defp merge_channels(base_channels, override_channels) do
    # Validate each override channel and merge into base
    Enum.reduce(override_channels, base_channels, fn {name, config}, acc ->
      case ChannelConfig.validate(config) do
        {:ok, channel_config} ->
          Map.put(acc, name, channel_config)

        {:error, %Error{}} ->
          # Invalid channel config, skip
          acc
      end
    end)
  end
end
