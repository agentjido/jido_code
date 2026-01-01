defmodule JidoCode.Tools.Definitions.GitCommandTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.GitCommand
  alias JidoCode.Tools.Tool

  # ============================================================================
  # all/0 Tests
  # ============================================================================

  describe "all/0" do
    test "returns list with git_command tool" do
      tools = GitCommand.all()
      assert length(tools) == 1
      assert hd(tools).name == "git_command"
    end
  end

  # ============================================================================
  # git_command/0 Tool Definition Tests
  # ============================================================================

  describe "git_command/0 definition" do
    test "has correct name" do
      tool = GitCommand.git_command()
      assert tool.name == "git_command"
    end

    test "has descriptive description" do
      tool = GitCommand.git_command()
      assert tool.description =~ "git command"
      assert tool.description =~ "Read-only"
      assert tool.description =~ "destructive"
    end

    test "has correct handler module" do
      tool = GitCommand.git_command()
      assert tool.handler == JidoCode.Tools.Handlers.Git.Command
    end

    test "has three parameters" do
      tool = GitCommand.git_command()
      assert length(tool.parameters) == 3
    end

    test "subcommand parameter is required string" do
      tool = GitCommand.git_command()
      param = Enum.find(tool.parameters, &(&1.name == "subcommand"))

      assert param.type == :string
      assert param.required == true
      assert param.description =~ "subcommand"
    end

    test "args parameter is optional array" do
      tool = GitCommand.git_command()
      param = Enum.find(tool.parameters, &(&1.name == "args"))

      assert param.type == :array
      assert param.required == false
      assert param.description =~ "arguments"
    end

    test "allow_destructive parameter is optional boolean" do
      tool = GitCommand.git_command()
      param = Enum.find(tool.parameters, &(&1.name == "allow_destructive"))

      assert param.type == :boolean
      assert param.required == false
      assert param.description =~ "destructive"
    end

    test "generates valid LLM function format" do
      tool = GitCommand.git_command()
      llm_fn = Tool.to_llm_function(tool)

      assert llm_fn.type == "function"
      assert llm_fn.function.name == "git_command"
      assert is_binary(llm_fn.function.description)
      assert is_map(llm_fn.function.parameters)

      # Check parameters schema
      params = llm_fn.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "subcommand")
      assert Map.has_key?(params.properties, "args")
      assert Map.has_key?(params.properties, "allow_destructive")

      # Only subcommand is required
      assert params.required == ["subcommand"]
    end
  end

  # ============================================================================
  # Subcommand Categories Tests
  # ============================================================================

  describe "always_allowed_subcommands/0" do
    test "includes read-only commands" do
      allowed = GitCommand.always_allowed_subcommands()

      assert "status" in allowed
      assert "diff" in allowed
      assert "log" in allowed
      assert "show" in allowed
      assert "branch" in allowed
      assert "remote" in allowed
      assert "tag" in allowed
      assert "rev-parse" in allowed
      assert "blame" in allowed
      assert "reflog" in allowed
    end

    test "does not include modifying commands" do
      allowed = GitCommand.always_allowed_subcommands()

      refute "add" in allowed
      refute "commit" in allowed
      refute "push" in allowed
      refute "merge" in allowed
    end
  end

  describe "modifying_subcommands/0" do
    test "includes state-changing commands" do
      modifying = GitCommand.modifying_subcommands()

      assert "add" in modifying
      assert "commit" in modifying
      assert "checkout" in modifying
      assert "merge" in modifying
      assert "rebase" in modifying
      assert "stash" in modifying
      assert "push" in modifying
      assert "pull" in modifying
      assert "fetch" in modifying
      assert "reset" in modifying
      assert "revert" in modifying
    end

    test "does not include read-only commands" do
      modifying = GitCommand.modifying_subcommands()

      refute "status" in modifying
      refute "diff" in modifying
      refute "log" in modifying
    end
  end

  describe "allowed_subcommands/0" do
    test "combines always_allowed and modifying subcommands" do
      allowed = GitCommand.allowed_subcommands()

      # Read-only
      assert "status" in allowed
      assert "diff" in allowed

      # Modifying
      assert "add" in allowed
      assert "commit" in allowed
    end

    test "does not include unknown subcommands" do
      allowed = GitCommand.allowed_subcommands()

      refute "gc" in allowed
      refute "fsck" in allowed
      refute "prune" in allowed
      refute "pack-objects" in allowed
    end
  end

  describe "subcommand_allowed?/1" do
    test "returns true for allowed subcommands" do
      assert GitCommand.subcommand_allowed?("status")
      assert GitCommand.subcommand_allowed?("diff")
      assert GitCommand.subcommand_allowed?("log")
      assert GitCommand.subcommand_allowed?("add")
      assert GitCommand.subcommand_allowed?("commit")
      assert GitCommand.subcommand_allowed?("push")
    end

    test "returns false for disallowed subcommands" do
      refute GitCommand.subcommand_allowed?("gc")
      refute GitCommand.subcommand_allowed?("fsck")
      refute GitCommand.subcommand_allowed?("prune")
      refute GitCommand.subcommand_allowed?("pack-objects")
      refute GitCommand.subcommand_allowed?("unknown")
    end
  end

  # ============================================================================
  # Destructive Pattern Tests
  # ============================================================================

  describe "destructive_patterns/0" do
    test "includes force push patterns" do
      patterns = GitCommand.destructive_patterns()

      assert {"push", ["--force"]} in patterns
      assert {"push", ["-f"]} in patterns
      assert {"push", ["--force-with-lease"]} in patterns
    end

    test "includes hard reset pattern" do
      patterns = GitCommand.destructive_patterns()

      assert {"reset", ["--hard"]} in patterns
    end

    test "includes clean patterns" do
      patterns = GitCommand.destructive_patterns()

      assert {"clean", ["-f"]} in patterns
      assert {"clean", ["-fd"]} in patterns
      assert {"clean", ["-fx"]} in patterns
      assert {"clean", ["-fxd"]} in patterns
    end

    test "includes force branch delete" do
      patterns = GitCommand.destructive_patterns()

      assert {"branch", ["-D"]} in patterns
      assert {"branch", ["--delete", "--force"]} in patterns
    end
  end

  describe "destructive?/2" do
    test "returns true for force push" do
      assert GitCommand.destructive?("push", ["--force", "origin", "main"])
      assert GitCommand.destructive?("push", ["-f", "origin", "main"])
      assert GitCommand.destructive?("push", ["origin", "main", "--force"])
    end

    test "returns false for normal push" do
      refute GitCommand.destructive?("push", ["origin", "main"])
      refute GitCommand.destructive?("push", ["-u", "origin", "feature"])
      refute GitCommand.destructive?("push", [])
    end

    test "returns true for hard reset" do
      assert GitCommand.destructive?("reset", ["--hard"])
      assert GitCommand.destructive?("reset", ["--hard", "HEAD~1"])
    end

    test "returns false for soft/mixed reset" do
      refute GitCommand.destructive?("reset", ["--soft", "HEAD~1"])
      refute GitCommand.destructive?("reset", ["--mixed", "HEAD~1"])
      refute GitCommand.destructive?("reset", ["HEAD~1"])
    end

    test "returns true for force clean" do
      assert GitCommand.destructive?("clean", ["-f"])
      assert GitCommand.destructive?("clean", ["-fd"])
      assert GitCommand.destructive?("clean", ["-fx"])
    end

    test "returns false for dry-run clean" do
      refute GitCommand.destructive?("clean", ["-n"])
      refute GitCommand.destructive?("clean", ["--dry-run"])
    end

    test "returns true for force branch delete" do
      assert GitCommand.destructive?("branch", ["-D", "feature"])
    end

    test "returns false for safe branch delete" do
      refute GitCommand.destructive?("branch", ["-d", "feature"])
      refute GitCommand.destructive?("branch", ["--delete", "feature"])
    end

    test "returns true for force branch delete with both flags" do
      assert GitCommand.destructive?("branch", ["--delete", "--force", "feature"])
      assert GitCommand.destructive?("branch", ["--force", "--delete", "feature"])
    end

    test "returns false for read-only commands" do
      refute GitCommand.destructive?("status", [])
      refute GitCommand.destructive?("diff", ["HEAD~1"])
      refute GitCommand.destructive?("log", ["-5"])
    end

    # Security bypass vector tests - ensure alternative flag syntaxes are caught
    test "detects --hard=value syntax (bypass vector #1)" do
      # Git accepts --hard=<commit> syntax which must be caught
      assert GitCommand.destructive?("reset", ["--hard=HEAD~1"])
      assert GitCommand.destructive?("reset", ["--hard=abc123"])
    end

    test "detects reordered clean flags (bypass vector #2)" do
      # Git accepts flags in any order - -df is same as -fd
      assert GitCommand.destructive?("clean", ["-df"])
      assert GitCommand.destructive?("clean", ["-xf"])
      assert GitCommand.destructive?("clean", ["-dxf"])
      assert GitCommand.destructive?("clean", ["-xdf"])
      assert GitCommand.destructive?("clean", ["-fxd"])
    end

    test "detects force push with --force-with-lease" do
      assert GitCommand.destructive?("push", ["--force-with-lease", "origin", "main"])
      assert GitCommand.destructive?("push", ["origin", "--force-with-lease"])
    end

    test "detects combined short flags containing force" do
      # Short flags can be combined - any combination with 'f' is destructive for clean
      assert GitCommand.destructive?("clean", ["-nfd"])
      assert GitCommand.destructive?("clean", ["-nfx"])
    end

    test "does not false positive on unrelated flags" do
      # -d alone should not match -D (case-sensitive)
      refute GitCommand.destructive?("branch", ["-d", "feature"])
      # -n (dry-run) for clean should not match -f
      refute GitCommand.destructive?("clean", ["-n"])
      refute GitCommand.destructive?("clean", ["-nd"])
    end
  end

  # ============================================================================
  # Tool Validation Tests
  # ============================================================================

  describe "tool argument validation" do
    test "validates required subcommand argument" do
      tool = GitCommand.git_command()

      assert {:error, _} = Tool.validate_args(tool, %{})
      assert {:error, _} = Tool.validate_args(tool, %{"args" => ["-5"]})
    end

    test "accepts valid subcommand only" do
      tool = GitCommand.git_command()

      assert :ok = Tool.validate_args(tool, %{"subcommand" => "status"})
    end

    test "accepts subcommand with args" do
      tool = GitCommand.git_command()

      assert :ok = Tool.validate_args(tool, %{"subcommand" => "log", "args" => ["-5", "--oneline"]})
    end

    test "accepts all parameters" do
      tool = GitCommand.git_command()

      assert :ok =
               Tool.validate_args(tool, %{
                 "subcommand" => "push",
                 "args" => ["--force"],
                 "allow_destructive" => true
               })
    end

    test "rejects invalid subcommand type" do
      tool = GitCommand.git_command()

      assert {:error, msg} = Tool.validate_args(tool, %{"subcommand" => 123})
      assert msg =~ "string"
    end

    test "rejects invalid args type" do
      tool = GitCommand.git_command()

      assert {:error, msg} = Tool.validate_args(tool, %{"subcommand" => "log", "args" => "not-array"})
      assert msg =~ "array"
    end

    test "rejects invalid allow_destructive type" do
      tool = GitCommand.git_command()

      assert {:error, msg} =
               Tool.validate_args(tool, %{
                 "subcommand" => "push",
                 "allow_destructive" => "yes"
               })

      assert msg =~ "boolean"
    end

    test "rejects unknown parameters" do
      tool = GitCommand.git_command()

      assert {:error, msg} =
               Tool.validate_args(tool, %{
                 "subcommand" => "status",
                 "unknown_param" => "value"
               })

      assert msg =~ "unknown"
    end
  end
end
