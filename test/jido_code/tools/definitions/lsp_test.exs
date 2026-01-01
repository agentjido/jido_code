defmodule JidoCode.Tools.Definitions.LSPTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}
  alias JidoCode.Tools.Definitions.LSP, as: Definitions
  alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers

  @moduletag :tmp_dir

  # ============================================================================
  # Shared Test Helpers (reduces duplication across tool tests)
  # ============================================================================

  @doc false
  def make_tool_call(name, arguments, id \\ "call_123") do
    %{id: id, name: name, arguments: arguments}
  end

  @doc false
  def assert_error_result(result, pattern) do
    assert result.status == :error
    assert result.content =~ pattern
  end

  @doc false
  def assert_ok_status(result, expected_status) do
    assert result.status == :ok
    response = Jason.decode!(result.content)
    assert response["status"] == expected_status
    response
  end

  setup %{tmp_dir: tmp_dir} do
    # Ensure application is started (Manager and registries)
    Application.ensure_all_started(:jido_code)

    # Clear registry for each test
    Registry.clear()

    # Register all LSP tools
    for tool <- Definitions.all() do
      :ok = Registry.register(tool)
    end

    {:ok, project_root: tmp_dir}
  end

  describe "all/0" do
    test "returns all LSP tools" do
      tools = Definitions.all()
      assert length(tools) == 4

      names = Enum.map(tools, & &1.name)
      assert "get_hover_info" in names
      assert "go_to_definition" in names
      assert "find_references" in names
      assert "get_diagnostics" in names
    end
  end

  describe "get_hover_info/0 definition" do
    test "has correct schema" do
      tool = Definitions.get_hover_info()
      assert tool.name == "get_hover_info"
      assert tool.description =~ "type information"
      assert length(tool.parameters) == 3

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      line_param = Enum.find(tool.parameters, &(&1.name == "line"))
      char_param = Enum.find(tool.parameters, &(&1.name == "character"))

      assert path_param.required == true
      assert path_param.type == :string

      assert line_param.required == true
      assert line_param.type == :integer

      assert char_param.required == true
      assert char_param.type == :integer
    end

    test "generates valid LLM function format" do
      tool = Definitions.get_hover_info()
      llm_fn = JidoCode.Tools.Tool.to_llm_function(tool)

      assert llm_fn.type == "function"
      assert llm_fn.function.name == "get_hover_info"
      assert is_binary(llm_fn.function.description)
      assert is_map(llm_fn.function.parameters)

      # Check parameters schema
      params = llm_fn.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "line")
      assert Map.has_key?(params.properties, "character")
      assert "path" in params.required
      assert "line" in params.required
      assert "character" in params.required
    end
  end

  describe "go_to_definition/0 definition" do
    test "has correct schema" do
      tool = Definitions.go_to_definition()
      assert tool.name == "go_to_definition"
      assert tool.description =~ "definition"
      assert length(tool.parameters) == 3

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      line_param = Enum.find(tool.parameters, &(&1.name == "line"))
      char_param = Enum.find(tool.parameters, &(&1.name == "character"))

      assert path_param.required == true
      assert path_param.type == :string

      assert line_param.required == true
      assert line_param.type == :integer

      assert char_param.required == true
      assert char_param.type == :integer
    end

    test "generates valid LLM function format" do
      tool = Definitions.go_to_definition()
      llm_fn = JidoCode.Tools.Tool.to_llm_function(tool)

      assert llm_fn.type == "function"
      assert llm_fn.function.name == "go_to_definition"
      assert is_binary(llm_fn.function.description)
      assert is_map(llm_fn.function.parameters)

      # Check parameters schema
      params = llm_fn.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "line")
      assert Map.has_key?(params.properties, "character")
      assert "path" in params.required
      assert "line" in params.required
      assert "character" in params.required
    end
  end

  describe "executor integration" do
    test "get_hover_info works via executor for Elixir files", %{project_root: project_root} do
      # Create an Elixir file
      file_path = Path.join(project_root, "test_module.ex")

      File.write!(file_path, """
      defmodule TestModule do
        def hello do
          :world
        end
      end
      """)

      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "test_module.ex", "line" => 2, "character" => 7}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      # Parse the response
      response = Jason.decode!(result.content)
      # Returns lsp_not_available when Expert is not installed
      assert response["status"] == "lsp_not_available"
      assert response["position"]["line"] == 2
      assert response["position"]["character"] == 7
    end

    test "get_hover_info handles non-Elixir files", %{project_root: project_root} do
      # Create a non-Elixir file
      file_path = Path.join(project_root, "readme.txt")
      File.write!(file_path, "This is a readme file")

      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "readme.txt", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      assert response["status"] == "unsupported_file_type"
    end

    test "get_hover_info returns error for non-existent file", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "nonexistent.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "executor validates required arguments", %{project_root: project_root} do
      # Missing required path argument
      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "get_hover_info validates line number", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # Line 0 is invalid (should be 1-indexed)
      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "test.ex", "line" => 0, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "get_hover_info validates character number", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # Character 0 is invalid (should be 1-indexed)
      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 0}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "results can be converted to LLM messages", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_abc",
        name: "get_hover_info",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert is_binary(message.content)
    end
  end

  describe "security" do
    test "get_hover_info blocks path traversal", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "../../../etc/passwd", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Security error" or result.content =~ "escapes"
    end

    test "get_hover_info blocks absolute paths outside project", %{project_root: _project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "/etc/passwd", "line" => 1, "character" => 1}
      }

      # Use a different project root to ensure absolute path is outside
      context = %{project_root: "/tmp/test_project"}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
    end
  end

  describe "session-aware context" do
    test "uses session_id when provided", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      # With an invalid session_id, should fall back or error
      context = %{session_id: "nonexistent_session", project_root: project_root}
      result = Executor.execute(tool_call, context: context)

      # Should work with fallback to project_root
      assert {:ok, _} = result
    end
  end

  # ============================================================================
  # go_to_definition tests
  # ============================================================================

  describe "go_to_definition executor integration" do
    test "go_to_definition works via executor for Elixir files", %{project_root: project_root} do
      # Create an Elixir file
      file_path = Path.join(project_root, "test_module.ex")

      File.write!(file_path, """
      defmodule TestModule do
        def hello do
          :world
        end
      end
      """)

      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "test_module.ex", "line" => 2, "character" => 7}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      # Parse the response
      response = Jason.decode!(result.content)
      # Returns lsp_not_available when Expert is not installed
      assert response["status"] == "lsp_not_available"
      assert response["position"]["line"] == 2
      assert response["position"]["character"] == 7
    end

    test "go_to_definition handles non-Elixir files", %{project_root: project_root} do
      # Create a non-Elixir file
      file_path = Path.join(project_root, "readme.txt")
      File.write!(file_path, "This is a readme file")

      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "readme.txt", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      assert response["status"] == "unsupported_file_type"
    end

    test "go_to_definition returns error for non-existent file", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "nonexistent.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "go_to_definition validates required arguments", %{project_root: project_root} do
      # Missing required path argument
      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "go_to_definition validates line number", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # Line 0 is invalid (should be 1-indexed)
      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "test.ex", "line" => 0, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "go_to_definition validates character number", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # Character 0 is invalid (should be 1-indexed)
      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 0}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "go_to_definition results can be converted to LLM messages", %{
      project_root: project_root
    } do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_def",
        name: "go_to_definition",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_def"
      assert is_binary(message.content)
    end
  end

  describe "go_to_definition security" do
    test "go_to_definition blocks path traversal", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "../../../etc/passwd", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Security error" or result.content =~ "escapes"
    end

    test "go_to_definition blocks absolute paths outside project", %{project_root: _project_root} do
      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "/etc/passwd", "line" => 1, "character" => 1}
      }

      # Use a different project root to ensure absolute path is outside
      context = %{project_root: "/tmp/test_project"}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
    end
  end

  describe "go_to_definition session-aware context" do
    test "uses session_id when provided", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_123",
        name: "go_to_definition",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      # With an invalid session_id, should fall back or error
      context = %{session_id: "nonexistent_session", project_root: project_root}
      result = Executor.execute(tool_call, context: context)

      # Should work with fallback to project_root
      assert {:ok, _} = result
    end
  end

  # ============================================================================
  # Output Path Validation Tests (3.4.2.5)
  # ============================================================================

  describe "output path validation" do
    alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers

    test "returns relative path for project files", %{project_root: project_root} do
      # Create a file in the project
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_path = Path.join(lib_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      context = %{project_root: project_root}

      assert {:ok, relative_path} = LSPHandlers.validate_output_path(file_path, context)
      assert relative_path == "lib/my_module.ex"
    end

    test "returns relative path for deps files", %{project_root: project_root} do
      # Create a deps directory and file
      deps_dir = Path.join(project_root, "deps/jason/lib")
      File.mkdir_p!(deps_dir)
      file_path = Path.join(deps_dir, "jason.ex")
      File.write!(file_path, "defmodule Jason, do: nil")

      context = %{project_root: project_root}

      assert {:ok, relative_path} = LSPHandlers.validate_output_path(file_path, context)
      assert relative_path == "deps/jason/lib/jason.ex"
    end

    test "returns relative path for _build files", %{project_root: project_root} do
      # Create a _build directory and file
      build_dir = Path.join(project_root, "_build/dev/lib/myapp")
      File.mkdir_p!(build_dir)
      file_path = Path.join(build_dir, "module.ex")
      File.write!(file_path, "defmodule Module, do: nil")

      context = %{project_root: project_root}

      assert {:ok, relative_path} = LSPHandlers.validate_output_path(file_path, context)
      assert relative_path == "_build/dev/lib/myapp/module.ex"
    end

    test "sanitizes Elixir stdlib paths", %{project_root: project_root} do
      # Simulate an Elixir stdlib path
      elixir_path = "/home/user/.asdf/installs/elixir/1.16.0/lib/elixir/lib/file.ex"
      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(elixir_path, context)
      assert sanitized == "elixir:File"
    end

    test "sanitizes Erlang OTP paths", %{project_root: project_root} do
      # Simulate an Erlang OTP path
      erlang_path = "/home/user/.asdf/installs/erlang/26.0/lib/kernel-9.0/src/file.erl"
      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(erlang_path, context)
      assert sanitized == "erlang:file"
    end

    test "returns error for external paths without revealing path", %{project_root: project_root} do
      # External path that is not in project, deps, or stdlib
      external_path = "/home/other_user/secret_project/lib/secret.ex"
      context = %{project_root: project_root}

      assert {:error, :external_path} = LSPHandlers.validate_output_path(external_path, context)
    end

    test "returns error for nil path", %{project_root: project_root} do
      context = %{project_root: project_root}
      assert {:error, :external_path} = LSPHandlers.validate_output_path(nil, context)
    end

    test "validates multiple output paths", %{project_root: project_root} do
      # Create some project files
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      File.write!(Path.join(lib_dir, "a.ex"), "defmodule A, do: nil")
      File.write!(Path.join(lib_dir, "b.ex"), "defmodule B, do: nil")

      paths = [
        Path.join(lib_dir, "a.ex"),
        Path.join(lib_dir, "b.ex"),
        "/home/secret/hidden.ex"
      ]

      context = %{project_root: project_root}

      assert {:ok, validated} = LSPHandlers.validate_output_paths(paths, context)
      # External path should be filtered out
      assert length(validated) == 2
      assert "lib/a.ex" in validated
      assert "lib/b.ex" in validated
    end
  end

  # ============================================================================
  # LSP Response Processing Tests (3.4.2.6 - Multiple Definitions)
  # ============================================================================

  describe "LSP response processing" do
    alias JidoCode.Tools.Handlers.LSP.GoToDefinition

    test "processes nil response as not found", %{project_root: project_root} do
      context = %{project_root: project_root}

      assert {:error, :definition_not_found} =
               GoToDefinition.process_lsp_definition_response(nil, context)
    end

    test "processes empty array as not found", %{project_root: project_root} do
      context = %{project_root: project_root}

      assert {:error, :definition_not_found} =
               GoToDefinition.process_lsp_definition_response([], context)
    end

    test "processes single definition", %{project_root: project_root} do
      # Create a file in the project
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_path = Path.join(lib_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      lsp_response = %{
        "uri" => "file://#{file_path}",
        "range" => %{
          "start" => %{"line" => 0, "character" => 10}
        }
      }

      context = %{project_root: project_root}
      assert {:ok, result} = GoToDefinition.process_lsp_definition_response(lsp_response, context)
      assert result["status"] == "found"
      assert result["definition"]["path"] == "lib/my_module.ex"
      # 0-indexed to 1-indexed conversion
      assert result["definition"]["line"] == 1
      assert result["definition"]["character"] == 11
    end

    test "processes multiple definitions", %{project_root: project_root} do
      # Create multiple files in the project
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_a = Path.join(lib_dir, "impl_a.ex")
      file_b = Path.join(lib_dir, "impl_b.ex")
      File.write!(file_a, "defimpl Proto, for: A, do: nil")
      File.write!(file_b, "defimpl Proto, for: B, do: nil")

      lsp_response = [
        %{
          "uri" => "file://#{file_a}",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        },
        %{
          "uri" => "file://#{file_b}",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        }
      ]

      context = %{project_root: project_root}
      assert {:ok, result} = GoToDefinition.process_lsp_definition_response(lsp_response, context)
      assert result["status"] == "found"
      assert is_list(result["definitions"])
      assert length(result["definitions"]) == 2

      paths = Enum.map(result["definitions"], & &1["path"])
      assert "lib/impl_a.ex" in paths
      assert "lib/impl_b.ex" in paths
    end

    test "filters out external paths from multiple definitions", %{project_root: project_root} do
      # Create one file in the project
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_path = Path.join(lib_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      lsp_response = [
        %{
          "uri" => "file://#{file_path}",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        },
        %{
          "uri" => "file:///home/secret/hidden.ex",
          "range" => %{"start" => %{"line" => 5, "character" => 10}}
        }
      ]

      context = %{project_root: project_root}
      assert {:ok, result} = GoToDefinition.process_lsp_definition_response(lsp_response, context)
      assert result["status"] == "found"
      # Multiple definitions filtered to single
      assert result["definition"]["path"] == "lib/my_module.ex"
      refute Map.has_key?(result, "definitions")
    end

    test "returns not found when all definitions are external", %{project_root: project_root} do
      lsp_response = [
        %{
          "uri" => "file:///home/secret/hidden.ex",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        }
      ]

      context = %{project_root: project_root}

      assert {:error, :definition_not_found} =
               GoToDefinition.process_lsp_definition_response(lsp_response, context)
    end

    test "handles stdlib definitions", %{project_root: project_root} do
      # Simulate a stdlib path
      lsp_response = %{
        "uri" => "file:///home/user/.asdf/installs/elixir/1.16.0/lib/elixir/lib/file.ex",
        "range" => %{"start" => %{"line" => 100, "character" => 5}}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = GoToDefinition.process_lsp_definition_response(lsp_response, context)
      assert result["status"] == "found"
      assert result["definition"]["path"] == "elixir:File"
      # Stdlib definitions don't have line/character
      assert result["definition"]["line"] == nil
      assert result["definition"]["character"] == nil
      assert result["definition"]["note"] =~ "standard library"
    end
  end

  # ============================================================================
  # Edge Case Tests (Suggestions from Review)
  # ============================================================================

  describe "edge cases - negative numbers" do
    test "get_hover_info rejects negative line numbers", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call =
        make_tool_call("get_hover_info", %{
          "path" => "test.ex",
          "line" => -1,
          "character" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end

    test "get_hover_info rejects negative character numbers", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call =
        make_tool_call("get_hover_info", %{
          "path" => "test.ex",
          "line" => 1,
          "character" => -5
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end

    test "go_to_definition rejects negative line numbers", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call =
        make_tool_call("go_to_definition", %{
          "path" => "test.ex",
          "line" => -1,
          "character" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end

    test "go_to_definition rejects negative character numbers", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call =
        make_tool_call("go_to_definition", %{
          "path" => "test.ex",
          "line" => 1,
          "character" => -5
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end

    test "find_references rejects negative line numbers", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call =
        make_tool_call("find_references", %{
          "path" => "test.ex",
          "line" => -1,
          "character" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end

    test "find_references rejects negative character numbers", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call =
        make_tool_call("find_references", %{
          "path" => "test.ex",
          "line" => 1,
          "character" => -5
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end
  end

  describe "edge cases - URI handling" do
    alias JidoCode.Tools.Handlers.LSP.GoToDefinition

    test "handles case-insensitive file:// URI", %{project_root: project_root} do
      # Test various case variations
      assert LSPHandlers.uri_to_path("file:///path/to/file.ex") == "/path/to/file.ex"
      assert LSPHandlers.uri_to_path("FILE:///path/to/file.ex") == "/path/to/file.ex"
      assert LSPHandlers.uri_to_path("File:///path/to/file.ex") == "/path/to/file.ex"
      assert LSPHandlers.uri_to_path("fiLe:///path/to/file.ex") == "/path/to/file.ex"
    end

    test "handles URL-encoded paths in URIs", %{project_root: project_root} do
      # Create a file with spaces in the directory name
      space_dir = Path.join(project_root, "lib with spaces")
      File.mkdir_p!(space_dir)
      file_path = Path.join(space_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      # URL-encoded path (spaces become %20)
      encoded_uri = "file://#{URI.encode(file_path)}"
      decoded_path = LSPHandlers.uri_to_path(encoded_uri)

      # Should decode the path correctly
      assert decoded_path == file_path
    end

    test "handles URL-encoded path traversal in LSP response", %{project_root: project_root} do
      # Create a project file for comparison
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_path = Path.join(lib_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      # URL-encoded path traversal attempt: ..%2f..%2fetc%2fpasswd (../../etc/passwd)
      malicious_uri = "file://#{project_root}%2f..%2f..%2fetc%2fpasswd"

      lsp_response = %{
        "uri" => malicious_uri,
        "range" => %{"start" => %{"line" => 0, "character" => 0}}
      }

      context = %{project_root: project_root}
      # Should fail because the decoded path escapes project_root
      assert {:error, :definition_not_found} =
               GoToDefinition.process_lsp_definition_response(lsp_response, context)
    end

    test "non-file URIs are passed through unchanged", %{project_root: _project_root} do
      # Non-file schemes should not be modified
      assert LSPHandlers.uri_to_path("https://example.com/path") == "https://example.com/path"
      assert LSPHandlers.uri_to_path("/absolute/path") == "/absolute/path"
      assert LSPHandlers.uri_to_path("relative/path") == "relative/path"
    end
  end

  describe "edge cases - missing arguments" do
    test "get_hover_info requires line argument", %{project_root: project_root} do
      tool_call =
        make_tool_call("get_hover_info", %{
          "path" => "test.ex",
          "character" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "missing required parameter")
    end

    test "get_hover_info requires character argument", %{project_root: project_root} do
      tool_call =
        make_tool_call("get_hover_info", %{
          "path" => "test.ex",
          "line" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "missing required parameter")
    end

    test "go_to_definition requires line argument", %{project_root: project_root} do
      tool_call =
        make_tool_call("go_to_definition", %{
          "path" => "test.ex",
          "character" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "missing required parameter")
    end

    test "go_to_definition requires character argument", %{project_root: project_root} do
      tool_call =
        make_tool_call("go_to_definition", %{
          "path" => "test.ex",
          "line" => 1
        })

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "missing required parameter")
    end
  end

  describe "edge cases - additional stdlib patterns" do
    test "recognizes mise-installed Elixir paths", %{project_root: project_root} do
      mise_path = "/home/user/.local/share/mise/installs/elixir/1.16.0/lib/elixir/lib/enum.ex"
      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(mise_path, context)
      assert sanitized == "elixir:Enum"
    end

    test "recognizes Nix-installed Elixir paths", %{project_root: project_root} do
      nix_path = "/nix/store/abc123-elixir-1.16.0/lib/elixir/lib/kernel.ex"
      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(nix_path, context)
      assert sanitized == "elixir:Kernel"
    end

    test "recognizes Homebrew-installed Elixir paths", %{project_root: project_root} do
      brew_path = "/opt/homebrew/Cellar/elixir/1.16.0/lib/elixir/lib/string.ex"
      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(brew_path, context)
      assert sanitized == "elixir:String"
    end

    test "recognizes mise-installed Erlang paths", %{project_root: project_root} do
      mise_erlang =
        "/home/user/.local/share/mise/installs/erlang/26.0/lib/kernel-9.0/src/file.erl"

      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(mise_erlang, context)
      assert sanitized == "erlang:file"
    end

    test "recognizes Docker/system Erlang paths", %{project_root: project_root} do
      docker_erlang = "/usr/local/lib/erlang/lib/kernel-9.0/src/gen_server.erl"
      context = %{project_root: project_root}

      assert {:ok, sanitized} = LSPHandlers.validate_output_path(docker_erlang, context)
      assert sanitized == "erlang:gen_server"
    end
  end

  # ============================================================================
  # find_references tests (Section 3.5.1)
  # ============================================================================

  describe "find_references/0 definition" do
    test "has correct schema" do
      tool = Definitions.find_references()
      assert tool.name == "find_references"
      assert tool.description =~ "usage"
      assert length(tool.parameters) == 4

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      line_param = Enum.find(tool.parameters, &(&1.name == "line"))
      char_param = Enum.find(tool.parameters, &(&1.name == "character"))
      incl_decl_param = Enum.find(tool.parameters, &(&1.name == "include_declaration"))

      assert path_param.required == true
      assert path_param.type == :string

      assert line_param.required == true
      assert line_param.type == :integer

      assert char_param.required == true
      assert char_param.type == :integer

      assert incl_decl_param.required == false
      assert incl_decl_param.type == :boolean
    end

    test "generates valid LLM function format" do
      tool = Definitions.find_references()
      llm_fn = JidoCode.Tools.Tool.to_llm_function(tool)

      assert llm_fn.type == "function"
      assert llm_fn.function.name == "find_references"
      assert is_binary(llm_fn.function.description)
      assert is_map(llm_fn.function.parameters)

      # Check parameters schema
      params = llm_fn.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "line")
      assert Map.has_key?(params.properties, "character")
      assert Map.has_key?(params.properties, "include_declaration")
      assert "path" in params.required
      assert "line" in params.required
      assert "character" in params.required
      # include_declaration should NOT be required
      refute "include_declaration" in params.required
    end
  end

  describe "find_references executor integration" do
    test "find_references works via executor for Elixir files", %{project_root: project_root} do
      # Create an Elixir file
      file_path = Path.join(project_root, "test_module.ex")

      File.write!(file_path, """
      defmodule TestModule do
        def hello do
          :world
        end
      end
      """)

      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "test_module.ex", "line" => 2, "character" => 7}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      # Parse the response
      response = Jason.decode!(result.content)
      # Returns lsp_not_available when Expert is not installed
      assert response["status"] == "lsp_not_available"
      assert response["position"]["line"] == 2
      assert response["position"]["character"] == 7
    end

    test "find_references handles non-Elixir files", %{project_root: project_root} do
      # Create a non-Elixir file
      file_path = Path.join(project_root, "readme.txt")
      File.write!(file_path, "This is a readme file")

      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "readme.txt", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      assert response["status"] == "unsupported_file_type"
    end

    test "find_references returns error for non-existent file", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "nonexistent.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "find_references validates required arguments", %{project_root: project_root} do
      # Missing required path argument
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "find_references validates line number", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # Line 0 is invalid (should be 1-indexed)
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "test.ex", "line" => 0, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "find_references validates character number", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # Character 0 is invalid (should be 1-indexed)
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 0}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "find_references include_declaration defaults to false", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      # No include_declaration parameter
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      assert response["include_declaration"] == false
    end

    test "find_references respects include_declaration=true", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{
          "path" => "test.ex",
          "line" => 1,
          "character" => 1,
          "include_declaration" => true
        }
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      assert response["include_declaration"] == true
    end

    test "find_references results can be converted to LLM messages", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_refs",
        name: "find_references",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_refs"
      assert is_binary(message.content)
    end
  end

  describe "find_references security" do
    test "find_references blocks path traversal", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "../../../etc/passwd", "line" => 1, "character" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Security error" or result.content =~ "escapes"
    end

    test "find_references blocks absolute paths outside project", %{project_root: _project_root} do
      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "/etc/passwd", "line" => 1, "character" => 1}
      }

      # Use a different project root to ensure absolute path is outside
      context = %{project_root: "/tmp/test_project"}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
    end
  end

  describe "find_references session-aware context" do
    test "uses session_id when provided", %{project_root: project_root} do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{"path" => "test.ex", "line" => 1, "character" => 1}
      }

      # With an invalid session_id, should fall back or error
      context = %{session_id: "nonexistent_session", project_root: project_root}
      result = Executor.execute(tool_call, context: context)

      # Should work with fallback to project_root
      assert {:ok, _} = result
    end
  end

  # ============================================================================
  # LSP References Response Processing Tests
  # ============================================================================

  describe "LSP references response processing" do
    alias JidoCode.Tools.Handlers.LSP.FindReferences

    test "processes nil response as no references found", %{project_root: project_root} do
      context = %{project_root: project_root}

      assert {:error, :no_references_found} =
               FindReferences.process_lsp_references_response(nil, context)
    end

    test "processes empty array as no references found", %{project_root: project_root} do
      context = %{project_root: project_root}

      assert {:error, :no_references_found} =
               FindReferences.process_lsp_references_response([], context)
    end

    test "processes multiple references", %{project_root: project_root} do
      # Create multiple files in the project
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_a = Path.join(lib_dir, "caller_a.ex")
      file_b = Path.join(lib_dir, "caller_b.ex")
      File.write!(file_a, "defmodule CallerA, do: nil")
      File.write!(file_b, "defmodule CallerB, do: nil")

      lsp_response = [
        %{
          "uri" => "file://#{file_a}",
          "range" => %{"start" => %{"line" => 0, "character" => 10}}
        },
        %{
          "uri" => "file://#{file_b}",
          "range" => %{"start" => %{"line" => 5, "character" => 20}}
        }
      ]

      context = %{project_root: project_root}
      assert {:ok, result} = FindReferences.process_lsp_references_response(lsp_response, context)
      assert result["status"] == "found"
      assert is_list(result["references"])
      assert result["count"] == 2

      paths = Enum.map(result["references"], & &1["path"])
      assert "lib/caller_a.ex" in paths
      assert "lib/caller_b.ex" in paths
    end

    test "filters out external paths from references", %{project_root: project_root} do
      # Create one file in the project
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_path = Path.join(lib_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      lsp_response = [
        %{
          "uri" => "file://#{file_path}",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        },
        %{
          "uri" => "file:///home/secret/hidden.ex",
          "range" => %{"start" => %{"line" => 5, "character" => 10}}
        }
      ]

      context = %{project_root: project_root}
      assert {:ok, result} = FindReferences.process_lsp_references_response(lsp_response, context)
      assert result["status"] == "found"
      assert result["count"] == 1
      assert hd(result["references"])["path"] == "lib/my_module.ex"
    end

    test "filters out stdlib paths from references", %{project_root: project_root} do
      # Create a project file
      lib_dir = Path.join(project_root, "lib")
      File.mkdir_p!(lib_dir)
      file_path = Path.join(lib_dir, "my_module.ex")
      File.write!(file_path, "defmodule MyModule, do: nil")

      lsp_response = [
        %{
          "uri" => "file://#{file_path}",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        },
        %{
          "uri" => "file:///home/user/.asdf/installs/elixir/1.16.0/lib/elixir/lib/enum.ex",
          "range" => %{"start" => %{"line" => 100, "character" => 5}}
        }
      ]

      context = %{project_root: project_root}
      assert {:ok, result} = FindReferences.process_lsp_references_response(lsp_response, context)
      # Stdlib reference should be filtered out
      assert result["count"] == 1
      assert hd(result["references"])["path"] == "lib/my_module.ex"
    end

    test "returns no references when all are external or stdlib", %{project_root: project_root} do
      lsp_response = [
        %{
          "uri" => "file:///home/secret/hidden.ex",
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        },
        %{
          "uri" => "file:///home/user/.asdf/installs/elixir/1.16.0/lib/elixir/lib/enum.ex",
          "range" => %{"start" => %{"line" => 100, "character" => 5}}
        }
      ]

      context = %{project_root: project_root}

      assert {:error, :no_references_found} =
               FindReferences.process_lsp_references_response(lsp_response, context)
    end

    test "includes deps paths in references", %{project_root: project_root} do
      # Create a deps file
      deps_dir = Path.join(project_root, "deps/jason/lib")
      File.mkdir_p!(deps_dir)
      deps_file = Path.join(deps_dir, "jason.ex")
      File.write!(deps_file, "defmodule Jason, do: nil")

      lsp_response = [
        %{
          "uri" => "file://#{deps_file}",
          "range" => %{"start" => %{"line" => 10, "character" => 5}}
        }
      ]

      context = %{project_root: project_root}
      assert {:ok, result} = FindReferences.process_lsp_references_response(lsp_response, context)
      assert result["count"] == 1
      assert hd(result["references"])["path"] == "deps/jason/lib/jason.ex"
    end

    test "handles invalid location structure (missing uri)", %{project_root: project_root} do
      # Location without "uri" key should be filtered out
      lsp_response = [
        %{
          "range" => %{"start" => %{"line" => 0, "character" => 0}}
        }
      ]

      context = %{project_root: project_root}

      assert {:error, :no_references_found} =
               FindReferences.process_lsp_references_response(lsp_response, context)
    end
  end

  # ============================================================================
  # include_declaration parameter validation tests (Concern 4)
  # ============================================================================

  describe "find_references include_declaration parameter validation" do
    test "rejects string value for include_declaration (must be boolean)", %{
      project_root: project_root
    } do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{
          "path" => "test.ex",
          "line" => 1,
          "character" => 1,
          "include_declaration" => "true"
        }
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      # Executor validates schema - string is rejected for boolean parameter
      assert result.status == :error
      assert result.content =~ "must be a boolean"
    end

    test "rejects integer value for include_declaration (must be boolean)", %{
      project_root: project_root
    } do
      file_path = Path.join(project_root, "test.ex")
      File.write!(file_path, "defmodule Test, do: nil")

      tool_call = %{
        id: "call_123",
        name: "find_references",
        arguments: %{
          "path" => "test.ex",
          "line" => 1,
          "character" => 1,
          "include_declaration" => 1
        }
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      # Executor validates schema - integer is rejected for boolean parameter
      assert result.status == :error
      assert result.content =~ "must be a boolean"
    end
  end

  # ============================================================================
  # Shared helper tests (new in review fixes)
  # ============================================================================

  describe "shared LSP helpers" do
    test "stdlib_path? detects Elixir stdlib paths" do
      assert LSPHandlers.stdlib_path?("elixir:File")
      assert LSPHandlers.stdlib_path?("elixir:Enum")
      assert LSPHandlers.stdlib_path?("elixir:Kernel")
      refute LSPHandlers.stdlib_path?("lib/my_module.ex")
      refute LSPHandlers.stdlib_path?("deps/jason/lib/jason.ex")
    end

    test "stdlib_path? detects Erlang OTP paths" do
      assert LSPHandlers.stdlib_path?("erlang:gen_server")
      assert LSPHandlers.stdlib_path?("erlang:file")
      refute LSPHandlers.stdlib_path?("lib/my_module.ex")
    end

    test "stdlib_path? handles non-binary input" do
      refute LSPHandlers.stdlib_path?(nil)
      refute LSPHandlers.stdlib_path?(123)
      refute LSPHandlers.stdlib_path?(%{})
    end

    test "get_line_from_location extracts and converts 0-indexed line" do
      location = %{"range" => %{"start" => %{"line" => 0, "character" => 5}}}
      assert LSPHandlers.get_line_from_location(location) == 1

      location = %{"range" => %{"start" => %{"line" => 99, "character" => 5}}}
      assert LSPHandlers.get_line_from_location(location) == 100
    end

    test "get_line_from_location returns 1 for invalid structure" do
      assert LSPHandlers.get_line_from_location(%{}) == 1
      assert LSPHandlers.get_line_from_location(%{"range" => %{}}) == 1
      assert LSPHandlers.get_line_from_location(%{"range" => %{"start" => %{}}}) == 1
      assert LSPHandlers.get_line_from_location(nil) == 1
    end

    test "get_character_from_location extracts and converts 0-indexed character" do
      location = %{"range" => %{"start" => %{"line" => 5, "character" => 0}}}
      assert LSPHandlers.get_character_from_location(location) == 1

      location = %{"range" => %{"start" => %{"line" => 5, "character" => 49}}}
      assert LSPHandlers.get_character_from_location(location) == 50
    end

    test "get_character_from_location returns 1 for invalid structure" do
      assert LSPHandlers.get_character_from_location(%{}) == 1
      assert LSPHandlers.get_character_from_location(%{"range" => %{}}) == 1
      assert LSPHandlers.get_character_from_location(%{"range" => %{"start" => %{}}}) == 1
      assert LSPHandlers.get_character_from_location(nil) == 1
    end
  end

  # ============================================================================
  # get_diagnostics tests (Section 3.2.1)
  # ============================================================================

  describe "get_diagnostics/0 definition" do
    test "has correct schema" do
      tool = Definitions.get_diagnostics()
      assert tool.name == "get_diagnostics"
      assert tool.description =~ "diagnostics"
      assert length(tool.parameters) == 3

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      severity_param = Enum.find(tool.parameters, &(&1.name == "severity"))
      limit_param = Enum.find(tool.parameters, &(&1.name == "limit"))

      # All parameters are optional
      assert path_param.required == false
      assert path_param.type == :string

      assert severity_param.required == false
      assert severity_param.type == :string
      assert severity_param.enum == ["error", "warning", "info", "hint"]

      assert limit_param.required == false
      assert limit_param.type == :integer
    end

    test "generates valid LLM function format" do
      tool = Definitions.get_diagnostics()
      llm_fn = JidoCode.Tools.Tool.to_llm_function(tool)

      assert llm_fn.type == "function"
      assert llm_fn.function.name == "get_diagnostics"
      assert is_binary(llm_fn.function.description)
      assert is_map(llm_fn.function.parameters)

      # Check parameters schema
      params = llm_fn.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "severity")
      assert Map.has_key?(params.properties, "limit")

      # No required parameters
      assert params.required == []
    end
  end

  describe "get_diagnostics executor integration" do
    test "get_diagnostics works via executor with no parameters", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      # Returns lsp_not_available when Expert is not installed
      assert response["status"] == "lsp_not_configured"
      assert response["diagnostics"] == []
      assert response["count"] == 0
    end

    test "get_diagnostics works via executor for specific file", %{project_root: project_root} do
      # Create an Elixir file
      file_path = Path.join(project_root, "test_module.ex")
      File.write!(file_path, "defmodule TestModule, do: nil")

      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"path" => "test_module.ex"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      response = Jason.decode!(result.content)
      # Returns lsp_not_available when Expert is not installed
      assert response["status"] == "lsp_not_configured"
    end

    test "get_diagnostics returns error for non-existent file", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"path" => "nonexistent.ex"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "get_diagnostics validates severity parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"severity" => "invalid"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Invalid severity"
    end

    test "get_diagnostics accepts valid severity values", %{project_root: project_root} do
      for severity <- ["error", "warning", "info", "hint"] do
        tool_call = %{
          id: "call_123",
          name: "get_diagnostics",
          arguments: %{"severity" => severity}
        }

        context = %{project_root: project_root}
        assert {:ok, result} = Executor.execute(tool_call, context: context)
        assert result.status == :ok
      end
    end

    test "get_diagnostics validates limit parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"limit" => 0}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "positive integer"
    end

    test "get_diagnostics accepts positive limit", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"limit" => 10}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok
    end

    test "get_diagnostics results can be converted to LLM messages", %{project_root: project_root} do
      tool_call = %{
        id: "call_diag",
        name: "get_diagnostics",
        arguments: %{}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_diag"
      assert is_binary(message.content)
    end
  end

  describe "get_diagnostics security" do
    test "get_diagnostics blocks path traversal", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"path" => "../../../etc/passwd"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Security error" or result.content =~ "escapes"
    end

    test "get_diagnostics blocks absolute paths outside project", %{project_root: _project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"path" => "/etc/passwd"}
      }

      # Use a different project root to ensure absolute path is outside
      context = %{project_root: "/tmp/test_project"}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
    end
  end

  describe "get_diagnostics session-aware context" do
    test "uses session_id when provided", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{}
      }

      # With an invalid session_id, should fall back or error
      context = %{session_id: "nonexistent_session", project_root: project_root}
      result = Executor.execute(tool_call, context: context)

      # Should work with fallback to project_root
      assert {:ok, _} = result
    end
  end

  describe "get_diagnostics edge cases" do
    test "rejects negative limit", %{project_root: project_root} do
      tool_call =
        make_tool_call("get_diagnostics", %{"limit" => -5})

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "positive integer")
    end

    test "rejects non-integer limit", %{project_root: project_root} do
      tool_call =
        make_tool_call("get_diagnostics", %{"limit" => "ten"})

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "integer")
    end

    test "rejects non-string severity", %{project_root: project_root} do
      tool_call =
        make_tool_call("get_diagnostics", %{"severity" => 1})

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "string")
    end

    test "rejects non-string path", %{project_root: project_root} do
      tool_call =
        make_tool_call("get_diagnostics", %{"path" => 123})

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert_error_result(result, "string")
    end
  end
end
