defmodule JidoCode.Integration.ToolsPhase2Test do
  @moduledoc """
  Integration tests for Phase 2 (Code Search & Shell Execution) tools.

  These tests verify that Phase 2 tools work correctly through the
  Executor → Handler chain with proper security boundary enforcement.

  ## Tested Tools

  - `grep` - Regex-based code searching (Section 2.1)
  - `run_command` - Foreground command execution (Section 2.2)

  ## Test Coverage (Section 2.6.1)

  - 2.6.1.2: All tools execute through Executor → Handler chain
  - 2.6.1.3: Security validation (path boundaries, command allowlist)
  - 2.6.1.4: Session-scoped execution isolation

  ## Why async: false

  These tests cannot run async because they:
  1. Share the SessionSupervisor (DynamicSupervisor)
  2. Use SessionRegistry which is a shared ETS table
  3. Use filesystem operations in temporary directories
  4. Require deterministic cleanup between test runs
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.Tools.Definitions.Search, as: SearchDefs
  alias JidoCode.Tools.Definitions.Shell, as: ShellDefs
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.Registry, as: ToolsRegistry

  @moduletag :integration
  @moduletag :phase2

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    Process.flag(:trap_exit, true)

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Suppress deprecation warnings for tests
    Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase2_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Register Phase 2 tools
    register_phase2_tools()

    on_exit(fn ->
      # Restore deprecation warnings
      Application.delete_env(:jido_code, :suppress_global_manager_warnings)

      # Stop all test sessions
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      File.rm_rf!(tmp_base)
    end)

    {:ok, tmp_base: tmp_base}
  end

  defp wait_for_supervisor(retries \\ 50) do
    if Process.whereis(SessionSupervisor) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_supervisor(retries - 1)
      else
        raise "SessionSupervisor not available after waiting"
      end
    end
  end

  defp register_phase2_tools do
    # Register search tools
    ToolsRegistry.register(SearchDefs.grep())
    ToolsRegistry.register(SearchDefs.find_files())

    # Register shell tools
    ToolsRegistry.register(ShellDefs.run_command())
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_dir(base, name) do
    path = Path.join(base, name)
    File.mkdir_p!(path)
    path
  end

  defp create_session(project_path) do
    config = SessionTestHelpers.valid_session_config()
    {:ok, session} = Session.new(project_path: project_path, config: config)
    {:ok, _pid} = SessionSupervisor.start_session(session)
    session
  end

  defp tool_call(name, args) do
    %{
      id: "tc-#{:rand.uniform(100_000)}",
      name: name,
      arguments: args
    }
  end

  # Helper to extract result from Executor.execute response
  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :ok, content: content}}),
    do: {:ok, content}

  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :error, content: content}}),
    do: {:error, content}

  defp unwrap_result({:error, reason}),
    do: {:error, reason}

  defp decode_result({:ok, json}) when is_binary(json), do: {:ok, Jason.decode!(json)}
  defp decode_result(other), do: other

  # ============================================================================
  # Section 2.6.1.2: Executor → Handler Chain Tests
  # ============================================================================

  describe "Executor → Handler chain execution" do
    test "grep executes through Executor and returns results", %{tmp_base: tmp_base} do
      # Setup: Create project with test files
      project_dir = create_test_dir(tmp_base, "grep_chain_test")

      File.write!(Path.join(project_dir, "test.ex"), """
      defmodule TestModule do
        def hello, do: "world"
        def goodbye, do: "world"
      end
      """)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute grep through Executor
      call = tool_call("grep", %{"pattern" => "def hello", "path" => "."})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, matches} = result |> unwrap_result() |> decode_result()
      assert is_list(matches)
      assert length(matches) == 1

      match = hd(matches)
      assert match["file"] == "test.ex"
      assert match["line"] == 2
      assert match["content"] =~ "def hello"
    end

    test "run_command executes through Executor and returns output", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "cmd_chain_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute run_command through Executor
      call = tool_call("run_command", %{"command" => "echo", "args" => ["hello", "world"]})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert output["exit_code"] == 0
      assert output["stdout"] =~ "hello world"
    end

    test "find_files executes through Executor", %{tmp_base: tmp_base} do
      # Setup: Create project with multiple files
      project_dir = create_test_dir(tmp_base, "find_chain_test")
      lib_dir = create_test_dir(project_dir, "lib")

      File.write!(Path.join(lib_dir, "module_a.ex"), "defmodule A do end")
      File.write!(Path.join(lib_dir, "module_b.ex"), "defmodule B do end")
      File.write!(Path.join(project_dir, "mix.exs"), "# mix file")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute find_files through Executor
      call = tool_call("find_files", %{"pattern" => "*.ex"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, files} = result |> unwrap_result() |> decode_result()
      assert is_list(files)
      assert length(files) >= 2

      file_names = Enum.map(files, &Path.basename/1)
      assert "module_a.ex" in file_names
      assert "module_b.ex" in file_names
    end
  end

  # ============================================================================
  # Section 2.6.1.3: Security Boundary Enforcement Tests
  # ============================================================================

  describe "security boundary enforcement" do
    test "grep respects project boundary - blocks path traversal", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "grep_security_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to grep outside project boundary
      call = tool_call("grep", %{"pattern" => "secret", "path" => "../../../etc"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "escapes" or error_msg =~ "outside" or error_msg =~ "boundary"
    end

    test "grep respects project boundary - blocks absolute paths outside project", %{
      tmp_base: tmp_base
    } do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "grep_abs_security_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to grep absolute path outside project
      call = tool_call("grep", %{"pattern" => "password", "path" => "/etc/passwd"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "escapes" or error_msg =~ "outside" or error_msg =~ "boundary"
    end

    test "run_command blocks disallowed commands", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "cmd_security_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to run disallowed command
      call = tool_call("run_command", %{"command" => "rm", "args" => ["-rf", "/"]})
      result = Executor.execute(call, context: context)

      # rm is actually allowed but would fail on root - test with actually blocked command
      call_blocked = tool_call("run_command", %{"command" => "sudo", "args" => ["rm", "-rf"]})
      result_blocked = Executor.execute(call_blocked, context: context)

      {:error, error_msg} = unwrap_result(result_blocked)
      assert error_msg =~ "not allowed"
    end

    test "run_command blocks shell interpreters", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "shell_security_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to run shell interpreter
      for shell <- ["bash", "sh", "zsh"] do
        call = tool_call("run_command", %{"command" => shell, "args" => ["-c", "echo pwned"]})
        result = Executor.execute(call, context: context)

        {:error, error_msg} = unwrap_result(result)
        assert error_msg =~ "blocked" or error_msg =~ "interpreter"
      end
    end

    test "run_command blocks path traversal in arguments", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "arg_security_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to use path traversal in arguments
      call = tool_call("run_command", %{"command" => "cat", "args" => ["../../../etc/passwd"]})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "traversal" or error_msg =~ "not allowed"
    end

    test "run_command blocks absolute paths outside project in arguments", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "abs_arg_security_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to use absolute path outside project
      call = tool_call("run_command", %{"command" => "cat", "args" => ["/etc/passwd"]})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "Absolute" or error_msg =~ "not allowed" or error_msg =~ "outside"
    end
  end

  # ============================================================================
  # Section 2.6.1.4: Session-Scoped Isolation Tests
  # ============================================================================

  describe "session-scoped execution isolation" do
    test "grep results are scoped to session's project directory", %{tmp_base: tmp_base} do
      # Setup: Create two separate project directories
      project_a = create_test_dir(tmp_base, "project_a")
      project_b = create_test_dir(tmp_base, "project_b")

      # Create different content in each project
      File.write!(Path.join(project_a, "code.ex"), "defmodule ProjectA do end")
      File.write!(Path.join(project_b, "code.ex"), "defmodule ProjectB do end")

      # Create sessions for each project
      session_a = create_session(project_a)
      session_b = create_session(project_b)

      {:ok, context_a} = Executor.build_context(session_a.id)
      {:ok, context_b} = Executor.build_context(session_b.id)

      # Execute grep in each session
      call = tool_call("grep", %{"pattern" => "defmodule", "path" => "."})

      result_a = Executor.execute(call, context: context_a)
      result_b = Executor.execute(call, context: context_b)

      {:ok, matches_a} = result_a |> unwrap_result() |> decode_result()
      {:ok, matches_b} = result_b |> unwrap_result() |> decode_result()

      # Verify results are isolated
      assert length(matches_a) == 1
      assert length(matches_b) == 1

      assert hd(matches_a)["content"] =~ "ProjectA"
      assert hd(matches_b)["content"] =~ "ProjectB"
    end

    test "run_command executes in session's project directory", %{tmp_base: tmp_base} do
      # Setup: Create two separate project directories
      project_a = create_test_dir(tmp_base, "run_project_a")
      project_b = create_test_dir(tmp_base, "run_project_b")

      # Create sessions for each project
      session_a = create_session(project_a)
      session_b = create_session(project_b)

      {:ok, context_a} = Executor.build_context(session_a.id)
      {:ok, context_b} = Executor.build_context(session_b.id)

      # Execute pwd in each session
      call = tool_call("run_command", %{"command" => "pwd", "args" => []})

      result_a = Executor.execute(call, context: context_a)
      result_b = Executor.execute(call, context: context_b)

      {:ok, output_a} = result_a |> unwrap_result() |> decode_result()
      {:ok, output_b} = result_b |> unwrap_result() |> decode_result()

      # Verify commands run in their respective directories
      assert output_a["stdout"] =~ "run_project_a"
      assert output_b["stdout"] =~ "run_project_b"
    end

    test "find_files results are scoped to session's project", %{tmp_base: tmp_base} do
      # Setup: Create two separate project directories
      project_a = create_test_dir(tmp_base, "find_project_a")
      project_b = create_test_dir(tmp_base, "find_project_b")

      # Create different files in each project
      File.write!(Path.join(project_a, "unique_a.txt"), "content a")
      File.write!(Path.join(project_b, "unique_b.txt"), "content b")

      # Create sessions for each project
      session_a = create_session(project_a)
      session_b = create_session(project_b)

      {:ok, context_a} = Executor.build_context(session_a.id)
      {:ok, context_b} = Executor.build_context(session_b.id)

      # Execute find_files in each session
      call_a = tool_call("find_files", %{"pattern" => "unique_a.txt"})
      call_b = tool_call("find_files", %{"pattern" => "unique_b.txt"})

      result_a_own = Executor.execute(call_a, context: context_a)
      result_a_other = Executor.execute(call_b, context: context_a)
      result_b_own = Executor.execute(call_b, context: context_b)
      result_b_other = Executor.execute(call_a, context: context_b)

      {:ok, files_a_own} = result_a_own |> unwrap_result() |> decode_result()
      {:ok, files_a_other} = result_a_other |> unwrap_result() |> decode_result()
      {:ok, files_b_own} = result_b_own |> unwrap_result() |> decode_result()
      {:ok, files_b_other} = result_b_other |> unwrap_result() |> decode_result()

      # Each session only finds files in its own project
      assert length(files_a_own) == 1
      assert length(files_a_other) == 0
      assert length(files_b_own) == 1
      assert length(files_b_other) == 0
    end
  end

  # ============================================================================
  # Section 2.6.2: Search Integration Tests
  # ============================================================================

  describe "grep search integration" do
    test "grep finds pattern matches with correct line numbers", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "grep_lines_test")

      File.write!(Path.join(project_dir, "multi.ex"), """
      # Line 1
      defmodule Test do
        # Line 3
        def foo, do: :bar
        # Line 5
        def bar, do: :foo
        # Line 7
      end
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("grep", %{"pattern" => "def \\w+", "path" => "."})
      result = Executor.execute(call, context: context)

      {:ok, matches} = result |> unwrap_result() |> decode_result()
      assert length(matches) == 2

      lines = Enum.map(matches, & &1["line"])
      assert 4 in lines
      assert 6 in lines
    end

    test "grep searches recursively by default", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "grep_recursive_test")
      nested = create_test_dir(project_dir, "lib/nested")

      File.write!(Path.join(project_dir, "top.ex"), "# MARKER_TOP")
      File.write!(Path.join(nested, "deep.ex"), "# MARKER_DEEP")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("grep", %{"pattern" => "MARKER_", "path" => "."})
      result = Executor.execute(call, context: context)

      {:ok, matches} = result |> unwrap_result() |> decode_result()
      files = Enum.map(matches, & &1["file"])

      assert "top.ex" in files
      assert Enum.any?(files, &String.ends_with?(&1, "deep.ex"))
    end

    test "grep respects max_results limit", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "grep_limit_test")

      # Create file with many matching lines
      content =
        1..50
        |> Enum.map(&"# Line #{&1} MATCH")
        |> Enum.join("\n")

      File.write!(Path.join(project_dir, "many.txt"), content)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("grep", %{"pattern" => "MATCH", "path" => ".", "max_results" => 5})
      result = Executor.execute(call, context: context)

      {:ok, matches} = result |> unwrap_result() |> decode_result()
      assert length(matches) == 5
    end

    test "grep handles no matches gracefully", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "grep_empty_test")
      File.write!(Path.join(project_dir, "empty.txt"), "nothing here")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("grep", %{"pattern" => "NONEXISTENT_PATTERN", "path" => "."})
      result = Executor.execute(call, context: context)

      {:ok, matches} = result |> unwrap_result() |> decode_result()
      assert matches == []
    end

    test "grep handles invalid regex gracefully", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "grep_regex_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Invalid regex pattern
      call = tool_call("grep", %{"pattern" => "[invalid(regex", "path" => "."})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "Invalid regex" or error_msg =~ "regex"
    end
  end

  # ============================================================================
  # Section 2.6.3: Shell Integration Tests
  # ============================================================================

  describe "run_command shell integration" do
    test "run_command captures exit code correctly", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "exit_code_test")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Test successful command
      success_call = tool_call("run_command", %{"command" => "true", "args" => []})
      success_result = Executor.execute(success_call, context: context)
      {:ok, success_output} = success_result |> unwrap_result() |> decode_result()
      assert success_output["exit_code"] == 0

      # Test failing command
      fail_call = tool_call("run_command", %{"command" => "false", "args" => []})
      fail_result = Executor.execute(fail_call, context: context)
      {:ok, fail_output} = fail_result |> unwrap_result() |> decode_result()
      assert fail_output["exit_code"] != 0
    end

    test "run_command merges stderr into stdout", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "stderr_test")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Test with a command that produces output
      call = tool_call("run_command", %{"command" => "ls", "args" => ["nonexistent_file_xyz"]})
      result = Executor.execute(call, context: context)

      # ls on nonexistent file should fail and stderr should be captured
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert output["exit_code"] != 0

      # stderr should be merged into stdout
      assert output["stdout"] =~ "nonexistent" or output["stdout"] =~ "No such"
    end

    test "run_command respects timeout", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "timeout_test")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Use a very short timeout with sleep command
      call =
        tool_call("run_command", %{"command" => "sleep", "args" => ["10"], "timeout" => 100})

      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "timeout" or error_msg =~ "timed out"
    end

    test "run_command runs allowed development commands", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "allowed_cmd_test")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Test various allowed commands
      allowed_commands = [
        {"echo", ["test"]},
        {"pwd", []},
        {"ls", ["-la"]}
      ]

      for {cmd, args} <- allowed_commands do
        call = tool_call("run_command", %{"command" => cmd, "args" => args})
        result = Executor.execute(call, context: context)

        case unwrap_result(result) do
          {:ok, json} ->
            output = Jason.decode!(json)
            assert is_integer(output["exit_code"])

          {:error, msg} ->
            flunk("Command #{cmd} failed unexpectedly: #{msg}")
        end
      end
    end
  end
end
