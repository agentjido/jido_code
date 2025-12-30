defmodule JidoCode.Integration.ToolsPhase3Test do
  @moduledoc """
  Integration tests for Phase 3 (LSP Code Intelligence) tools.

  These tests verify that Phase 3 LSP tools work correctly through the
  Executor → Handler chain with proper security boundary enforcement.

  ## Tested Tools

  - `get_hover_info` - Type and documentation at cursor position (Section 3.3)
  - `go_to_definition` - Symbol definition navigation (Section 3.4)
  - `find_references` - Symbol usage finding (Section 3.5)

  ## Test Coverage (Section 3.7)

  - 3.7.1.3: LSP tools execute through Executor → Handler chain
  - 3.7.1.4: Session-scoped context isolation
  - 3.7.3: LSP integration tests (hover, definition, references)

  ## Note on Expert Integration

  LSP tools connect to Expert (the official Elixir LSP) when available.
  When Expert is not installed, handlers return `lsp_not_available` status.
  Integration tests that require Expert are tagged with `:expert_required`.

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
  alias JidoCode.Tools.Definitions.LSP, as: LSPDefs
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.LSP.Client
  alias JidoCode.Tools.Registry, as: ToolsRegistry

  @moduletag :integration
  @moduletag :phase3

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
    tmp_base = Path.join(System.tmp_dir!(), "phase3_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Register Phase 3 LSP tools
    register_phase3_tools()

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

  defp register_phase3_tools do
    # Register LSP tools
    ToolsRegistry.register(LSPDefs.get_hover_info())
    ToolsRegistry.register(LSPDefs.go_to_definition())
    ToolsRegistry.register(LSPDefs.find_references())
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

  defp create_elixir_file(dir, filename, content) do
    path = Path.join(dir, filename)
    File.write!(path, content)
    path
  end

  # ============================================================================
  # Section 3.7.1.3: LSP Tools Execute Through Executor → Handler Chain
  # ============================================================================

  describe "Executor → Handler chain execution for LSP tools" do
    test "get_hover_info executes through Executor and returns result", %{tmp_base: tmp_base} do
      # Setup: Create project with Elixir file
      project_dir = create_test_dir(tmp_base, "hover_chain_test")

      create_elixir_file(project_dir, "test_module.ex", """
      defmodule TestModule do
        def hello, do: :world
      end
      """)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute get_hover_info through Executor
      call =
        tool_call("get_hover_info", %{"path" => "test_module.ex", "line" => 2, "character" => 7})

      result = Executor.execute(call, context: context)

      # Verify result structure
      {:ok, response} = result |> unwrap_result() |> decode_result()
      assert is_map(response)
      assert Map.has_key?(response, "status")
      # Status will be "lsp_not_available" without Expert, or "found"/"no_info" with it
      assert response["status"] in ["lsp_not_available", "found", "no_info"]
    end

    test "go_to_definition executes through Executor and returns result", %{tmp_base: tmp_base} do
      # Setup: Create project with Elixir file
      project_dir = create_test_dir(tmp_base, "def_chain_test")

      create_elixir_file(project_dir, "test_module.ex", """
      defmodule TestModule do
        def hello, do: :world

        def call_hello do
          hello()
        end
      end
      """)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute go_to_definition through Executor
      call =
        tool_call("go_to_definition", %{"path" => "test_module.ex", "line" => 5, "character" => 5})

      result = Executor.execute(call, context: context)

      # Verify result structure
      {:ok, response} = result |> unwrap_result() |> decode_result()
      assert is_map(response)
      assert Map.has_key?(response, "status")
      assert response["status"] in ["lsp_not_available", "found", "not_found"]
    end

    test "find_references executes through Executor and returns result", %{tmp_base: tmp_base} do
      # Setup: Create project with Elixir files
      project_dir = create_test_dir(tmp_base, "refs_chain_test")

      create_elixir_file(project_dir, "module_a.ex", """
      defmodule ModuleA do
        def shared_func, do: :ok
      end
      """)

      create_elixir_file(project_dir, "module_b.ex", """
      defmodule ModuleB do
        def caller do
          ModuleA.shared_func()
        end
      end
      """)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Execute find_references through Executor
      call =
        tool_call("find_references", %{"path" => "module_a.ex", "line" => 2, "character" => 7})

      result = Executor.execute(call, context: context)

      # Verify result structure
      {:ok, response} = result |> unwrap_result() |> decode_result()
      assert is_map(response)
      assert Map.has_key?(response, "status")
      assert response["status"] in ["lsp_not_available", "found", "no_references"]
    end
  end

  # ============================================================================
  # Section 3.7.1.4: Session-Scoped Context Isolation
  # ============================================================================

  describe "session-scoped context isolation for LSP tools" do
    test "get_hover_info uses session's project directory", %{tmp_base: tmp_base} do
      # Setup: Create two separate project directories
      project_a = create_test_dir(tmp_base, "hover_project_a")
      project_b = create_test_dir(tmp_base, "hover_project_b")

      # Create different content in each project
      create_elixir_file(project_a, "code.ex", """
      defmodule ProjectA do
        @moduledoc "Project A module"
        def hello, do: :project_a
      end
      """)

      create_elixir_file(project_b, "code.ex", """
      defmodule ProjectB do
        @moduledoc "Project B module"
        def hello, do: :project_b
      end
      """)

      # Create sessions for each project
      session_a = create_session(project_a)
      session_b = create_session(project_b)

      {:ok, context_a} = Executor.build_context(session_a.id)
      {:ok, context_b} = Executor.build_context(session_b.id)

      # Execute get_hover_info in each session
      call = tool_call("get_hover_info", %{"path" => "code.ex", "line" => 3, "character" => 7})

      result_a = Executor.execute(call, context: context_a)
      result_b = Executor.execute(call, context: context_b)

      # Both should succeed (no errors)
      {:ok, _response_a} = result_a |> unwrap_result() |> decode_result()
      {:ok, _response_b} = result_b |> unwrap_result() |> decode_result()
    end

    test "LSP tools reject paths outside session project", %{tmp_base: tmp_base} do
      # Setup: Create project directory
      project_dir = create_test_dir(tmp_base, "isolation_test")

      create_elixir_file(project_dir, "safe.ex", """
      defmodule Safe do
        def ok, do: :ok
      end
      """)

      # Create session and build context
      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Attempt to access file outside project boundary
      call =
        tool_call("get_hover_info", %{
          "path" => "../../../etc/passwd",
          "line" => 1,
          "character" => 1
        })

      result = Executor.execute(call, context: context)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "escapes" or error_msg =~ "outside" or error_msg =~ "boundary"
    end

    test "go_to_definition respects session project boundary", %{tmp_base: tmp_base} do
      # Setup: Create two separate projects
      project_a = create_test_dir(tmp_base, "def_project_a")
      project_b = create_test_dir(tmp_base, "def_project_b")

      create_elixir_file(project_a, "module.ex", "defmodule A do end")
      create_elixir_file(project_b, "module.ex", "defmodule B do end")

      # Create session for project A
      session_a = create_session(project_a)
      {:ok, context_a} = Executor.build_context(session_a.id)

      # Try to access project B's file from project A's session
      # Using a relative path that would escape to sibling project
      call =
        tool_call("go_to_definition", %{
          "path" => "../def_project_b/module.ex",
          "line" => 1,
          "character" => 10
        })

      result = Executor.execute(call, context: context_a)

      # Should fail with security error
      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "escapes" or error_msg =~ "outside" or error_msg =~ "boundary"
    end
  end

  # ============================================================================
  # Section 3.7.3: LSP Handler Integration
  # ============================================================================

  describe "LSP handler integration - hover info" do
    test "get_hover_info for Elixir file returns structured response", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "hover_elixir_test")

      create_elixir_file(project_dir, "test.ex", """
      defmodule TestHover do
        @moduledoc "A test module for hover info"

        @doc "Says hello"
        def hello do
          :world
        end
      end
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("get_hover_info", %{"path" => "test.ex", "line" => 5, "character" => 7})
      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert is_map(response)
      assert Map.has_key?(response, "status")
      assert Map.has_key?(response, "position") or response["status"] == "lsp_not_available"
    end

    test "get_hover_info for non-Elixir file returns unsupported status", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "hover_notelixir_test")

      # Create a non-Elixir file
      File.write!(Path.join(project_dir, "readme.txt"), "This is not Elixir code")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("get_hover_info", %{"path" => "readme.txt", "line" => 1, "character" => 1})
      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert response["status"] == "unsupported_file_type"
    end

    test "get_hover_info for nonexistent file returns error", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "hover_nofile_test")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call =
        tool_call("get_hover_info", %{"path" => "nonexistent.ex", "line" => 1, "character" => 1})

      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "not found" or error_msg =~ "does not exist"
    end
  end

  describe "LSP handler integration - go to definition" do
    test "go_to_definition for Elixir file returns structured response", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "def_elixir_test")

      create_elixir_file(project_dir, "test.ex", """
      defmodule TestDef do
        def target, do: :ok

        def caller do
          target()
        end
      end
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("go_to_definition", %{"path" => "test.ex", "line" => 5, "character" => 5})
      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert is_map(response)
      assert Map.has_key?(response, "status")
      assert response["status"] in ["lsp_not_available", "found", "not_found"]
    end

    test "go_to_definition for non-Elixir file returns unsupported status", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "def_notelixir_test")

      File.write!(Path.join(project_dir, "config.json"), "{}")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call =
        tool_call("go_to_definition", %{"path" => "config.json", "line" => 1, "character" => 1})

      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert response["status"] == "unsupported_file_type"
    end
  end

  describe "LSP handler integration - find references" do
    test "find_references for Elixir file returns structured response", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "refs_elixir_test")

      create_elixir_file(project_dir, "test.ex", """
      defmodule TestRefs do
        def target, do: :ok

        def caller1, do: target()
        def caller2, do: target()
      end
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("find_references", %{"path" => "test.ex", "line" => 2, "character" => 7})
      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert is_map(response)
      assert Map.has_key?(response, "status")
      assert response["status"] in ["lsp_not_available", "found", "no_references"]
    end

    test "find_references with include_declaration option", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "refs_decl_test")

      create_elixir_file(project_dir, "test.ex", """
      defmodule TestRefsDecl do
        def func, do: :ok
        def caller, do: func()
      end
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call =
        tool_call("find_references", %{
          "path" => "test.ex",
          "line" => 2,
          "character" => 7,
          "include_declaration" => true
        })

      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert is_map(response)
      assert Map.has_key?(response, "status")
      # With include_declaration, we expect the result to include declaration info
      if response["status"] == "lsp_not_available" do
        assert response["include_declaration"] == true
      end
    end

    test "find_references for non-Elixir file returns unsupported status", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "refs_notelixir_test")

      File.write!(Path.join(project_dir, "style.css"), "body { color: red; }")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("find_references", %{"path" => "style.css", "line" => 1, "character" => 1})
      result = Executor.execute(call, context: context)

      {:ok, response} = result |> unwrap_result() |> decode_result()

      assert response["status"] == "unsupported_file_type"
    end
  end

  # ============================================================================
  # Section 3.7.3.7: Output Path Validation (Security)
  # ============================================================================

  describe "output path validation and security" do
    test "LSP handlers validate input paths against project boundary", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "path_security_test")

      create_elixir_file(project_dir, "safe.ex", "defmodule Safe do end")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Test various path traversal attempts
      traversal_paths = [
        "../../../etc/passwd",
        "../../other_project/secret.ex",
        "/etc/passwd",
        "/home/user/.ssh/id_rsa"
      ]

      for bad_path <- traversal_paths do
        call = tool_call("get_hover_info", %{"path" => bad_path, "line" => 1, "character" => 1})
        result = Executor.execute(call, context: context)

        {:error, error_msg} = unwrap_result(result)

        assert error_msg =~ "escapes" or error_msg =~ "outside" or error_msg =~ "boundary",
               "Path #{bad_path} should be rejected but got: #{error_msg}"
      end
    end

    test "LSP handlers accept valid project paths", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "valid_path_test")
      lib_dir = create_test_dir(project_dir, "lib")

      create_elixir_file(lib_dir, "module.ex", """
      defmodule Lib.Module do
        def func, do: :ok
      end
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Valid paths within project
      valid_paths = [
        "lib/module.ex",
        "./lib/module.ex"
      ]

      for good_path <- valid_paths do
        call = tool_call("get_hover_info", %{"path" => good_path, "line" => 2, "character" => 7})
        result = Executor.execute(call, context: context)

        # Should not return an error about path validation
        case unwrap_result(result) do
          {:ok, json} ->
            response = Jason.decode!(json)
            refute response["status"] == "error"

          {:error, msg} ->
            refute msg =~ "escapes" or msg =~ "outside" or msg =~ "boundary",
                   "Path #{good_path} should be accepted but got: #{msg}"
        end
      end
    end

    test "absolute paths within project are accepted", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "abs_path_test")

      file_path =
        create_elixir_file(project_dir, "module.ex", """
        defmodule AbsPath do
          def func, do: :ok
        end
        """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Use absolute path within project
      call = tool_call("get_hover_info", %{"path" => file_path, "line" => 2, "character" => 7})
      result = Executor.execute(call, context: context)

      # Should not return path validation error
      case unwrap_result(result) do
        {:ok, json} ->
          response = Jason.decode!(json)
          refute response["status"] == "error"

        {:error, msg} ->
          refute msg =~ "escapes" or msg =~ "outside" or msg =~ "boundary",
                 "Absolute path within project should be accepted but got: #{msg}"
      end
    end
  end

  # ============================================================================
  # Section 3.7.3: Expert Integration Tests (require Expert)
  # ============================================================================

  describe "integration with Expert (when installed)" do
    @tag :integration
    @tag :expert_required

    test "get_hover_info returns actual hover content when Expert available", %{
      tmp_base: tmp_base
    } do
      case Client.find_expert_path() do
        {:ok, _path} ->
          project_dir = create_test_dir(tmp_base, "expert_hover_test")

          create_elixir_file(project_dir, "test.ex", """
          defmodule ExpertHover do
            @moduledoc "Test module for Expert integration"

            @doc "A documented function"
            def documented_func do
              :ok
            end
          end
          """)

          session = create_session(project_dir)
          {:ok, context} = Executor.build_context(session.id)

          # Give Expert time to start and index
          Process.sleep(2000)

          call =
            tool_call("get_hover_info", %{"path" => "test.ex", "line" => 5, "character" => 7})

          result = Executor.execute(call, context: context)

          {:ok, response} = result |> unwrap_result() |> decode_result()

          # With Expert, we should get actual hover content
          assert response["status"] in ["found", "no_info"]

        {:error, :not_found} ->
          # Skip test if Expert is not installed
          :ok
      end
    end

    test "go_to_definition navigates to function definition when Expert available", %{
      tmp_base: tmp_base
    } do
      case Client.find_expert_path() do
        {:ok, _path} ->
          project_dir = create_test_dir(tmp_base, "expert_def_test")

          create_elixir_file(project_dir, "test.ex", """
          defmodule ExpertDef do
            def target, do: :ok

            def caller do
              target()
            end
          end
          """)

          session = create_session(project_dir)
          {:ok, context} = Executor.build_context(session.id)

          Process.sleep(2000)

          call =
            tool_call("go_to_definition", %{"path" => "test.ex", "line" => 5, "character" => 5})

          result = Executor.execute(call, context: context)

          {:ok, response} = result |> unwrap_result() |> decode_result()

          assert response["status"] in ["found", "not_found"]

          if response["status"] == "found" do
            assert Map.has_key?(response, "definition") or Map.has_key?(response, "definitions")
          end

        {:error, :not_found} ->
          :ok
      end
    end

    test "find_references locates function usages when Expert available", %{tmp_base: tmp_base} do
      case Client.find_expert_path() do
        {:ok, _path} ->
          project_dir = create_test_dir(tmp_base, "expert_refs_test")

          create_elixir_file(project_dir, "test.ex", """
          defmodule ExpertRefs do
            def shared_func, do: :ok

            def caller1, do: shared_func()
            def caller2, do: shared_func()
            def caller3, do: shared_func()
          end
          """)

          session = create_session(project_dir)
          {:ok, context} = Executor.build_context(session.id)

          Process.sleep(2000)

          call =
            tool_call("find_references", %{
              "path" => "test.ex",
              "line" => 2,
              "character" => 7,
              "include_declaration" => true
            })

          result = Executor.execute(call, context: context)

          {:ok, response} = result |> unwrap_result() |> decode_result()

          assert response["status"] in ["found", "no_references"]

          if response["status"] == "found" do
            assert Map.has_key?(response, "references")
            assert is_list(response["references"])
          end

        {:error, :not_found} ->
          :ok
      end
    end
  end

  # ============================================================================
  # Parameter Validation Tests
  # ============================================================================

  describe "parameter validation" do
    test "get_hover_info requires path parameter", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "param_path_test")
      create_elixir_file(project_dir, "test.ex", "defmodule Test do end")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Missing path
      call = tool_call("get_hover_info", %{"line" => 1, "character" => 1})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "path" or error_msg =~ "required" or error_msg =~ "missing"
    end

    test "get_hover_info requires line parameter", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "param_line_test")
      create_elixir_file(project_dir, "test.ex", "defmodule Test do end")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Missing line
      call = tool_call("get_hover_info", %{"path" => "test.ex", "character" => 1})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "line" or error_msg =~ "required" or error_msg =~ "missing"
    end

    test "get_hover_info requires character parameter", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "param_char_test")
      create_elixir_file(project_dir, "test.ex", "defmodule Test do end")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Missing character
      call = tool_call("get_hover_info", %{"path" => "test.ex", "line" => 1})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "character" or error_msg =~ "required" or error_msg =~ "missing"
    end

    test "line and character must be positive integers", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "param_int_test")
      create_elixir_file(project_dir, "test.ex", "defmodule Test do end")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Negative line
      call = tool_call("get_hover_info", %{"path" => "test.ex", "line" => -1, "character" => 1})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "positive" or error_msg =~ "invalid" or error_msg =~ "greater"

      # Zero line
      call_zero =
        tool_call("get_hover_info", %{"path" => "test.ex", "line" => 0, "character" => 1})

      result_zero = Executor.execute(call_zero, context: context)

      {:error, error_msg_zero} = unwrap_result(result_zero)

      assert error_msg_zero =~ "positive" or error_msg_zero =~ "invalid" or
               error_msg_zero =~ "greater"
    end
  end
end
