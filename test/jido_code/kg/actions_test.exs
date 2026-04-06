defmodule JidoCode.KGActionsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Actions.KGQuery
  alias JidoCode.Actions.KGUpdate
  alias JidoCode.Actions.KGExplore
  alias JidoCode.KG.MockAdapter

  @mock_backend JidoCode.KG.MockAdapter

  describe "KGQuery" do
    test "executes SPARQL query against KG backend" do
      {:ok, _pid} = MockAdapter.start_link()

      params = %{
        sparql: "SELECT *",
        limit: 10,
        backend: @mock_backend
      }

      assert {:ok, result} = KGQuery.run(params, %{})
      assert %{results: results, count: count} = result
      assert is_list(results)
      assert is_integer(count)
      assert count > 0

      MockAdapter.stop_link()
    end

    test "queries by file pattern" do
      {:ok, _pid} = MockAdapter.start_link()

      params = %{
        sparql: "SELECT file:lib/test.ex",
        limit: 10,
        backend: @mock_backend
      }

      assert {:ok, result} = KGQuery.run(params, %{})
      assert %{results: results} = result
      assert is_list(results)

      MockAdapter.stop_link()
    end
  end

  describe "KGUpdate" do
    test "adds facts to KG" do
      {:ok, _pid} = MockAdapter.start_link()

      params = %{
        operation: :add_facts,
        data: [{"file.ex", :defines, "MyModule"}],
        backend: @mock_backend
      }

      assert {:ok, result} = KGUpdate.run(params, %{})
      assert result.status == :ok
      assert result.operation == :add_facts

      MockAdapter.stop_link()
    end

    test "triggers index operation" do
      {:ok, _pid} = MockAdapter.start_link()

      params = %{
        operation: :index,
        data: [],
        backend: @mock_backend
      }

      assert {:ok, result} = KGUpdate.run(params, %{})
      assert result.operation == :index

      MockAdapter.stop_link()
    end
  end

  describe "KGExplore" do
    test "explores relationships from start node" do
      {:ok, _pid} = MockAdapter.start_link()

      params = %{
        start_node: "lib/jido_code/web/router.ex",
        direction: :both,
        depth: 2,
        backend: @mock_backend
      }

      assert {:ok, result} = KGExplore.run(params, %{})
      assert %{
        start_node: start_node,
        results: results,
        count: count
      } = result
      assert start_node == "lib/jido_code/web/router.ex"
      assert is_list(results)
      assert count > 0

      MockAdapter.stop_link()
    end

    test "supports different exploration directions" do
      {:ok, _pid} = MockAdapter.start_link()

      for direction <- [:in, :out, :both] do
        params = %{
          start_node: "lib/file.ex",
          direction: direction,
          depth: 1,
          backend: @mock_backend
        }

        assert {:ok, _result} = KGExplore.run(params, %{})
      end

      MockAdapter.stop_link()
    end
  end
end

