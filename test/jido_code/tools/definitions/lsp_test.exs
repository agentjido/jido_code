defmodule JidoCode.Tools.Definitions.LSPTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}
  alias JidoCode.Tools.Definitions.LSP, as: Definitions

  @moduletag :tmp_dir

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
      assert length(tools) == 2

      names = Enum.map(tools, & &1.name)
      assert "get_hover_info" in names
      assert "go_to_definition" in names
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
      # Currently returns lsp_not_configured since LSP client isn't implemented
      assert response["status"] == "lsp_not_configured"
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
      # Currently returns lsp_not_configured since LSP client isn't implemented
      assert response["status"] == "lsp_not_configured"
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

    test "go_to_definition results can be converted to LLM messages", %{project_root: project_root} do
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
      assert {:error, :definition_not_found} = GoToDefinition.process_lsp_definition_response(nil, context)
    end

    test "processes empty array as not found", %{project_root: project_root} do
      context = %{project_root: project_root}
      assert {:error, :definition_not_found} = GoToDefinition.process_lsp_definition_response([], context)
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
      assert {:error, :definition_not_found} = GoToDefinition.process_lsp_definition_response(lsp_response, context)
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
end
