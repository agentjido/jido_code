defmodule JidoCode.Extensibility.SlashParserTest do
  use ExUnit.Case, async: true
  alias JidoCode.Extensibility.SlashParser

  # ============================================================================
  # Basic Parsing Tests
  # ============================================================================

  describe "parse/1" do
    test "parses simple command" do
      assert {:ok, parsed} = SlashParser.parse("/commit")
      assert parsed.command == "commit"
      assert parsed.args == []
      assert parsed.flags == %{}
      assert parsed.raw == "/commit"
    end

    test "parses command with single argument" do
      assert {:ok, parsed} = SlashParser.parse("/review file.ex")
      assert parsed.command == "review"
      assert parsed.args == ["file.ex"]
      assert parsed.flags == %{}
    end

    test "parses command with multiple arguments" do
      assert {:ok, parsed} = SlashParser.parse("/review file1.ex file2.ex file3.ex")
      assert parsed.command == "review"
      assert parsed.args == ["file1.ex", "file2.ex", "file3.ex"]
    end

    test "parses command with long flag and value" do
      assert {:ok, parsed} = SlashParser.parse("/review --mode strict")
      assert parsed.command == "review"
      assert parsed.args == []
      assert parsed.flags == %{"mode" => "strict"}
    end

    test "parses command with multiple flags" do
      assert {:ok, parsed} = SlashParser.parse("/review --mode strict --verbose true")
      assert parsed.command == "review"
      assert parsed.flags == %{"mode" => "strict", "verbose" => "true"}
    end

    test "parses command with short flag" do
      assert {:ok, parsed} = SlashParser.parse("/review -v")
      assert parsed.command == "review"
      assert parsed.flags == %{"v" => true}
    end

    test "parses command with short flag and value" do
      assert {:ok, parsed} = SlashParser.parse("/review -m strict")
      assert parsed.command == "review"
      assert parsed.flags == %{"m" => "strict"}
    end

    test "parses command with quoted string" do
      assert {:ok, parsed} = SlashParser.parse(~s(/commit -m "fix bug"))
      assert parsed.command == "commit"
      assert parsed.flags == %{"m" => "fix bug"}
    end

    test "parses command with quoted string containing spaces" do
      assert {:ok, parsed} = SlashParser.parse(~s(/commit -m "fix the nasty bug"))
      assert parsed.flags == %{"m" => "fix the nasty bug"}
    end

    test "parses command with single-quoted string" do
      assert {:ok, parsed} = SlashParser.parse("/review 'file with spaces.ex'")
      assert parsed.args == ["file with spaces.ex"]
    end

    test "parses complex command with all elements" do
      assert {:ok, parsed} =
               SlashParser.parse(~s(/commit --amend -m "fix bug" src/))

      assert parsed.command == "commit"
      assert parsed.args == ["src/"]
      assert parsed.flags == %{"amend" => true, "m" => "fix bug"}
    end

    test "handles flags at the end" do
      assert {:ok, parsed} = SlashParser.parse("/review file.ex --verbose")
      assert parsed.args == ["file.ex"]
      assert parsed.flags == %{"verbose" => true}
    end

    test "handles boolean flag when next token is also a flag" do
      assert {:ok, parsed} = SlashParser.parse("/review --verbose --mode strict")
      assert parsed.flags == %{"verbose" => true, "mode" => "strict"}
    end
  end

  # ============================================================================
  # Error Cases
  # ============================================================================

  describe "parse/1 errors" do
    test "returns error for non-slash input" do
      assert {:error, :not_a_slash_command} = SlashParser.parse("commit")
      assert {:error, :not_a_slash_command} = SlashParser.parse("commit -m test")
    end

    test "returns error for empty slash" do
      assert {:error, :empty_command} = SlashParser.parse("/")
    end

    test "returns error for unclosed quote" do
      assert {:error, :unclosed_quote} = SlashParser.parse(~s(/commit -m "unclosed))
    end

    test "returns error for unclosed single quote" do
      assert {:error, :unclosed_quote} = SlashParser.parse("/commit 'unclosed")
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "parse/1 edge cases" do
    test "handles extra whitespace" do
      assert {:ok, parsed} = SlashParser.parse("  /commit  ")
      assert parsed.command == "commit"
    end

    test "handles tabs and newlines" do
      assert {:ok, parsed} = SlashParser.parse("\t/commit\n")
      assert parsed.command == "commit"
    end

    test "handles empty quoted string" do
      assert {:ok, parsed} = SlashParser.parse(~s(/commit -m ""))
      assert parsed.flags == %{"m" => ""}
    end

    test "handles command starting with dash (edge case)" do
      # When command name starts with dash, it's treated as empty command with flags
      assert {:ok, parsed} = SlashParser.parse("/--flag value")
      assert parsed.command == ""
      assert parsed.args == []
      assert parsed.flags == %{"flag" => "value"}
    end

    test "handles short flag with single character value" do
      assert {:ok, parsed} = SlashParser.parse("/cmd -f x")
      assert parsed.flags == %{"f" => "x"}
    end

    test "handles multiple short flags" do
      assert {:ok, parsed} = SlashParser.parse("/cmd -v -x -y")
      assert parsed.flags == %{"v" => true, "x" => true, "y" => true}
    end
  end

  # ============================================================================
  # slash_command?/1 Tests
  # ============================================================================

  describe "slash_command?/1" do
    test "returns true for slash commands" do
      assert SlashParser.slash_command?("/commit")
      assert SlashParser.slash_command?("/review")
      assert SlashParser.slash_command?("/help --verbose")
    end

    test "returns false for non-slash input" do
      refute SlashParser.slash_command?("commit")
      refute SlashParser.slash_command?("")
      refute SlashParser.slash_command?("no slash here")
    end

    test "handles whitespace" do
      assert SlashParser.slash_command?("  /commit  ")
      refute SlashParser.slash_command?("  commit")
    end
  end

  # ============================================================================
  # ParsedCommand Struct Tests
  # ============================================================================

  describe "ParsedCommand struct" do
    test "creates struct with default values" do
      cmd = %SlashParser.ParsedCommand{command: "test"}
      assert cmd.command == "test"
      assert cmd.args == []
      assert cmd.flags == %{}
      assert cmd.raw == nil
    end

    test "creates struct with custom values" do
      cmd = %SlashParser.ParsedCommand{
        command: "test",
        args: ["arg1"],
        flags: %{"flag" => "value"},
        raw: "/test arg1 --flag value"
      }

      assert cmd.command == "test"
      assert cmd.args == ["arg1"]
      assert cmd.flags == %{"flag" => "value"}
      assert cmd.raw == "/test arg1 --flag value"
    end
  end

  # ============================================================================
  # Tokenization Edge Cases
  # ============================================================================

  describe "tokenization" do
    test "handles multiple spaces between tokens" do
      assert {:ok, parsed} = SlashParser.parse("/cmd   arg1    arg2")
      assert parsed.args == ["arg1", "arg2"]
    end

    test "handles mixed whitespace" do
      assert {:ok, parsed} = SlashParser.parse("/cmd\targ1\narg2")
      assert parsed.args == ["arg1", "arg2"]
    end

    test "handles quoted string with multiple words" do
      assert {:ok, parsed} = SlashParser.parse(~s(/cmd "one two three" four))
      assert parsed.args == ["one two three", "four"]
    end

    test "handles multiple quoted strings" do
      assert {:ok, parsed} = SlashParser.parse(~s(/cmd "first" "second" "third"))
      assert parsed.args == ["first", "second", "third"]
    end

    test "handles quoted strings with flags" do
      assert {:ok, parsed} = SlashParser.parse(~s(/cmd "quoted arg" --flag "quoted value"))
      assert parsed.args == ["quoted arg"]
      assert parsed.flags == %{"flag" => "quoted value"}
    end
  end

  # ============================================================================
  # Flag Parsing Edge Cases
  # ============================================================================

  describe "flag parsing edge cases" do
    test "handles flag value that looks like a flag" do
      # When we explicitly provide a value to a flag, use it even if it starts with dash
      # But our parser treats next token starting with dash as a flag, not a value
      # So --flag --value would treat --value as a boolean flag
      assert {:ok, parsed} = SlashParser.parse("/cmd --flag --value")
      assert parsed.flags == %{"flag" => true, "value" => true}
    end

    test "handles short flag with attached value (not supported, treated as boolean)" do
      # -fvalue style - our parser sees this as flag "fvalue"
      assert {:ok, parsed} = SlashParser.parse("/cmd -fvalue")
      assert parsed.flags == %{"f" => true}
      # "value" part is not parsed as attached
    end

    test "handles trailing flags" do
      assert {:ok, parsed} = SlashParser.parse("/cmd arg --flag1 --flag2")
      assert parsed.args == ["arg"]
      assert parsed.flags == %{"flag1" => true, "flag2" => true}
    end

    test "handles flag with value at beginning" do
      assert {:ok, parsed} = SlashParser.parse("/cmd --flag arg")
      assert parsed.args == []
      assert parsed.flags == %{"flag" => "arg"}
    end
  end
end
