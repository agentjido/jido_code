defmodule JidoCode.Extensibility.Skills.ChannelBroadcasterTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility.Skills.ChannelBroadcaster
  alias JidoCode.Extensibility.{ChannelConfig, Permissions}

  describe "mount/2" do
    setup do
      # Mock agent
      agent = %{
        name: "test_agent",
        state: %{}
      }

      {:ok, agent: agent}
    end

    test "loads default channels when no config provided", %{agent: agent} do
      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, [])

      assert is_map(skill_state.channels)
      assert Map.has_key?(skill_state.channels, "ui_state")
      assert Map.has_key?(skill_state.channels, "agent")
      assert Map.has_key?(skill_state.channels, "hooks")
      assert skill_state.connected == false
      assert is_nil(skill_state.agent_name)
    end

    test "loads channels from direct config", %{agent: agent} do
      direct_channels = %{
        "custom_channel" => %{
          "socket" => "ws://localhost:4000/socket",
          "topic" => "jido:custom"
        }
      }

      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, channels: direct_channels)

      assert Map.has_key?(skill_state.channels, "custom_channel")
      assert skill_state.channels["custom_channel"].topic == "jido:custom"
    end

    test "accepts atom agent_name in config", %{agent: agent} do
      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, agent_name: :llm_agent)

      assert skill_state.agent_name == :llm_agent
      assert is_map(skill_state.channels)
    end

    test "accepts string agent_name in config", %{agent: agent} do
      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, agent_name: "llm_agent")

      assert skill_state.agent_name == "llm_agent"
      assert is_map(skill_state.channels)
    end

    test "accepts map-based config", %{agent: agent} do
      config = %{agent_name: :task_agent}

      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, config)

      assert skill_state.agent_name == :task_agent
    end
  end

  describe "get_channel/2" do
    setup do
      agent = %{name: "test_agent", state: %{}}

      direct_channels = %{
        "ui_state" => %{
          "socket" => "ws://localhost:4000/socket",
          "topic" => "jido:ui"
        }
      }

      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, channels: direct_channels)

      {:ok, skill_state: skill_state}
    end

    test "returns {:ok, channel} for existing channel", %{skill_state: skill_state} do
      assert {:ok, %ChannelConfig{} = channel} =
        ChannelBroadcaster.get_channel(skill_state, "ui_state")

      assert channel.topic == "jido:ui"
    end

    test "returns :error for non-existent channel", %{skill_state: skill_state} do
      assert :error = ChannelBroadcaster.get_channel(skill_state, "nonexistent")
    end
  end

  describe "list_channels/1" do
    test "returns list of channel names for default config" do
      agent = %{name: "test_agent", state: %{}}
      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, [])

      channels = ChannelBroadcaster.list_channels(skill_state)

      assert "ui_state" in channels
      assert "agent" in channels
      assert "hooks" in channels
    end

    test "returns list of channel names for custom config" do
      agent = %{name: "test_agent", state: %{}}

      direct_channels = %{
        "custom1" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:1"},
        "custom2" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:2"}
      }

      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, channels: direct_channels)

      channels = ChannelBroadcaster.list_channels(skill_state)

      assert "custom1" in channels
      assert "custom2" in channels
    end
  end

  describe "should_broadcast?/3" do
    setup do
      agent = %{name: "test_agent", state: %{}}

      direct_channels = %{
        "ui_state" => %{
          "socket" => "ws://localhost:4000/socket",
          "topic" => "jido:ui",
          "broadcast_events" => ["state_change", "progress"]
        }
      }

      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, channels: direct_channels)

      {:ok, skill_state: skill_state}
    end

    test "returns true for configured broadcast events", %{skill_state: skill_state} do
      assert ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "state_change")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "progress")
    end

    test "returns false for unconfigured events", %{skill_state: skill_state} do
      refute ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "not_configured")
    end

    test "returns false for non-existent channels", %{skill_state: skill_state} do
      refute ChannelBroadcaster.should_broadcast?(skill_state, "nonexistent", "any_event")
    end
  end

  describe "should_broadcast?/3 with default channels" do
    setup do
      agent = %{name: "test_agent", state: %{}}
      assert {:ok, skill_state} = ChannelBroadcaster.mount(agent, [])

      {:ok, skill_state: skill_state}
    end

    test "uses default events for ui_state channel", %{skill_state: skill_state} do
      assert ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "state_change")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "progress")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "ui_state", "error")
    end

    test "uses default events for agent channel", %{skill_state: skill_state} do
      assert ChannelBroadcaster.should_broadcast?(skill_state, "agent", "started")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "agent", "stopped")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "agent", "state_changed")
    end

    test "uses default events for hooks channel", %{skill_state: skill_state} do
      assert ChannelBroadcaster.should_broadcast?(skill_state, "hooks", "triggered")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "hooks", "completed")
      assert ChannelBroadcaster.should_broadcast?(skill_state, "hooks", "failed")
    end
  end
end
