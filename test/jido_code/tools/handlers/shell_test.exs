defmodule JidoCode.Tools.Handlers.ShellTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Handlers.Shell.RunCommand

  @moduletag :tmp_dir

  # ============================================================================
  # RunCommand Tests
  # ============================================================================

  describe "RunCommand.execute/2" do
    test "executes simple command", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "echo", "args" => ["hello"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert String.trim(result["stdout"]) == "hello"
    end

    test "captures exit code", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "false"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] != 0
    end

    test "runs in project directory", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "pwd"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert String.trim(result["stdout"]) == tmp_dir
    end

    test "handles command with multiple arguments", %{tmp_dir: tmp_dir} do
      # Create a test file
      File.write!(Path.join(tmp_dir, "test.txt"), "hello world")

      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "cat", "args" => ["test.txt"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["stdout"] == "hello world"
    end

    test "returns error for non-existent command", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = RunCommand.execute(%{"command" => "nonexistent_cmd_xyz"}, context)
      assert error =~ "Command not found"
    end

    test "handles empty args", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "true", "args" => []}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "handles missing args key", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "true"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "captures stderr in stdout (merged)", %{tmp_dir: tmp_dir} do
      # Use bash -c to write to stderr
      context = %{project_root: tmp_dir}

      {:ok, json} =
        RunCommand.execute(
          %{"command" => "bash", "args" => ["-c", "echo 'to stderr' >&2"]},
          context
        )

      result = Jason.decode!(json)
      # stderr is merged into stdout
      assert result["stdout"] =~ "to stderr"
    end

    test "respects timeout", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # Use a very short timeout
      {:ok, json} =
        RunCommand.execute(
          %{"command" => "sleep", "args" => ["5"], "timeout" => 100},
          context
        )

      result = Jason.decode!(json)
      assert result["exit_code"] == -1
      assert result["stderr"] =~ "timed out"
    end

    test "returns error for missing command", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = RunCommand.execute(%{}, context)
      assert error =~ "requires a command"
    end

    test "converts non-string args to strings", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "echo", "args" => [123, "test"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert String.trim(result["stdout"]) == "123 test"
    end

    test "creates file in project directory", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "touch", "args" => ["newfile.txt"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert File.exists?(Path.join(tmp_dir, "newfile.txt"))
    end

    test "lists files in project directory", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.write!(Path.join(tmp_dir, "b.txt"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "ls"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["stdout"] =~ "a.txt"
      assert result["stdout"] =~ "b.txt"
    end
  end
end
