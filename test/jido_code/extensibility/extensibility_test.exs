defmodule JidoCode.ExtensibilityTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility
  alias JidoCode.Extensibility.{ChannelConfig, Permissions, Error}

  describe "load_extensions/1" do
    test "loads valid extensions from settings map" do
      settings = %{
        channels: %{
          "ui" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:ui"}
        },
        permissions: %{
          "allow" => ["Read:*"],
          "deny" => ["*delete*"]
        }
      }

      assert {:ok, ext} = Extensibility.load_extensions(settings)
      assert is_map(ext.channels)
      assert ext.channels["ui"].topic == "jido:ui"
      assert ext.permissions.allow == ["Read:*"]
      assert ext.permissions.deny == ["*delete*"]
    end

    test "uses defaults when channels is nil" do
      settings = %{
        channels: nil,
        permissions: nil
      }

      assert {:ok, ext} = Extensibility.load_extensions(settings)
      assert Map.has_key?(ext.channels, "ui_state")
      assert Map.has_key?(ext.channels, "agent")
      assert Map.has_key?(ext.channels, "hooks")
      assert ext.permissions == nil
    end

    test "returns error when channel config is invalid" do
      settings = %{
        channels: %{
          "ui" => %{"socket" => "invalid-url", "topic" => "jido:ui"}
        },
        permissions: nil
      }

      assert {:error, %Error{code: :socket_invalid}} =
               Extensibility.load_extensions(settings)
    end

    test "returns error when permissions config is invalid" do
      settings = %{
        channels: nil,
        permissions: %{"allow" => "not_a_list"}
      }

      assert {:error, %Error{code: :field_list_invalid}} =
               Extensibility.load_extensions(settings)
    end

    test "handles string keys in settings map" do
      settings = %{
        "channels" => %{
          "ui" => %{"socket" => "ws://localhost:4000/socket", "topic" => "jido:ui"}
        },
        "permissions" => %{
          "allow" => ["Read:*"]
        }
      }

      assert {:ok, ext} = Extensibility.load_extensions(settings)
      assert is_map(ext.channels)
    end
  end

  describe "validate_channel_config/1" do
    test "delegates to ChannelConfig.validate/1" do
      assert {:ok, config} =
               Extensibility.validate_channel_config(%{
                 "socket" => "ws://localhost:4000/socket",
                 "topic" => "jido:ui"
               })

      assert config.topic == "jido:ui"
    end

    test "returns error for invalid config" do
      assert {:error, %Error{}} =
               Extensibility.validate_channel_config(%{
                 "socket" => "invalid-url",
                 "topic" => "jido:ui"
               })
    end
  end

  describe "validate_permissions/1" do
    test "delegates to Permissions.from_json/1" do
      assert {:ok, perms} =
               Extensibility.validate_permissions(%{
                 "allow" => ["Read:*"],
                 "deny" => ["*delete*"]
               })

      assert perms.allow == ["Read:*"]
      assert perms.default_mode == :deny
    end

    test "returns error for invalid permissions" do
      assert {:error, %Error{}} =
               Extensibility.validate_permissions(%{
                 "allow" => "not_a_list"
               })
    end
  end

  describe "check_permission/3" do
    test "delegates to Permissions.check_permission/3" do
      perms = %Permissions{
        allow: ["Read:*"],
        deny: ["*delete*"],
        ask: [],
        default_mode: :deny
      }

      assert Extensibility.check_permission(perms, "Read", "file.txt") == :allow
      assert Extensibility.check_permission(perms, "Edit", "delete_file") == :deny
    end
  end

  describe "defaults/0" do
    test "returns default extensibility configuration" do
      defaults = Extensibility.defaults()

      assert is_map(defaults.channels)
      assert Map.has_key?(defaults.channels, "ui_state")
      assert Map.has_key?(defaults.channels, "agent")
      assert Map.has_key?(defaults.channels, "hooks")

      assert %Permissions{} = defaults.permissions
      assert defaults.permissions.default_mode == :deny
    end

    test "default permissions are secure by default" do
      defaults = Extensibility.defaults()

      # Safe operations allowed
      assert Extensibility.check_permission(defaults.permissions, "Read", "file.txt") ==
               :allow

      # Unmatched operations denied
      assert Extensibility.check_permission(defaults.permissions, "Unknown", "action") ==
               :deny
    end
  end
end
