defmodule JidoCode.Tools.GitCommandIntegrationTest do
  @moduledoc """
  Integration tests for the git_command tool through the executor/sandbox flow.

  These tests verify end-to-end execution of git commands through:
  - Tool registration and lookup
  - Executor parsing and dispatch
  - Handler execution through bridge
  - Result formatting and parsing

  Part of Phase 3.1.4 - Git Command Tool Integration Tests
  """

  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}
  alias JidoCode.Tools.Definitions.GitCommand

  @moduletag :tmp_dir

  # ============================================================================
  # Setup
  # ============================================================================

  setup %{tmp_dir: tmp_dir} do
    # Ensure application is started
    Application.ensure_all_started(:jido_code)

    # Initialize git repo in tmp_dir
    {_, 0} = System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    {_, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

    # Register git_command tool
    Registry.clear()
    :ok = Registry.register(GitCommand.git_command())

    # Executor options with context
    exec_opts = [context: %{project_root: tmp_dir}]

    %{tmp_dir: tmp_dir, exec_opts: exec_opts}
  end

  # ============================================================================
  # Basic Command Execution Tests
  # ============================================================================

  describe "git status through executor" do
    test "executes git status and returns result", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("status")

      assert {:ok, result} = Executor.execute(tool_call, exec_opts)
      assert %Result{} = result
      assert result.status == :ok
      assert is_binary(result.content)

      # Content is JSON with output and exit_code
      {:ok, decoded} = Jason.decode(result.content)
      assert Map.has_key?(decoded, "output")
      assert Map.has_key?(decoded, "exit_code")
      assert decoded["exit_code"] == 0
    end

    test "status shows untracked files", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      # Create an untracked file
      File.write!(Path.join(tmp_dir, "new_file.txt"), "content")

      tool_call = build_tool_call("status")
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["output"] =~ "new_file.txt"
    end
  end

  describe "git diff through executor" do
    test "executes git diff on clean repo", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("diff")

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] == 0
      # Empty diff on clean repo
      assert decoded["output"] == ""
    end

    test "diff shows modified file content", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      # Create and commit a file
      file_path = Path.join(tmp_dir, "tracked.txt")
      File.write!(file_path, "original content")
      {_, 0} = System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Add file"], cd: tmp_dir)

      # Modify the file
      File.write!(file_path, "modified content")

      tool_call = build_tool_call("diff")
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["output"] =~ "tracked.txt"
      assert decoded["output"] =~ "-original content"
      assert decoded["output"] =~ "+modified content"
    end
  end

  describe "git log through executor" do
    setup %{tmp_dir: tmp_dir} do
      # Create some commits for log testing
      File.write!(Path.join(tmp_dir, "file1.txt"), "content1")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "First commit"], cd: tmp_dir)

      File.write!(Path.join(tmp_dir, "file2.txt"), "content2")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Second commit"], cd: tmp_dir)

      :ok
    end

    test "executes git log", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("log")

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] == 0
      assert decoded["output"] =~ "First commit"
      assert decoded["output"] =~ "Second commit"
    end

    test "log with format options", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("log", ["--oneline", "-1"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] == 0
      assert decoded["output"] =~ "Second commit"
      # Oneline format should be short
      lines = String.split(decoded["output"], "\n", trim: true)
      assert length(lines) == 1
    end
  end

  describe "git branch through executor" do
    setup %{tmp_dir: tmp_dir} do
      # Need at least one commit for branch to work
      File.write!(Path.join(tmp_dir, "init.txt"), "content")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Initial"], cd: tmp_dir)
      :ok
    end

    test "lists branches", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("branch")

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] == 0
      # Should show current branch (master or main)
      assert decoded["output"] =~ "master" or decoded["output"] =~ "main"
    end

    test "creates new branch", %{exec_opts: exec_opts, tmp_dir: tmp_dir} do
      tool_call = build_tool_call("branch", ["feature-test"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] == 0

      # Verify branch was created
      {output, 0} = System.cmd("git", ["branch"], cd: tmp_dir)
      assert output =~ "feature-test"
    end
  end

  # ============================================================================
  # Destructive Operation Blocking Tests
  # ============================================================================

  describe "force push blocking" do
    test "blocks force push by default", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("push", ["--force", "origin", "main"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "blocks -f push by default", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("push", ["-f", "origin", "main"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "allows force push with allow_destructive", %{exec_opts: exec_opts, tmp_dir: tmp_dir} do
      # Create a commit first
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Test"], cd: tmp_dir)

      tool_call = build_tool_call("push", ["--force", "origin", "main"], true)

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      # Should execute (but fail with non-zero exit code since no remote)
      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] != 0
    end
  end

  describe "reset --hard blocking" do
    test "blocks reset --hard by default", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("reset", ["--hard", "HEAD~1"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "allows reset --hard with allow_destructive", %{exec_opts: exec_opts, tmp_dir: tmp_dir} do
      # Create a commit first
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Test"], cd: tmp_dir)

      tool_call = build_tool_call("reset", ["--hard", "HEAD"], true)

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] == 0
    end
  end

  describe "other destructive operations" do
    test "blocks clean -fd by default", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("clean", ["-fd"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "blocks branch -D by default", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("branch", ["-D", "some-branch"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end
  end

  describe "security bypass vector blocking" do
    test "blocks --hard=value syntax", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("reset", ["--hard=HEAD~1"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "blocks reordered clean flags (-df)", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("clean", ["-df"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "blocks reordered clean flags (-xdf)", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("clean", ["-xdf"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end

    test "blocks --force-with-lease push", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("push", ["--force-with-lease", "origin", "main"])

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "destructive operation blocked"
    end
  end

  # ============================================================================
  # Project Directory Tests
  # ============================================================================

  describe "runs in project directory" do
    test "executes in context project_root", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      # Create a unique file in the tmp_dir
      unique_name = "unique_#{:rand.uniform(100_000)}.txt"
      File.write!(Path.join(tmp_dir, unique_name), "content")

      tool_call = build_tool_call("status")
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      # Should see the unique file in status
      assert decoded["output"] =~ unique_name
    end

    test "different project roots are isolated", %{tmp_dir: tmp_dir} do
      # Create a second tmp_dir
      other_dir = Path.join(System.tmp_dir!(), "other_git_#{:rand.uniform(100_000)}")
      File.mkdir_p!(other_dir)
      {_, 0} = System.cmd("git", ["init"], cd: other_dir, stderr_to_stdout: true)
      {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: other_dir)
      {_, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: other_dir)

      on_exit(fn -> File.rm_rf!(other_dir) end)

      # Create unique files in each directory
      File.write!(Path.join(tmp_dir, "file_in_first.txt"), "content")
      File.write!(Path.join(other_dir, "file_in_second.txt"), "content")

      # Check first directory
      tool_call = build_tool_call("status")
      {:ok, result1} = Executor.execute(tool_call, context: %{project_root: tmp_dir})
      assert result1.status == :ok
      {:ok, decoded1} = Jason.decode(result1.content)
      assert decoded1["output"] =~ "file_in_first.txt"
      refute decoded1["output"] =~ "file_in_second.txt"

      # Check second directory
      {:ok, result2} = Executor.execute(tool_call, context: %{project_root: other_dir})
      assert result2.status == :ok
      {:ok, decoded2} = Jason.decode(result2.content)
      assert decoded2["output"] =~ "file_in_second.txt"
      refute decoded2["output"] =~ "file_in_first.txt"
    end
  end

  # ============================================================================
  # Output Parsing Tests
  # ============================================================================

  describe "status output parsing" do
    test "parses untracked files", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      File.write!(Path.join(tmp_dir, "untracked.txt"), "content")

      tool_call = build_tool_call("status")
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      # Parsed data should be present
      assert Map.has_key?(decoded, "parsed")
    end

    test "parses staged files", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      File.write!(Path.join(tmp_dir, "staged.txt"), "content")
      {_, 0} = System.cmd("git", ["add", "staged.txt"], cd: tmp_dir)

      tool_call = build_tool_call("status")
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["output"] =~ "staged.txt"
    end
  end

  describe "diff output parsing" do
    test "parses file changes", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      # Create and commit a file
      file_path = Path.join(tmp_dir, "parse_test.txt")
      File.write!(file_path, "line1\nline2\nline3")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Add file"], cd: tmp_dir)

      # Modify it
      File.write!(file_path, "line1\nmodified\nline3")

      tool_call = build_tool_call("diff")
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["output"] =~ "parse_test.txt"
      assert decoded["output"] =~ "-line2"
      assert decoded["output"] =~ "+modified"
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "git error handling" do
    test "handles non-existent ref gracefully", %{tmp_dir: tmp_dir, exec_opts: exec_opts} do
      # Create a commit first so we have a valid repo
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "Initial"], cd: tmp_dir)

      # Try to show a non-existent ref
      tool_call = build_tool_call("show", ["nonexistent-ref-12345"])
      {:ok, result} = Executor.execute(tool_call, exec_opts)

      # Should execute but return non-zero exit code
      assert result.status == :ok
      {:ok, decoded} = Jason.decode(result.content)
      assert decoded["exit_code"] != 0
    end

    test "handles invalid subcommand", %{exec_opts: exec_opts} do
      tool_call = build_tool_call("invalid-command-xyz")

      {:ok, result} = Executor.execute(tool_call, exec_opts)

      assert result.status == :error
      assert result.content =~ "not allowed"
    end

    test "handles missing required parameters" do
      # Tool call without subcommand
      tool_call = %{
        id: "call_#{:rand.uniform(100_000)}",
        name: "git_command",
        arguments: %{}
      }

      {:ok, result} = Executor.execute(tool_call, context: %{project_root: "/tmp"})

      assert result.status == :error
      assert result.content =~ "subcommand"
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp build_tool_call(subcommand, args \\ [], allow_destructive \\ false) do
    arguments =
      %{"subcommand" => subcommand}
      |> maybe_add_args(args)
      |> maybe_add_destructive(allow_destructive)

    %{
      id: "call_#{:rand.uniform(100_000)}",
      name: "git_command",
      arguments: arguments
    }
  end

  defp maybe_add_args(args_map, []), do: args_map
  defp maybe_add_args(args_map, args), do: Map.put(args_map, "args", args)

  defp maybe_add_destructive(args_map, false), do: args_map
  defp maybe_add_destructive(args_map, true), do: Map.put(args_map, "allow_destructive", true)
end
