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
end
