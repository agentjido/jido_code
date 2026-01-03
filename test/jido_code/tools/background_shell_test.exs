defmodule JidoCode.Tools.BackgroundShellTest do
  @moduledoc """
  Tests for the BackgroundShell module and background shell handlers.

  Sections 2.3.4, 2.4.4, and 2.5.4 of Phase 2 planning document.

  Note: These tests run with the full application started (via test_helper.exs).
  The BackgroundShell GenServer must be running from the application supervision tree.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Tools.BackgroundShell
  alias JidoCode.Tools.Handlers.Shell.BashBackground
  alias JidoCode.Tools.Handlers.Shell.BashOutput
  alias JidoCode.Tools.Handlers.Shell.KillShell

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

  # ============================================================================
  # BashOutput Handler Tests (Section 2.4.4)
  # ============================================================================

  describe "BashOutput.execute/2" do
    @tag :integration
    test "retrieves output from completed process", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("echo", ["hello output"], session_id, tmp_dir)

      # Wait for completion
      Process.sleep(200)

      context = %{session_id: session_id, project_root: tmp_dir}
      {:ok, json} = BashOutput.execute(%{"shell_id" => shell_id, "block" => true, "timeout" => 5000}, context)

      result = Jason.decode!(json)
      assert result["status"] == "completed"
      assert result["exit_code"] == 0
      assert String.contains?(result["output"], "hello output")
    end

    @tag :integration
    test "returns running status for in-progress process", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("sleep", ["10"], session_id, tmp_dir)

      context = %{session_id: session_id, project_root: tmp_dir}
      {:ok, json} = BashOutput.execute(%{"shell_id" => shell_id, "block" => false}, context)

      result = Jason.decode!(json)
      assert result["status"] == "running"

      # Clean up
      BackgroundShell.kill(shell_id)
    end

    test "returns error for non-existent shell_id" do
      context = %{session_id: "test-session"}

      {:error, message} = BashOutput.execute(%{"shell_id" => "nonexistent-id"}, context)

      assert message =~ "Shell not found"
    end

    test "requires shell_id argument" do
      context = %{session_id: "test-session"}

      {:error, message} = BashOutput.execute(%{}, context)

      assert message =~ "requires a shell_id argument"
    end

    @tag :integration
    test "defaults to blocking mode", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("echo", ["quick"], session_id, tmp_dir)

      context = %{session_id: session_id, project_root: tmp_dir}
      # No block parameter - should default to true and wait for completion
      {:ok, json} = BashOutput.execute(%{"shell_id" => shell_id, "timeout" => 5000}, context)

      result = Jason.decode!(json)
      assert result["status"] == "completed"
    end
  end

  # ============================================================================
  # KillShell Handler Tests (Section 2.5.4)
  # ============================================================================

  describe "KillShell.execute/2" do
    @tag :integration
    test "kills a running process", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("sleep", ["60"], session_id, tmp_dir)

      # Verify it's running
      {:ok, result1} = BackgroundShell.get_output(shell_id)
      assert result1.status == :running

      context = %{session_id: session_id, project_root: tmp_dir}
      {:ok, json} = KillShell.execute(%{"shell_id" => shell_id}, context)

      result = Jason.decode!(json)
      assert result["success"] == true
      assert result["message"] =~ "terminated"

      # Wait for kill to propagate and verify
      Process.sleep(100)
      {:ok, result2} = BackgroundShell.get_output(shell_id)
      assert result2.status == :killed
    end

    @tag :integration
    test "handles already-finished process", %{tmp_dir: tmp_dir} do
      session_id = Uniq.UUID.uuid4()

      {:ok, shell_id} = BackgroundShell.start_command("echo", ["done"], session_id, tmp_dir)

      # Wait for it to complete
      Process.sleep(200)

      context = %{session_id: session_id, project_root: tmp_dir}
      {:ok, json} = KillShell.execute(%{"shell_id" => shell_id}, context)

      result = Jason.decode!(json)
      assert result["success"] == true
      assert result["message"] =~ "already finished"
    end

    test "returns error for non-existent shell_id" do
      context = %{session_id: "test-session"}

      {:error, message} = KillShell.execute(%{"shell_id" => "nonexistent-id"}, context)

      assert message =~ "Shell not found"
    end

    test "requires shell_id argument" do
      context = %{session_id: "test-session"}

      {:error, message} = KillShell.execute(%{}, context)

      assert message =~ "requires a shell_id argument"
    end
  end
end
