defmodule JidoCode.Extensibility.Parser.FrontmatterTest do
  use ExUnit.Case, async: false
  alias JidoCode.Extensibility.Parser.Frontmatter

  @valid_content """
  ---
  name: test_command
  description: A test command
  model: anthropic:claude-sonnet-4-20250514
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
    channels:
      broadcast_to: ["ui_state"]
    signals:
      emit: ["custom.event"]
      events:
        on_start: ["cmd.started"]
        on_complete: ["cmd.done"]
  ---

  This is the command body.
  """

  @minimal_content """
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
      assert {:ok, frontmatter, body} = Frontmatter.parse_frontmatter(@valid_content)

      assert frontmatter["name"] == "test_command"
      assert frontmatter["description"] == "A test command"
      assert frontmatter["model"] == "anthropic:claude-sonnet-4-20250514"
      assert frontmatter["tools"] == ["read_file", "grep"]
      assert String.contains?(body, "command body")
    end

    test "parses minimal content with required fields only" do
      assert {:ok, frontmatter, body} = Frontmatter.parse_frontmatter(@minimal_content)

      assert frontmatter["name"] == "minimal"
      assert frontmatter["description"] == "A minimal command"
      assert body == "Minimal content"
    end

    test "returns error for content without frontmatter" do
      assert {:error, :no_frontmatter} = Frontmatter.parse_frontmatter(@no_frontmatter)
    end

    test "parses jido configuration with schema" do
      assert {:ok, frontmatter, _body} = Frontmatter.parse_frontmatter(@valid_content)

      jido = frontmatter["jido"]
      assert jido["schema"]["status"]["type"] == "atom"
      assert jido["schema"]["status"]["default"] == "idle"
      assert jido["schema"]["count"]["type"] == "integer"
      assert jido["schema"]["count"]["default"] == 0
    end

    test "parses jido configuration with channels" do
      assert {:ok, frontmatter, _body} = Frontmatter.parse_frontmatter(@valid_content)

      jido = frontmatter["jido"]
      assert jido["channels"]["broadcast_to"] == ["ui_state"]
    end

    test "parses jido configuration with signals" do
      assert {:ok, frontmatter, _body} = Frontmatter.parse_frontmatter(@valid_content)

      jido = frontmatter["jido"]
      assert jido["signals"]["emit"] == ["custom.event"]
      assert jido["signals"]["events"]["on_start"] == ["cmd.started"]
      assert jido["signals"]["events"]["on_complete"] == ["cmd.done"]
    end
  end

  describe "validate_required/2" do
    test "returns :ok when all required fields present" do
      frontmatter = %{"name" => "test", "description" => "A test command"}
      assert :ok = Frontmatter.validate_required(frontmatter, [:name, :description])
    end

    test "returns :ok when required fields have non-empty values" do
      frontmatter = %{"name" => "test", "description" => "A description"}
      assert :ok = Frontmatter.validate_required(frontmatter, [:name, :description])
    end

    test "returns error when required fields are missing" do
      frontmatter = %{"name" => "test"}
      assert {:error, {:missing_required, ["description"]}} =
               Frontmatter.validate_required(frontmatter, [:name, :description])
    end

    test "returns error when required fields are empty strings" do
      frontmatter = %{"name" => "test", "description" => ""}
      assert {:error, {:missing_required, ["description"]}} =
               Frontmatter.validate_required(frontmatter, [:name, :description])
    end

    test "accepts string or atom field names" do
      frontmatter = %{"name" => "test", "description" => "A description"}
      assert :ok = Frontmatter.validate_required(frontmatter, ["name", "description"])
      assert :ok = Frontmatter.validate_required(frontmatter, [:name, :description])
    end
  end

  describe "parse_schema/1" do
    test "returns empty list for nil" do
      assert {:ok, []} = Frontmatter.parse_schema(nil)
    end

    test "parses string field with default" do
      schema = %{
        "status" => %{"type" => "string", "default" => "idle"}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:status][:type] == :string
      assert parsed[:status][:default] == "idle"
    end

    test "parses integer field" do
      schema = %{
        "count" => %{"type" => "integer", "default" => 0}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:count][:type] == :integer
      assert parsed[:count][:default] == 0
    end

    test "parses float field" do
      schema = %{
        "rate" => %{"type" => "float", "default" => 0.5}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:rate][:type] == :float
      assert parsed[:rate][:default] == 0.5
    end

    test "parses boolean field" do
      schema = %{
        "enabled" => %{"type" => "boolean", "default" => true}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:enabled][:type] == :boolean
      assert parsed[:enabled][:default] == true
    end

    test "parses atom field" do
      schema = %{
        "status" => %{"type" => "atom", "default" => :idle}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:status][:type] == :atom
      assert parsed[:status][:default] == :idle
    end

    test "parses atom field with allowed values" do
      schema = %{
        "mode" => %{"type" => "atom", "values" => [:quick, :standard, :thorough], "default" => :standard}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:mode][:type] == {:in, [:quick, :standard, :thorough]}
      assert parsed[:mode][:default] == :standard
    end

    test "parses list field with item type" do
      schema = %{
        "tags" => %{"type" => "list", "item_type" => "string", "default" => ["a", "b"]}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
      assert Keyword.keyword?(parsed)
      assert parsed[:tags][:type] == {:list, :string}
      assert parsed[:tags][:default] == ["a", "b"]
    end

    test "parses list field with integer items" do
      schema = %{
        "numbers" => %{"type" => "list", "item_type" => "integer", "default" => [1, 2, 3]}
      }

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
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

      assert {:ok, parsed} = Frontmatter.parse_schema(schema)
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

  describe "parse_channels/1" do
    test "parses channels configuration" do
      channels = %{"broadcast_to" => ["ui_state", "agent_events"]}

      assert Frontmatter.parse_channels(channels) == [broadcast_to: ["ui_state", "agent_events"]]
    end

    test "returns empty list for empty map" do
      assert Frontmatter.parse_channels(%{}) == []
    end

    test "returns empty list for non-map input" do
      assert Frontmatter.parse_channels("invalid") == []
    end

    test "handles multiple channel configurations" do
      channels = %{
        "broadcast_to" => ["ui_state"],
        "another_key" => "value"
      }

      result = Frontmatter.parse_channels(channels)
      assert Keyword.keyword?(result)
      assert result[:broadcast_to] == ["ui_state"]
      assert result[:another_key] == "value"
    end
  end

  describe "parse_signals/1" do
    test "parses signals configuration with emit" do
      signals = %{"emit" => ["task.done", "task.error"]}

      assert Frontmatter.parse_signals(signals) == [emit: ["task.done", "task.error"]]
    end

    test "parses signals configuration with events" do
      signals = %{
        "events" => %{
          "on_start" => ["agent.started"],
          "on_complete" => ["agent.finished"]
        }
      }

      result = Frontmatter.parse_signals(signals)
      assert result[:events][:on_start] == ["agent.started"]
      assert result[:events][:on_complete] == ["agent.finished"]
    end

    test "parses complex signals configuration" do
      signals = %{
        "emit" => ["task.done", "task.error"],
        "events" => %{
          "on_start" => ["agent.started"],
          "on_complete" => ["agent.finished"]
        }
      }

      result = Frontmatter.parse_signals(signals)
      assert result[:emit] == ["task.done", "task.error"]
      assert result[:events][:on_start] == ["agent.started"]
      assert result[:events][:on_complete] == ["agent.finished"]
    end

    test "returns empty list for empty map" do
      assert Frontmatter.parse_signals(%{}) == []
    end

    test "returns empty list for non-map input" do
      assert Frontmatter.parse_signals("invalid") == []
    end
  end

  describe "has_frontmatter?/1" do
    test "returns true for content with frontmatter" do
      assert Frontmatter.has_frontmatter?(@valid_content)
      assert Frontmatter.has_frontmatter?(@minimal_content)
    end

    test "returns false for content without frontmatter" do
      refute Frontmatter.has_frontmatter?(@no_frontmatter)
    end

    test "returns false for empty string" do
      refute Frontmatter.has_frontmatter?("")
    end

    test "returns false for incomplete frontmatter" do
      incomplete = """
      ---
      name: test
      Content without closing delimiter
      """

      refute Frontmatter.has_frontmatter?(incomplete)
    end
  end
end
