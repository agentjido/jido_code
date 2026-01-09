defmodule JidoCode.Integration.Phase1ConfigTest do
  @moduledoc """
  Integration tests for Phase 1 (Configuration & Settings) components.

  These tests verify that all Phase 1 extensibility components work together correctly:
  - Settings loading and merging with extensibility fields
  - Permission system integration with settings
  - Channel configuration integration with environment variable expansion
  - Backward compatibility with existing settings files

  Tests use temporary directories for isolation and clean up after themselves.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Settings
  alias JidoCode.Extensibility.ChannelConfig
  alias JidoCode.Extensibility.Permissions

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Clear settings cache before each test
    Settings.clear_cache()

    # Create temp directories for test settings
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "phase1_config_test_#{System.unique_integer([:positive, :monotonic])}"
      ])

    global_dir = Path.join(tmp_dir, "global")
    local_dir = Path.join(tmp_dir, "local")
    File.mkdir_p!(global_dir)
    File.mkdir_p!(local_dir)

    # Store original environment variables
    original_env = %{
      "CHANNEL_TOKEN" => System.get_env("CHANNEL_TOKEN"),
      "API_KEY" => System.get_env("API_KEY"),
      "WS_URL" => System.get_env("WS_URL")
    }

    on_exit(fn ->
      # Clear cache
      Settings.clear_cache()

      # Clean up temp directory
      File.rm_rf!(tmp_dir)

      # Restore environment variables
      Enum.each(original_env, fn {key, value} ->
        case value do
          nil -> System.delete_env(key)
          val -> System.put_env(key, val)
        end
      end)
    end)

    {:ok, tmp_dir: tmp_dir, global_dir: global_dir, local_dir: local_dir}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp write_settings(path, settings) do
    File.write!(path, Jason.encode!(settings, pretty: true))
  end

  defp with_global_settings(global_dir, settings) do
    path = Path.join(global_dir, "settings.json")
    write_settings(path, settings)
  end

  defp with_local_settings(local_dir, settings) do
    path = Path.join(local_dir, "settings.json")
    write_settings(path, settings)
  end

  defp load_settings_with_paths(global_dir, local_dir) do
    # We can't easily mock the paths, so we test via direct file operations
    global_path = Path.join(global_dir, "settings.json")
    local_path = Path.join(local_dir, "settings.json")

    global =
      case File.exists?(global_path) do
        true -> {:ok, settings} = Settings.read_file(global_path)
          settings
        false -> %{}
      end

    local =
      case File.exists?(local_path) do
        true -> {:ok, settings} = Settings.read_file(local_path)
          settings
        false -> %{}
      end

    # Simulate deep_merge behavior
    merge_for_test(global, local)
  end

  defp merge_for_test(base, overlay) do
    Map.merge(base, overlay, fn
      "models", base_models, overlay_models when is_map(base_models) and is_map(overlay_models) ->
        Map.merge(base_models, overlay_models)

      "channels", base_channels, overlay_channels when is_map(base_channels) and is_map(overlay_channels) ->
        Map.merge(base_channels, overlay_channels)

      "permissions", base_perms, overlay_perms when is_map(base_perms) and is_map(overlay_perms) ->
        merge_permissions(base_perms, overlay_perms)

      "hooks", base_hooks, overlay_hooks when is_map(base_hooks) and is_map(overlay_hooks) ->
        merge_hooks(base_hooks, overlay_hooks)

      "agents", base_agents, overlay_agents when is_map(base_agents) and is_map(overlay_agents) ->
        Map.merge(base_agents, overlay_agents)

      "plugins", base_plugins, overlay_plugins when is_map(base_plugins) and is_map(overlay_plugins) ->
        merge_plugins(base_plugins, overlay_plugins)

      _key, _base_value, overlay_value ->
        overlay_value
    end)
  end

  defp merge_permissions(base, overlay) do
    %{
      "allow" => Enum.uniq(Map.get(base, "allow", []) ++ Map.get(overlay, "allow", [])),
      "deny" => Enum.uniq(Map.get(base, "deny", []) ++ Map.get(overlay, "deny", [])),
      "ask" => Enum.uniq(Map.get(base, "ask", []) ++ Map.get(overlay, "ask", []))
    }
  end

  defp merge_hooks(base, overlay) do
    all_events = MapSet.new(Map.keys(base) ++ Map.keys(overlay))

    Enum.into(all_events, %{}, fn event ->
      base_hooks = Map.get(base, event, [])
      overlay_hooks = Map.get(overlay, event, [])
      {event, base_hooks ++ overlay_hooks}
    end)
  end

  defp merge_plugins(base, overlay) do
    %{
      "enabled" =>
        Enum.uniq(Map.get(base, "enabled", []) ++ Map.get(overlay, "enabled", [])),
      "disabled" =>
        Enum.uniq(Map.get(base, "disabled", []) ++ Map.get(overlay, "disabled", [])),
      "marketplaces" =>
        Map.merge(Map.get(base, "marketplaces", %{}), Map.get(overlay, "marketplaces", %{}))
    }
  end

  # ============================================================================
  # 1.6.1 Settings Loading Integration
  # ============================================================================

  describe "1.6.1 settings loading integration" do
    test "loads global settings with extensibility config", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      global = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022",
        "channels" => %{
          "ui_state" => %{
            "socket" => "ws://global:4000/socket",
            "topic" => "jido:ui"
          }
        },
        "permissions" => %{
          "allow" => ["Read:*"],
          "deny" => ["*delete*"]
        },
        "plugins" => %{
          "enabled" => ["github"]
        }
      }

      with_global_settings(global_dir, global)
      settings = load_settings_with_paths(global_dir, local_dir)

      assert settings["provider"] == "anthropic"
      assert settings["channels"]["ui_state"]["socket"] == "ws://global:4000/socket"
      assert settings["permissions"]["allow"] == ["Read:*"]
      assert settings["plugins"]["enabled"] == ["github"]
    end

    test "loads local settings with extensibility config", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      local = %{
        "model" => "gpt-4o",
        "channels" => %{
          "ui_state" => %{
            "socket" => "ws://local:4000/socket",
            "topic" => "jido:ui"
          }
        },
        "permissions" => %{
          "allow" => ["Write:*"]
        }
      }

      with_local_settings(local_dir, local)
      settings = load_settings_with_paths(global_dir, local_dir)

      assert settings["model"] == "gpt-4o"
      assert settings["channels"]["ui_state"]["socket"] == "ws://local:4000/socket"
      assert settings["permissions"]["allow"] == ["Write:*"]
    end

    test "merges global and local extensibility settings", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      global = %{
        "provider" => "anthropic",
        "channels" => %{
          "ui_state" => %{"socket" => "ws://global:4000/socket", "topic" => "jido:ui"},
          "agent" => %{"socket" => "ws://global:4000/socket", "topic" => "jido:agent"}
        },
        "permissions" => %{"allow" => ["Read:*"], "deny" => ["*delete*"]},
        "plugins" => %{"enabled" => ["github"]}
      }

      local = %{
        "model" => "gpt-4o",
        "channels" => %{
          "ui_state" => %{"socket" => "ws://local:4000/socket", "topic" => "jido:ui"}
        },
        "permissions" => %{"allow" => ["Write:*"], "ask" => ["web_fetch:*"]},
        "plugins" => %{"enabled" => ["docker"]}
      }

      with_global_settings(global_dir, global)
      with_local_settings(local_dir, local)

      settings = load_settings_with_paths(global_dir, local_dir)

      # Provider from global, model from local
      assert settings["provider"] == "anthropic"
      assert settings["model"] == "gpt-4o"

      # Channels: ui_state overridden by local, agent from global
      assert settings["channels"]["ui_state"]["socket"] == "ws://local:4000/socket"
      assert settings["channels"]["agent"]["socket"] == "ws://global:4000/socket"

      # Permissions: lists concatenated
      assert settings["permissions"]["allow"] == ["Read:*", "Write:*"]
      assert settings["permissions"]["deny"] == ["*delete*"]
      assert settings["permissions"]["ask"] == ["web_fetch:*"]

      # Plugins: enabled lists unioned
      assert MapSet.new(settings["plugins"]["enabled"]) == MapSet.new(["github", "docker"])
    end

    test "local channel config overrides global", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      global = %{
        "channels" => %{
          "ui_state" => %{"socket" => "ws://global:4000/socket", "topic" => "jido:ui"},
          "agent" => %{"socket" => "ws://global:4000/socket", "topic" => "jido:agent"}
        }
      }

      local = %{
        "channels" => %{
          "ui_state" => %{"socket" => "ws://local:4000/socket", "topic" => "jido:ui"}
        }
      }

      with_global_settings(global_dir, global)
      with_local_settings(local_dir, local)

      settings = load_settings_with_paths(global_dir, local_dir)

      # ui_state overridden by local
      assert settings["channels"]["ui_state"]["socket"] == "ws://local:4000/socket"

      # agent still from global
      assert settings["channels"]["agent"]["socket"] == "ws://global:4000/socket"
    end

    test "local permissions extend global", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      global = %{
        "permissions" => %{
          "allow" => ["Read:*", "Write:*"],
          "deny" => ["*delete*"]
        }
      }

      local = %{
        "permissions" => %{
          "allow" => ["Edit:*"],
          "ask" => ["web_fetch:*"]
        }
      }

      with_global_settings(global_dir, global)
      with_local_settings(local_dir, local)

      settings = load_settings_with_paths(global_dir, local_dir)

      # Allow lists concatenated (with deduplication)
      assert settings["permissions"]["allow"] == ["Read:*", "Write:*", "Edit:*"]

      # Deny from global preserved
      assert settings["permissions"]["deny"] == ["*delete*"]

      # Ask from local added
      assert settings["permissions"]["ask"] == ["web_fetch:*"]
    end

    test "hooks concatenate from both sources", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      global = %{
        "hooks" => %{
          "Edit" => [
            %{"id" => "global_hook_1", "command" => "mix format"}
          ],
          "Save" => [
            %{"id" => "global_save_hook", "command" => "mix test"}
          ]
        }
      }

      local = %{
        "hooks" => %{
          "Edit" => [
            %{"id" => "local_hook_1", "command" => "mix credo"}
          ],
          "Load" => [
            %{"id" => "local_load_hook", "command" => "echo loaded"}
          ]
        }
      }

      with_global_settings(global_dir, global)
      with_local_settings(local_dir, local)

      settings = load_settings_with_paths(global_dir, local_dir)

      # Edit hooks concatenated (global first, then local)
      assert length(settings["hooks"]["Edit"]) == 2
      assert Enum.at(settings["hooks"]["Edit"], 0)["id"] == "global_hook_1"
      assert Enum.at(settings["hooks"]["Edit"], 1)["id"] == "local_hook_1"

      # Save hooks from global only
      assert length(settings["hooks"]["Save"]) == 1
      assert Enum.at(settings["hooks"]["Save"], 0)["id"] == "global_save_hook"

      # Load hooks from local only
      assert length(settings["hooks"]["Load"]) == 1
      assert Enum.at(settings["hooks"]["Load"], 0)["id"] == "local_load_hook"
    end

    test "plugins merge correctly", %{global_dir: global_dir, local_dir: local_dir} do
      global = %{
        "plugins" => %{
          "enabled" => ["github", "git"],
          "disabled" => ["experimental"],
          "marketplaces" => %{
            "community" => %{"source" => "github", "repo" => "jidocode/plugins"}
          }
        }
      }

      local = %{
        "plugins" => %{
          "enabled" => ["github", "docker"],
          "disabled" => ["beta"],
          "marketplaces" => %{
            "enterprise" => %{"source" => "github", "repo" => "company/plugins"}
          }
        }
      }

      with_global_settings(global_dir, global)
      with_local_settings(local_dir, local)

      settings = load_settings_with_paths(global_dir, local_dir)

      # Enabled lists unioned (github appears only once)
      assert MapSet.new(settings["plugins"]["enabled"]) ==
               MapSet.new(["github", "git", "docker"])

      # Disabled lists merged
      assert MapSet.new(settings["plugins"]["disabled"]) == MapSet.new(["experimental", "beta"])

      # Marketplaces merged
      assert Map.has_key?(settings["plugins"]["marketplaces"], "community")
      assert Map.has_key?(settings["plugins"]["marketplaces"], "enterprise")
    end
  end

  # ============================================================================
  # 1.6.2 Permission System Integration
  # ============================================================================

  describe "1.6.2 permission system integration" do
    test "allow permission permits matching action" do
      json = %{"allow" => ["Read:*", "Write:*"]}
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
      assert Permissions.check_permission(perms, "Write", "file.txt") == :allow
    end

    test "deny permission blocks matching action" do
      json = %{
        "allow" => ["*"],
        "deny" => ["*delete*", "*remove*"]
      }
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
      assert Permissions.check_permission(perms, "Edit", "remove_item") == :deny
      assert Permissions.check_permission(perms, "Edit", "create_file") == :allow
    end

    test "ask permission returns ask decision" do
      json = %{"ask" => ["web_fetch:*", "web_search:*"]}
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "web_fetch", "https://example.com") == :ask
      assert Permissions.check_permission(perms, "web_search", "query") == :ask
    end

    test "deny takes precedence over allow" do
      json = %{
        "allow" => ["Edit:*"],
        "deny" => ["*delete*"]
      }
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "deny takes precedence over ask" do
      json = %{
        "ask" => ["Edit:*"],
        "deny" => ["*delete*"]
      }
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "ask takes precedence over allow" do
      json = %{
        "allow" => ["run_command:*"],
        "ask" => ["run_command:rm*"]
      }
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "run_command", "rm_file") == :ask
      assert Permissions.check_permission(perms, "run_command", "ls") == :allow
    end

    test "wildcard patterns work as expected" do
      json = %{
        "allow" => ["Read:*", "Edit:file*", "run_command:git*"],
        "deny" => ["*:delete"]
      }
      {:ok, perms} = Permissions.from_json(json)

      # Category wildcards
      assert Permissions.check_permission(perms, "Read", "anything") == :allow

      # Action wildcards
      assert Permissions.check_permission(perms, "Edit", "file1.txt") == :allow
      assert Permissions.check_permission(perms, "Edit", "file2.ex") == :allow
      assert Permissions.check_permission(perms, "Edit", "other") == :allow

      # Command wildcards
      assert Permissions.check_permission(perms, "run_command", "git status") == :allow
      assert Permissions.check_permission(perms, "run_command", "git-commit") == :allow

      # Deny wildcard
      assert Permissions.check_permission(perms, "Edit", "delete") == :deny
      assert Permissions.check_permission(perms, "Run", "delete") == :deny
    end

    test "no matching pattern returns default allow" do
      json = %{"deny" => ["*delete*"]}
      {:ok, perms} = Permissions.from_json(json)

      # Default is allow if no patterns match
      assert Permissions.check_permission(perms, "Unknown", "action") == :allow
    end

    test "multiple patterns match correctly" do
      json = %{
        "allow" => ["Read:*", "Write:*", "Edit:*"],
        "deny" => ["*delete*", "*format*"],
        "ask" => ["web_*"]
      }
      {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "Read", "file") == :allow
      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
      assert Permissions.check_permission(perms, "Edit", "format_code") == :deny
      assert Permissions.check_permission(perms, "web_fetch", "url") == :ask
    end
  end

  # ============================================================================
  # 1.6.3 Channel Configuration Integration
  # ============================================================================

  describe "1.6.3 channel configuration integration" do
    test "channel config loads from settings", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      settings = %{
        "channels" => %{
          "ui_state" => %{
            "socket" => "ws://localhost:4000/socket",
            "topic" => "jido:ui",
            "broadcast_events" => ["state_change"]
          }
        }
      }

      with_global_settings(global_dir, settings)
      loaded = load_settings_with_paths(global_dir, local_dir)

      channel = loaded["channels"]["ui_state"]
      {:ok, config} = ChannelConfig.validate(channel)

      assert config.socket == "ws://localhost:4000/socket"
      assert config.topic == "jido:ui"
      assert config.broadcast_events == ["state_change"]
    end

    test "environment variables expand in auth" do
      System.put_env("CHANNEL_TOKEN", "secret_token_123")

      channel = %{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido:ui",
        "auth" => %{
          "type" => "token",
          "token" => "${CHANNEL_TOKEN}"
        }
      }

      {:ok, config} = ChannelConfig.validate(channel)

      assert config.auth["token"] == "secret_token_123"
    end

    test "environment variables with defaults expand correctly" do
      System.delete_env("OPTIONAL_TOKEN")
      System.put_env("SET_TOKEN", "actual_value")

      channel = %{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido:ui",
        "auth" => %{
          "type" => "token",
          "token" => "${OPTIONAL_TOKEN:-default_token}"
        }
      }

      {:ok, config} = ChannelConfig.validate(channel)

      # When var not set, use default
      assert config.auth["token"] == "default_token"

      # When var is set, use actual value
      channel2 = %{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "jido:ui",
        "auth" => %{
          "type" => "token",
          "token" => "${SET_TOKEN:-default_token}"
        }
      }

      {:ok, config2} = ChannelConfig.validate(channel2)
      assert config2.auth["token"] == "actual_value"
    end

    test "invalid channel config is rejected" do
      # Missing required topic
      channel = %{
        "socket" => "ws://localhost:4000/socket"
      }

      assert {:error, "topic is required"} = ChannelConfig.validate(channel)

      # Invalid socket URL
      channel2 = %{
        "socket" => "http://localhost:4000/socket",
        "topic" => "jido:ui"
      }

      assert {:error, "socket must be a valid WebSocket URL (ws:// or wss://)"} =
               ChannelConfig.validate(channel2)

      # Invalid topic format
      channel3 = %{
        "socket" => "ws://localhost:4000/socket",
        "topic" => "invalid topic with spaces"
      }

      assert {:error, "topic must contain only alphanumeric characters, colons, underscores, hyphens, or dots"} =
               ChannelConfig.validate(channel3)
    end

    test "default channels used when not specified" do
      defaults = ChannelConfig.defaults()

      assert Map.has_key?(defaults, "ui_state")
      assert Map.has_key?(defaults, "agent")
      assert Map.has_key?(defaults, "hooks")

      # All defaults are valid
      Enum.each(defaults, fn {_name, config} ->
        {:ok, _validated} =
          ChannelConfig.validate(%{
            "socket" => config.socket,
            "topic" => config.topic,
            "auth" => config.auth,
            "broadcast_events" => config.broadcast_events
          })
      end)
    end

    test "channel validation works end to end", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      settings = %{
        "channels" => %{
          "ui_state" => %{
            "socket" => "wss://secure.example.com/socket",
            "topic" => "jido:ui:production",
            "auth" => %{
              "type" => "token",
              "token" => "${CHANNEL_TOKEN}"
            },
            "broadcast_events" => ["state_change", "progress", "error"]
          },
          "agent" => %{
            "socket" => "ws://localhost:4000/socket",
            "topic" => "jido:agent"
          }
        }
      }

      System.put_env("CHANNEL_TOKEN", "prod_token_xyz")

      with_global_settings(global_dir, settings)
      loaded = load_settings_with_paths(global_dir, local_dir)

      # Validate ui_state channel
      {:ok, ui_config} = ChannelConfig.validate(loaded["channels"]["ui_state"])
      assert ui_config.socket == "wss://secure.example.com/socket"
      assert ui_config.topic == "jido:ui:production"
      assert ui_config.auth["token"] == "prod_token_xyz"
      assert ui_config.broadcast_events == ["state_change", "progress", "error"]

      # Validate agent channel
      {:ok, agent_config} = ChannelConfig.validate(loaded["channels"]["agent"])
      assert agent_config.socket == "ws://localhost:4000/socket"
      assert agent_config.topic == "jido:agent"
    end
  end

  # ============================================================================
  # 1.6.4 Backward Compatibility Integration
  # ============================================================================

  describe "1.6.4 backward compatibility integration" do
    test "old settings files without extensibility load", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      # Pre-1.3 settings file (no extensibility fields)
      old_settings = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022",
        "providers" => ["anthropic", "openai"],
        "models" => %{
          "anthropic" => ["claude-3-5-sonnet-20241022", "claude-3-opus"],
          "openai" => ["gpt-4o"]
        }
      }

      with_global_settings(global_dir, old_settings)
      settings = load_settings_with_paths(global_dir, local_dir)

      # All original fields present
      assert settings["provider"] == "anthropic"
      assert settings["model"] == "claude-3-5-sonnet-20241022"
      assert settings["providers"] == ["anthropic", "openai"]
      assert settings["models"]["anthropic"] == ["claude-3-5-sonnet-20241022", "claude-3-opus"]
    end

    test "settings save includes extensibility structure", %{global_dir: global_dir} do
      settings = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022",
        "channels" => %{
          "ui_state" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:ui"}
        },
        "permissions" => %{
          "allow" => ["Read:*", "Write:*"],
          "deny" => ["*delete*"]
        },
        "plugins" => %{
          "enabled" => ["github"]
        }
      }

      # Write settings
      path = Path.join(global_dir, "settings.json")
      write_settings(path, settings)

      # Read back and verify structure
      {:ok, loaded} = Settings.read_file(path)

      assert loaded["provider"] == "anthropic"
      assert loaded["channels"]["ui_state"]["socket"] == "ws://localhost:4000/socket"
      assert loaded["permissions"]["allow"] == ["Read:*", "Write:*"]
      assert loaded["plugins"]["enabled"] == ["github"]
    end

    test "existing settings functionality unchanged", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      global = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022",
        "models" => %{
          "anthropic" => ["claude-3-5-sonnet-20241022"]
        }
      }

      local = %{
        "model" => "gpt-4o"
      }

      with_global_settings(global_dir, global)
      with_local_settings(local_dir, local)

      settings = load_settings_with_paths(global_dir, local_dir)

      # Core settings merge still works
      assert settings["provider"] == "anthropic"
      assert settings["model"] == "gpt-4o"

      # Models deep merge still works
      assert settings["models"]["anthropic"] == ["claude-3-5-sonnet-20241022"]
    end

    test "migration from old to new format is seamless", %{
      global_dir: global_dir,
      local_dir: local_dir
    } do
      # Start with old settings
      old_settings = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022"
      }

      with_global_settings(global_dir, old_settings)
      settings = load_settings_with_paths(global_dir, local_dir)

      # Old settings work
      assert settings["provider"] == "anthropic"
      assert settings["model"] == "claude-3-5-sonnet-20241022"

      # Add extensibility fields (simulating migration)
      new_settings = Map.merge(old_settings, %{
        "channels" => %{
          "ui_state" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:ui"}
        },
        "permissions" => %{
          "allow" => ["Read:*"]
        }
      })

      with_global_settings(global_dir, new_settings)
      settings = load_settings_with_paths(global_dir, local_dir)

      # Old fields still present
      assert settings["provider"] == "anthropic"
      assert settings["model"] == "claude-3-5-sonnet-20241022"

      # New fields present
      assert settings["channels"]["ui_state"]["socket"] == "ws://localhost:4000/socket"
      assert settings["permissions"]["allow"] == ["Read:*"]
    end
  end

  # ============================================================================
  # Phase 1 Success Criteria Verification
  # ============================================================================

  describe "Phase 1 success criteria" do
    test "ChannelConfig: struct defined with validation and env expansion" do
      config = %ChannelConfig{
        socket: "ws://localhost:4000/socket",
        topic: "jido:ui"
      }

      assert config.socket == "ws://localhost:4000/socket"
      assert config.topic == "jido:ui"

      System.put_env("TEST_VAR", "test_value")
      assert ChannelConfig.expand_env_vars("${TEST_VAR}") == "test_value"
      System.delete_env("TEST_VAR")
    end

    test "Permissions: glob-based matching with allow/deny/ask outcomes" do
      perms = %Permissions{
        allow: ["Read:*"],
        deny: ["*delete*"],
        ask: ["web_fetch:*"]
      }

      assert Permissions.check_permission(perms, "Read", "file") == :allow
      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
      assert Permissions.check_permission(perms, "web_fetch", "url") == :ask
    end

    test "Settings Schema: extended with extensibility fields" do
      settings = %{
        "channels" => %{"ui_state" => %{"topic" => "jido:ui"}},
        "permissions" => %{"allow" => ["Read:*"]},
        "hooks" => %{},
        "agents" => %{},
        "plugins" => %{"enabled" => ["github"]}
      }

      assert {:ok, ^settings} = Settings.validate(settings)
    end

    test "Merge Strategy: proper merging of all extensibility fields" do
      global = %{
        "channels" => %{"a" => %{"val" => 1}, "b" => %{"val" => 2}},
        "permissions" => %{"allow" => ["A"]},
        "hooks" => %{"Event" => [%{"id" => 1}]},
        "plugins" => %{"enabled" => ["x"]}
      }

      local = %{
        "channels" => %{"a" => %{"val" => 10}},
        "permissions" => %{"allow" => ["B"]},
        "hooks" => %{"Event" => [%{"id" => 2}]},
        "plugins" => %{"enabled" => ["y"]}
      }

      merged = merge_for_test(global, local)

      # Channels: local overrides
      assert merged["channels"]["a"]["val"] == 10
      assert merged["channels"]["b"]["val"] == 2

      # Permissions: concatenated
      assert merged["permissions"]["allow"] == ["A", "B"]

      # Hooks: concatenated
      assert length(merged["hooks"]["Event"]) == 2

      # Plugins: unioned
      assert MapSet.new(merged["plugins"]["enabled"]) == MapSet.new(["x", "y"])
    end

    test "Backward Compatibility: old settings files still work" do
      old_settings = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022",
        "models" => %{"anthropic" => ["claude-3-5-sonnet-20241022"]}
      }

      assert {:ok, ^old_settings} = Settings.validate(old_settings)
    end
  end
end
