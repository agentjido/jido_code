defmodule JidoCode.KGIndexerTest do
  use ExUnit.Case, async: true

  alias JidoCode.KG.Parser
  alias JidoCode.KG.Indexer
  alias JidoCode.KG.MockAdapter

  describe "Parser" do
    test "extracts module definition" do
      code = """
      defmodule MyApp.User do
        def hello, do: "world"
      end
      """

      assert {:ok, result} = Parser.parse_string(code)
      assert "MyApp.User" in result.modules
      assert length(result.modules) == 1
    end

    test "extracts public functions" do
      code = """
      defmodule MyApp.User do
        def hello(name), do: "Hello, \#{name}"
        def goodbye, do: "Goodbye"
      end
      """

      assert {:ok, result} = Parser.parse_string(code)
      assert length(result.functions) == 2

      function_names = Enum.map(result.functions, & &1.name)
      assert :hello in function_names
      assert :goodbye in function_names
    end

    test "extracts private functions" do
      code = """
      defmodule MyApp.User do
        defp helper, do: "help"
      end
      """

      assert {:ok, result} = Parser.parse_string(code)
      assert length(result.functions) == 1

      [func] = result.functions
      assert func.name == :helper
      assert func.kind == :defp
    end

    test "extracts function with guard" do
      code = """
      defmodule MyApp.User do
        def process(x) when is_integer(x), do: x * 2
      end
      """

      assert {:ok, result} = Parser.parse_string(code)
      assert length(result.functions) == 1

      [func] = result.functions
      assert func.name == :process
      assert func.arity == 1
    end

    test "extracts external function calls" do
      code = """
      defmodule MyApp.User do
        def create do
          IO.puts("Creating user")
          Enum.map([1, 2], fn x -> x * 2 end)
        end
      end
      """

      assert {:ok, result} = Parser.parse_string(code)
      assert length(result.calls) > 0

      # Check for IO.puts call
      io_call = Enum.find(result.calls, fn c ->
        c.to_function == :puts or c.to_module == "IO"
      end)
      assert io_call != nil
    end

    test "handles parse errors gracefully" do
      code = """
      defmodule Broken do
        def broken(
      """

      assert {:error, :parse_error, _msg} = Parser.parse_string(code)
    end
  end

  describe "Indexer" do
    test "indexes a single file" do
      {:ok, _pid} = MockAdapter.start_link()

      # Create a temporary file
      tmp_dir = tmp_dir!()
      file_path = Path.join(tmp_dir, "test_module.ex")

      File.write!(file_path, """
      defmodule TestModule do
        def test_func, do: :ok
      end
      """)

      assert {:ok, result} = Indexer.index_file(file_path, backend: MockAdapter)
      assert result.modules == 1
      assert result.functions >= 1

      File.rm_rf!(tmp_dir)
      MockAdapter.stop_link()
    end

    test "indexes all files in a directory" do
      {:ok, _pid} = MockAdapter.start_link()

      tmp_dir = tmp_dir!()

      # Create multiple files
      File.write!(Path.join(tmp_dir, "file1.ex"), "defmodule M1, do: def f, do: 1")
      File.write!(Path.join(tmp_dir, "file2.ex"), "defmodule M2, do: def g, do: 2")

      assert {:ok, result} = Indexer.index_directory(tmp_dir, backend: MockAdapter)
      assert result.total == 2
      assert result.indexed == 2

      File.rm_rf!(tmp_dir)
      MockAdapter.stop_link()
    end
  end

  defp tmp_dir! do
    path = Path.join(System.tmp_dir!(), "kg_test_#{System.unique_integer()}")
    File.mkdir_p!(path)
    path
  end
end
