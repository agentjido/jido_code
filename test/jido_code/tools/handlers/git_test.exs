defmodule JidoCode.Tools.Handlers.Git.CommandTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Handlers.Git.Command

  @valid_context %{project_root: "/tmp/test_project"}

  # ============================================================================
  # Subcommand Validation Tests
  # ============================================================================

  describe "execute/2 subcommand validation" do
    test "rejects nil subcommand" do
      params = %{}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "subcommand is required"
    end

    test "rejects non-string subcommand" do
      params = %{"subcommand" => 123}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "subcommand must be a string"
    end

    test "rejects disallowed subcommands" do
      params = %{"subcommand" => "gc"}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "'gc' is not allowed"
    end

    test "rejects unknown subcommands" do
      params = %{"subcommand" => "made-up-command"}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "'made-up-command' is not allowed"
    end
  end

  # ============================================================================
  # Destructive Operation Tests
  # ============================================================================

  describe "execute/2 destructive operation blocking" do
    test "blocks force push by default" do
      params = %{"subcommand" => "push", "args" => ["--force", "origin", "main"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "destructive operation blocked"
      assert msg =~ "requires allow_destructive: true"
    end

    test "blocks -f push by default" do
      params = %{"subcommand" => "push", "args" => ["-f", "origin", "main"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "destructive operation blocked"
    end

    test "blocks hard reset by default" do
      params = %{"subcommand" => "reset", "args" => ["--hard", "HEAD~1"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "destructive operation blocked"
    end

    test "blocks force clean by default" do
      params = %{"subcommand" => "clean", "args" => ["-fd"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "destructive operation blocked"
    end

    test "blocks force branch delete by default" do
      params = %{"subcommand" => "branch", "args" => ["-D", "feature"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "destructive operation blocked"
    end
  end

  # ============================================================================
  # Context Validation Tests
  # ============================================================================

  describe "execute/2 context validation" do
    test "rejects missing context" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{})
      assert msg =~ "project_root is required"
    end

    test "rejects nil project_root" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{project_root: nil})
      assert msg =~ "project_root is required"
    end

    test "rejects non-string project_root" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{project_root: 123})
      assert msg =~ "project_root is required"
    end
  end

  # ============================================================================
  # Placeholder Response Tests
  # ============================================================================

  describe "execute/2 placeholder response" do
    test "returns not implemented error for valid read-only command" do
      params = %{"subcommand" => "status"}

      # Handler passes validation but returns placeholder error
      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "not yet implemented"
      assert msg =~ "Phase 3.1.2"
    end

    test "returns not implemented error for valid modifying command" do
      params = %{"subcommand" => "add", "args" => ["lib/module.ex"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "not yet implemented"
    end

    test "returns not implemented for allowed destructive command" do
      params = %{
        "subcommand" => "push",
        "args" => ["--force", "origin", "main"],
        "allow_destructive" => true
      }

      # With allow_destructive=true, validation passes
      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "not yet implemented"
    end
  end

  # ============================================================================
  # Allow Destructive Tests
  # ============================================================================

  describe "execute/2 allow_destructive parameter" do
    test "allows force push when allow_destructive is true" do
      params = %{
        "subcommand" => "push",
        "args" => ["--force", "origin", "main"],
        "allow_destructive" => true
      }

      # Should pass validation (returns placeholder error, not blocking error)
      assert {:error, msg} = Command.execute(params, @valid_context)
      refute msg =~ "destructive operation blocked"
      assert msg =~ "not yet implemented"
    end

    test "allows hard reset when allow_destructive is true" do
      params = %{
        "subcommand" => "reset",
        "args" => ["--hard", "HEAD~1"],
        "allow_destructive" => true
      }

      assert {:error, msg} = Command.execute(params, @valid_context)
      refute msg =~ "destructive operation blocked"
    end

    test "defaults allow_destructive to false" do
      params = %{"subcommand" => "push", "args" => ["--force"]}

      assert {:error, msg} = Command.execute(params, @valid_context)
      assert msg =~ "destructive operation blocked"
    end
  end

  # ============================================================================
  # Args Handling Tests
  # ============================================================================

  describe "execute/2 args handling" do
    test "handles missing args as empty list" do
      params = %{"subcommand" => "status"}

      # Should not raise on missing args
      assert {:error, _} = Command.execute(params, @valid_context)
    end

    test "handles explicit empty args" do
      params = %{"subcommand" => "status", "args" => []}

      assert {:error, _} = Command.execute(params, @valid_context)
    end
  end
end
