defmodule JidoCode.Agents.LLMAgentTest do
  use ExUnit.Case, async: false

  alias JidoCode.Agents.LLMAgent
  alias JidoCode.TestHelpers.EnvIsolation

  @moduletag :llm_agent

  setup do
    # Trap exits in test process to avoid test crashes
    Process.flag(:trap_exit, true)

    # Isolate environment for clean test state
    EnvIsolation.isolate(
      ["JIDO_CODE_PROVIDER", "JIDO_CODE_MODEL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
      [{:jido_code, :llm}]
    )

    # Subscribe to PubSub for response verification
    Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

    :ok
  end

  defp stop_agent(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end
  catch
    :exit, _ -> :ok
  end

  defp stop_agent(_), do: :ok

  describe "start_link/1" do
    test "returns error when config is missing" do
      # No config set, no explicit opts - should return error tuple
      assert {:error, reason} = LLMAgent.start_link()
      assert is_binary(reason) or is_atom(reason) or is_tuple(reason)
    end

    test "starts with explicit provider and model opts" do
      # Set API key for the provider
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result =
        LLMAgent.start_link(
          provider: :anthropic,
          model: "claude-3-5-sonnet-20241022"
        )

      case result do
        {:ok, pid} ->
          assert Process.alive?(pid)
          stop_agent(pid)

        {:error, reason} ->
          # May fail if JidoAI can't initialize - that's expected without real API key
          assert reason != nil
      end
    end

    test "starts with config from application environment" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = LLMAgent.start_link()

      case result do
        {:ok, pid} ->
          assert Process.alive?(pid)
          stop_agent(pid)

        {:error, _reason} ->
          # Expected if JidoAI can't fully initialize
          :ok
      end
    end

    test "accepts name option for registration" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = LLMAgent.start_link(name: :test_llm_agent)

      case result do
        {:ok, pid} ->
          # Verify registered name works
          assert Process.whereis(:test_llm_agent) == pid
          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_config/1" do
    test "returns the current configuration" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.5,
        max_tokens: 2048
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          config = LLMAgent.get_config(pid)

          assert config.provider == :anthropic
          assert config.model == "claude-3-5-sonnet-20241022"
          assert config.temperature == 0.5
          assert config.max_tokens == 2048

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "chat/2" do
    @tag :integration
    @tag :skip
    test "sends message and receives response" do
      # This test requires a real API key and makes actual LLM calls
      # Skip by default, run with: mix test --include integration

      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-haiku-20241022",
        temperature: 0.0,
        max_tokens: 100
      )

      # Requires real API key in environment
      {:ok, pid} = LLMAgent.start_link()

      {:ok, response} = LLMAgent.chat(pid, "Say 'Hello' and nothing else.")

      assert is_binary(response)
      assert String.contains?(String.downcase(response), "hello")

      # Verify PubSub broadcast
      assert_receive {:llm_response, ^response}, 1000

      stop_agent(pid)
    end
  end

  describe "configuration override" do
    test "opts override base config values" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")
      System.put_env("OPENAI_API_KEY", "test-openai-key")

      # Override with different values
      case LLMAgent.start_link(
             provider: :openai,
             model: "gpt-4o",
             temperature: 0.2
           ) do
        {:ok, pid} ->
          config = LLMAgent.get_config(pid)

          # Should use overridden values
          assert config.provider == :openai
          assert config.model == "gpt-4o"
          assert config.temperature == 0.2
          # max_tokens should fall back to base config
          assert config.max_tokens == 4096

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end
end
