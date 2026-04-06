defmodule JidoCode.KGIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCode.KG.{Parser, Indexer}
  alias JidoCode.KG.MemoryBackend
  alias JidoCode.Actions.{KGQuery, KGExplore, KGUpdate}

  @tmp_dir Path.join(System.tmp_dir!(), "kg_integration_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)

    {:ok, _pid} = MemoryBackend.start_link()

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
      MemoryBackend.stop_link()
    end)

    :ok
  end

  describe "KG Query Integration" do
    test "queries return indexed code structure" do
      # Create test files
      File.write!(Path.join(@tmp_dir, "user.ex"), """
      defmodule MyApp.User do
        def create(attrs), do: :ok
        def update(id, attrs), do: :ok
      end
      """)

      File.write!(Path.join(@tmp_dir, "post.ex"), """
      defmodule MyApp.Post do
        def create(attrs), do: :ok
        def get_user_posts(user_id), do: []
      end
      """)

      # Index the files
      {:ok, _} = Indexer.index_directory(@tmp_dir, backend: MemoryBackend)

      # Query for modules
      {:ok, result} = KGQuery.run(%{
        sparql: "SELECT *",
        limit: 100,
        backend: MemoryBackend
      }, %{})

      assert %{results: results, count: count} = result
      assert is_list(results)
      assert count > 0
    end

    test "KGQuery action works with backend" do
      {:ok, result} = KGQuery.run(%{
        sparql: "SELECT *",
        limit: 10,
        backend: MemoryBackend
      }, %{})

      assert %{results: _, count: _} = result
    end
  end

  describe "KG Explore Integration" do
    test "KGExplore finds relationships" do
      # Create test files with relationships
      File.write!(Path.join(@tmp_dir, "service.ex"), """
      defmodule MyApp.Service do
        def process(data) do
          MyApp.Helper.format(data)
        end
      end
      """)

      File.write!(Path.join(@tmp_dir, "helper.ex"), """
      defmodule MyApp.Helper do
        def format(data), do: data
      end
      """)

      # Index the files
      {:ok, _} = Indexer.index_directory(@tmp_dir, backend: MemoryBackend)

      # Explore from Service module
      {:ok, result} = KGExplore.run(%{
        start_node: "MyApp.Service",
        direction: :both,
        depth: 2,
        backend: MemoryBackend
      }, %{})

      assert %{start_node: "MyApp.Service", results: results} = result
      assert is_list(results)
    end
  end

  describe "KG Update Integration" do
    test "reindexing updates the KG" do
      file_path = Path.join(@tmp_dir, "reindex_test.ex")

      # Create initial file
      File.write!(file_path, """
      defmodule ReindexTest do
        def old_func, do: :old
      end
      """)

      # Index it
      {:ok, result1} = Indexer.index_file(file_path, backend: MemoryBackend)
      assert result1.functions >= 1

      # Update the file
      File.write!(file_path, """
      defmodule ReindexTest do
        def old_func, do: :old
        def new_func, do: :new
      end
      """)

      # Reindex
      {:ok, result2} = Indexer.reindex_file(file_path, backend: MemoryBackend)
      assert result2.functions >= 1
    end

    test "KGUpdate action triggers reindex" do
      file_path = Path.join(@tmp_dir, "update_test.ex")
      File.write!(file_path, "defmodule UpdateTest, do: def test, do: :ok")

      # Use KGUpdate to index
      {:ok, result} = KGUpdate.run(%{
        operation: :add_facts,
        data: [{file_path, :defines, "UpdateTest"}],
        backend: MemoryBackend
      }, %{})

      assert result.status == :ok
    end
  end

  describe "End-to-End Scenarios" do
    test "index and query a multi-module project" do
      # Create a small project structure
      File.write!(Path.join(@tmp_dir, "account.ex"), """
      defmodule MyApp.Account do
        defstruct [:id, :balance]

        def open(attrs) do
          %__MODULE__{id: generate_id(), balance: 0}
        end

        def deposit(%__MODULE__{} = account, amount) do
          %{account | balance: account.balance + amount}
        end

        defp generate_id, do: UUID.uuid4()
      end
      """)

      File.write!(Path.join(@tmp_dir, "transaction.ex"), """
      defmodule MyApp.Transaction do
        def execute(account, amount) do
          MyApp.Account.deposit(account, amount)
        end
      end
      """)

      # Index the project
      {:ok, index_result} = Indexer.index_directory(@tmp_dir, backend: MemoryBackend)
      assert index_result.total == 2
      assert index_result.indexed == 2

      # Query for all modules
      {:ok, query_result} = KGQuery.run(%{
        sparql: "SELECT *",
        limit: 100,
        backend: MemoryBackend
      }, %{})

      assert query_result.count > 0
    end

    test "parser extracts complex code structure" do
      code = """
      defmodule ComplexModule do
        @moduledoc "A complex module"

        alias MyApp.Helper

        def public_function(x, y \\\\ nil) do
          private_function(x)
          Helper.external_call(y)
        end

        defp private_function(x), do: x * 2

        def with_guard(x) when is_integer(x), do: x
      end
      """

      assert {:ok, result} = Parser.parse_string(code)

      # Should extract the module
      assert "ComplexModule" in result.modules

      # Should extract functions
      public_funcs = Enum.filter(result.functions, fn f -> f.kind == :def end)
      private_funcs = Enum.filter(result.functions, fn f -> f.kind == :defp end)

      assert length(public_funcs) >= 2  # public_function and with_guard
      assert length(private_funcs) >= 1  # private_function

      # Should extract calls
      assert length(result.calls) > 0
    end
  end
end
