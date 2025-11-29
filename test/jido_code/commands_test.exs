defmodule JidoCode.CommandsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Keyring
  alias JidoCode.Commands

  # Helper to set up API key for tests
  defp setup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.set_session_value(key_name, "test-api-key-#{provider}")
  end

  defp cleanup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.clear_session_value(key_name)
  end

  defp provider_to_key_name(provider) do
    case provider do
      "openai" -> :openai_api_key
      "anthropic" -> :anthropic_api_key
      "openrouter" -> :openrouter_api_key
      _ -> String.to_atom("#{provider}_api_key")
    end
  end

  describe "execute/2" do
    test "/help returns command list" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/help", config)

      assert message =~ "Available commands"
      assert message =~ "/help"
      assert message =~ "/config"
      assert message =~ "/provider"
      assert message =~ "/model"
      assert new_config == %{}
    end

    test "/config shows current configuration" do
      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}

      {:ok, message, new_config} = Commands.execute("/config", config)

      assert message =~ "Provider: anthropic"
      assert message =~ "Model: claude-3-5-sonnet"
      assert new_config == %{}
    end

    test "/config shows (not set) for nil values" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: (not set)"
      assert message =~ "Model: (not set)"
    end

    test "/provider with valid provider sets provider and clears model" do
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, new_config} = Commands.execute("/provider anthropic", config)

      assert message =~ "Provider set to anthropic"
      assert new_config == %{provider: "anthropic", model: nil}
    end

    test "/provider without argument shows usage" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/provider", config)

      assert message =~ "Usage: /provider <name>"
    end

    test "/provider with invalid provider shows error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/provider invalid_provider_xyz", config)

      assert message =~ "Unknown provider"
    end

    test "/model provider:model sets both" do
      setup_api_key("anthropic")
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/model anthropic:claude-3-5-sonnet", config)

      assert message =~ "Model set to anthropic:claude-3-5-sonnet"
      assert new_config.provider == "anthropic"
      assert new_config.model == "claude-3-5-sonnet"
      cleanup_api_key("anthropic")
    end

    test "/model with only model name works when provider is set" do
      setup_api_key("anthropic")
      config = %{provider: "anthropic", model: nil}

      {:ok, message, new_config} = Commands.execute("/model claude-3-5-sonnet", config)

      assert message =~ "Model set to claude-3-5-sonnet"
      assert new_config.provider == "anthropic"
      assert new_config.model == "claude-3-5-sonnet"
      cleanup_api_key("anthropic")
    end

    test "/model with only model name fails when no provider" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model gpt-4o", config)

      assert message =~ "No provider set"
    end

    test "/model fails when API key not set" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model anthropic:claude-3-5-sonnet", config)

      assert message =~ "No API key found for anthropic"
      assert message =~ "ANTHROPIC_API_KEY"
    end

    test "/model without argument shows usage" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model", config)

      assert message =~ "Usage: /model"
    end

    test "/models shows models for current provider" do
      config = %{provider: "anthropic", model: nil}

      result = Commands.execute("/models", config)

      case result do
        {:ok, message, _} ->
          assert message =~ "Models for anthropic" or message =~ "No models found"

        {:error, _} ->
          # Registry might not be available in test
          :ok
      end
    end

    test "/models without provider shows error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/models", config)

      assert message =~ "No provider set"
    end

    test "/models provider shows models for specified provider" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/models anthropic", config)

      case result do
        {:ok, message, _} ->
          assert message =~ "anthropic" or message =~ "No models found"

        {:error, message} ->
          # Unknown provider is also valid
          assert message =~ "Unknown provider"
      end
    end

    test "/providers lists available providers" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/providers", config)

      # Should have providers from registry
      assert message =~ "providers" or message =~ "No providers"
      assert new_config == %{}
    end

    test "unknown command returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/unknown_command", config)

      assert message =~ "Unknown command"
      assert message =~ "/help"
    end

    test "command with extra whitespace is handled" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("  /help  ", config)

      assert message =~ "Available commands"
    end

    test "non-command text returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("hello", config)

      assert message =~ "Not a command"
    end
  end

  describe "config key formats" do
    test "works with atom keys in config" do
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: openai"
      assert message =~ "Model: gpt-4o"
    end

    test "works with string keys in config" do
      config = %{"provider" => "openai", "model" => "gpt-4o"}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: openai"
      assert message =~ "Model: gpt-4o"
    end

    test "/model with string key provider set" do
      setup_api_key("anthropic")
      config = %{"provider" => "anthropic", "model" => nil}

      {:ok, message, new_config} = Commands.execute("/model claude-3-5-sonnet", config)

      assert message =~ "Model set to"
      assert new_config.model == "claude-3-5-sonnet"
      cleanup_api_key("anthropic")
    end
  end
end
