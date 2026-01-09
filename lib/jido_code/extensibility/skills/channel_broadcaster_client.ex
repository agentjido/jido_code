defmodule JidoCode.Extensibility.Skills.ChannelBroadcasterClient do
  @moduledoc """
  Slipstream WebSocket client for broadcasting to Phoenix channels.

  This module uses Slipstream to connect to Phoenix channels and broadcast
  events from JidoCode agents. It implements the Slipstream behaviour
  for GenServer-like WebSocket client management.

  ## Features

  - Automatic reconnection with configurable backoff
  - Automatic rejoining of channels after reconnection
  - Support for multiple channels on a single connection
  - Graceful handling of connection failures

  ## Usage

  This client is typically started by the ChannelBroadcaster skill:

      {:ok, pid} = ChannelBroadcasterClient.start_link(channels: %{
        "ui_state" => %ChannelConfig{
          socket: "ws://localhost:4000/socket",
          topic: "jido:ui"
        }
      })

  ## Configuration

  Each channel configuration requires:
  - `:socket` - WebSocket URL (e.g., "ws://localhost:4000/socket")
  - `:topic` - Phoenix channel topic (e.g., "jido:ui")
  - `:auth` - Optional authentication configuration

  """

  use Slipstream, restart: :temporary

  require Logger

  alias JidoCode.Extensibility.ChannelConfig

  @type channel_name :: String.t()
  @type channels :: %{channel_name() => ChannelConfig.t()}

  @doc """
  Starts the ChannelBroadcasterClient.

  ## Options

  - `:channels` - Map of channel name to ChannelConfig struct (required)
  - `:name` - Name to register the process (optional)

  ## Examples

      {:ok, pid} = ChannelBroadcasterClient.start_link(
        channels: %{"ui_state" => channel_config},
        name: :my_broadcaster
      )
  """
  @impl true
  def start_link(opts) do
    channels = Keyword.fetch!(opts, :channels)
    name = Keyword.get(opts, :name)

    # Use the first channel's socket as the connection URI
    # All channels must share the same socket endpoint
    {socket_uri, first_config} = get_first_socket(channels)

    if socket_uri do
      config = build_config(socket_uri, first_config)
      Slipstream.start_link(__MODULE__, %{channels: channels}, name: name)
    else
      # No valid socket configuration, start without connecting
      {:ok, pid} = Slipstream.start_link(__MODULE__, %{channels: channels}, name: name)

      # Don't connect, just stay in a disconnected state
      {:ok, pid}
    end
  end

  @impl true
  def init(%{channels: channels}) do
    # Check if we have a valid socket to connect to
    {socket_uri, first_config} = get_first_socket(channels)

    if socket_uri do
      config = build_config(socket_uri, first_config)
      {:ok, connect!(config), {:continue, :join_channels}}
    else
      # No valid socket, start but don't connect
      Logger.warning("ChannelBroadcasterClient: No valid socket configuration, starting in disconnected state")

      {:ok, new_socket() |> assign(:channels, channels), {:continue, :no_connection}}
    end
  end

  @impl true
  def handle_continue(:join_channels, socket) do
    # Join all configured channels
    channels = socket.assigns[:channels] || %{}

    Enum.each(channels, fn {name, %ChannelConfig{topic: topic}} ->
      if topic do
        case join(socket, topic, %{}) do
          {:ok, _ref} ->
            Logger.debug("ChannelBroadcasterClient: Joining channel #{name} (topic: #{topic})")

          {:error, reason} ->
            Logger.error("ChannelBroadcasterClient: Failed to join #{name}: #{inspect(reason)}")
        end
      else
        Logger.warning("ChannelBroadcasterClient: Channel #{name} has no topic configured")
      end
    end)

    {:noreply, assign(socket, :joined_channels, MapSet.new())}
  end

  @impl true
  def handle_continue(:no_connection, socket) do
    # No connection available, just store the channels
    {:noreply, assign(socket, :joined_channels, MapSet.new())}
  end

  @impl true
  def handle_connect(socket) do
    Logger.info("ChannelBroadcasterClient: Connected to Phoenix server")
    {:ok, socket}
  end

  @impl true
  def handle_join(topic, _response, socket) do
    Logger.debug("ChannelBroadcasterClient: Joined topic #{topic}")

    joined = MapSet.put(socket.assigns[:joined_channels] || MapSet.new(), topic)
    {:ok, assign(socket, :joined_channels, joined)}
  end

  @impl true
  def handle_topic_close(topic, _reason, socket) do
    Logger.warning("ChannelBroadcasterClient: Topic #{topic} closed, attempting to rejoin")
    {:ok, rejoin(socket, topic)}
  end

  @impl true
  def handle_disconnect(reason, socket) do
    Logger.warning("ChannelBroadcasterClient: Disconnected: #{inspect(reason)}")

    # Attempt to reconnect using built-in retry mechanism
    case reconnect(socket) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, reason} ->
        Logger.error("ChannelBroadcasterClient: Reconnection failed: #{inspect(reason)}")
        # Stop the process with a normal shutdown - supervisor will restart
        {:stop, :normal, socket}
    end
  end

  @impl true
  def handle_info({:broadcast, topic, event, payload}, socket) do
    # Broadcast an event to a Phoenix topic
    case push(socket, topic, event, payload) do
      {:ok, _ref} ->
        {:noreply, socket}

      {:error, reason} ->
        Logger.error("ChannelBroadcasterClient: Failed to broadcast to #{topic}: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_call({:broadcast, topic, event, payload}, _from, socket) do
    # Synchronous broadcast - returns after push is queued
    case push(socket, topic, event, payload) do
      {:ok, _ref} ->
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  @impl true
  def handle_info({:broadcast_sync, topic, event, payload, from}, socket) do
    # Broadcast and wait for reply from server
    case push(socket, topic, event, payload) do
      {:ok, ref} ->
        # Store the from reference so we can reply when the server responds
        {:noreply, assign(socket, {:pending_reply, ref}, from)}

      {:error, reason} ->
        GenServer.reply(from, {:error, reason})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_reply(ref, reply, socket) do
    # Check if this reply is pending
    case socket.assigns[{:pending_reply, ref}] do
      nil ->
        # Not a pending reply, just log it
        Logger.debug("ChannelBroadcasterClient: Received unexpected reply: #{inspect(reply)}")
        {:ok, socket}

      from ->
        # Reply to the waiting process
        GenServer.reply(from, {:ok, reply})
        {:ok, assign(socket, {:pending_reply, ref}, nil)}
    end
  end

  @impl true
  def handle_message(topic, event, message, socket) do
    # Handle incoming messages from the server
    Logger.debug("ChannelBroadcasterClient: Received message on #{topic}: #{event} => #{inspect(message)}")
    {:ok, socket}
  end

  #
  # Public API
  #

  @doc """
  Broadcast an event to a Phoenix topic.

  ## Parameters

  - `client` - PID or name of the client process
  - `topic` - Phoenix channel topic
  - `event` - Event name
  - `payload` - Event payload (must be JSON-serializable)

  ## Returns

  - `:ok` - Event was queued for sending
  - `{:error, reason}` - Failed to queue event

  ## Examples

      :ok = ChannelBroadcasterClient.broadcast(client, "jido:ui", "state_change", %{state: "working"})
  """
  @spec broadcast(GenServer.server(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def broadcast(client, topic, event, payload) do
    GenServer.call(client, {:broadcast, topic, event, payload})
  end

  @doc """
  Broadcast an event asynchronously (fire and forget).

  ## Parameters

  - `client` - PID or name of the client process
  - `topic` - Phoenix channel topic
  - `event` - Event name
  - `payload` - Event payload (must be JSON-serializable)

  ## Examples

      send(client, {:broadcast, "jido:ui", "state_change", %{state: "working"}})
  """
  @spec broadcast_async(GenServer.server(), String.t(), String.t(), map()) :: :ok
  def broadcast_async(client, topic, event, payload) do
    send(client, {:broadcast, topic, event, payload})
    :ok
  end

  @doc """
  Get the current connection status.

  ## Returns

  - `:connected` - Connected and channels joined
  - `:connecting` - Connection in progress
  - `:disconnected` - Not connected

  ## Examples

      :connected = ChannelBroadcasterClient.status(client)
  """
  @spec status(GenServer.server()) :: :connected | :connecting | :disconnected
  def status(client) do
    GenServer.call(client, :status)
  end

  @impl true
  def handle_call(:status, _from, socket) do
    status =
      cond do
        socket.assigns[:joined_channels] != nil and
            map_size(socket.assigns[:joined_channels] || %{}) > 0 ->
          :connected

        true ->
          :disconnected
      end

    {:reply, status, socket}
  end

  #
  # Private helpers
  #

  # Get the first valid socket configuration from the channels map
  defp get_first_socket(channels) when is_map(channels) do
    Enum.find_value(channels, fn
      {_name, %ChannelConfig{socket: nil}} -> nil
      {_name, %ChannelConfig{socket: ""}} -> nil
      {_name, %ChannelConfig{socket: socket} = config} -> {socket, config}
      {_name, _} -> nil
    end)
  end

  # Build Slipstream configuration from ChannelConfig
  defp build_config(socket_uri, %ChannelConfig{auth: nil}) do
    [
      uri: socket_uri,
      reconnect_after_msec: [1000, 2000, 5000, 10_000],
      rejoin_after_msec: [1000, 2000, 5000],
      heartbeat_interval: 30_000
    ]
  end

  defp build_config(socket_uri, %ChannelConfig{auth: auth}) when is_map(auth) do
    base = build_config(socket_uri, %ChannelConfig{auth: nil})

    # Add authentication headers based on auth type
    headers = auth_headers(auth)

    Keyword.put(base, :headers, headers)
  end

  # Build authentication headers from auth config
  defp auth_headers(%{"type" => "token", "token" => token}) do
    [{"authorization", "Bearer #{token}"}]
  end

  defp auth_headers(%{"type" => "basic", "username" => username, "password" => password}) do
    credentials = Base.encode64("#{username}:#{password}")
    [{"authorization", "Basic #{credentials}"}]
  end

  defp auth_headers(%{"type" => "custom"} = auth) do
    # For custom auth, pass through the headers directly
    Map.to_list(auth)
    |> Enum.reject(fn {k, _} -> k == "type" end)
  end

  defp auth_headers(_), do: []
end
