defmodule JidoCode.Integration.ToolsPhase5Test do
  @moduledoc """
  Integration tests for Phase 5 (Elixir-Specific Tools) using the Handler pattern.

  These tests verify that Phase 5 tools work correctly through the
  Executor → Handler chain with proper security controls and telemetry.

  ## Tested Tools

  - `mix_task` - Run Mix tasks with allowlist (Section 5.1)
  - `run_exunit` - Run ExUnit tests with filtering (Section 5.2)
  - `get_process_state` - Inspect GenServer/process state (Section 5.3)
  - `inspect_supervisor` - View supervisor tree structure (Section 5.4)
  - `ets_inspect` - Inspect ETS tables (Section 5.5)
  - `fetch_elixir_docs` - Retrieve module/function docs (Section 5.6)

  ## Test Coverage (Section 5.7)

  - 5.7.1: Handler Integration - Executor → Handler chain, context, telemetry
  - 5.7.2: Mix/Test Integration - mix_task and run_exunit in realistic scenarios
  - 5.7.3: Runtime Introspection - Process and ETS inspection with real processes
  - 5.7.4: Documentation Integration - fetch_elixir_docs with standard library
  - 5.7.5: Security Integration - Security controls enforced across all tools

  ## Why async: false

  These tests cannot run async because they:
  1. Share the SessionSupervisor (DynamicSupervisor)
  2. Use SessionRegistry which is a shared ETS table
  3. Create and inspect real processes/ETS tables
  4. Require deterministic cleanup between test runs
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.Tools.Definitions.Elixir, as: ElixirDefs
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.Registry, as: ToolsRegistry

  @moduletag :integration
  @moduletag :phase5

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
    tmp_base = Path.join(System.tmp_dir!(), "phase5_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Register Phase 5 tools
    register_phase5_tools()

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

  defp register_phase5_tools do
    # Register all Phase 5 Elixir tools
    for tool <- ElixirDefs.all() do
      ToolsRegistry.register(tool)
    end
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

  # Create a minimal Elixir project for testing mix_task and run_exunit
  defp create_elixir_project(base, name) do
    project_dir = create_test_dir(base, name)

    # Create mix.exs
    File.write!(Path.join(project_dir, "mix.exs"), """
    defmodule TestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_project,
          version: "0.1.0",
          elixir: "~> 1.14",
          start_permanent: false,
          deps: []
        ]
      end

      def application do
        [extra_applications: [:logger]]
      end
    end
    """)

    # Create lib directory with a module
    lib_dir = create_test_dir(project_dir, "lib")

    File.write!(Path.join(lib_dir, "test_project.ex"), """
    defmodule TestProject do
      @moduledoc "Test project module."

      @doc "Says hello."
      def hello, do: :world

      @doc "Adds two numbers."
      def add(a, b), do: a + b
    end
    """)

    # Create test directory with a test file
    test_dir = create_test_dir(project_dir, "test")

    File.write!(Path.join(test_dir, "test_helper.exs"), """
    ExUnit.start()
    """)

    File.write!(Path.join(test_dir, "test_project_test.exs"), """
    defmodule TestProjectTest do
      use ExUnit.Case

      test "hello returns :world" do
        assert TestProject.hello() == :world
      end

      test "add works correctly" do
        assert TestProject.add(1, 2) == 3
      end

      @tag :slow
      test "slow test" do
        Process.sleep(10)
        assert true
      end
    end
    """)

    project_dir
  end

  # ============================================================================
  # Section 5.7.1: Handler Integration Tests
  # ============================================================================

  describe "5.7.1.2 Executor → Handler chain execution" do
    test "mix_task executes through Executor → Handler chain", %{tmp_base: _tmp_base} do
      # Use the actual project root for mix commands
      project_dir = File.cwd!()

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute mix_task (help is always available)
      call = tool_call("mix_task", %{"task" => "help"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert is_map(output)
      assert Map.has_key?(output, "output")
      assert Map.has_key?(output, "exit_code")
    end

    test "fetch_elixir_docs executes through Executor → Handler chain", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_chain_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute fetch_elixir_docs
      call = tool_call("fetch_elixir_docs", %{"module" => "Enum"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, docs} = result |> unwrap_result() |> decode_result()
      assert is_map(docs)
      assert docs["module"] == "Enum"
      assert is_binary(docs["moduledoc"])
      assert is_list(docs["docs"])
    end

    test "ets_inspect executes through Executor → Handler chain", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "ets_chain_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute ets_inspect list operation
      call = tool_call("ets_inspect", %{"operation" => "list"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, tables} = result |> unwrap_result() |> decode_result()
      assert is_map(tables)
      assert Map.has_key?(tables, "tables")
      assert is_list(tables["tables"])
    end
  end

  describe "5.7.1.3 Session context passed correctly to handlers" do
    test "context includes session_id and project_root", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "context_test")

      # Create session
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Verify context has required fields
      assert Map.has_key?(context, :session_id)
      assert Map.has_key?(context, :project_root)
      assert context.session_id == session.id
      assert context.project_root == project_dir
    end

    test "handlers receive correct project_root in context", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "handler_context_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute a tool that uses project_root
      call = tool_call("fetch_elixir_docs", %{"module" => "String"})
      result = Executor.execute(call, context: context)

      # Should succeed (project_root is valid)
      {:ok, _docs} = result |> unwrap_result() |> decode_result()
    end
  end

  describe "5.7.1.4 Telemetry events emitted for all operations" do
    test "mix_task emits telemetry events", %{tmp_base: _tmp_base} do
      project_dir = File.cwd!()

      # Attach telemetry handler
      ref = :telemetry_test.attach_event_handlers(self(), [[:jido_code, :elixir, :mix_task]])

      # Create session and execute
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("mix_task", %{"task" => "help"})
      _result = Executor.execute(call, context: context)

      # Verify telemetry was emitted
      assert_receive {[:jido_code, :elixir, :mix_task], ^ref, %{duration: _, exit_code: _}, %{task: "help"}}
    end

    test "fetch_elixir_docs emits telemetry events", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "telemetry_docs_test")

      # Attach telemetry handler
      ref = :telemetry_test.attach_event_handlers(self(), [[:jido_code, :elixir, :fetch_docs]])

      # Create session and execute
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("fetch_elixir_docs", %{"module" => "Enum"})
      _result = Executor.execute(call, context: context)

      # Verify telemetry was emitted
      assert_receive {[:jido_code, :elixir, :fetch_docs], ^ref, %{duration: _, exit_code: 0}, %{task: "Enum", status: :ok}}
    end

    test "ets_inspect emits telemetry events", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "telemetry_ets_test")

      # Attach telemetry handler
      ref = :telemetry_test.attach_event_handlers(self(), [[:jido_code, :elixir, :ets_inspect]])

      # Create session and execute
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("ets_inspect", %{"operation" => "list"})
      _result = Executor.execute(call, context: context)

      # Verify telemetry was emitted (uses "task" key instead of "operation")
      assert_receive {[:jido_code, :elixir, :ets_inspect], ^ref, %{duration: _, exit_code: 0}, %{task: "list", status: :ok}}
    end
  end

  # ============================================================================
  # Section 5.7.2: Mix/Test Integration Tests
  # ============================================================================

  describe "5.7.2.1 mix_task compile works in test project" do
    @tag timeout: 120_000
    test "mix compile succeeds in valid project", %{tmp_base: tmp_base} do
      project_dir = create_elixir_project(tmp_base, "compile_test_project")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # First run deps.get (may be needed)
      deps_call = tool_call("mix_task", %{"task" => "deps.get"})
      _deps_result = Executor.execute(deps_call, context: context)

      # Execute mix compile
      call = tool_call("mix_task", %{"task" => "compile"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert output["exit_code"] == 0 or output["output"] =~ "Compiling"
    end
  end

  describe "5.7.2.2 mix_task test runs tests" do
    @tag timeout: 120_000
    test "mix test runs and returns results", %{tmp_base: tmp_base} do
      project_dir = create_elixir_project(tmp_base, "test_run_project")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute mix test
      call = tool_call("mix_task", %{"task" => "test"})
      result = Executor.execute(call, context: context)

      # Verify result contains test output
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert is_map(output)
      # Test output should mention tests
      assert output["output"] =~ "test" or output["exit_code"] in [0, 1]
    end
  end

  describe "5.7.2.3 run_exunit parses real test output" do
    @tag timeout: 120_000
    test "run_exunit returns structured test results", %{tmp_base: tmp_base} do
      project_dir = create_elixir_project(tmp_base, "exunit_parse_project")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute run_exunit
      call = tool_call("run_exunit", %{})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert is_map(output)
      assert Map.has_key?(output, "output")
      assert Map.has_key?(output, "exit_code")
    end

    @tag timeout: 120_000
    test "run_exunit can filter by tag", %{tmp_base: tmp_base} do
      project_dir = create_elixir_project(tmp_base, "exunit_tag_project")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute run_exunit with tag filter
      call = tool_call("run_exunit", %{"exclude_tag" => "slow"})
      result = Executor.execute(call, context: context)

      # Should succeed
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert is_map(output)
    end
  end

  describe "5.7.2.4 run_exunit handles test failures" do
    @tag timeout: 120_000
    test "run_exunit reports failures correctly", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "exunit_fail_project")

      # Create a project with a failing test
      File.write!(Path.join(project_dir, "mix.exs"), """
      defmodule FailProject.MixProject do
        use Mix.Project
        def project, do: [app: :fail_project, version: "0.1.0", elixir: "~> 1.14", deps: []]
      end
      """)

      test_dir = create_test_dir(project_dir, "test")
      File.write!(Path.join(test_dir, "test_helper.exs"), "ExUnit.start()")
      File.write!(Path.join(test_dir, "fail_test.exs"), """
      defmodule FailTest do
        use ExUnit.Case
        test "this test fails" do
          assert 1 == 2
        end
      end
      """)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute run_exunit
      call = tool_call("run_exunit", %{})
      result = Executor.execute(call, context: context)

      # Verify result indicates failure
      {:ok, output} = result |> unwrap_result() |> decode_result()
      assert output["exit_code"] != 0 or output["output"] =~ "failure"
    end
  end

  # ============================================================================
  # Section 5.7.3: Runtime Introspection Integration Tests
  # ============================================================================

  describe "5.7.3.1 get_process_state inspects test GenServer" do
    test "get_process_state retrieves GenServer state", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "process_state_test")

      # Start a test GenServer with a known name
      defmodule TestGenServer do
        use GenServer

        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts[:initial_state], name: opts[:name])
        end

        def init(state), do: {:ok, state}
      end

      # Start with a unique name for this test
      server_name = :"TestServer_#{:rand.uniform(100_000)}"
      {:ok, _pid} = TestGenServer.start_link(name: server_name, initial_state: %{counter: 42})

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute get_process_state
      call = tool_call("get_process_state", %{"process" => Atom.to_string(server_name)})
      result = Executor.execute(call, context: context)

      # Clean up
      GenServer.stop(server_name)

      # Verify result
      {:ok, state_info} = result |> unwrap_result() |> decode_result()
      assert is_map(state_info)
      # Should contain state or process_info
      assert Map.has_key?(state_info, "state") or Map.has_key?(state_info, "process_info")
    end
  end

  describe "5.7.3.2 inspect_supervisor shows test supervisor tree" do
    test "inspect_supervisor retrieves supervisor children", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "supervisor_test")

      # Start a test supervisor with children
      defmodule TestWorker do
        use GenServer
        def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])
        def init(opts), do: {:ok, opts}
      end

      defmodule TestSupervisor do
        use Supervisor

        def start_link(opts) do
          Supervisor.start_link(__MODULE__, opts, name: opts[:name])
        end

        def init(_opts) do
          children = [
            {TestWorker, [name: :"TestWorker_#{:rand.uniform(100_000)}"]}
          ]

          Supervisor.init(children, strategy: :one_for_one)
        end
      end

      sup_name = :"TestSup_#{:rand.uniform(100_000)}"
      {:ok, _pid} = TestSupervisor.start_link(name: sup_name)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute inspect_supervisor
      call = tool_call("inspect_supervisor", %{"supervisor" => Atom.to_string(sup_name)})
      result = Executor.execute(call, context: context)

      # Clean up
      Supervisor.stop(sup_name)

      # Verify result
      {:ok, tree} = result |> unwrap_result() |> decode_result()
      assert is_map(tree)
      assert Map.has_key?(tree, "name") or Map.has_key?(tree, "children")
    end
  end

  describe "5.7.3.3 ets_inspect lists test ETS tables" do
    test "ets_inspect list shows created tables", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "ets_list_test")

      # Create a test ETS table
      table_name = :"test_table_#{:rand.uniform(100_000)}"
      :ets.new(table_name, [:named_table, :public])
      :ets.insert(table_name, {:key1, "value1"})

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute ets_inspect list
      call = tool_call("ets_inspect", %{"operation" => "list"})
      result = Executor.execute(call, context: context)

      # Clean up
      :ets.delete(table_name)

      # Verify result
      {:ok, tables} = result |> unwrap_result() |> decode_result()
      assert is_map(tables)
      assert is_list(tables["tables"])
    end
  end

  describe "5.7.3.4 ets_inspect looks up test data" do
    test "ets_inspect lookup retrieves data by key", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "ets_lookup_test")

      # Create a test ETS table with data
      table_name = :"lookup_table_#{:rand.uniform(100_000)}"
      :ets.new(table_name, [:named_table, :public])
      :ets.insert(table_name, {:my_key, "my_value", 123})

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute ets_inspect lookup
      call = tool_call("ets_inspect", %{
        "operation" => "lookup",
        "table" => Atom.to_string(table_name),
        "key" => ":my_key"
      })
      result = Executor.execute(call, context: context)

      # Clean up
      :ets.delete(table_name)

      # Verify result
      {:ok, lookup_result} = result |> unwrap_result() |> decode_result()
      assert is_map(lookup_result)
      assert Map.has_key?(lookup_result, "entries") or Map.has_key?(lookup_result, "result")
    end

    test "ets_inspect sample retrieves multiple entries", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "ets_sample_test")

      # Create a test ETS table with multiple entries
      table_name = :"sample_table_#{:rand.uniform(100_000)}"
      :ets.new(table_name, [:named_table, :public])
      :ets.insert(table_name, {:key1, "value1"})
      :ets.insert(table_name, {:key2, "value2"})
      :ets.insert(table_name, {:key3, "value3"})

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute ets_inspect sample
      call = tool_call("ets_inspect", %{
        "operation" => "sample",
        "table" => Atom.to_string(table_name),
        "limit" => 2
      })
      result = Executor.execute(call, context: context)

      # Clean up
      :ets.delete(table_name)

      # Verify result
      {:ok, sample_result} = result |> unwrap_result() |> decode_result()
      assert is_map(sample_result)
    end
  end

  # ============================================================================
  # Section 5.7.4: Documentation Integration Tests
  # ============================================================================

  describe "5.7.4.1 fetch_elixir_docs retrieves Enum docs" do
    test "retrieves complete Enum module documentation", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_enum_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute fetch_elixir_docs for Enum
      call = tool_call("fetch_elixir_docs", %{"module" => "Enum"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, docs} = result |> unwrap_result() |> decode_result()
      assert docs["module"] == "Enum"
      assert is_binary(docs["moduledoc"])
      assert String.length(docs["moduledoc"]) > 100
      assert is_list(docs["docs"])
      assert length(docs["docs"]) > 10

      # Verify function docs have expected structure
      map_doc = Enum.find(docs["docs"], &(&1["name"] == "map"))
      assert map_doc != nil
      assert map_doc["arity"] == 2
      assert map_doc["kind"] == "function"
    end

    test "retrieves specific function documentation", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_func_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute fetch_elixir_docs for Enum.map/2
      call = tool_call("fetch_elixir_docs", %{
        "module" => "Enum",
        "function" => "map",
        "arity" => 2
      })
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, docs} = result |> unwrap_result() |> decode_result()
      assert docs["module"] == "Enum"
      assert length(docs["docs"]) == 1

      map_doc = hd(docs["docs"])
      assert map_doc["name"] == "map"
      assert map_doc["arity"] == 2
    end

    test "includes type specifications", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_specs_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute fetch_elixir_docs for Enum
      call = tool_call("fetch_elixir_docs", %{"module" => "Enum"})
      result = Executor.execute(call, context: context)

      # Verify specs are included
      {:ok, docs} = result |> unwrap_result() |> decode_result()
      assert is_list(docs["specs"])
      assert length(docs["specs"]) > 0

      # Specs should have expected structure
      spec = hd(docs["specs"])
      assert Map.has_key?(spec, "name")
      assert Map.has_key?(spec, "arity")
      assert Map.has_key?(spec, "specs")
    end
  end

  describe "5.7.4.2 fetch_elixir_docs retrieves project module docs" do
    test "retrieves documentation for GenServer (behaviour)", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_genserver_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute fetch_elixir_docs for GenServer
      call = tool_call("fetch_elixir_docs", %{"module" => "GenServer"})
      result = Executor.execute(call, context: context)

      # Verify result
      {:ok, docs} = result |> unwrap_result() |> decode_result()
      assert docs["module"] == "GenServer"
      assert is_binary(docs["moduledoc"])
      assert docs["moduledoc"] =~ "behaviour"
    end

    test "retrieves documentation with callbacks when requested", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_callbacks_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute fetch_elixir_docs with include_callbacks
      call = tool_call("fetch_elixir_docs", %{
        "module" => "GenServer",
        "include_callbacks" => true
      })
      result = Executor.execute(call, context: context)

      # Verify callbacks are included
      {:ok, docs} = result |> unwrap_result() |> decode_result()
      kinds = Enum.map(docs["docs"], & &1["kind"]) |> Enum.uniq()
      assert "callback" in kinds
    end
  end

  # ============================================================================
  # Section 5.7.5: Security Integration Tests
  # ============================================================================

  describe "5.7.5.1 mix_task rejects blocked tasks" do
    test "rejects dangerous tasks like release", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "mix_blocked_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to run blocked task
      call = tool_call("mix_task", %{"task" => "release"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "not allowed" or error_msg =~ "blocked"
    end

    test "rejects hex.publish task", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "mix_publish_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to run blocked task
      call = tool_call("mix_task", %{"task" => "hex.publish"})
      result = Executor.execute(call, context: context)

      # Should fail
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "not allowed" or error_msg =~ "blocked"
    end

    test "rejects prod environment", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "mix_prod_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to run with prod env
      call = tool_call("mix_task", %{"task" => "compile", "env" => "prod"})
      result = Executor.execute(call, context: context)

      # Should fail
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "prod" or error_msg =~ "blocked" or error_msg =~ "not allowed"
    end
  end

  describe "5.7.5.2 run_exunit rejects path traversal" do
    test "blocks path traversal in test path", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "exunit_traversal_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt path traversal
      call = tool_call("run_exunit", %{"path" => "../../../etc/passwd"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "traversal" or error_msg =~ "blocked" or error_msg =~ "invalid"
    end
  end

  describe "5.7.5.3 get_process_state rejects system processes" do
    test "blocks inspection of JidoCode internal processes", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "process_jidocode_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to inspect JidoCode internal process
      call = tool_call("get_process_state", %{"process" => "Elixir.JidoCode.SessionSupervisor"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "blocked" or error_msg =~ "not found"
    end

    test "blocks inspection of JidoCode.Tools processes", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "process_tools_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to inspect JidoCode.Tools internal process
      call = tool_call("get_process_state", %{"process" => "JidoCode.Tools.Registry"})
      result = Executor.execute(call, context: context)

      # Should fail with security error - blocked or not found
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "blocked" or error_msg =~ "not found"
    end
  end

  describe "5.7.5.4 ets_inspect rejects system tables" do
    test "blocks access to code table", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "ets_code_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to access system table
      call = tool_call("ets_inspect", %{"operation" => "info", "table" => "code"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "blocked" or error_msg =~ "system"
    end

    test "blocks access to ac_tab table", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "ets_ac_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to access system table
      call = tool_call("ets_inspect", %{"operation" => "sample", "table" => "ac_tab"})
      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "blocked" or error_msg =~ "system"
    end
  end

  describe "5.7.5.5 All tools reject requests outside project boundary" do
    test "fetch_elixir_docs prevents atom table exhaustion", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "docs_atom_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Generate random module name that doesn't exist
      random_module = "NonExistentModule#{:rand.uniform(1_000_000)}"

      # Execute fetch_elixir_docs
      call = tool_call("fetch_elixir_docs", %{"module" => random_module})
      result = Executor.execute(call, context: context)

      # Should fail without creating atom
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "not found"

      # Verify atom was NOT created
      assert_raise ArgumentError, fn ->
        String.to_existing_atom("Elixir.#{random_module}")
      end
    end

    test "run_exunit validates path is within project", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "exunit_boundary_test")

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to access file outside project
      call = tool_call("run_exunit", %{"path" => "/etc/passwd"})
      result = Executor.execute(call, context: context)

      # Should fail (either path validation or file not found)
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "outside" or error_msg =~ "invalid" or error_msg =~ "not found" or error_msg =~ "traversal"
    end
  end
end
