defmodule JidoCode.Extensibility.Skills.ConfigLoaderTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility.Skills.ConfigLoader
  alias JidoCode.Extensibility.{ChannelConfig, Permissions, Error}

  describe "load_for_agent/0" do
    test "returns default configuration when settings are empty" do
      # This test assumes Settings.get() returns empty map
      # The actual behavior depends on Settings implementation
      config = ConfigLoader.load_for_agent()

      assert is_map(config)
      assert Map.has_key?(config, :permissions)
      assert Map.has_key?(config, :channels)
      assert %Permissions{} = config.permissions
      assert is_map(config.channels)
    end

    test "returns configuration with valid permissions structure" do
      config = ConfigLoader.load_for_agent()

      assert %Permissions{
        allow: allow_list,
        deny: deny_list,
        ask: ask_list,
        default_mode: :deny
      } = config.permissions

      assert is_list(allow_list)
      assert is_list(deny_list)
      assert is_list(ask_list)
    end

    test "returns configuration with valid channels structure" do
      config = ConfigLoader.load_for_agent()

      assert is_map(config.channels)
      # Check that default channels exist
      assert Map.has_key?(config.channels, "ui_state")
      assert Map.has_key?(config.channels, "agent")
      assert Map.has_key?(config.channels, "hooks")
    end
  end

  describe "load_for_agent/1" do
    test "returns same config when agent_name is nil" do
      config_nil = ConfigLoader.load_for_agent(nil)
      config_no_arg = ConfigLoader.load_for_agent()

      assert config_nil.permissions == config_no_arg.permissions
      assert config_nil.channels == config_no_arg.channels
    end

    test "accepts atom agent name" do
      # Should not raise
      config = ConfigLoader.load_for_agent(:llm_agent)

      assert is_map(config)
      assert Map.has_key?(config, :permissions)
      assert Map.has_key?(config, :channels)
    end

    test "accepts string agent name" do
      # Should not raise
      config = ConfigLoader.load_for_agent("llm_agent")

      assert is_map(config)
      assert Map.has_key?(config, :permissions)
      assert Map.has_key?(config, :channels)
    end
  end

  describe "load_from_settings/2" do
    test "loads configuration from valid settings map" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*", "Write:*"],
            "deny" => ["*delete*"]
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings)
      assert %Permissions{} = config.permissions
      assert "Read:*" in config.permissions.allow
      assert "*delete*" in config.permissions.deny
    end

    test "returns defaults when extensibility key is missing" do
      settings = %{}

      assert {:ok, config} = ConfigLoader.load_from_settings(settings)
      assert %Permissions{} = config.permissions
      assert is_map(config.channels)
    end

    test "applies agent-specific overrides when provided" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*"]
          },
          "agents" => %{
            "llm_agent" => %{
              "permissions" => %{
                "allow" => ["Read:*", "run_command:*"]
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      assert "Read:*" in config.permissions.allow
      assert "run_command:*" in config.permissions.allow
    end

    test "ignores agent-specific overrides for different agent" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*"]
          },
          "agents" => %{
            "task_agent" => %{
              "permissions" => %{
                "allow" => ["run_command:*"]
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # Should have base allow, not task_agent's override
      assert "Read:*" in config.permissions.allow
      # run_command:* should NOT be in allow list
      refute "run_command:*" in config.permissions.allow
    end

    test "merges agent-specific channel overrides" do
      settings = %{
        "extensibility" => %{
          "channels" => %{
            "ui_state" => %{
              "socket" => "ws://localhost:4000/socket",
              "topic" => "jido:ui"
            }
          },
          "agents" => %{
            "llm_agent" => %{
              "channels" => %{
                "custom_channel" => %{
                  "socket" => "ws://localhost:4000/socket",
                  "topic" => "jido:custom"
                }
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # Should have both base and custom channels
      assert Map.has_key?(config.channels, "ui_state")
      assert Map.has_key?(config.channels, "custom_channel")
    end

    test "returns error for invalid permissions configuration" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => "not_a_list"
          }
        }
      }

      assert {:error, %Error{code: :field_list_invalid}} =
        ConfigLoader.load_from_settings(settings)
    end

    test "returns error for invalid channel configuration" do
      settings = %{
        "extensibility" => %{
          "channels" => %{
            "bad_channel" => %{
              "socket" => "invalid://url",
              "topic" => "jido:test"
            }
          }
        }
      }

      assert {:error, %Error{code: :socket_invalid}} =
        ConfigLoader.load_from_settings(settings)
    end
  end

  describe "defaults/0" do
    test "returns default configuration" do
      config = ConfigLoader.defaults()

      assert is_map(config)
      assert Map.has_key?(config, :permissions)
      assert Map.has_key?(config, :channels)
    end

    test "default permissions include safe file operations" do
      config = ConfigLoader.defaults()

      assert "Read:*" in config.permissions.allow
      assert "Write:*" in config.permissions.allow
      assert "Edit:*" in config.permissions.allow
    end

    test "default permissions deny dangerous operations" do
      config = ConfigLoader.defaults()

      assert "*delete*" in config.permissions.deny
      assert "*remove*" in config.permissions.deny
      assert "*shutdown*" in config.permissions.deny
    end

    test "default permissions ask for risky operations" do
      config = ConfigLoader.defaults()

      assert "web_fetch:*" in config.permissions.ask
      assert "web_search:*" in config.permissions.ask
    end

    test "default permissions use deny as default mode" do
      config = ConfigLoader.defaults()

      assert config.permissions.default_mode == :deny
    end

    test "default channels include standard channels" do
      config = ConfigLoader.defaults()

      assert Map.has_key?(config.channels, "ui_state")
      assert Map.has_key?(config.channels, "agent")
      assert Map.has_key?(config.channels, "hooks")
    end

    test "default channels have valid configurations" do
      config = ConfigLoader.defaults()

      ui_state = config.channels["ui_state"]
      assert %ChannelConfig{socket: socket, topic: topic} = ui_state
      assert String.starts_with?(socket, ["ws://", "wss://"])
      assert is_binary(topic)
      assert topic != ""
    end
  end

  describe "permission merging" do
    test "agent override replaces base allow list" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*", "Write:*"]
          },
          "agents" => %{
            "llm_agent" => %{
              "permissions" => %{
                "allow" => ["run_command:*"]
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # Allow list should be replaced, not merged
      assert config.permissions.allow == ["run_command:*"]
    end

    test "agent override can inherit base with explicit list" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*"]
          },
          "agents" => %{
            "llm_agent" => %{
              "permissions" => %{
                "allow" => ["Read:*", "run_command:*"]
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      assert "Read:*" in config.permissions.allow
      assert "run_command:*" in config.permissions.allow
    end

    test "agent override default_mode is inherited if not specified" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*"],
            "default_mode" => "allow"
          },
          "agents" => %{
            "llm_agent" => %{
              "permissions" => %{
                "allow" => ["run_command:*"]
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # default_mode should be inherited from base
      assert config.permissions.default_mode == :allow
    end

    test "agent override can specify default_mode" do
      settings = %{
        "extensibility" => %{
          "permissions" => %{
            "allow" => ["Read:*"],
            "default_mode" => "allow"
          },
          "agents" => %{
            "llm_agent" => %{
              "permissions" => %{
                "allow" => ["run_command:*"],
                "default_mode" => "deny"
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # default_mode should be overridden
      assert config.permissions.default_mode == :deny
    end
  end

  describe "channel merging" do
    test "agent override adds new channels" do
      settings = %{
        "extensibility" => %{
          "channels" => %{
            "base_channel" => %{
              "socket" => "ws://localhost:4000/socket",
              "topic" => "jido:base"
            }
          },
          "agents" => %{
            "llm_agent" => %{
              "channels" => %{
                "agent_channel" => %{
                  "socket" => "ws://localhost:4000/socket",
                  "topic" => "jido:agent"
                }
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # Should have both channels
      assert Map.has_key?(config.channels, "base_channel")
      assert Map.has_key?(config.channels, "agent_channel")
    end

    test "agent override can replace base channel" do
      settings = %{
        "extensibility" => %{
          "channels" => %{
            "shared_channel" => %{
              "socket" => "ws://localhost:4000/socket",
              "topic" => "jido:base"
            }
          },
          "agents" => %{
            "llm_agent" => %{
              "channels" => %{
                "shared_channel" => %{
                  "socket" => "ws://localhost:4000/socket",
                  "topic" => "jido:agent"
                }
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # Agent's topic should override base
      assert config.channels["shared_channel"].topic == "jido:agent"
    end

    test "invalid agent channel config is skipped" do
      settings = %{
        "extensibility" => %{
          "channels" => %{
            "valid_channel" => %{
              "socket" => "ws://localhost:4000/socket",
              "topic" => "jido:valid"
            }
          },
          "agents" => %{
            "llm_agent" => %{
              "channels" => %{
                "invalid_channel" => %{
                  "socket" => "invalid://url",
                  "topic" => "jido:invalid"
                }
              }
            }
          }
        }
      }

      assert {:ok, config} = ConfigLoader.load_from_settings(settings, "llm_agent")
      # Valid channel should be present
      assert Map.has_key?(config.channels, "valid_channel")
      # Invalid channel should be skipped
      refute Map.has_key?(config.channels, "invalid_channel")
    end
  end
end
