defmodule JidoCode.Tools.BackgroundShellTest do
  @moduledoc """
  Tests for the BackgroundShell module and BashBackground handler.

  Section 2.3.4 of Phase 2 planning document.

  Note: These tests run with the full application started (via test_helper.exs).
  The BackgroundShell GenServer must be running from the application supervision tree.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Tools.BackgroundShell
  alias JidoCode.Tools.Handlers.Shell.BashBackground

  @moduletag :tmp_dir
  @moduletag :phase2

  # ============================================================================
  # BackgroundShell Module Tests
  # ============================================================================

  describe "BackgroundShell.start_command/5" do
    @tag :integration
    test "starts a background process and returns shell_id", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("echo", ["hello"], session_id, tmp_dir)

      assert is_binary(shell_id)
      assert String.length(shell_id) > 0
    end

    @tag :integration
    test "returns unique shell_ids for multiple commands", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id1} = BackgroundShell.start_command("echo", ["one"], session_id, tmp_dir)
      {:ok, shell_id2} = BackgroundShell.start_command("echo", ["two"], session_id, tmp_dir)

      assert shell_id1 != shell_id2
    end

    test "validates command against allowlist", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:error, message} = BackgroundShell.start_command("bash", ["-c", "echo test"], session_id, tmp_dir)

      assert message =~ "Shell interpreters are blocked"
    end

    test "rejects disallowed commands", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:error, message} = BackgroundShell.start_command("sudo", ["rm", "-rf"], session_id, tmp_dir)

      assert message =~ "Command not allowed"
    end
  end

  describe "BackgroundShell.get_output/2" do
    @tag :integration
    test "retrieves output from a completed process", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("echo", ["hello world"], session_id, tmp_dir)

      # Wait for completion with blocking
      {:ok, result} = BackgroundShell.get_output(shell_id, block: true, timeout: 5000)

      assert result.status == :completed
      assert result.exit_code == 0
      assert String.contains?(result.output, "hello world")
    end

    test "returns not_found for invalid shell_id" do
      {:error, :not_found} = BackgroundShell.get_output("nonexistent-shell-id")
    end
  end

  describe "BackgroundShell.kill/1" do
    @tag :integration
    test "kills a running process", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("sleep", ["60"], session_id, tmp_dir)

      # Verify it's running
      {:ok, result1} = BackgroundShell.get_output(shell_id)
      assert result1.status == :running

      # Kill it
      :ok = BackgroundShell.kill(shell_id)

      # Wait a bit for the kill to propagate
      Process.sleep(100)

      # Verify it's killed
      {:ok, result2} = BackgroundShell.get_output(shell_id)
      assert result2.status == :killed
    end

    test "returns not_found for invalid shell_id" do
      {:error, :not_found} = BackgroundShell.kill("nonexistent-shell-id")
    end
  end

  describe "BackgroundShell.list/1" do
    test "returns empty list when no shells for session" do
      shells = BackgroundShell.list("nonexistent-session-id")
      assert shells == []
    end

    @tag :integration
    test "returns shells for the session", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id1} = BackgroundShell.start_command("echo", ["one"], session_id, tmp_dir)
      {:ok, shell_id2} = BackgroundShell.start_command("echo", ["two"], session_id, tmp_dir)

      # Wait for them to complete
      Process.sleep(200)

      shells = BackgroundShell.list(session_id)
      shell_ids = Enum.map(shells, & &1.shell_id)

      assert shell_id1 in shell_ids
      assert shell_id2 in shell_ids
    end
  end

  # ============================================================================
  # BashBackground Handler Tests
  # ============================================================================

  describe "BashBackground.execute/2" do
    test "requires session_id in context", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:error, message} = BashBackground.execute(%{"command" => "echo"}, context)

      assert message =~ "requires a session context"
    end

    test "requires command argument" do
      context = %{session_id: "test-session"}

      {:error, message} = BashBackground.execute(%{}, context)

      assert message =~ "requires a command argument"
    end
  end
end
