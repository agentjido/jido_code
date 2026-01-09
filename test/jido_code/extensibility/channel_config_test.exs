defmodule JidoCode.Extensibility.ChannelConfigTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility.ChannelConfig

  doctest ChannelConfig

  describe "struct creation" do
    test "creates struct with all fields" do
      config = %ChannelConfig{
        socket: "ws://localhost:4000/socket",
        topic: "jido:ui",
        auth: nil,
        broadcast_events: ["event1", "event2"]
      }

      assert config.socket == "ws://localhost:4000/socket"
      assert config.topic == "jido:ui"
      assert config.auth == nil
      assert config.broadcast_events == ["event1", "event2"]
    end

    test "creates struct with optional fields as nil" do
      config = %ChannelConfig{
        socket: nil,
        topic: "jido:ui",
        auth: nil,
        broadcast_events: nil
      }

      assert config.socket == nil
      assert config.topic == "jido:ui"
      assert config.auth == nil
      assert config.broadcast_events == nil
    end
  end

  describe "validate/1" do
    test "validates minimal valid config" do
      assert {:ok, config} = ChannelConfig.validate(%{"topic" => "jido:ui"})
      assert config.topic == "jido:ui"
      assert config.socket == nil
      assert config.auth == nil
      assert config.broadcast_events == nil
    end

    test "validates full config with socket and auth" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido:agent",
        "auth" => %{"type" => "token", "token" => "test_token"},
        "broadcast_events" => ["event1", "event2"]
      })

      assert config.socket == "ws://localhost:4000/socket"
      assert config.topic == "jido:agent"
      assert config.auth == %{"type" => "token", "token" => "test_token"}
      assert config.broadcast_events == ["event1", "event2"]
    end

    test "accepts ws:// socket URL" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido:ui"
      })

      assert config.socket == "ws://localhost:4000/socket"
    end

    test "accepts wss:// socket URL" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "socket" => "wss://example.com/socket",
        "topic" => "jido:ui"
      })

      assert config.socket == "wss://example.com/socket"
    end

    test "rejects invalid socket URL without ws:// or wss://" do
      assert {:error, error} = ChannelConfig.validate(%{
        "socket" => "http://localhost:4000/socket",
        "topic" => "jido:ui"
      })

      assert error == "socket must be a valid WebSocket URL (ws:// or wss://)"
    end

    test "rejects empty string for socket" do
      assert {:error, error} = ChannelConfig.validate(%{
        "socket" => "",
        "topic" => "jido:ui"
      })

      assert error == "socket cannot be empty string"
    end

    test "rejects missing topic" do
      assert {:error, error} = ChannelConfig.validate(%{
        "socket" => "ws://localhost:4000/socket"
      })

      assert error == "topic is required"
    end

    test "rejects empty string for topic" do
      assert {:error, error} = ChannelConfig.validate(%{"topic" => ""})

      assert error == "topic cannot be empty"
    end

    test "rejects topic with invalid characters" do
      assert {:error, error} = ChannelConfig.validate(%{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido ui"
      })

      assert error == "topic must contain only alphanumeric characters, colons, underscores, hyphens, or dots"
    end

    test "accepts topic with valid characters" do
      valid_topics = [
        "jido:ui",
        "jido:agent",
        "jido.ui.state",
        "jido_agent",
        "jido-agent",
        "jido:agent:status"
      ]

      Enum.each(valid_topics, fn topic ->
        assert {:ok, _config} = ChannelConfig.validate(%{"topic" => topic})
      end)
    end

    test "rejects auth without type" do
      assert {:error, error} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "auth" => %{"token" => "test"}
      })

      assert error == "auth.type is required when auth is provided"
    end

    test "rejects auth with invalid type" do
      assert {:error, error} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "auth" => %{"type" => "invalid"}
      })

      assert error == "auth.type must be one of: token, basic, custom. Got: invalid"
    end

    test "accepts auth with token type" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "auth" => %{"type" => "token", "token" => "secret"}
      })

      assert config.auth["type"] == "token"
      assert config.auth["token"] == "secret"
    end

    test "accepts auth with basic type" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "auth" => %{"type" => "basic", "username" => "user"}
      })

      assert config.auth["type"] == "basic"
    end

    test "accepts auth with custom type" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "auth" => %{"type" => "custom", "key" => "value"}
      })

      assert config.auth["type"] == "custom"
    end

    test "accepts nil broadcast_events" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "broadcast_events" => nil
      })

      assert config.broadcast_events == nil
    end

    test "accepts valid broadcast_events list" do
      assert {:ok, config} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "broadcast_events" => ["event1", "event2", "event3"]
      })

      assert config.broadcast_events == ["event1", "event2", "event3"]
    end

    test "rejects broadcast_events with empty string" do
      assert {:error, error} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "broadcast_events" => ["event1", "", "event3"]
      })

      assert error == "broadcast_events must be a list of non-empty strings"
    end

    test "rejects broadcast_events with non-list" do
      assert {:error, error} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "broadcast_events" => "not_a_list"
      })

      assert error == "broadcast_events must be a list of non-empty strings"
    end
  end

  describe "expand_env_vars/1" do
    test "returns string without variables unchanged" do
      assert ChannelConfig.expand_env_vars("no_vars_here") == "no_vars_here"
    end

    test "expands single environment variable" do
      System.put_env("TEST_VAR_CHANNEL", "test_value")

      result = ChannelConfig.expand_env_vars("${TEST_VAR_CHANNEL}")

      assert result == "test_value"

      System.delete_env("TEST_VAR_CHANNEL")
    end

    test "expands variable with default when not set" do
      System.delete_env("UNDEFINED_VAR")

      result = ChannelConfig.expand_env_vars("${UNDEFINED_VAR:-default_value}")

      assert result == "default_value"
    end

    test "uses actual value when variable is set with default syntax" do
      System.put_env("DEFINED_VAR", "actual")

      result = ChannelConfig.expand_env_vars("${DEFINED_VAR:-default}")

      assert result == "actual"

      System.delete_env("DEFINED_VAR")
    end

    test "expands multiple variables in one string" do
      System.put_env("VAR1", "value1")
      System.put_env("VAR2", "value2")

      result = ChannelConfig.expand_env_vars("${VAR1}_${VAR2}")

      assert result == "value1_value2"

      System.delete_env("VAR1")
      System.delete_env("VAR2")
    end

    test "expands variable with colon in default value" do
      result = ChannelConfig.expand_env_vars("${UNDEFINED_VAR:-ws://localhost:4000}")

      assert result == "ws://localhost:4000"
    end

    test "raises when variable without default is not set" do
      System.delete_env("MISSING_VAR")

      assert_raise RuntimeError, "environment variable MISSING_VAR is not set", fn ->
        ChannelConfig.expand_env_vars("${MISSING_VAR}")
      end
    end

    test "expands variables in auth context during validation" do
      System.put_env("CHANNEL_TOKEN", "secret_token")

      assert {:ok, config} = ChannelConfig.validate(%{
        "topic" => "jido:ui",
        "auth" => %{
          "type" => "token",
          "token" => "${CHANNEL_TOKEN}"
        }
      })

      assert config.auth["token"] == "secret_token"

      System.delete_env("CHANNEL_TOKEN")
    end
  end

  describe "defaults/0" do
    test "returns map with three default channels" do
      defaults = ChannelConfig.defaults()

      assert is_map(defaults)
      assert Map.has_key?(defaults, "ui_state")
      assert Map.has_key?(defaults, "agent")
      assert Map.has_key?(defaults, "hooks")
    end

    test "ui_state channel has correct configuration" do
      defaults = ChannelConfig.defaults()
      ui_state = defaults["ui_state"]

      assert ui_state.socket == "ws://localhost:4000/socket"
      assert ui_state.topic == "jido:ui"
      assert ui_state.auth == nil
      assert ui_state.broadcast_events == ["state_change", "progress", "error"]
    end

    test "agent channel has correct configuration" do
      defaults = ChannelConfig.defaults()
      agent = defaults["agent"]

      assert agent.socket == "ws://localhost:4000/socket"
      assert agent.topic == "jido:agent"
      assert agent.auth == nil
      assert agent.broadcast_events == ["started", "stopped", "state_changed"]
    end

    test "hooks channel has correct configuration" do
      defaults = ChannelConfig.defaults()
      hooks = defaults["hooks"]

      assert hooks.socket == "ws://localhost:4000/socket"
      assert hooks.topic == "jido:hooks"
      assert hooks.auth == nil
      assert hooks.broadcast_events == ["triggered", "completed", "failed"]
    end

    test "all defaults pass validation" do
      defaults = ChannelConfig.defaults()

      Enum.each(defaults, fn {_name, config} ->
        assert {:ok, _validated} = ChannelConfig.validate(%{
          "socket" => config.socket,
          "topic" => config.topic,
          "auth" => config.auth,
          "broadcast_events" => config.broadcast_events
        })
      end)
    end
  end
end
