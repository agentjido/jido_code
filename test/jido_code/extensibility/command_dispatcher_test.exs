defmodule JidoCode.Extensibility.CommandDispatcherTest do
  use ExUnit.Case, async: false
  alias JidoCode.Extensibility.{CommandDispatcher, CommandRegistry, SlashParser, Command}

  # Test command module
  defmodule TestCommand do
    use Jido.Action,
      name: "test_command",
      description: "A test command",
      schema: [
        message: [type: :string, required: false],
        verbose: [type: :boolean, default: false]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{executed: true, params: params}}
    end
  end

  # Failing command module
  defmodule FailingCommand do
    use Jido.Action,
      name: "failing_command",
      description: "A command that fails"

    @impl true
    def run(_params, _context) do
      {:error, :intentional_failure}
    end
  end

  # Command with custom execute logic
  defmodule CustomCommand do
    use Jido.Action,
      name: "custom_command",
      description: "A custom command",
      schema: [
        value: [type: :integer, required: true]
      ]

    @impl true
    def run(params, context) do
      # Convert string to integer if needed (simulating what Jido.Action does)
      value = if is_binary(params.value), do: String.to_integer(params.value), else: params.value
      result = value * 2
      {:ok, %{result: result, context_tools: Map.get(context, :command_tools)}}
    end
  end

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Start registry for testing
    {:ok, _pid} = CommandRegistry.start_link(auto_scan: false)

    # Subscribe to dispatcher events
    Phoenix.PubSub.subscribe(JidoCode.PubSub, "command_dispatcher")

    :ok
  end

  defp create_test_command(name, module, opts \\ []) do
    # Build base attributes
    attrs =
      %{
        name: name,
        description: "Test command",
        tools: Keyword.get(opts, :tools, []),
        prompt: "Test prompt",
        schema: []
      }

    # Add module if provided (not nil)
    attrs = if module, do: Map.put(attrs, :module, module), else: attrs

    # Add optional fields if provided
    attrs = if model = Keyword.get(opts, :model), do: Map.put(attrs, :model, model), else: attrs
    attrs = if channels = Keyword.get(opts, :channels), do: Map.put(attrs, :channels, channels), else: attrs
    attrs = if signals = Keyword.get(opts, :signals), do: Map.put(attrs, :signals, signals), else: attrs

    {:ok, command} = Command.new(attrs)
    command
  end

  # ============================================================================
  # dispatch/2 Tests
  # ============================================================================

  describe "dispatch/2" do
    test "executes a registered command successfully" do
      # Register test command
      command = create_test_command("test_dispatch", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      # Parse and dispatch
      {:ok, parsed} = SlashParser.parse("/test_dispatch --verbose")
      assert {:ok, result} = CommandDispatcher.dispatch(parsed, %{})

      assert result.executed == true
      assert result.params.verbose == true
    end

    test "returns error for unregistered command" do
      {:ok, parsed} = SlashParser.parse("/nonexistent")

      assert {:error, {:not_found, "nonexistent"}} =
               CommandDispatcher.dispatch(parsed, %{})
    end

    test "passes flags as params to command" do
      command = create_test_command("test_flags", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse(~s(/test_flags --message "hello world"))
      assert {:ok, result} = CommandDispatcher.dispatch(parsed, %{})

      assert result.params.message == "hello world"
    end

    test "emits command:started signal" do
      command = create_test_command("test_signal_start", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/test_signal_start")
      _ = CommandDispatcher.dispatch(parsed, %{})

      assert_receive({"command:started", %{command: "test_signal_start"}}, 1000)
    end

    test "emits command:completed signal on success" do
      command = create_test_command("test_signal_complete", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/test_signal_complete")
      assert {:ok, _result} = CommandDispatcher.dispatch(parsed, %{})

      assert_receive({"command:completed", %{command: "test_signal_complete"}}, 1000)
    end

    test "emits command:failed signal on execution error" do
      command = create_test_command("test_signal_fail", FailingCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/test_signal_fail")
      # The dispatcher wraps the error
      assert {:error, {:execution_failed, :intentional_failure}} =
               CommandDispatcher.dispatch(parsed, %{})

      assert_receive({"command:failed", %{command: "test_signal_fail"}}, 1000)
    end

    test "emits command:failed signal for missing command" do
      {:ok, parsed} = SlashParser.parse("/missing_command")
      assert {:error, {:not_found, "missing_command"}} =
               CommandDispatcher.dispatch(parsed, %{})

      assert_receive({"command:failed", %{command: "missing_command", error: :not_found}}, 1000)
    end
  end

  # ============================================================================
  # dispatch_string/2 Tests
  # ============================================================================

  describe "dispatch_string/2" do
    test "parses and dispatches in one step" do
      command = create_test_command("test_string", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      assert {:ok, result} =
               CommandDispatcher.dispatch_string("/test_string --verbose", %{})

      assert result.executed == true
    end

    test "returns parse_error for invalid slash command" do
      assert {:error, {:parse_error, :not_a_slash_command}} =
               CommandDispatcher.dispatch_string("not a slash command", %{})
    end

    test "returns parse_error for empty command" do
      assert {:error, {:parse_error, :empty_command}} =
               CommandDispatcher.dispatch_string("/", %{})
    end
  end

  # ============================================================================
  # build_context/2 Tests
  # ============================================================================

  describe "build_context/2" do
    test "merges base context with command config" do
      command = create_test_command("ctx_test", TestCommand,
        tools: ["read_file", "write_file"],
        model: "anthropic:claude-3-5-sonnet",
        channels: ["ui_events"],
        signals: [emit: ["custom.started"]]
      )

      base_context = %{user_id: "123", session_id: "abc"}
      context = CommandDispatcher.build_context(command, base_context)

      assert context.user_id == "123"
      assert context.session_id == "abc"
      assert context.command_name == "ctx_test"
      assert context.command_tools == ["read_file", "write_file"]
      assert context.command_model == "anthropic:claude-3-5-sonnet"
    end

    test "adds allowed_tools from command config" do
      command = create_test_command("ctx_tools", TestCommand,
        tools: ["grep", "find"]
      )

      context = CommandDispatcher.build_context(command, %{})
      assert context.allowed_tools == ["grep", "find"]
    end

    test "adds model override when specified" do
      command = create_test_command("ctx_model", TestCommand,
        model: "gpt-4"
      )

      context = CommandDispatcher.build_context(command, %{})
      assert context.model == "gpt-4"
    end

    test "handles empty command config" do
      command = create_test_command("ctx_empty", TestCommand)
      context = CommandDispatcher.build_context(command, %{existing: "value"})

      assert context.existing == "value"
      assert context.command_name == "ctx_empty"
      assert context.command_tools == []
    end

    test "normalizes channels configuration" do
      command = create_test_command("ctx_channels", TestCommand,
        channels: %{broadcast_to: ["channel1", "channel2"]}
      )

      context = CommandDispatcher.build_context(command, %{})
      assert context.command_channels == %{broadcast_to: ["channel1", "channel2"]}
    end

    test "normalizes signals configuration" do
      command = create_test_command("ctx_signals", TestCommand,
        signals: %{emit: ["started", "completed"]}
      )

      context = CommandDispatcher.build_context(command, %{})
      assert context.command_signals == %{emit: ["started", "completed"]}
    end
  end

  # ============================================================================
  # Parameter Building Tests
  # ============================================================================

  describe "parameter building" do
    test "merges flags into params map" do
      command = create_test_command("param_flags", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/param_flags --message hello --verbose true")
      {:ok, result} = CommandDispatcher.dispatch(parsed, %{})

      assert result.params.message == "hello"
      assert result.params.verbose == "true"
    end

    test "converts string flag names to atoms when possible" do
      command = create_test_command("param_atoms", CustomCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/param_atoms --value 42")
      {:ok, result} = CommandDispatcher.dispatch(parsed, %{})

      assert result.result == 84
    end

    test "handles positional arguments" do
      command = create_test_command("param_args", TestCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/param_args file1.ex file2.ex")
      {:ok, result} = CommandDispatcher.dispatch(parsed, %{})

      # Positional args are added based on schema
      assert result.params.args == ["file1.ex", "file2.ex"]
    end
  end

  # ============================================================================
  # Channel Broadcasting Tests
  # ============================================================================

  describe "channel broadcasting" do
    test "broadcasts to configured channels on start" do
      channel = "test_channel_start"

      command = create_test_command("broadcast_start", TestCommand,
        channels: [channel]
      )

      {:ok, _} = CommandRegistry.register_command(command)

      # Subscribe to the test channel
      Phoenix.PubSub.subscribe(JidoCode.PubSub, channel)

      {:ok, parsed} = SlashParser.parse("/broadcast_start")
      {:ok, _} = CommandDispatcher.dispatch(parsed, %{})

      assert_receive({:command_event, %{status: :started}}, 1000)

      Phoenix.PubSub.unsubscribe(JidoCode.PubSub, channel)
    end

    test "broadcasts to configured channels on completion" do
      channel = "test_channel_complete"

      command = create_test_command("broadcast_complete", TestCommand,
        channels: [channel]
      )

      {:ok, _} = CommandRegistry.register_command(command)

      Phoenix.PubSub.subscribe(JidoCode.PubSub, channel)

      {:ok, parsed} = SlashParser.parse("/broadcast_complete")
      {:ok, _} = CommandDispatcher.dispatch(parsed, %{})

      assert_receive({:command_event, %{status: :completed}}, 1000)

      Phoenix.PubSub.unsubscribe(JidoCode.PubSub, channel)
    end

    test "broadcasts to configured channels on failure" do
      channel = "test_channel_fail"

      command = create_test_command("broadcast_fail", FailingCommand,
        channels: [channel]
      )

      {:ok, _} = CommandRegistry.register_command(command)

      Phoenix.PubSub.subscribe(JidoCode.PubSub, channel)

      {:ok, parsed} = SlashParser.parse("/broadcast_fail")
      {:error, _} = CommandDispatcher.dispatch(parsed, %{})

      assert_receive({:command_event, %{status: :failed}}, 1000)

      Phoenix.PubSub.unsubscribe(JidoCode.PubSub, channel)
    end

    test "broadcasts includes timestamp" do
      channel = "test_channel_timestamp"

      command = create_test_command("broadcast_timestamp", TestCommand,
        channels: [channel]
      )

      {:ok, _} = CommandRegistry.register_command(command)

      Phoenix.PubSub.subscribe(JidoCode.PubSub, channel)

      {:ok, parsed} = SlashParser.parse("/broadcast_timestamp")
      {:ok, _} = CommandDispatcher.dispatch(parsed, %{})

      assert_receive({:command_event, payload}, 1000)
      assert Map.has_key?(payload, :timestamp)
      assert is_binary(payload.timestamp)

      Phoenix.PubSub.unsubscribe(JidoCode.PubSub, channel)
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error handling" do
    test "handles command with nil module" do
      command = create_test_command("no_module", nil)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/no_module")
      assert {:error, {:execution_failed, :no_module}} =
               CommandDispatcher.dispatch(parsed, %{})
    end

    test "handles module that doesn't export run/2" do
      defmodule NoRunCommand do
        # Intentionally doesn't use Jido.Action or define run/2
      end

      command = create_test_command("no_run", NoRunCommand)
      {:ok, _} = CommandRegistry.register_command(command)

      {:ok, parsed} = SlashParser.parse("/no_run")
      assert {:error, {:execution_failed, :module_not_ready}} =
               CommandDispatcher.dispatch(parsed, %{})
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "full flow: parse, dispatch, execute, broadcast" do
      # Create a realistic command
      channel = "integration_test"

      command = create_test_command("integration", TestCommand,
        tools: ["read_file", "grep"],
        model: "claude-3-5-sonnet",
        channels: [channel]
      )

      {:ok, _} = CommandRegistry.register_command(command)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, channel)

      # Parse slash command
      {:ok, parsed} = SlashParser.parse(~s(/integration --message "test message"))

      # Dispatch and execute
      assert {:ok, result} = CommandDispatcher.dispatch(parsed, %{})

      # Verify result
      assert result.executed == true
      assert result.params.message == "test message"

      # Verify signals
      assert_receive({"command:started", %{command: "integration"}}, 1000)
      assert_receive({"command:completed", %{command: "integration"}}, 1000)

      # Verify broadcast
      assert_receive({:command_event, %{status: :started}}, 1000)
      assert_receive({:command_event, %{status: :completed}}, 1000)

      Phoenix.PubSub.unsubscribe(JidoCode.PubSub, channel)
    end
  end
end
