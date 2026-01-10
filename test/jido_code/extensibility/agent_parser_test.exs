defmodule JidoCode.Extensibility.AgentParserTest do
  use ExUnit.Case, async: false
  alias JidoCode.Extensibility.AgentParser
  alias JidoCode.Extensibility.SubAgent

  @valid_agent """
  ---
  name: code_reviewer
  description: Reviews code for security issues
  model: anthropic:claude-sonnet-4-20250514
  temperature: 0.3
  max_tokens: 8192
  tools:
    - read_file
    - grep

  jido:
    schema:
      review_depth:
        type: atom
        default: standard
      focus_areas:
        type: list
        item_type: string
        default: [security]
    channels:
      broadcast_to: ["ui_state"]
    signals:
      events:
        on_start: ["agent.started"]
        on_complete: ["review.completed"]
  ---

  You are a code reviewer.
  Focus on security and performance.
  """

  @minimal_agent """
  ---
  name: minimal
  description: A minimal agent
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

  @invalid_yaml """
  ---
  name: test
  description: invalid
    bad yaml indentation here
  ---

  Content
  """

  describe "parse_frontmatter/1" do
    test "parses valid markdown with frontmatter" do
      assert {:ok, frontmatter, body} = AgentParser.parse_frontmatter(@valid_agent)

      assert frontmatter["name"] == "code_reviewer"
      assert frontmatter["description"] == "Reviews code for security issues"
      assert frontmatter["model"] == "anthropic:claude-sonnet-4-20250514"
      assert frontmatter["temperature"] == 0.3
      assert frontmatter["max_tokens"] == 8192
      assert frontmatter["tools"] == ["read_file", "grep"]
      assert String.contains?(body, "code reviewer")
    end

    test "parses minimal agent with required fields only" do
      assert {:ok, frontmatter, body} = AgentParser.parse_frontmatter(@minimal_agent)

      assert frontmatter["name"] == "minimal"
      assert frontmatter["description"] == "A minimal agent"
      assert body == "Minimal content"
    end

    test "returns error for content without frontmatter" do
      assert {:error, :no_frontmatter} = AgentParser.parse_frontmatter(@no_frontmatter)
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_required, ["description"]}} =
               AgentParser.parse_frontmatter(@missing_required)
    end
  end

  describe "parse_zoi_schema/1" do
    test "returns empty list for nil" do
      assert {:ok, []} = AgentParser.parse_zoi_schema(nil)
    end

    test "parses string field with default" do
      schema = %{
        "status" => %{"type" => "string", "default" => "idle"}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:status][:type] == :string
      assert parsed[:status][:default] == "idle"
    end

    test "parses integer field" do
      schema = %{
        "count" => %{"type" => "integer", "default" => 0}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:count][:type] == :integer
      assert parsed[:count][:default] == 0
    end

    test "parses float field" do
      schema = %{
        "rate" => %{"type" => "float", "default" => 0.5}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:rate][:type] == :float
      assert parsed[:rate][:default] == 0.5
    end

    test "parses boolean field" do
      schema = %{
        "enabled" => %{"type" => "boolean", "default" => true}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:enabled][:type] == :boolean
      assert parsed[:enabled][:default] == true
    end

    test "parses atom field" do
      schema = %{
        "status" => %{"type" => "atom", "default" => :idle}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:status][:type] == :atom
      assert parsed[:status][:default] == :idle
    end

    test "parses atom field with allowed values" do
      schema = %{
        "mode" => %{"type" => "atom", "values" => [:quick, :standard, :thorough], "default" => :standard}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:mode][:type] == {:in, [:quick, :standard, :thorough]}
      assert parsed[:mode][:default] == :standard
    end

    test "parses list field with item type" do
      schema = %{
        "tags" => %{"type" => "list", "item_type" => "string", "default" => ["a", "b"]}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:tags][:type] == {:list, :string}
      assert parsed[:tags][:default] == ["a", "b"]
    end

    test "parses list field with integer items" do
      schema = %{
        "numbers" => %{"type" => "list", "item_type" => "integer", "default" => [1, 2, 3]}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:numbers][:type] == {:list, :integer}
      assert parsed[:numbers][:default] == [1, 2, 3]
    end

    test "parses complex schema with multiple fields" do
      schema = %{
        "name" => %{"type" => "string", "default" => "test"},
        "age" => %{"type" => "integer", "default" => 0},
        "active" => %{"type" => "boolean", "default" => true},
        "mode" => %{"type" => "atom", "default" => :normal},
        "items" => %{"type" => "list", "item_type" => "string", "default" => []}
      }

      assert {:ok, parsed} = AgentParser.parse_zoi_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:name][:type] == :string
      assert parsed[:name][:default] == "test"
      assert parsed[:age][:type] == :integer
      assert parsed[:age][:default] == 0
      assert parsed[:active][:type] == :boolean
      assert parsed[:active][:default] == true
      assert parsed[:mode][:type] == :atom
      assert parsed[:mode][:default] == :normal
      assert parsed[:items][:type] == {:list, :string}
      assert parsed[:items][:default] == []
    end
  end

  describe "parse_file/1" do
    setup do
      # Create temp directory for test files
      tmp_dir = Path.join([System.tmp_dir!(), "agent_parser_test", Integer.to_string(:erlang.unique_integer([:positive]))])
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "parses valid agent file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "valid_agent.md")
      File.write!(path, @valid_agent)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert sub_agent.name == "code_reviewer"
      assert sub_agent.description == "Reviews code for security issues"
      assert sub_agent.model == "anthropic:claude-sonnet-4-20250514"
      assert sub_agent.temperature == 0.3
      assert sub_agent.max_tokens == 8192
      assert sub_agent.tools == ["read_file", "grep"]
      assert String.contains?(sub_agent.prompt, "code reviewer")
      assert sub_agent.source_path == path
    end

    test "parses minimal agent file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "minimal_agent.md")
      File.write!(path, @minimal_agent)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert sub_agent.name == "minimal"
      assert sub_agent.description == "A minimal agent"
      assert String.contains?(sub_agent.prompt, "Minimal")
    end

    test "returns error for non-existent file" do
      path = "/nonexistent/path/agent.md"
      assert {:error, _reason} = AgentParser.parse_file(path)
    end

    test "returns error for file without frontmatter", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "no_frontmatter.md")
      File.write!(path, @no_frontmatter)

      assert {:error, :no_frontmatter} = AgentParser.parse_file(path)
    end

    test "returns error for file missing required fields", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing_required.md")
      File.write!(path, @missing_required)

      assert {:error, {:missing_required, ["description"]}} = AgentParser.parse_file(path)
    end

    test "sets default values for optional fields", %{tmp_dir: tmp_dir} do
      agent_content = """
      ---
      name: defaults_test
      description: Test default values
      ---

      Content
      """

      path = Path.join(tmp_dir, "defaults.md")
      File.write!(path, agent_content)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert sub_agent.temperature == 0.7
      assert sub_agent.max_tokens == 4096
      assert sub_agent.tools == []
      assert sub_agent.schema == []
      assert sub_agent.channels == []
      assert sub_agent.signals == []
    end

    test "parses jido configuration with channels", %{tmp_dir: tmp_dir} do
      agent_content = """
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
      File.write!(path, agent_content)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert Keyword.keyword?(sub_agent.channels)
      assert sub_agent.channels[:broadcast_to] == ["ui_state", "agent_events"]
      assert sub_agent.channels[:another_key] == "value"
    end

    test "parses jido configuration with signals", %{tmp_dir: tmp_dir} do
      agent_content = """
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
      File.write!(path, agent_content)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)

      assert Keyword.keyword?(sub_agent.signals)
      assert sub_agent.signals[:emit] == ["task.done", "task.error"]
      events = sub_agent.signals[:events]
      assert Keyword.keyword?(events)
      assert events[:on_start] == ["agent.started"]
      assert events[:on_complete] == ["agent.finished"]
    end
  end

  describe "generate_module/1" do
    setup do
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "agent_gen_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "generates a module from minimal agent definition", %{tmp_dir: tmp_dir} do
      agent_content = """
      ---
      name: test_agent
      description: A test agent
      ---

      You are a test agent.
      """

      path = Path.join(tmp_dir, "test_agent.md")
      File.write!(path, agent_content)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert {:ok, module} = AgentParser.generate_module(sub_agent)

      # Verify module name
      assert module == JidoCode.Extensibility.Agents.TestAgent

      # Verify module is accessible and has expected functions
      assert function_exported?(module, :system_prompt, 0)
      assert function_exported?(module, :allowed_tools, 0)
      assert function_exported?(module, :channel_config, 0)
      assert function_exported?(module, :signal_config, 0)

      # Verify the system prompt
      assert module.system_prompt() == "You are a test agent."
    end

    test "generates a module with schema and tools", %{tmp_dir: tmp_dir} do
      agent_content = """
      ---
      name: advanced_agent
      description: An advanced agent
      tools:
        - read_file
        - grep

      jido:
        schema:
          status:
            type: atom
            default: "idle"
          count:
            type: integer
            default: 0
      ---

      You are an advanced agent with tools.
      """

      path = Path.join(tmp_dir, "advanced_agent.md")
      File.write!(path, agent_content)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert {:ok, module} = AgentParser.generate_module(sub_agent)

      # Verify module
      assert module == JidoCode.Extensibility.Agents.AdvancedAgent

      # Verify tools
      assert module.allowed_tools() == ["read_file", "grep"]

      # Can create an agent instance
      agent = module.new()
      assert %Jido.Agent{} = agent
      # The YAML parser returns strings, so the default is stored as a string
      # Jido.Agent's NimbleOptions schema will validate it on access
      assert agent.state.status in ["idle", :idle]
      assert agent.state.count in [0]
    end

    test "generates unique module names for kebab-case names", %{tmp_dir: tmp_dir} do
      agent_content = """
      ---
      name: my-special-agent
      description: Special agent
      ---

      Content
      """

      path = Path.join(tmp_dir, "special.md")
      File.write!(path, agent_content)

      assert {:ok, %SubAgent{} = sub_agent} = AgentParser.parse_file(path)
      assert {:ok, module} = AgentParser.generate_module(sub_agent)

      assert module == JidoCode.Extensibility.Agents.MySpecialAgent
    end
  end

  describe "load_and_generate/1" do
    setup do
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "agent_load_gen_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "parses and generates module in one step", %{tmp_dir: tmp_dir} do
      agent_content = """
      ---
      name: oneshot
      description: One shot agent
      ---

      One shot content
      """

      path = Path.join(tmp_dir, "oneshot.md")
      File.write!(path, agent_content)

      assert {:ok, module} = AgentParser.load_and_generate(path)
      assert module == JidoCode.Extensibility.Agents.Oneshot
      assert module.system_prompt() == "One shot content"
    end

    test "returns error for invalid agent file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "invalid.md")
      File.write!(path, "No frontmatter here")

      assert {:error, _reason} = AgentParser.load_and_generate(path)
    end
  end

  describe "has_frontmatter?/1" do
    test "returns true for content with frontmatter" do
      assert AgentParser.has_frontmatter?(@valid_agent)
      assert AgentParser.has_frontmatter?(@minimal_agent)
    end

    test "returns false for content without frontmatter" do
      refute AgentParser.has_frontmatter?(@no_frontmatter)
    end

    test "returns false for empty string" do
      refute AgentParser.has_frontmatter?("")
    end

    test "returns false for incomplete frontmatter" do
      incomplete = """
      ---
      name: test
      Content without closing delimiter
      """

      refute AgentParser.has_frontmatter?(incomplete)
    end
  end
end
