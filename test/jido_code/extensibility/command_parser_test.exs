defmodule JidoCode.Extensibility.CommandParserTest do
  use ExUnit.Case, async: false
  alias JidoCode.Extensibility.{Command, CommandParser}

  @valid_command """
  ---
  name: commit
  description: Create a git commit with a generated message
  model: anthropic:claude-sonnet-4-20250514
  tools:
    - read_file
    - grep

  jido:
    schema:
      message:
        type: string
        default: ""
      amend:
        type: boolean
        default: false
    channels:
      broadcast_to: ["ui_state"]
    signals:
      emit: ["commit.done"]
      events:
        on_start: ["commit.started"]
        on_complete: ["commit.completed"]
  ---

  You are a git commit message generator.
  Analyze the changes and create a concise commit message.
  """

  @minimal_command """
  ---
  name: minimal
  description: A minimal command
  ---

  Minimal content
  """

  @no_frontmatter "No frontmatter here"

  @missing_required """
  ---
  name: test
  ---

  Missing description
  """

  describe "parse_frontmatter/1" do
    test "parses valid markdown with frontmatter" do
      assert {:ok, frontmatter, body} = CommandParser.parse_frontmatter(@valid_command)

      assert frontmatter["name"] == "commit"
      assert frontmatter["description"] == "Create a git commit with a generated message"
      assert frontmatter["model"] == "anthropic:claude-sonnet-4-20250514"
      assert frontmatter["tools"] == ["read_file", "grep"]
      assert String.contains?(body, "git commit message generator")
    end

    test "parses minimal command with required fields only" do
      assert {:ok, frontmatter, body} = CommandParser.parse_frontmatter(@minimal_command)

      assert frontmatter["name"] == "minimal"
      assert frontmatter["description"] == "A minimal command"
      assert body == "Minimal content"
    end

    test "returns error for content without frontmatter" do
      assert {:error, :no_frontmatter} = CommandParser.parse_frontmatter(@no_frontmatter)
    end
  end

  describe "parse_schema/1" do
    test "returns empty list for nil" do
      assert {:ok, []} = CommandParser.parse_schema(nil)
    end

    test "parses string field with default" do
      schema = %{
        "message" => %{"type" => "string", "default" => ""}
      }

      assert {:ok, parsed} = CommandParser.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:message][:type] == :string
      assert parsed[:message][:default] == ""
    end

    test "parses boolean field" do
      schema = %{
        "amend" => %{"type" => "boolean", "default" => false}
      }

      assert {:ok, parsed} = CommandParser.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:amend][:type] == :boolean
      assert parsed[:amend][:default] == false
    end

    test "parses atom field with allowed values" do
      schema = %{
        "mode" => %{"type" => "atom", "values" => [:quick, :standard], "default" => :standard}
      }

      assert {:ok, parsed} = CommandParser.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:mode][:type] == {:in, [:quick, :standard]}
    end

    test "parses list field with item type" do
      schema = %{
        "files" => %{"type" => "list", "item_type" => "string", "default" => []}
      }

      assert {:ok, parsed} = CommandParser.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:files][:type] == {:list, :string}
    end
  end

  describe "has_frontmatter?/1" do
    test "returns true for content with frontmatter" do
      assert CommandParser.has_frontmatter?(@valid_command)
      assert CommandParser.has_frontmatter?(@minimal_command)
    end

    test "returns false for content without frontmatter" do
      refute CommandParser.has_frontmatter?(@no_frontmatter)
    end

    test "returns false for empty string" do
      refute CommandParser.has_frontmatter?("")
    end
  end

  describe "parse_file/1" do
    setup do
      # Create temp directory for test files
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "command_parser_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "parses valid command file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "commit.md")
      File.write!(path, @valid_command)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert command.name == "commit"
      assert command.description == "Create a git commit with a generated message"
      assert command.model == "anthropic:claude-sonnet-4-20250514"
      assert command.tools == ["read_file", "grep"]
      assert String.contains?(command.prompt, "git commit message generator")
      assert command.source_path == path
    end

    test "parses minimal command file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "minimal.md")
      File.write!(path, @minimal_command)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert command.name == "minimal"
      assert command.description == "A minimal command"
      assert String.contains?(command.prompt, "Minimal")
    end

    test "returns error for non-existent file" do
      path = "/nonexistent/path/command.md"
      assert {:error, _reason} = CommandParser.parse_file(path)
    end

    test "returns error for file without frontmatter", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "no_frontmatter.md")
      File.write!(path, @no_frontmatter)

      assert {:error, :no_frontmatter} = CommandParser.parse_file(path)
    end

    test "returns error for file missing required fields", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing_required.md")
      File.write!(path, @missing_required)

      assert {:error, {:missing_required, ["description"]}} = CommandParser.parse_file(path)
    end

    test "sets default values for optional fields", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: defaults_test
      description: Test default values
      ---

      Content
      """

      path = Path.join(tmp_dir, "defaults.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert command.tools == []
      assert command.schema == []
      assert command.channels == []
      assert command.signals == []
    end

    test "parses jido configuration with channels", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: channels_test
      description: Test channels
      jido:
        channels:
          broadcast_to: ["ui_state", "agent_events"]
          another_key: "value"
      ---

      Content
      """

      path = Path.join(tmp_dir, "channels.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert Keyword.keyword?(command.channels)
      assert command.channels[:broadcast_to] == ["ui_state", "agent_events"]
      assert command.channels[:another_key] == "value"
    end

    test "parses jido configuration with signals", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: signals_test
      description: Test signals
      jido:
        signals:
          emit: ["task.done", "task.error"]
          events:
            on_start: ["agent.started"]
            on_complete: ["agent.finished"]
      ---

      Content
      """

      path = Path.join(tmp_dir, "signals.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)

      assert Keyword.keyword?(command.signals)
      assert command.signals[:emit] == ["task.done", "task.error"]
      events = command.signals[:events]
      assert Keyword.keyword?(events)
      assert events[:on_start] == ["agent.started"]
      assert events[:on_complete] == ["agent.finished"]
    end

    test "parses jido configuration with schema", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: schema_test
      description: Test schema
      jido:
        schema:
          message:
            type: string
            default: ""
          count:
            type: integer
            default: 0
      ---

      Content
      """

      path = Path.join(tmp_dir, "schema.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert Keyword.keyword?(command.schema)
      assert command.schema[:message][:type] == :string
      assert command.schema[:message][:default] == ""
      assert command.schema[:count][:type] == :integer
      assert command.schema[:count][:default] == 0
    end
  end

  describe "generate_module/1" do
    setup do
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "command_gen_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "generates a module from minimal command definition", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: test_command
      description: A test command
      ---

      You are a test command.
      """

      path = Path.join(tmp_dir, "test_command.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert {:ok, module} = CommandParser.generate_module(command)

      # Verify module name
      assert module == JidoCode.Extensibility.Commands.TestCommand

      # Verify module is accessible and has expected functions
      assert function_exported?(module, :system_prompt, 0)
      assert function_exported?(module, :allowed_tools, 0)
      assert function_exported?(module, :channel_config, 0)
      assert function_exported?(module, :signal_config, 0)

      # Verify the system prompt
      assert module.system_prompt() == "You are a test command."
    end

    test "generates a module with schema and tools", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: advanced_command
      description: An advanced command
      tools:
        - read_file
        - grep

      jido:
        schema:
          status:
            type: atom
            default: idle
          count:
            type: integer
            default: 0
      ---

      You are an advanced command with tools.
      """

      path = Path.join(tmp_dir, "advanced_command.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert {:ok, module} = CommandParser.generate_module(command)

      # Verify module
      assert module == JidoCode.Extensibility.Commands.AdvancedCommand

      # Verify tools
      assert module.allowed_tools() == ["read_file", "grep"]
    end

    test "generates unique module names for kebab-case names", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: my-special-command
      description: Special command
      ---

      Content
      """

      path = Path.join(tmp_dir, "special.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert {:ok, module} = CommandParser.generate_module(command)

      assert module == JidoCode.Extensibility.Commands.MySpecialCommand
    end

    test "generated module is Jido.Action-compliant", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: action_test
      description: Test action compliance
      ---

      Content
      """

      path = Path.join(tmp_dir, "action_test.md")
      File.write!(path, command_content)

      assert {:ok, %Command{} = command} = CommandParser.parse_file(path)
      assert {:ok, module} = CommandParser.generate_module(command)

      # Should have run/2 function from Jido.Action
      assert function_exported?(module, :run, 2)

      # Should be able to execute
      assert {:ok, result, directives} = module.run(%{}, %{})
      assert is_map(result)
      assert is_list(directives)
    end
  end

  describe "load_and_generate/1" do
    setup do
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "command_load_gen_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "parses and generates module in one step", %{tmp_dir: tmp_dir} do
      command_content = """
      ---
      name: oneshot
      description: One shot command
      ---

      One shot content
      """

      path = Path.join(tmp_dir, "oneshot.md")
      File.write!(path, command_content)

      assert {:ok, module} = CommandParser.load_and_generate(path)
      assert module == JidoCode.Extensibility.Commands.Oneshot
      assert module.system_prompt() == "One shot content"
    end

    test "returns error for invalid command file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "invalid.md")
      File.write!(path, "No frontmatter here")

      assert {:error, _reason} = CommandParser.load_and_generate(path)
    end
  end
end
