defmodule JidoCode.Extensibility.Skills.ChannelBroadcaster do
  @moduledoc """
  Skill for broadcasting events to configured Phoenix channels via Slipstream.

  This skill integrates the extensibility channel configuration with
  Jido v2's signal system for real-time event broadcasting using
  the Slipstream WebSocket client.

  ## Features

  - Loads channel configuration from extensibility settings
  - Starts and manages a Slipstream WebSocket client process
  - Broadcasts agent signals to configured Phoenix channels
  - Automatic reconnection and rejoining on connection loss
  - Support for agent-specific channel overrides

  ## Usage

      defmodule MyAgent do
        use Jido.AI.ReActAgent,
          name: "my_agent",
          description: "My agent with channel broadcasting",
          skills: [
            {JidoCode.Extensibility.Skills.ChannelBroadcaster, [agent_name: :my_agent]}
          ]
      end

  ## State

  The skill stores the following in the agent's state under `:channel_broadcaster`:

  - `:channels` - Map of channel name to ChannelConfig struct
  - `:client_pid` - PID of the Slipstream client process (or nil if not connected)
  - `:agent_name` - The agent name used for channel overrides
  - `:connected` - Boolean indicating if client is connected

  ## Channel Configuration

  Channels are configured via the extensibility settings:

      {
        "extensibility": {
          "channels": {
            "ui_state": {
              "socket": "ws://localhost:4000/socket",
              "topic": "jido:ui",
              "broadcast_events": ["state_change", "progress"]
            }
          }
        }
      }

  ## Signal Integration

  The skill responds to Jido v2 signals and broadcasts matching events:

  - `{:jido_signal, signal_type, payload}` - Broadcasts signal to configured channels

  """

  use Jido.Skill,
    name: "channel_broadcaster",
    state_key: :channel_broadcaster,
    actions: [],
    description:
      "Integrates extensibility channel configuration with Jido agents for Phoenix channel broadcasting via Slipstream"

  alias JidoCode.{Settings, Extensibility}
  alias JidoCode.Extensibility.Skills.{ConfigLoader, ChannelBroadcasterClient}
  alias JidoCode.Extensibility.{ChannelConfig, Error}

  @doc """
  Mounts the skill and starts the Slipstream client.

  ## Parameters

  - `agent` - The agent struct
  - `config` - Configuration map with optional keys:
    - `:agent_name` - Agent name for agent-specific channel overrides
    - `:channels` - Direct channels map (skips settings load)
    - `:auto_connect` - Boolean to automatically start client (default: true)

  ## Returns

  - `{:ok, skill_state}` - Successfully loaded channels and started client
  - `{:ok, skill_state, child_spec}` - Successfully loaded with child spec for supervision

  ## Examples

      # Load from settings with agent-specific overrides
      {:ok, state, child_spec} = ChannelBroadcaster.mount(agent, [agent_name: :llm_agent])

      # Load with direct channels (for testing)
      {:ok, state, child_spec} = ChannelBroadcaster.mount(agent,
        channels: %{"ui_state" => %{...}}
      )

      # Load without auto-connecting
      {:ok, state} = ChannelBroadcaster.mount(agent, auto_connect: false)
  """
  @impl true
  def mount(_agent, config) when is_list(config) do
    agent_name = Keyword.get(config, :agent_name)
    direct_channels = Keyword.get(config, :channels)
    auto_connect = Keyword.get(config, :auto_connect, false)

    channels =
      case direct_channels do
        nil ->
          # Load from settings
          ext_config = ConfigLoader.load_for_agent(agent_name)
          ext_config.channels

        chans_map when is_map(chans_map) ->
          # Use direct channels (for testing/overrides)
          # Convert string-keyed maps to ChannelConfig structs
          convert_channels_to_structs(chans_map)

        _ ->
          # Invalid, use defaults
          ChannelConfig.defaults()
      end

    skill_state = %{
      channels: channels,
      agent_name: agent_name,
      client_pid: nil,
      connected: false
    }

    # Return child spec for the Slipstream client if auto_connect is true
    if auto_connect and map_size(channels) > 0 do
      # Check if we have valid socket configurations
      has_valid_socket? =
        Enum.any?(channels, fn
          {_name, %ChannelConfig{socket: nil}} -> false
          {_name, %ChannelConfig{socket: ""}} -> false
          {_name, %ChannelConfig{socket: _}} -> true
          _ -> false
        end)

      if has_valid_socket? do
        client_name = Module.concat(__MODULE__, Client)

        child_spec = %{
          id: ChannelBroadcasterClient,
          start:
            {ChannelBroadcasterClient, :start_link,
             [[channels: channels, name: client_name]]},
          restart: :temporary,
          type: :worker
        }

        # Store the client name in state so we can reference it
        skill_state = Map.put(skill_state, :client_name, client_name)

        {:ok, skill_state, [child_spec]}
      else
        # No valid socket configuration, don't start the client
        {:ok, skill_state}
      end
    else
      {:ok, skill_state}
    end
  end

  @impl true
  def mount(_agent, config) when is_map(config) do
    # Handle map-based config
    mount(_agent, Map.to_list(config))
  end

  @impl true
  def mount(_agent, _config) do
    # Handle no config - use defaults without auto-connect
    skill_state = %{
      channels: ChannelConfig.defaults(),
      agent_name: nil,
      client_pid: nil,
      client_name: nil,
      connected: false
    }

    {:ok, skill_state}
  end

  @doc """
  Gets the channel configuration for a specific channel name.

  ## Parameters

  - `skill_state` - The skill's state from agent state
  - `channel_name` - The name of the channel to get

  ## Returns

  - `{:ok, channel_config}` - Found channel
  - `:error` - Channel not found

  ## Examples

      {:ok, channel} = ChannelBroadcaster.get_channel(skill_state, "ui_state")
  """
  def get_channel(skill_state, channel_name) when is_map(skill_state) do
    channels = Map.get(skill_state, :channels, %{})

    case Map.get(channels, channel_name) do
      nil -> :error
      channel -> {:ok, channel}
    end
  end

  @doc """
  Lists all configured channel names.

  ## Parameters

  - `skill_state` - The skill's state from agent state

  ## Returns

  List of channel names

  ## Examples

      ["ui_state", "agent", "hooks"] = ChannelBroadcaster.list_channels(skill_state)
  """
  def list_channels(skill_state) when is_map(skill_state) do
    channels = Map.get(skill_state, :channels, %{})
    Map.keys(channels)
  end

  @doc """
  Checks if a signal should be broadcast to a specific channel.

  ## Parameters

  - `skill_state` - The skill's state from agent state
  - `channel_name` - The name of the channel
  - `signal_type` - The type of signal (e.g., "state_change", "progress")

  ## Returns

  - `true` - Signal should be broadcast
  - `false` - Signal should not be broadcast

  ## Examples

      ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "state_change")
      # => true
  """
  def should_broadcast?(skill_state, channel_name, signal_type) do
    case get_channel(skill_state, channel_name) do
      {:ok, %ChannelConfig{broadcast_events: events}} when is_list(events) ->
        Enum.member?(events, signal_type)

      {:ok, %ChannelConfig{broadcast_events: nil}} ->
        # No specific events configured, use defaults
        default_events_for_channel(channel_name)
        |> Enum.member?(signal_type)

      _ ->
        false
    end
  end

  @doc """
  Broadcasts an event to a specific channel.

  ## Parameters

  - `skill_state` - The skill's state from agent state
  - `channel_name` - The name of the channel to broadcast to
  - `event` - The event name to broadcast
  - `payload` - The payload to broadcast (must be JSON-serializable)

  ## Returns

  - `:ok` - Event was queued for sending
  - `{:error, reason}` - Failed to queue event

  ## Examples

      :ok = ChannelBroadcaster.broadcast(skill_state, "ui_state", "state_change", %{state: "working"})
  """
  def broadcast(skill_state, channel_name, event, payload) do
    case get_channel(skill_state, channel_name) do
      {:ok, %ChannelConfig{topic: topic}} when is_binary(topic) ->
        client_name = Map.get(skill_state, :client_name)

        if client_name do
          ChannelBroadcasterClient.broadcast(client_name, topic, event, payload)
        else
          {:error, :client_not_started}
        end

      {:ok, %ChannelConfig{topic: nil}} ->
        {:error, :no_topic_configured}

      :error ->
        {:error, :channel_not_found}
    end
  end

  @doc """
  Broadcasts an event asynchronously to a specific channel (fire and forget).

  ## Parameters

  - `skill_state` - The skill's state from agent state
  - `channel_name` - The name of the channel to broadcast to
  - `event` - The event name to broadcast
  - `payload` - The payload to broadcast (must be JSON-serializable)

  ## Examples

      :ok = ChannelBroadcaster.broadcast_async(skill_state, "ui_state", "progress", %{percent: 50})
  """
  def broadcast_async(skill_state, channel_name, event, payload) do
    case get_channel(skill_state, channel_name) do
      {:ok, %ChannelConfig{topic: topic}} when is_binary(topic) ->
        client_name = Map.get(skill_state, :client_name)

        if client_name do
          ChannelBroadcasterClient.broadcast_async(client_name, topic, event, payload)
        else
          {:error, :client_not_started}
        end

      {:ok, %ChannelConfig{topic: nil}} ->
        {:error, :no_topic_configured}

      :error ->
        {:error, :channel_not_found}
    end
  end

  @doc """
  Gets the current connection status of the Slipstream client.

  ## Parameters

  - `skill_state` - The skill's state from agent state

  ## Returns

  - `:connected` - Connected and channels joined
  - `:connecting` - Connection in progress
  - `:disconnected` - Not connected
  - `:client_not_started` - Client was not started

  ## Examples

      :connected = ChannelBroadcaster.status(skill_state)
  """
  def status(skill_state) do
    client_name = Map.get(skill_state, :client_name)

    if client_name do
      case ChannelBroadcasterClient.status(client_name) do
        status when status in [:connected, :connecting, :disconnected] ->
          status

        _ ->
          :disconnected
      end
    else
      :client_not_started
    end
  end

  #
  # Jido.Skill callbacks
  #

  @impl true
  def handle_signal(_agent, signal, skill_state) do
    # Process signals and broadcast to configured channels
    # Signal format: {:jido_signal, signal_type, payload} or similar
    signal_type = signal_type(signal)
    payload = signal_payload(signal)

    # Broadcast to all channels that should receive this signal type
    channels = Map.get(skill_state, :channels, %{})

    Enum.each(channels, fn {channel_name, %ChannelConfig{} = channel_config} ->
      if should_broadcast_to_channel?(channel_config, signal_type) do
        # Broadcast the signal to this channel
        broadcast_event(skill_state, channel_name, channel_config, signal_type, payload)
      end
    end)

    {:ok, :continue, skill_state}
  end

  # Default broadcast events for each channel type
  defp default_events_for_channel("ui_state"), do: ["state_change", "progress", "error"]
  defp default_events_for_channel("agent"), do: ["started", "stopped", "state_changed"]
  defp default_events_for_channel("hooks"), do: ["triggered", "completed", "failed"]
  defp default_events_for_channel(_), do: []

  # Extract signal type from various signal formats
  defp signal_type({:jido_signal, type, _payload}), do: to_string(type)
  defp signal_type({:signal, type, _payload}), do: to_string(type)
  defp signal_type(%{type: type}), do: to_string(type)
  defp signal_type(%{"type" => type}), do: type
  defp signal_type(_), do: nil

  # Extract payload from various signal formats
  defp signal_payload({:jido_signal, _type, payload}), do: payload
  defp signal_payload({:signal, _type, payload}), do: payload
  defp signal_payload(%{payload: payload}), do: payload
  defp signal_payload(%{"payload" => payload}), do: payload
  defp signal_payload(signal), do: signal

  # Check if a channel should receive a specific signal type
  defp should_broadcast_to_channel?(%ChannelConfig{broadcast_events: nil}, signal_type) do
    # No specific events configured, signal will be checked against defaults
    signal_type != nil
  end

  defp should_broadcast_to_channel?(%ChannelConfig{broadcast_events: events}, signal_type) do
    is_list(events) and signal_type in events
  end

  defp should_broadcast_to_channel?(%ChannelConfig{}, _signal_type), do: false

  # Broadcast an event to a specific channel
  defp broadcast_event(skill_state, channel_name, %ChannelConfig{topic: topic}, event_type, payload) do
    if is_binary(topic) do
      client_name = Map.get(skill_state, :client_name)

      if client_name do
        # Broadcast asynchronously (fire and forget)
        ChannelBroadcasterClient.broadcast_async(client_name, topic, event_type, %{
          "channel" => channel_name,
          "payload" => payload,
          "timestamp" => System.system_time(:millisecond)
        })
      else
        # Client not started, log a warning
        require Logger
        Logger.warning(
          "ChannelBroadcaster: Cannot broadcast to #{channel_name}, client not started. Event: #{event_type}"
        )
      end
    end
  end

  # Convert a map of channel configurations to ChannelConfig structs
  defp convert_channels_to_structs(channels_map) when is_map(channels_map) do
    Enum.into(channels_map, %{}, fn {name, config} ->
      normalized_config =
        cond do
          # Already a ChannelConfig struct, use as-is
          is_struct(config, ChannelConfig) ->
            config

          # String-keyed map, validate and convert
          is_map(config) and not is_struct(config) ->
            case ChannelConfig.validate(config) do
              {:ok, channel_config} ->
                channel_config

              {:error, _reason} ->
                # If validation fails, use default config for this channel
                ChannelConfig.defaults() |> Map.get(name, %ChannelConfig{})
            end

          # Atom-keyed map
          is_map(config) ->
            # Convert to string keys and validate
            string_keyed =
              Enum.into(config, %{}, fn {k, v} -> {to_string(k), v} end)

            case ChannelConfig.validate(string_keyed) do
              {:ok, channel_config} ->
                channel_config

              {:error, _reason} ->
                ChannelConfig.defaults() |> Map.get(name, %ChannelConfig{})
            end

          # Unknown format, use empty config
          true ->
            %ChannelConfig{}
        end

      {name, normalized_config}
    end)
  end
end
