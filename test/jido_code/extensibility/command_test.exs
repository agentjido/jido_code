defmodule JidoCode.Extensibility.CommandTest do
  use ExUnit.Case, async: false
  alias JidoCode.Extensibility.Command

  describe "Command struct" do
    test "creates a valid Command with required fields" do
      attrs = %{
        name: "test-command",
        description: "A test command"
      }

      assert {:ok, command} = Command.new(attrs)
      assert command.name == "test-command"
      assert command.description == "A test command"
      assert command.tools == []
      assert command.prompt == ""
      assert command.schema == []
    end

    test "creates a Command with optional fields" do
      attrs = %{
        name: "complex-command",
        description: "A complex command",
        model: "anthropic:claude-sonnet-4-20250514",
        tools: ["read_file", "grep"],
        prompt: "You are a helper.",
        schema: [value: [type: :integer]],
        channels: [broadcast_to: ["ui_state"]],
        signals: [emit: ["command.done"]],
        source_path: "/path/to/command.md"
      }

      assert {:ok, command} = Command.new(attrs)
      assert command.model == "anthropic:claude-sonnet-4-20250514"
      assert command.tools == ["read_file", "grep"]
      assert command.prompt == "You are a helper."
      assert command.schema == [value: [type: :integer]]
      assert command.channels == [broadcast_to: ["ui_state"]]
      assert command.signals == [emit: ["command.done"]]
      assert command.source_path == "/path/to/command.md"
    end

    test "new!/1 returns struct on success" do
      command = Command.new!(%{name: "test-command", description: "Test"})
      assert command.name == "test-command"
    end

    test "to_map converts struct to map with string keys" do
      command = Command.new!(%{name: "test", description: "Test", model: "test-model"})
      map = Command.to_map(command)

      assert is_map(map)
      assert Map.has_key?(map, "name")
      assert Map.has_key?(map, "description")
      assert map["name"] == "test"
      assert map["model"] == "test-model"
      refute Map.has_key?(map, :name)
    end
  end

  describe "sanitize_module_name/1" do
    test "converts kebab-case to CamelCase" do
      assert Command.sanitize_module_name("code-reviewer") == "CodeReviewer"
      assert Command.sanitize_module_name("my-test-command") == "MyTestCommand"
    end

    test "handles single word" do
      assert Command.sanitize_module_name("command") == "Command"
    end

    test "handles snake_case" do
      assert Command.sanitize_module_name("my_command") == "MyCommand"
      assert Command.sanitize_module_name("test_command") == "TestCommand"
    end

    test "handles numbers" do
      assert Command.sanitize_module_name("command-123") == "Command123"
      assert Command.sanitize_module_name("v2-command") == "V2Command"
    end
  end

  describe "module_name/1" do
    test "generates fully qualified module name" do
      assert Command.module_name("code-reviewer") ==
               JidoCode.Extensibility.Commands.CodeReviewer

      assert Command.module_name("test-command") ==
               JidoCode.Extensibility.Commands.TestCommand
    end
  end

  describe "using the macro" do
    defmodule TestCommand do
      use JidoCode.Extensibility.Command,
        name: "test_command",
        description: "A test command for macro testing",
        schema: [
          status: [type: :atom, default: :idle],
          counter: [type: :integer, default: 0]
        ],
        system_prompt: "You are a test command.",
        tools: [:read_file],
        channels: [broadcast_to: ["ui_state"]],
        signals: [
          emit: ["test.done"],
          events: [
            on_start: ["test.started"],
            on_complete: ["test.finished"]
          ]
        ]
    end

    test "macro creates a Jido.Action-compliant module" do
      # The module should have the run/2 function
      assert function_exported?(TestCommand, :run, 2)
    end

    test "macro provides system_prompt/0 function" do
      assert TestCommand.system_prompt() == "You are a test command."
    end

    test "macro provides allowed_tools/0 function" do
      assert TestCommand.allowed_tools() == [:read_file]
    end

    test "macro provides channel_config/0 function" do
      assert TestCommand.channel_config() == [broadcast_to: ["ui_state"]]
    end

    test "macro provides signal_config/0 function" do
      config = TestCommand.signal_config()
      assert config[:emit] == ["test.done"]
      assert config[:events][:on_start] == ["test.started"]
      assert config[:events][:on_complete] == ["test.finished"]
    end

    test "run/2 returns ok tuple with result and directives" do
      assert {:ok, result, directives} = TestCommand.run(%{}, %{})
      assert is_map(result)
      assert is_list(directives)
    end
  end

  describe "macro with minimal configuration" do
    defmodule MinimalCommand do
      use JidoCode.Extensibility.Command,
        name: "minimal",
        description: "A minimal command"
    end

    test "creates command with minimal config" do
      assert function_exported?(MinimalCommand, :run, 2)
    end

    test "default values are applied" do
      assert MinimalCommand.system_prompt() == ""
      assert MinimalCommand.allowed_tools() == []
      assert MinimalCommand.channel_config() == []
      assert MinimalCommand.signal_config() == []
    end
  end

  describe "macro with schema and execute_command override" do
    defmodule AddCommand do
      use JidoCode.Extensibility.Command,
        name: "add",
        description: "Adds two numbers",
        schema: [
          a: [type: :integer, required: true],
          b: [type: :integer, required: true]
        ]

      @impl true
      def execute_command(%{a: a, b: b}, _context) do
        {:ok, %{sum: a + b}}
      end
    end

    test "execute_command override is called" do
      assert {:ok, result, _directives} = AddCommand.run(%{a: 2, b: 3}, %{})
      assert result.sum == 5
    end

    test "run includes signal directives" do
      assert {:ok, _result, directives} = AddCommand.run(%{a: 2, b: 3}, %{})
      assert is_list(directives)
    end
  end

  describe "macro with signals" do
    defmodule SignalCommand do
      use JidoCode.Extensibility.Command,
        name: "signal_test",
        description: "Test signals",
        signals: [
          emit: ["custom.event"],
          events: [
            on_start: ["cmd.started"],
            on_complete: ["cmd.done"]
          ]
        ]
    end

    test "run/2 emits start signal" do
      assert {:ok, _result, directives} = SignalCommand.run(%{}, %{})
      # Should have directives for on_start events
      assert length(directives) > 0
    end

    test "run/2 emits completion signal" do
      assert {:ok, result, directives} = SignalCommand.run(%{}, %{})
      # Check that directives includes Emit directives
      emit_directives = Enum.filter(directives, fn
        %Jido.Agent.Directive.Emit{} -> true
        _ -> false
      end)

      # Should have start and completion signals
      assert length(emit_directives) >= 2
    end
  end
end
