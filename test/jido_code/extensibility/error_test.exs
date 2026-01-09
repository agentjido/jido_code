defmodule JidoCode.Extensibility.ErrorTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility.Error

  describe "new/3" do
    test "creates error with code and message" do
      error = Error.new(:test_code, "test message")

      assert error.code == :test_code
      assert error.message == "test message"
      assert error.details == nil
    end

    test "creates error with code, message, and details" do
      error = Error.new(:test_code, "test message", %{key: "value"})

      assert error.code == :test_code
      assert error.message == "test message"
      assert error.details == %{key: "value"}
    end
  end

  describe "validation_failed/2" do
    test "creates validation error" do
      error = Error.validation_failed("channel", "invalid topic")

      assert error.code == :validation_failed
      assert error.message == "channel validation failed: invalid topic"
      assert error.details == %{field: "channel"}
    end
  end

  describe "channel_config_invalid/1" do
    test "creates channel config error" do
      error = Error.channel_config_invalid("socket is required")

      assert error.code == :channel_config_invalid
      assert error.message == "socket is required"
      assert error.details == %{reason: "socket is required"}
    end
  end

  describe "socket_invalid/0" do
    test "creates socket validation error" do
      error = Error.socket_invalid()

      assert error.code == :socket_invalid
      assert error.message == "socket must be a valid WebSocket URL (ws:// or wss://)"
    end
  end

  describe "socket_empty/0" do
    test "creates socket empty error" do
      error = Error.socket_empty()

      assert error.code == :socket_invalid
      assert error.message == "socket cannot be empty string"
    end
  end

  describe "topic_required/0" do
    test "creates topic required error" do
      error = Error.topic_required()

      assert error.code == :topic_invalid
      assert error.message == "topic is required"
    end
  end

  describe "topic_empty/0" do
    test "creates topic empty error" do
      error = Error.topic_empty()

      assert error.code == :topic_invalid
      assert error.message == "topic cannot be empty"
    end
  end

  describe "topic_format_invalid/0" do
    test "creates topic format error" do
      error = Error.topic_format_invalid()

      assert error.code == :topic_invalid
      assert error.message ==
               "topic must contain only alphanumeric characters, colons, underscores, hyphens, or dots"
    end
  end

  describe "auth_type_required/0" do
    test "creates auth type required error" do
      error = Error.auth_type_required()

      assert error.code == :auth_invalid
      assert error.message == "auth.type is required when auth is provided"
    end
  end

  describe "auth_type_invalid/1" do
    test "creates auth type invalid error" do
      error = Error.auth_type_invalid("oauth")

      assert error.code == :auth_type_invalid
      assert error.message =~ "auth.type must be one of: token, basic, custom"
      assert error.message =~ "oauth"
      assert error.details == %{got: "oauth"}
    end
  end

  describe "token_required/0" do
    test "creates token required error" do
      error = Error.token_required()

      assert error.code == :token_required
      assert error.message == "auth.token is required for token type"
    end
  end

  describe "token_invalid/1" do
    test "creates token invalid error" do
      error = Error.token_invalid("token too short")

      assert error.code == :token_invalid
      assert error.message == "token too short"
      assert error.details == %{reason: "token too short"}
    end
  end

  describe "basic_credentials_required/0" do
    test "creates basic credentials required error" do
      error = Error.basic_credentials_required()

      assert error.code == :auth_invalid
      assert error.message == "auth.username and auth.password are required for basic type"
    end
  end

  describe "broadcast_events_invalid/0" do
    test "creates broadcast events invalid error" do
      error = Error.broadcast_events_invalid()

      assert error.code == :broadcast_events_invalid
      assert error.message == "broadcast_events must be a list of non-empty strings"
    end
  end

  describe "permissions_invalid/1" do
    test "creates permissions error" do
      error = Error.permissions_invalid("allow must be a list")

      assert error.code == :permissions_invalid
      assert error.message == "allow must be a list"
      assert error.details == %{reason: "allow must be a list"}
    end
  end

  describe "field_list_invalid/1" do
    test "creates field list invalid error" do
      error = Error.field_list_invalid("allow")

      assert error.code == :field_list_invalid
      assert error.message == "allow must be a list of strings"
      assert error.details == %{field: "allow"}
    end
  end

  describe "pattern_invalid/1" do
    test "creates pattern invalid error" do
      error = Error.pattern_invalid("patterns must be non-empty")

      assert error.code == :pattern_invalid
      assert error.message == "patterns must be non-empty"
      assert error.details == %{reason: "patterns must be non-empty"}
    end
  end

  describe "missing_env_var/1" do
    test "creates missing env var error without leaking value" do
      error = Error.missing_env_var("SECRET_TOKEN")

      assert error.code == :missing_env_var
      assert error.message == "required environment variable not set: SECRET_TOKEN"
      # The variable NAME is included, but NOT the value
      assert error.details == %{var_name: "SECRET_TOKEN"}
      # Value should NOT be in message
      refute error.message =~ "value"
      refute error.message =~ "secret"
    end

    test "does not include environment variable value" do
      # Even if we had access to the value, it should not be in the error
      error = Error.missing_env_var("API_KEY")

      assert error.code == :missing_env_var
      assert error.details.var_name == "API_KEY"
      # Only the name, never the value
      assert error.message == "required environment variable not set: API_KEY"
    end
  end

  describe "wrap/3" do
    test "wraps error in tuple" do
      assert {:error, %Error{code: :test_code, message: "test"}} =
               Error.wrap(:test_code, "test")
    end

    test "wraps error with details in tuple" do
      assert {:error, %Error{code: :test_code, message: "test", details: %{key: "val"}}} =
               Error.wrap(:test_code, "test", %{key: "val"})
    end
  end
end
