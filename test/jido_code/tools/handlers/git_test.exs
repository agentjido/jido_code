defmodule JidoCode.Tools.Handlers.Git.CommandTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Handlers.Git.Command

  @moduletag :tmp_dir

  # ============================================================================
  # Subcommand Validation Tests
  # ============================================================================

  describe "execute/2 subcommand validation" do
    setup %{tmp_dir: tmp_dir} do
      # Initialize a git repo for testing
      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
      System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
      %{context: %{project_root: tmp_dir}}
    end

    test "rejects nil subcommand", %{context: context} do
      params = %{}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "subcommand is required"
    end

    test "rejects non-string subcommand", %{context: context} do
      params = %{"subcommand" => 123}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "subcommand must be a string"
    end

    test "rejects disallowed subcommands", %{context: context} do
      params = %{"subcommand" => "gc"}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "'gc' is not allowed"
    end

    test "rejects unknown subcommands", %{context: context} do
      params = %{"subcommand" => "made-up-command"}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "'made-up-command' is not allowed"
    end
  end

  # ============================================================================
  # Destructive Operation Tests
  # ============================================================================

  describe "execute/2 destructive operation blocking" do
    setup %{tmp_dir: tmp_dir} do
      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
      System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
      %{context: %{project_root: tmp_dir}}
    end

    test "blocks force push by default", %{context: context} do
      params = %{"subcommand" => "push", "args" => ["--force", "origin", "main"]}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "destructive operation blocked"
      assert msg =~ "allow_destructive"
    end

    test "blocks -f push by default", %{context: context} do
      params = %{"subcommand" => "push", "args" => ["-f", "origin", "main"]}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "destructive operation blocked"
    end

    test "blocks hard reset by default", %{context: context} do
      params = %{"subcommand" => "reset", "args" => ["--hard", "HEAD~1"]}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "destructive operation blocked"
    end

    test "blocks force clean by default", %{context: context} do
      params = %{"subcommand" => "clean", "args" => ["-fd"]}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "destructive operation blocked"
    end

    test "blocks force branch delete by default", %{context: context} do
      params = %{"subcommand" => "branch", "args" => ["-D", "feature"]}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "destructive operation blocked"
    end
  end

  # ============================================================================
  # Context Validation Tests
  # ============================================================================

  describe "execute/2 context validation" do
    setup do
      # Enable require_session_context for strict validation testing
      prev = Application.get_env(:jido_code, :require_session_context, false)
      Application.put_env(:jido_code, :require_session_context, true)
      on_exit(fn -> Application.put_env(:jido_code, :require_session_context, prev) end)
      :ok
    end

    test "rejects missing context when require_session_context is true" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{})
      assert msg =~ "session_id or project_root required"
    end

    test "rejects nil project_root when require_session_context is true" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{project_root: nil})
      assert msg =~ "session_id or project_root required"
    end

    test "rejects non-string project_root when require_session_context is true" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{project_root: 123})
      assert msg =~ "session_id or project_root required"
    end

    test "rejects invalid session_id format" do
      params = %{"subcommand" => "status"}

      assert {:error, msg} = Command.execute(params, %{session_id: "invalid-uuid"})
      assert msg =~ "invalid session ID format"
    end
  end

  # ============================================================================
  # Successful Execution Tests
  # ============================================================================

  describe "execute/2 successful execution" do
    setup %{tmp_dir: tmp_dir} do
      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
      System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
      %{context: %{project_root: tmp_dir}}
    end

    test "executes git status successfully", %{context: context} do
      params = %{"subcommand" => "status"}

      assert {:ok, result} = Command.execute(params, context)
      assert is_map(result)
      assert Map.has_key?(result, :output)
      assert Map.has_key?(result, :exit_code)
      assert result.exit_code == 0
    end

    test "executes git log successfully", %{context: context, tmp_dir: tmp_dir} do
      # Create a commit first
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: tmp_dir)

      params = %{"subcommand" => "log", "args" => ["-1", "--oneline"]}

      assert {:ok, result} = Command.execute(params, context)
      assert result.exit_code == 0
      assert result.output =~ "Initial commit"
    end

    test "executes git diff with no changes", %{context: context} do
      params = %{"subcommand" => "diff"}

      assert {:ok, result} = Command.execute(params, context)
      assert result.exit_code == 0
      # Empty diff on clean repo
      assert result.output == ""
    end

    test "returns parsed data for status command", %{context: context, tmp_dir: tmp_dir} do
      # Create an untracked file
      File.write!(Path.join(tmp_dir, "newfile.txt"), "content")

      params = %{"subcommand" => "status"}

      assert {:ok, result} = Command.execute(params, context)
      assert is_map(result.parsed) or is_nil(result.parsed) or is_list(result.parsed)
    end
  end

  # ============================================================================
  # Allow Destructive Tests
  # ============================================================================

  describe "execute/2 allow_destructive parameter" do
    setup %{tmp_dir: tmp_dir} do
      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
      System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
      %{context: %{project_root: tmp_dir}}
    end

    test "allows force push when allow_destructive is true (fails with no remote)", %{
      context: context
    } do
      params = %{
        "subcommand" => "push",
        "args" => ["--force", "origin", "main"],
        "allow_destructive" => true
      }

      # The command should be allowed but will fail since there's no remote
      assert {:ok, result} = Command.execute(params, context)
      # Will fail with non-zero exit code since no remote exists
      assert result.exit_code != 0
    end

    test "allows hard reset when allow_destructive is true", %{
      context: context,
      tmp_dir: tmp_dir
    } do
      # Create a commit first
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: tmp_dir)

      params = %{
        "subcommand" => "reset",
        "args" => ["--hard", "HEAD"],
        "allow_destructive" => true
      }

      assert {:ok, result} = Command.execute(params, context)
      assert result.exit_code == 0
    end

    test "defaults allow_destructive to false", %{context: context} do
      params = %{"subcommand" => "push", "args" => ["--force"]}

      assert {:error, msg} = Command.execute(params, context)
      assert msg =~ "destructive operation blocked"
    end
  end

  # ============================================================================
  # Args Handling Tests
  # ============================================================================

  describe "execute/2 args handling" do
    setup %{tmp_dir: tmp_dir} do
      System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
      System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
      %{context: %{project_root: tmp_dir}}
    end

    test "handles missing args as empty list", %{context: context} do
      params = %{"subcommand" => "status"}

      assert {:ok, result} = Command.execute(params, context)
      assert result.exit_code == 0
    end

    test "handles explicit empty args", %{context: context} do
      params = %{"subcommand" => "status", "args" => []}

      assert {:ok, result} = Command.execute(params, context)
      assert result.exit_code == 0
    end

    test "passes args correctly to git command", %{context: context, tmp_dir: tmp_dir} do
      # Create a commit first
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: tmp_dir)

      params = %{"subcommand" => "log", "args" => ["--oneline", "-1"]}

      assert {:ok, result} = Command.execute(params, context)
      assert result.exit_code == 0
      # Output should be short (oneline format)
      assert String.length(result.output) < 100
    end
  end
end
