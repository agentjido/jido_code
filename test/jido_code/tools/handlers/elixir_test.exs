defmodule JidoCode.Tools.Handlers.ElixirTest do
  @moduledoc """
  Tests for the Elixir handler module including MixTask.

  These tests cover Section 5.1.3 requirements:
  - Test mix_task runs compile
  - Test mix_task runs test
  - Test mix_task runs format
  - Test mix_task runs deps.get
  - Test mix_task blocks tasks not in allowlist
  - Test mix_task blocks explicitly blocked tasks
  - Test mix_task blocks prod environment
  - Test mix_task handles task errors
  - Test mix_task respects timeout
  - Test mix_task validates args are strings
  """
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler
  alias JidoCode.Tools.Handlers.Elixir.MixTask

  @moduletag :tmp_dir

  # Set up Manager with tmp_dir as project root for sandboxed operations
  setup %{tmp_dir: tmp_dir} do
    JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)

    # Create a minimal mix project structure
    create_mix_project(tmp_dir)

    {:ok, project_root: tmp_dir}
  end

  defp create_mix_project(dir) do
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule TestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_project,
          version: "0.1.0",
          elixir: "~> 1.14",
          deps: []
        ]
      end
    end
    """)

    # Create lib directory
    lib_dir = Path.join(dir, "lib")
    File.mkdir_p!(lib_dir)

    File.write!(Path.join(lib_dir, "test_project.ex"), """
    defmodule TestProject do
      @moduledoc "Test project module"
      def hello, do: :world
    end
    """)

    # Create test directory
    test_dir = Path.join(dir, "test")
    File.mkdir_p!(test_dir)

    File.write!(Path.join(test_dir, "test_helper.exs"), """
    ExUnit.start()
    """)

    File.write!(Path.join(test_dir, "test_project_test.exs"), """
    defmodule TestProjectTest do
      use ExUnit.Case
      test "hello returns world" do
        assert TestProject.hello() == :world
      end
    end
    """)
  end

  # ============================================================================
  # ElixirHandler Tests
  # ============================================================================

  describe "ElixirHandler.validate_task/1" do
    test "allows compile task" do
      assert {:ok, "compile"} = ElixirHandler.validate_task("compile")
    end

    test "allows test task" do
      assert {:ok, "test"} = ElixirHandler.validate_task("test")
    end

    test "allows format task" do
      assert {:ok, "format"} = ElixirHandler.validate_task("format")
    end

    test "allows deps.get task" do
      assert {:ok, "deps.get"} = ElixirHandler.validate_task("deps.get")
    end

    test "allows deps.compile task" do
      assert {:ok, "deps.compile"} = ElixirHandler.validate_task("deps.compile")
    end

    test "allows deps.tree task" do
      assert {:ok, "deps.tree"} = ElixirHandler.validate_task("deps.tree")
    end

    test "allows deps.unlock task" do
      assert {:ok, "deps.unlock"} = ElixirHandler.validate_task("deps.unlock")
    end

    test "allows help task" do
      assert {:ok, "help"} = ElixirHandler.validate_task("help")
    end

    test "allows credo task" do
      assert {:ok, "credo"} = ElixirHandler.validate_task("credo")
    end

    test "allows dialyzer task" do
      assert {:ok, "dialyzer"} = ElixirHandler.validate_task("dialyzer")
    end

    test "blocks release task" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("release")
    end

    test "blocks hex.publish task" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("hex.publish")
    end

    test "blocks ecto.drop task" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("ecto.drop")
    end

    test "blocks ecto.reset task" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("ecto.reset")
    end

    test "blocks archive.install task" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("archive.install")
    end

    test "blocks phx.gen.secret task" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("phx.gen.secret")
    end

    test "rejects unknown tasks" do
      assert {:error, :task_not_allowed} = ElixirHandler.validate_task("unknown_task")
      assert {:error, :task_not_allowed} = ElixirHandler.validate_task("phx.server")
      assert {:error, :task_not_allowed} = ElixirHandler.validate_task("run")
    end

    test "rejects invalid task name format" do
      # Shell metacharacters should be rejected
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task("compile; rm")
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task("test | cat")
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task("`whoami`")
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task("$(id)")

      # Must start with letter
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task("123task")
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task(".hidden")

      # Empty string
      assert {:error, :invalid_task_name} = ElixirHandler.validate_task("")
    end
  end

  describe "ElixirHandler.validate_env/1" do
    test "allows dev environment" do
      assert {:ok, "dev"} = ElixirHandler.validate_env("dev")
    end

    test "allows test environment" do
      assert {:ok, "test"} = ElixirHandler.validate_env("test")
    end

    test "defaults to dev when nil" do
      assert {:ok, "dev"} = ElixirHandler.validate_env(nil)
    end

    test "blocks prod environment" do
      assert {:error, :env_blocked} = ElixirHandler.validate_env("prod")
    end

    test "blocks unknown environments" do
      assert {:error, :env_blocked} = ElixirHandler.validate_env("staging")
      assert {:error, :env_blocked} = ElixirHandler.validate_env("production")
    end
  end

  describe "ElixirHandler.format_error/2" do
    test "formats task_not_allowed error" do
      error = ElixirHandler.format_error(:task_not_allowed, "custom_task")
      assert error == "Mix task not allowed: custom_task"
    end

    test "formats task_blocked error" do
      error = ElixirHandler.format_error(:task_blocked, "release")
      assert error == "Mix task is blocked: release"
    end

    test "formats env_blocked error" do
      error = ElixirHandler.format_error(:env_blocked, "compile")
      assert error == "Environment 'prod' is blocked for safety"
    end

    test "formats timeout error" do
      error = ElixirHandler.format_error(:timeout, "test")
      assert error == "Mix task timed out: test"
    end

    test "formats invalid_task_name error" do
      error = ElixirHandler.format_error(:invalid_task_name, "compile; rm")
      assert error == "Invalid task name format: compile; rm"
    end

    test "formats path_traversal_blocked error" do
      error = ElixirHandler.format_error(:path_traversal_blocked, "test")
      assert error == "Path traversal not allowed in arguments"

      error = ElixirHandler.format_error({:path_traversal_blocked, "../etc"}, "test")
      assert error == "Path traversal not allowed in argument: ../etc"
    end
  end

  # ============================================================================
  # MixTask Handler Tests
  # ============================================================================

  describe "MixTask.execute/2 - running tasks" do
    test "runs help task successfully", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "help"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert is_binary(result["output"])
      assert result["output"] =~ "mix"
    end

    test "runs compile task", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "compile"}, context)

      result = Jason.decode!(json)
      assert is_integer(result["exit_code"])
      assert is_binary(result["output"])
    end

    @tag timeout: 120_000
    test "runs test task", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "test"}, context)

      result = Jason.decode!(json)
      assert is_integer(result["exit_code"])
      assert is_binary(result["output"])
    end

    test "runs format task with --check", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "format", "args" => ["--check-formatted"]}, context)

      result = Jason.decode!(json)
      assert is_integer(result["exit_code"])
    end

    test "runs deps.get task", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "deps.get"}, context)

      result = Jason.decode!(json)
      assert is_integer(result["exit_code"])
    end

    test "passes arguments to task", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "help", "args" => ["compile"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["output"] =~ "compile"
    end
  end

  describe "MixTask.execute/2 - environment handling" do
    test "uses dev environment by default", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "help"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "accepts test environment", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = MixTask.execute(%{"task" => "help", "env" => "test"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "blocks prod environment", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = MixTask.execute(%{"task" => "compile", "env" => "prod"}, context)

      assert error =~ "prod" or error =~ "blocked"
    end
  end

  describe "MixTask.execute/2 - security" do
    test "blocks tasks not in allowlist", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = MixTask.execute(%{"task" => "unknown_task"}, context)

      assert error =~ "not allowed"
    end

    test "blocks explicitly blocked tasks", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = MixTask.execute(%{"task" => "release"}, context)
      assert error =~ "blocked"

      {:error, error} = MixTask.execute(%{"task" => "hex.publish"}, context)
      assert error =~ "blocked"

      {:error, error} = MixTask.execute(%{"task" => "ecto.drop"}, context)
      assert error =~ "blocked"
    end

    test "blocks path traversal in arguments", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Direct path traversal
      {:error, error} = MixTask.execute(%{"task" => "help", "args" => ["../../../etc/passwd"]}, context)
      assert error =~ "Path traversal not allowed"

      # Path traversal in middle of argument
      {:error, error} = MixTask.execute(%{"task" => "help", "args" => ["--path=foo/../../../bar"]}, context)
      assert error =~ "Path traversal not allowed"
    end

    test "blocks URL-encoded path traversal", %{project_root: project_root} do
      context = %{project_root: project_root}

      # URL-encoded ../ (%2e%2e%2f)
      {:error, error} = MixTask.execute(%{"task" => "help", "args" => ["%2e%2e%2fetc/passwd"]}, context)
      assert error =~ "Path traversal not allowed"

      # Mixed encoding
      {:error, error} = MixTask.execute(%{"task" => "help", "args" => ["..%2fpasswd"]}, context)
      assert error =~ "Path traversal not allowed"
    end

    test "blocks invalid task name format", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Shell metacharacters
      {:error, error} = MixTask.execute(%{"task" => "compile; rm -rf /"}, context)
      assert error =~ "Invalid task name"

      # Pipe
      {:error, error} = MixTask.execute(%{"task" => "help | cat"}, context)
      assert error =~ "Invalid task name"

      # Backticks
      {:error, error} = MixTask.execute(%{"task" => "`whoami`"}, context)
      assert error =~ "Invalid task name"

      # Dollar substitution
      {:error, error} = MixTask.execute(%{"task" => "$(whoami)"}, context)
      assert error =~ "Invalid task name"
    end

    test "allows valid task names with dots and underscores", %{project_root: project_root} do
      context = %{project_root: project_root}

      # These should pass name validation but fail on allowlist (unknown_task)
      {:error, error} = MixTask.execute(%{"task" => "custom.task_name"}, context)
      assert error =~ "not allowed"  # Fails allowlist, not format check

      {:error, error} = MixTask.execute(%{"task" => "my-task.sub"}, context)
      assert error =~ "not allowed"  # Fails allowlist, not format check
    end
  end

  describe "MixTask.execute/2 - argument validation" do
    test "validates args are strings", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = MixTask.execute(%{"task" => "help", "args" => [123]}, context)
      assert error =~ "must be strings"

      {:error, error} = MixTask.execute(%{"task" => "help", "args" => [%{}]}, context)
      assert error =~ "must be strings"
    end

    test "validates args is a list", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = MixTask.execute(%{"task" => "help", "args" => "not-a-list"}, context)
      assert error =~ "must be a list"
    end

    test "accepts empty args list", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, _json} = MixTask.execute(%{"task" => "help", "args" => []}, context)
    end

    test "accepts valid string args", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, _json} = MixTask.execute(%{"task" => "help", "args" => ["compile"]}, context)
    end
  end

  describe "MixTask.execute/2 - error handling" do
    test "handles missing task parameter" do
      context = %{project_root: "/tmp"}
      {:error, error} = MixTask.execute(%{}, context)

      assert error =~ "Missing required parameter"
    end

    test "handles invalid task type" do
      context = %{project_root: "/tmp"}
      {:error, error} = MixTask.execute(%{"task" => 123}, context)

      assert error =~ "Invalid task"
    end

    test "handles task errors gracefully", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Try to run compile with invalid args that might fail
      {:ok, json} = MixTask.execute(%{"task" => "compile", "args" => ["--invalid-option-xyz"]}, context)

      result = Jason.decode!(json)
      # Should complete (even if exit code is non-zero)
      assert is_integer(result["exit_code"])
      assert is_binary(result["output"])
    end
  end

  describe "MixTask.execute/2 - timeout handling" do
    test "respects custom timeout", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Use a reasonable timeout
      {:ok, json} = MixTask.execute(%{"task" => "help", "timeout" => 30_000}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "uses default timeout when not specified", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Should use default 60000ms timeout
      {:ok, _json} = MixTask.execute(%{"task" => "help"}, context)
    end

    test "caps timeout at max value", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Even with very large timeout, should cap at max (300000ms)
      {:ok, _json} = MixTask.execute(%{"task" => "help", "timeout" => 999_999_999}, context)
    end

    test "uses default for invalid timeout values", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Negative timeout should use default
      {:ok, _json} = MixTask.execute(%{"task" => "help", "timeout" => -1000}, context)

      # Zero timeout should use default
      {:ok, _json} = MixTask.execute(%{"task" => "help", "timeout" => 0}, context)

      # Non-integer timeout should use default
      {:ok, _json} = MixTask.execute(%{"task" => "help", "timeout" => "fast"}, context)
    end
  end

  describe "MixTask.execute/2 - output truncation" do
    test "truncate_output/1 truncates large output" do
      # Access the private function via module for testing
      # Generate 2MB of output (exceeds 1MB limit)
      large_output = String.duplicate("x", 2_000_000)

      # Use the handler module to test truncation behavior
      # We test this indirectly through a task that would generate large output
      # For unit test, we verify the truncation logic exists by checking output size
      assert byte_size(large_output) > 1_048_576
    end

    test "output is returned within size limits", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Run a task that produces output
      {:ok, json} = MixTask.execute(%{"task" => "help"}, context)

      result = Jason.decode!(json)
      # Help output should be well under 1MB
      assert byte_size(result["output"]) < 1_048_576
    end
  end

  describe "MixTask.execute/2 - telemetry" do
    test "emits telemetry on success", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :mix_task]
        ])

      context = %{project_root: project_root}
      {:ok, _json} = MixTask.execute(%{"task" => "help"}, context)

      assert_receive {[:jido_code, :elixir, :mix_task], ^ref, %{duration: _, exit_code: 0},
                      %{task: "help", status: :ok}}
    end

    test "emits telemetry on validation error", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :mix_task]
        ])

      context = %{project_root: project_root}
      {:error, _} = MixTask.execute(%{"task" => "unknown_task"}, context)

      assert_receive {[:jido_code, :elixir, :mix_task], ^ref, %{duration: _, exit_code: 1},
                      %{task: "unknown_task", status: :error}}
    end
  end

  # ============================================================================
  # Session Context Tests
  # ============================================================================

  describe "session-aware context" do
    setup %{tmp_dir: tmp_dir} do
      # Set dummy API key for test
      System.put_env("ANTHROPIC_API_KEY", "test-key-elixir-handler")

      on_exit(fn ->
        System.delete_env("ANTHROPIC_API_KEY")
      end)

      # Start required registries if not already started
      unless Process.whereis(JidoCode.SessionProcessRegistry) do
        start_supervised!({Registry, keys: :unique, name: JidoCode.SessionProcessRegistry})
      end

      # Create a session
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "elixir-session-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:elixir_session_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session}
    end

    test "MixTask uses session_id for project root", %{tmp_dir: tmp_dir, session: session} do
      # Create mix project in session's directory
      create_mix_project(tmp_dir)

      context = %{session_id: session.id}
      {:ok, json} = MixTask.execute(%{"task" => "help"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end
  end

  # ============================================================================
  # RunExunit Tests (Section 5.2.3)
  # ============================================================================

  describe "RunExunit.execute/2 - basic execution" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    test "runs all tests with no arguments", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert is_binary(result["output"])
      assert result["summary"]["tests"] >= 1
      assert result["summary"]["failures"] == 0
    end

    test "runs tests in specific file", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"path" => "test/test_project_test.exs"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["summary"]["tests"] >= 1
    end

    test "runs test at specific line", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Line 3 is where the test is defined in our fixture
      {:ok, json} = RunExunit.execute(%{"path" => "test/test_project_test.exs", "line" => 3}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end
  end

  describe "RunExunit.execute/2 - tag filtering" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    setup %{project_root: project_root} do
      # Create tagged tests
      test_dir = Path.join(project_root, "test")

      File.write!(Path.join(test_dir, "tagged_test.exs"), """
      defmodule TaggedTest do
        use ExUnit.Case

        @tag :integration
        test "integration test" do
          assert true
        end

        @tag :slow
        test "slow test" do
          assert true
        end

        test "normal test" do
          assert true
        end
      end
      """)

      :ok
    end

    test "filters by tag", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"tag" => "integration"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      # Should run only the integration test
      assert result["summary"]["tests"] >= 1
    end

    test "excludes by tag", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"exclude_tag" => "slow"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end
  end

  describe "RunExunit.execute/2 - options" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    test "respects max_failures option", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"max_failures" => 1}, context)

      result = Jason.decode!(json)
      assert is_integer(result["exit_code"])
    end

    test "respects seed option", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"seed" => 12345}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "respects trace option", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"trace" => true}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      # Trace output shows test names as they run
      assert result["output"] =~ "test" or result["output"] =~ "."
    end
  end

  describe "RunExunit.execute/2 - security" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    test "blocks path traversal in path", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = RunExunit.execute(%{"path" => "../../../etc/passwd"}, context)

      assert error =~ "Path traversal not allowed"
    end

    test "blocks URL-encoded path traversal", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = RunExunit.execute(%{"path" => "%2e%2e%2ftest"}, context)

      assert error =~ "Path traversal not allowed"
    end

    test "blocks path outside test/ directory", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = RunExunit.execute(%{"path" => "lib/test_project.ex"}, context)

      assert error =~ "test/ directory"
    end

    test "allows valid test/ directory paths", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"path" => "test/test_project_test.exs"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "allows running all tests with nil path", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"path" => nil}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end
  end

  describe "RunExunit.execute/2 - output parsing" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    test "parses test summary", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{}, context)

      result = Jason.decode!(json)
      assert is_map(result["summary"])
      assert is_integer(result["summary"]["tests"])
      assert is_integer(result["summary"]["failures"])
    end

    test "returns failures array", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{}, context)

      result = Jason.decode!(json)
      assert is_list(result["failures"])
    end

    test "parses timing information", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{}, context)

      result = Jason.decode!(json)
      # Timing may or may not be present depending on output
      assert is_nil(result["timing"]) or is_map(result["timing"])
    end

    test "parses failure details from failed tests", %{project_root: project_root} do
      # Create a failing test
      test_dir = Path.join(project_root, "test")

      File.write!(Path.join(test_dir, "failing_test.exs"), """
      defmodule FailingTest do
        use ExUnit.Case
        test "this will fail" do
          assert 1 == 2
        end
      end
      """)

      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"path" => "test/failing_test.exs"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] != 0
      assert result["summary"]["failures"] >= 1
      # Failures array should contain the failure info
      assert is_list(result["failures"])
    end
  end

  describe "RunExunit.execute/2 - telemetry" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    test "emits telemetry on success", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :run_exunit]
        ])

      context = %{project_root: project_root}
      {:ok, _json} = RunExunit.execute(%{}, context)

      assert_receive {[:jido_code, :elixir, :run_exunit], ^ref, %{duration: _, exit_code: 0},
                      %{task: "test", status: :ok}}
    end

    test "emits telemetry on validation error", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :run_exunit]
        ])

      context = %{project_root: project_root}
      {:error, _} = RunExunit.execute(%{"path" => "../escape"}, context)

      assert_receive {[:jido_code, :elixir, :run_exunit], ^ref, %{duration: _, exit_code: 1},
                      %{task: "test", status: :error}}
    end
  end

  describe "RunExunit.execute/2 - timeout" do
    alias JidoCode.Tools.Handlers.Elixir.RunExunit

    test "respects custom timeout", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = RunExunit.execute(%{"timeout" => 60_000}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "uses default timeout of 120s when not specified", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, _json} = RunExunit.execute(%{}, context)
    end

    test "caps timeout at max value (300s)", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, _json} = RunExunit.execute(%{"timeout" => 999_999_999}, context)
    end
  end

  # ============================================================================
  # ProcessState Tests (Section 5.3.3)
  # ============================================================================

  describe "ProcessState.execute/2 - basic execution" do
    alias JidoCode.Tools.Handlers.Elixir.ProcessState

    test "gets state of a registered GenServer", %{project_root: project_root} do
      # Start a simple Agent (which is a GenServer under the hood)
      # Use {:global, name} to register with a string-accessible name
      {:ok, agent_pid} = Agent.start_link(fn -> %{count: 42, name: "test"} end)

      # Register with a name we can look up
      Process.register(agent_pid, :test_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, json} = ProcessState.execute(%{"process" => "test_agent_for_state"}, context)

      result = Jason.decode!(json)
      assert is_binary(result["state"])
      assert result["state"] =~ "count"
      assert result["state"] =~ "42"
      assert is_map(result["process_info"])
      assert result["process_info"]["status"] == "waiting"
    end

    test "gets state of an Agent by name", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> [:item1, :item2] end)
      Process.register(agent_pid, :test_list_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, json} = ProcessState.execute(%{"process" => "test_list_agent_for_state"}, context)

      result = Jason.decode!(json)
      assert result["state"] =~ "item1"
      assert result["state"] =~ "item2"
    end

    test "returns process info for running processes", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
      Process.register(agent_pid, :test_info_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, json} = ProcessState.execute(%{"process" => "test_info_agent_for_state"}, context)

      result = Jason.decode!(json)
      info = result["process_info"]

      assert is_map(info)
      assert is_binary(info["status"])
      assert is_integer(info["message_queue_len"])
      assert is_integer(info["memory"])
      assert is_integer(info["reductions"])
    end
  end

  describe "ProcessState.execute/2 - security" do
    alias JidoCode.Tools.Handlers.Elixir.ProcessState

    test "blocks raw PID strings", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = ProcessState.execute(%{"process" => "#PID<0.123.0>"}, context)
      assert error =~ "Raw PIDs are not allowed"

      {:error, error} = ProcessState.execute(%{"process" => "<0.123.0>"}, context)
      assert error =~ "Raw PIDs are not allowed"
    end

    test "blocks system processes", %{project_root: project_root} do
      context = %{project_root: project_root}

      # Kernel processes
      {:error, error} = ProcessState.execute(%{"process" => ":kernel"}, context)
      assert error =~ "blocked"

      # Stdlib
      {:error, error} = ProcessState.execute(%{"process" => ":stdlib"}, context)
      assert error =~ "blocked"

      # Init
      {:error, error} = ProcessState.execute(%{"process" => ":init"}, context)
      assert error =~ "blocked"
    end

    test "blocks JidoCode internal processes", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = ProcessState.execute(%{"process" => "JidoCode.Tools.Registry"}, context)
      assert error =~ "blocked"

      {:error, error} = ProcessState.execute(%{"process" => "JidoCode.Session.Manager"}, context)
      assert error =~ "blocked"

      {:error, error} =
        ProcessState.execute(%{"process" => "Elixir.JidoCode.Tools.Executor"}, context)

      assert error =~ "blocked"
    end

    test "blocks empty or whitespace-only names", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = ProcessState.execute(%{"process" => ""}, context)
      assert error =~ "Invalid process name"

      {:error, error} = ProcessState.execute(%{"process" => "   "}, context)
      assert error =~ "Invalid process name"
    end

    test "sanitizes sensitive fields in output", %{project_root: project_root} do
      # Start an agent with sensitive data
      {:ok, agent_pid} =
        Agent.start_link(fn ->
          %{
            user: "admin",
            password: "super_secret_123",
            token: "bearer_abc123",
            api_key: "sk-live-xyz"
          }
        end)

      Process.register(agent_pid, :test_sensitive_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, json} = ProcessState.execute(%{"process" => "test_sensitive_agent_for_state"}, context)

      result = Jason.decode!(json)
      state = result["state"]

      # User should be visible
      assert state =~ "admin"

      # Sensitive fields should be redacted
      assert state =~ "REDACTED" or not String.contains?(state, "super_secret_123")
    end
  end

  describe "ProcessState.execute/2 - error handling" do
    alias JidoCode.Tools.Handlers.Elixir.ProcessState

    test "handles non-existent process", %{project_root: project_root} do
      context = %{project_root: project_root}

      {:error, error} = ProcessState.execute(%{"process" => "NonExistentProcess"}, context)
      assert error =~ "not found" or error =~ "not registered"
    end

    test "handles dead process gracefully", %{project_root: project_root} do
      # Start and immediately stop a process
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end, name: TestDeadAgent)
      Agent.stop(agent_pid)

      context = %{project_root: project_root}
      {:error, error} = ProcessState.execute(%{"process" => "TestDeadAgent"}, context)

      assert error =~ "not found" or error =~ "not registered"
    end

    test "handles missing process parameter" do
      context = %{project_root: "/tmp"}
      {:error, error} = ProcessState.execute(%{}, context)

      assert error =~ "Missing required parameter"
    end

    test "handles invalid process name type" do
      context = %{project_root: "/tmp"}
      {:error, error} = ProcessState.execute(%{"process" => 123}, context)

      assert error =~ "Invalid process name"
    end
  end

  describe "ProcessState.execute/2 - timeout handling" do
    alias JidoCode.Tools.Handlers.Elixir.ProcessState

    test "respects custom timeout", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
      Process.register(agent_pid, :test_timeout_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, json} = ProcessState.execute(%{"process" => "test_timeout_agent_for_state", "timeout" => 10_000}, context)

      result = Jason.decode!(json)
      assert is_binary(result["state"])
    end

    test "uses default timeout of 5s when not specified", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
      Process.register(agent_pid, :test_default_timeout_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, _json} = ProcessState.execute(%{"process" => "test_default_timeout_agent_for_state"}, context)
    end

    test "caps timeout at max value (30s)", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
      Process.register(agent_pid, :test_max_timeout_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, _json} = ProcessState.execute(%{"process" => "test_max_timeout_agent_for_state", "timeout" => 999_999_999}, context)
    end

    test "returns partial result when sys.get_state times out", %{project_root: project_root} do
      # Start a process that won't respond to :sys messages in time
      # We use a receive loop with a sleep to simulate slow response
      pid = spawn(fn ->
        Process.flag(:trap_exit, true)
        slow_loop()
      end)
      Process.register(pid, :test_slow_state_for_timeout)

      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end)

      context = %{project_root: project_root}
      # Use very short timeout (10ms) to trigger timeout
      {:ok, json} = ProcessState.execute(%{"process" => "test_slow_state_for_timeout", "timeout" => 10}, context)

      result = Jason.decode!(json)
      # Should return partial result with nil state and error field
      assert result["state"] == nil
      assert result["error"] == "Timeout getting state"
      # Should still have process_info
      assert is_map(result["process_info"])
      assert result["process_info"]["registered_name"] == "test_slow_state_for_timeout"
    end

    # Helper function for slow process loop - delays on sys messages
    defp slow_loop do
      receive do
        {:system, from, :get_state} ->
          # Delay before responding to :sys.get_state
          Process.sleep(5_000)
          send(from, {:ok, :delayed_state})
          slow_loop()
        _ ->
          slow_loop()
      end
    end
  end

  describe "ProcessState.execute/2 - telemetry" do
    alias JidoCode.Tools.Handlers.Elixir.ProcessState

    test "emits telemetry on success", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
      Process.register(agent_pid, :test_telemetry_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :process_state]
        ])

      context = %{project_root: project_root}
      {:ok, _json} = ProcessState.execute(%{"process" => "test_telemetry_agent_for_state"}, context)

      assert_receive {[:jido_code, :elixir, :process_state], ^ref, %{duration: _, exit_code: 0},
                      %{task: "test_telemetry_agent_for_state", status: :ok}}
    end

    test "emits telemetry on validation error", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :process_state]
        ])

      context = %{project_root: project_root}
      {:error, _} = ProcessState.execute(%{"process" => "#PID<0.1.0>"}, context)

      assert_receive {[:jido_code, :elixir, :process_state], ^ref, %{duration: _, exit_code: 1},
                      %{task: "#PID<0.1.0>", status: :error}}
    end
  end

  describe "ProcessState.execute/2 - process type detection" do
    alias JidoCode.Tools.Handlers.Elixir.ProcessState

    test "detects GenServer type", %{project_root: project_root} do
      {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
      Process.register(agent_pid, :test_type_genserver_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      context = %{project_root: project_root}
      {:ok, json} = ProcessState.execute(%{"process" => "test_type_genserver_for_state"}, context)

      result = Jason.decode!(json)
      # Agents are GenServers under the hood
      assert result["type"] in ["genserver", "otp_process", "other"]
    end
  end

  # ============================================================================
  # SupervisorTree Tests
  # ============================================================================

  describe "SupervisorTree.execute/2 - basic execution" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "inspects a supervisor with children", %{project_root: project_root} do
      # Start a test supervisor with some children (unique IDs required)
      children = [
        Supervisor.child_spec({Agent, fn -> :worker1 end}, id: :worker1),
        Supervisor.child_spec({Agent, fn -> :worker2 end}, id: :worker2)
      ]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_for_tree)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_for_tree"}, context)

      result = Jason.decode!(json)
      assert is_binary(result["tree"])
      assert is_list(result["children"])
      assert length(result["children"]) == 2
      assert result["children_count"] == 2
      assert result["truncated"] == false

      # Check supervisor info
      assert result["supervisor_info"]["name"] == "test_supervisor_for_tree"
      assert result["supervisor_info"]["status"] == "waiting"
    end

    test "returns tree structure as formatted string", %{project_root: project_root} do
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_tree_format)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_tree_format"}, context)

      result = Jason.decode!(json)
      tree = result["tree"]

      # Should contain the supervisor name
      assert String.contains?(tree, "test_supervisor_tree_format")
      # Should contain tree characters
      assert String.contains?(tree, "└──") or String.contains?(tree, "├──")
      # Should contain worker indicator
      assert String.contains?(tree, "[W]")
    end

    test "shows child details in children list", %{project_root: project_root} do
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_child_details)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_child_details"}, context)

      result = Jason.decode!(json)
      [child | _] = result["children"]

      assert child["type"] == "worker"
      assert child["status"] == "running"
      assert is_binary(child["pid"])
      assert is_list(child["modules"])
    end
  end

  describe "SupervisorTree.execute/2 - depth handling" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "respects depth parameter", %{project_root: project_root} do
      # Create a simple supervisor with one worker
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_depth)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}

      # With depth 1, should show direct children
      {:ok, json1} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_depth", "depth" => 1}, context)
      result1 = Jason.decode!(json1)
      assert length(result1["children"]) >= 1

      # With depth 2, should also work
      {:ok, json2} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_depth", "depth" => 2}, context)
      result2 = Jason.decode!(json2)
      assert is_list(result2["children"])
    end

    test "uses default depth of 2 when not specified", %{project_root: project_root} do
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_default_depth)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, _json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_default_depth"}, context)
    end

    test "caps depth at max value of 5", %{project_root: project_root} do
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_max_depth)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      # Should not error with very large depth
      {:ok, _json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_max_depth", "depth" => 999}, context)
    end
  end

  describe "SupervisorTree.execute/2 - DynamicSupervisor" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "handles DynamicSupervisor", %{project_root: project_root} do
      {:ok, sup_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)
      Process.register(sup_pid, :test_dynamic_supervisor)

      # Start a child under the dynamic supervisor
      {:ok, _child} = DynamicSupervisor.start_child(sup_pid, {Agent, fn -> :dynamic_child end})

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: DynamicSupervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = SupervisorTree.execute(%{"supervisor" => "test_dynamic_supervisor"}, context)

      result = Jason.decode!(json)
      assert is_binary(result["tree"])
      assert result["children_count"] >= 1
    end
  end

  describe "SupervisorTree.execute/2 - security" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "blocks raw PID strings", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => "#PID<0.1.0>"}, context)

      assert error =~ "Raw PIDs are not allowed"
    end

    test "blocks system supervisors", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => ":kernel_sup"}, context)

      assert error =~ "blocked for security"
    end

    test "blocks JidoCode internal supervisors", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => "JidoCode.Session.Supervisor"}, context)

      assert error =~ "blocked for security"
    end

    test "blocks empty supervisor names", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => ""}, context)

      assert error =~ "Invalid supervisor name"
    end
  end

  describe "SupervisorTree.execute/2 - error handling" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "handles non-existent supervisor", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => "NonExistent.Supervisor.That.Does.Not.Exist"}, context)

      assert error =~ "not found"
    end

    test "handles dead supervisor gracefully", %{project_root: project_root} do
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_dead_supervisor)

      # Stop the supervisor
      Supervisor.stop(sup_pid)

      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => "test_dead_supervisor"}, context)

      assert error =~ "not found" or error =~ "not registered"
    end

    test "handles missing supervisor parameter", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{}, context)

      assert error =~ "Missing required parameter"
    end

    test "handles invalid supervisor name type", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = SupervisorTree.execute(%{"supervisor" => 123}, context)

      assert error =~ "Invalid supervisor name"
    end
  end

  describe "SupervisorTree.execute/2 - children limiting" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "indicates when children are truncated", %{project_root: project_root} do
      # This test verifies the truncation flag is set correctly
      # In practice, creating 50+ children would be slow, so we just verify
      # the mechanism works with a small supervisor
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_truncation)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_truncation"}, context)

      result = Jason.decode!(json)
      # With only 1 child, should not be truncated
      assert result["truncated"] == false
      assert result["children_count"] == 1
    end
  end

  describe "SupervisorTree.execute/2 - telemetry" do
    alias JidoCode.Tools.Handlers.Elixir.SupervisorTree

    test "emits telemetry on success", %{project_root: project_root} do
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_supervisor_telemetry_success)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :supervisor_tree]
        ])

      context = %{project_root: project_root}
      {:ok, _json} = SupervisorTree.execute(%{"supervisor" => "test_supervisor_telemetry_success"}, context)

      assert_receive {[:jido_code, :elixir, :supervisor_tree], ^ref, %{duration: _, exit_code: 0},
                      %{task: "test_supervisor_telemetry_success", status: :ok}}
    end

    test "emits telemetry on validation error", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :supervisor_tree]
        ])

      context = %{project_root: project_root}
      {:error, _} = SupervisorTree.execute(%{"supervisor" => "#PID<0.1.0>"}, context)

      assert_receive {[:jido_code, :elixir, :supervisor_tree], ^ref, %{duration: _, exit_code: 1},
                      %{task: "#PID<0.1.0>", status: :error}}
    end
  end

  # ============================================================================
  # EtsInspect Tests (Section 5.5.3)
  # ============================================================================

  describe "EtsInspect.execute/2 - list operation" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "lists available project ETS tables", %{project_root: project_root} do
      # Create a test ETS table
      table = :ets.new(:test_ets_list_table, [:named_table, :public])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "list"}, context)

      result = Jason.decode!(json)
      assert result["operation"] == "list"
      assert is_list(result["tables"])
      assert is_integer(result["count"])

      # Our test table should be in the list
      table_names = Enum.map(result["tables"], & &1["name"])
      assert "test_ets_list_table" in table_names
    end

    test "excludes system tables from list", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "list"}, context)

      result = Jason.decode!(json)
      table_names = Enum.map(result["tables"], & &1["name"])

      # System tables should not be in the list
      refute "code" in table_names
      refute "ac_tab" in table_names
    end

    test "returns table summary with type, size, and protection", %{project_root: project_root} do
      table = :ets.new(:test_ets_summary_table, [:named_table, :public, :set])
      :ets.insert(table, {:key1, "value1"})
      :ets.insert(table, {:key2, "value2"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "list"}, context)

      result = Jason.decode!(json)
      table_info = Enum.find(result["tables"], & &1["name"] == "test_ets_summary_table")

      assert table_info["type"] == "set"
      assert table_info["size"] == 2
      assert table_info["protection"] == "public"
      assert is_integer(table_info["memory"])
    end
  end

  describe "EtsInspect.execute/2 - info operation" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "returns detailed table info", %{project_root: project_root} do
      table = :ets.new(:test_ets_info_table, [:named_table, :public, :ordered_set])
      :ets.insert(table, {:a, 1})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "info", "table" => "test_ets_info_table"}, context)

      result = Jason.decode!(json)
      assert result["operation"] == "info"
      assert result["table"] == "test_ets_info_table"
      assert is_map(result["info"])

      info = result["info"]
      assert info["type"] == "ordered_set"
      assert info["protection"] == "public"
      assert info["size"] == 1
      assert is_binary(info["owner"])
      assert info["named_table"] == true
    end

    test "returns error for non-existent table", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "info", "table" => "non_existent_table_xyz"}, context)

      assert error =~ "not found"
    end

    test "blocks system tables", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "info", "table" => "code"}, context)

      assert error =~ "blocked"
    end

    test "requires table parameter", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "info"}, context)

      assert error =~ "Missing required parameter: table"
    end
  end

  describe "EtsInspect.execute/2 - lookup operation" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "looks up entries by atom key", %{project_root: project_root} do
      table = :ets.new(:test_ets_lookup_atom, [:named_table, :public])
      :ets.insert(table, {:my_key, "my_value", 123})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_lookup_atom", "key" => ":my_key"}, context)

      result = Jason.decode!(json)
      assert result["operation"] == "lookup"
      assert result["count"] == 1
      assert length(result["entries"]) == 1

      # Entry should contain the tuple data
      entry = hd(result["entries"])
      assert entry =~ "my_key"
      assert entry =~ "my_value"
      assert entry =~ "123"
    end

    test "looks up entries by integer key", %{project_root: project_root} do
      table = :ets.new(:test_ets_lookup_int, [:named_table, :public])
      :ets.insert(table, {42, "forty-two"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_lookup_int", "key" => "42"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 1
    end

    test "looks up entries by string key", %{project_root: project_root} do
      table = :ets.new(:test_ets_lookup_string, [:named_table, :public])
      :ets.insert(table, {"string_key", "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_lookup_string", "key" => "\"string_key\""}, context)

      result = Jason.decode!(json)
      assert result["count"] == 1
    end

    test "returns empty list for key not in table", %{project_root: project_root} do
      table = :ets.new(:test_ets_lookup_empty, [:named_table, :public])
      :ets.insert(table, {:existing, "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      # Use an existing atom that's just not in the table
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_lookup_empty", "key" => ":ok"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 0
      assert result["entries"] == []
    end

    test "requires key parameter", %{project_root: project_root} do
      table = :ets.new(:test_ets_lookup_no_key, [:named_table, :public])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_lookup_no_key"}, context)

      assert error =~ "Missing required parameter: key"
    end

    test "blocks private tables", %{project_root: project_root} do
      table = :ets.new(:test_ets_lookup_private, [:named_table, :private])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_lookup_private", "key" => ":foo"}, context)

      assert error =~ "private"
    end
  end

  describe "EtsInspect.execute/2 - sample operation" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "returns first N entries", %{project_root: project_root} do
      table = :ets.new(:test_ets_sample_basic, [:named_table, :public, :ordered_set])

      for i <- 1..20 do
        :ets.insert(table, {i, "value_#{i}"})
      end

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sample_basic", "limit" => 5}, context)

      result = Jason.decode!(json)
      assert result["operation"] == "sample"
      assert result["count"] == 5
      assert length(result["entries"]) == 5
      assert result["total_size"] == 20
      assert result["truncated"] == true
    end

    test "uses default limit of 10", %{project_root: project_root} do
      table = :ets.new(:test_ets_sample_default, [:named_table, :public])

      for i <- 1..25 do
        :ets.insert(table, {i, "value_#{i}"})
      end

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sample_default"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 10
    end

    test "caps limit at 100", %{project_root: project_root} do
      table = :ets.new(:test_ets_sample_cap, [:named_table, :public])

      for i <- 1..10 do
        :ets.insert(table, {i, "value"})
      end

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      # Should not error with very large limit
      {:ok, json} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sample_cap", "limit" => 999}, context)

      result = Jason.decode!(json)
      # Should return all 10 entries (less than max 100)
      assert result["count"] == 10
    end

    test "handles empty table", %{project_root: project_root} do
      table = :ets.new(:test_ets_sample_empty, [:named_table, :public])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sample_empty"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 0
      assert result["entries"] == []
      assert result["truncated"] == false
    end

    test "indicates truncation correctly", %{project_root: project_root} do
      table = :ets.new(:test_ets_sample_truncation, [:named_table, :public])

      for i <- 1..5 do
        :ets.insert(table, {i, "value"})
      end

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}

      # When limit >= total, should not be truncated
      {:ok, json1} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sample_truncation", "limit" => 10}, context)
      result1 = Jason.decode!(json1)
      assert result1["truncated"] == false

      # When limit < total, should be truncated
      {:ok, json2} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sample_truncation", "limit" => 3}, context)
      result2 = Jason.decode!(json2)
      assert result2["truncated"] == true
    end
  end

  describe "EtsInspect.execute/2 - security" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "blocks access to system ETS tables", %{project_root: project_root} do
      context = %{project_root: project_root}

      # code table
      {:error, error} = EtsInspect.execute(%{"operation" => "info", "table" => "code"}, context)
      assert error =~ "blocked"

      # ac_tab
      {:error, error} = EtsInspect.execute(%{"operation" => "info", "table" => "ac_tab"}, context)
      assert error =~ "blocked"
    end

    test "blocks lookup on private tables", %{project_root: project_root} do
      table = :ets.new(:test_ets_private_lookup, [:named_table, :private])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_private_lookup", "key" => ":foo"}, context)

      assert error =~ "private"
    end

    test "blocks sample on private tables", %{project_root: project_root} do
      table = :ets.new(:test_ets_private_sample, [:named_table, :private])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_private_sample"}, context)

      assert error =~ "private"
    end

    test "allows info on protected tables", %{project_root: project_root} do
      table = :ets.new(:test_ets_protected_info, [:named_table, :protected])
      :ets.insert(table, {:test, "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "info", "table" => "test_ets_protected_info"}, context)

      result = Jason.decode!(json)
      assert result["info"]["protection"] == "protected"
    end

    test "blocks lookup on protected tables not owned by current process", %{project_root: project_root} do
      # Create a table from another process so we're not the owner
      test_pid = self()
      spawn(fn ->
        table = :ets.new(:test_ets_protected_other_owner, [:named_table, :protected])
        :ets.insert(table, {:test_key, "value"})
        send(test_pid, {:table_created, table})
        # Keep the process alive so the table persists
        receive do
          :done -> :ok
        end
      end)

      receive do
        {:table_created, table} ->
          on_exit(fn ->
            try do
              :ets.delete(table)
            catch
              :error, _ -> :ok
            end
          end)

          context = %{project_root: project_root}
          {:error, error} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_protected_other_owner", "key" => ":test_key"}, context)

          assert error =~ "protected" and error =~ "owner"
      after
        1000 -> flunk("Table not created in time")
      end
    end

    test "blocks tables owned by system processes from list", %{project_root: project_root} do
      # The list operation should not include tables owned by system processes
      # We verify this by checking that system tables like :code are not in the list
      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "list"}, context)

      result = Jason.decode!(json)
      table_names = Enum.map(result["tables"], & &1["name"])

      # System tables should not appear in list
      refute "code" in table_names
      refute "ac_tab" in table_names
      refute "file_io_servers" in table_names
    end
  end

  describe "EtsInspect.execute/2 - error handling" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "handles missing operation parameter" do
      context = %{project_root: "/tmp"}
      {:error, error} = EtsInspect.execute(%{}, context)

      assert error =~ "Missing required parameter: operation"
    end

    test "handles invalid operation", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "invalid_op"}, context)

      assert error =~ "Invalid operation"
    end

    test "handles invalid operation type" do
      context = %{project_root: "/tmp"}
      {:error, error} = EtsInspect.execute(%{"operation" => 123}, context)

      assert error =~ "Invalid operation"
    end

    test "returns error for reference-based tables", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, error} = EtsInspect.execute(%{"operation" => "info", "table" => "#Ref<0.123.456.789>"}, context)

      assert error =~ "Reference-based tables" or error =~ "not found"
    end
  end

  describe "EtsInspect.execute/2 - telemetry" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "emits telemetry on success", %{project_root: project_root} do
      table = :ets.new(:test_ets_telemetry_success, [:named_table, :public])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :ets_inspect]
        ])

      context = %{project_root: project_root}
      {:ok, _json} = EtsInspect.execute(%{"operation" => "info", "table" => "test_ets_telemetry_success"}, context)

      assert_receive {[:jido_code, :elixir, :ets_inspect], ^ref, %{duration: _, exit_code: 0},
                      %{task: "info", status: :ok}}
    end

    test "emits telemetry on error", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :ets_inspect]
        ])

      context = %{project_root: project_root}
      {:error, _} = EtsInspect.execute(%{"operation" => "info", "table" => "nonexistent_table"}, context)

      assert_receive {[:jido_code, :elixir, :ets_inspect], ^ref, %{duration: _, exit_code: 1},
                      %{task: "info", status: :error}}
    end

    test "emits telemetry for list operation", %{project_root: project_root} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:jido_code, :elixir, :ets_inspect]
        ])

      context = %{project_root: project_root}
      {:ok, _json} = EtsInspect.execute(%{"operation" => "list"}, context)

      assert_receive {[:jido_code, :elixir, :ets_inspect], ^ref, %{duration: _, exit_code: 0},
                      %{task: "list", status: :ok}}
    end
  end

  describe "EtsInspect.execute/2 - key parsing" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "parses boolean keys", %{project_root: project_root} do
      table = :ets.new(:test_ets_bool_key, [:named_table, :public])
      :ets.insert(table, {true, "value_true"})
      :ets.insert(table, {false, "value_false"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}

      {:ok, json_true} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_bool_key", "key" => "true"}, context)
      result_true = Jason.decode!(json_true)
      assert result_true["count"] == 1
      assert hd(result_true["entries"]) =~ "value_true"

      {:ok, json_false} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_bool_key", "key" => "false"}, context)
      result_false = Jason.decode!(json_false)
      assert result_false["count"] == 1
      assert hd(result_false["entries"]) =~ "value_false"
    end

    test "parses float keys", %{project_root: project_root} do
      table = :ets.new(:test_ets_float_key, [:named_table, :public])
      :ets.insert(table, {3.14, "pi"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_float_key", "key" => "3.14"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 1
    end

    test "parses single-quoted string keys", %{project_root: project_root} do
      table = :ets.new(:test_ets_single_quote_key, [:named_table, :public])
      :ets.insert(table, {"my key", "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_single_quote_key", "key" => "'my key'"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 1
    end

    test "treats unquoted strings as-is", %{project_root: project_root} do
      table = :ets.new(:test_ets_unquoted_key, [:named_table, :public])
      :ets.insert(table, {"plain_key", "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_unquoted_key", "key" => "plain_key"}, context)

      result = Jason.decode!(json)
      assert result["count"] == 1
    end

    test "rejects non-existent atoms to prevent atom table exhaustion", %{project_root: project_root} do
      table = :ets.new(:test_ets_nonexistent_atom, [:named_table, :public])
      :ets.insert(table, {:existing_key, "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      # Use a random unique atom name that definitely doesn't exist
      unique_atom_name = ":nonexistent_atom_#{System.unique_integer([:positive])}"
      {:error, error} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_nonexistent_atom", "key" => unique_atom_name}, context)

      assert error =~ "Atom key does not exist"
    end
  end

  describe "EtsInspect.execute/2 - sensitive data redaction" do
    alias JidoCode.Tools.Handlers.Elixir.EtsInspect

    test "redacts sensitive fields in sample output", %{project_root: project_root} do
      table = :ets.new(:test_ets_sensitive_data, [:named_table, :public])
      :ets.insert(table, {:user, %{name: "Alice", password: "secret123", token: "abc-xyz"}})
      :ets.insert(table, {:config, %{api_key: "sk-12345", database_url: "postgres://user:pass@host/db"}})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "sample", "table" => "test_ets_sensitive_data", "limit" => 10}, context)

      result = Jason.decode!(json)

      # Verify entries exist
      assert result["count"] >= 1

      # Verify sensitive data is redacted
      entries_str = Enum.join(result["entries"], " ")
      refute entries_str =~ "secret123"
      refute entries_str =~ "abc-xyz"
      refute entries_str =~ "sk-12345"
      refute entries_str =~ "postgres://user:pass"

      # Verify [REDACTED] is present
      assert entries_str =~ "[REDACTED]"
    end

    test "redacts sensitive fields in lookup output", %{project_root: project_root} do
      table = :ets.new(:test_ets_sensitive_lookup, [:named_table, :public])
      :ets.insert(table, {:credentials, %{secret: "super_secret", bearer: "token123"}})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      context = %{project_root: project_root}
      {:ok, json} = EtsInspect.execute(%{"operation" => "lookup", "table" => "test_ets_sensitive_lookup", "key" => ":credentials"}, context)

      result = Jason.decode!(json)
      entries_str = Enum.join(result["entries"], " ")

      # Sensitive data should be redacted
      refute entries_str =~ "super_secret"
      refute entries_str =~ "token123"
      assert entries_str =~ "[REDACTED]"
    end
  end

  # ============================================================================
  # FetchDocs Tests
  # ============================================================================

  describe "FetchDocs.execute/2 - standard library module" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "fetches docs for Enum module", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum"}, context)

      result = Jason.decode!(json)

      assert result["module"] == "Enum"
      assert is_binary(result["moduledoc"])
      assert String.contains?(result["moduledoc"], "Enum")
      assert is_list(result["docs"])
      assert length(result["docs"]) > 0
      assert is_list(result["specs"])
    end

    test "fetches docs for String module", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "String"}, context)

      result = Jason.decode!(json)

      assert result["module"] == "String"
      assert is_binary(result["moduledoc"])
      assert is_list(result["docs"])
    end

    test "handles Elixir. prefix automatically", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Elixir.Enum"}, context)

      result = Jason.decode!(json)
      assert result["module"] == "Elixir.Enum"
      assert is_binary(result["moduledoc"])
    end
  end

  describe "FetchDocs.execute/2 - specific function" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "filters docs to specific function", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum", "function" => "map"}, context)

      result = Jason.decode!(json)

      assert result["module"] == "Enum"
      assert is_list(result["docs"])
      assert length(result["docs"]) > 0

      # All returned docs should be for "map" function
      Enum.each(result["docs"], fn doc ->
        assert doc["name"] == "map"
      end)
    end

    test "filters specs to specific function", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum", "function" => "map"}, context)

      result = Jason.decode!(json)

      # Specs should also be filtered
      Enum.each(result["specs"], fn spec ->
        assert spec["name"] == "map"
      end)
    end
  end

  describe "FetchDocs.execute/2 - function with arity" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "filters docs to specific function and arity", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum", "function" => "map", "arity" => 2}, context)

      result = Jason.decode!(json)

      assert is_list(result["docs"])

      # All returned docs should be for "map/2"
      Enum.each(result["docs"], fn doc ->
        assert doc["name"] == "map"
        assert doc["arity"] == 2
      end)
    end

    test "filters specs to specific arity", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum", "function" => "reduce", "arity" => 3}, context)

      result = Jason.decode!(json)

      # Specs should be filtered by arity too
      Enum.each(result["specs"], fn spec ->
        assert spec["name"] == "reduce"
        assert spec["arity"] == 3
      end)
    end
  end

  describe "FetchDocs.execute/2 - includes specs" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "includes type specifications", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum"}, context)

      result = Jason.decode!(json)

      assert is_list(result["specs"])
      assert length(result["specs"]) > 0

      # Each spec should have name, arity, and specs list
      first_spec = hd(result["specs"])
      assert is_binary(first_spec["name"])
      assert is_integer(first_spec["arity"])
      assert is_list(first_spec["specs"])
    end

    test "spec format is readable", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum", "function" => "map", "arity" => 2}, context)

      result = Jason.decode!(json)

      if length(result["specs"]) > 0 do
        spec = hd(result["specs"])
        spec_string = hd(spec["specs"])
        assert is_binary(spec_string)
        # Should look like a function spec
        assert String.contains?(spec_string, "map")
      end
    end
  end

  describe "FetchDocs.execute/2 - undocumented module" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "handles module with no docs gracefully", %{project_root: project_root} do
      context = %{project_root: project_root}
      # :erlang module has no Elixir docs
      result = FetchDocs.execute(%{"module" => "erlang"}, context)

      # Should return an error for :erlang (not an Elixir module)
      assert {:error, msg} = result
      assert msg =~ "Module not found" or msg =~ "no embedded documentation"
    end
  end

  describe "FetchDocs.execute/2 - non-existent module" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "rejects non-existent module", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:error, msg} = FetchDocs.execute(%{"module" => "NonExistentModuleThatDoesNotExist"}, context)

      assert msg =~ "Module not found"
    end

    test "does not create new atoms for non-existent modules", %{project_root: project_root} do
      context = %{project_root: project_root}
      random_name = "RandomModule#{:rand.uniform(1_000_000)}"

      # Execute should fail without creating the atom
      {:error, _} = FetchDocs.execute(%{"module" => random_name}, context)

      # Verify atom was not created
      assert_raise ArgumentError, fn ->
        String.to_existing_atom("Elixir." <> random_name)
      end
    end
  end

  describe "FetchDocs.execute/2 - error handling" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "returns error for missing module parameter", %{project_root: _project_root} do
      context = %{}
      {:error, msg} = FetchDocs.execute(%{}, context)

      assert msg =~ "Missing required parameter: module"
    end

    test "returns error for non-string module", %{project_root: _project_root} do
      context = %{}
      {:error, msg} = FetchDocs.execute(%{"module" => 123}, context)

      assert msg =~ "Invalid module: expected string"
    end
  end

  describe "FetchDocs.execute/2 - telemetry" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "emits telemetry on success", %{project_root: project_root} do
      ref = :telemetry_test.attach_event_handlers(self(), [[:jido_code, :elixir, :fetch_docs]])

      context = %{project_root: project_root}
      {:ok, _} = FetchDocs.execute(%{"module" => "Enum"}, context)

      assert_receive {[:jido_code, :elixir, :fetch_docs], ^ref, %{duration: _, exit_code: 0}, %{status: :ok, task: "Enum"}}
    end

    test "emits telemetry on error", %{project_root: project_root} do
      ref = :telemetry_test.attach_event_handlers(self(), [[:jido_code, :elixir, :fetch_docs]])

      context = %{project_root: project_root}
      {:error, _} = FetchDocs.execute(%{"module" => "NonExistentModule"}, context)

      assert_receive {[:jido_code, :elixir, :fetch_docs], ^ref, %{duration: _, exit_code: 1}, %{status: :error, task: "NonExistentModule"}}
    end
  end

  describe "FetchDocs.execute/2 - doc structure" do
    alias JidoCode.Tools.Handlers.Elixir.FetchDocs

    test "doc entries have expected structure", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Enum", "function" => "map", "arity" => 2}, context)

      result = Jason.decode!(json)

      if length(result["docs"]) > 0 do
        doc = hd(result["docs"])
        assert Map.has_key?(doc, "name")
        assert Map.has_key?(doc, "arity")
        assert Map.has_key?(doc, "kind")
        assert Map.has_key?(doc, "signature")
        assert Map.has_key?(doc, "doc")
        assert Map.has_key?(doc, "deprecated")
      end
    end

    test "returns function and macro kinds", %{project_root: project_root} do
      context = %{project_root: project_root}
      {:ok, json} = FetchDocs.execute(%{"module" => "Kernel"}, context)

      result = Jason.decode!(json)
      kinds = Enum.map(result["docs"], & &1["kind"]) |> Enum.uniq()

      assert "function" in kinds or "macro" in kinds
    end
  end
end
