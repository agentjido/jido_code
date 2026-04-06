defmodule JidoCode.KGBackendTest do
  use ExUnit.Case, async: true

  alias JidoCode.KG.MemoryBackend

  describe "KG.Adapter behaviour" do
    test "defines required callbacks" do
      # Behaviours define callbacks, not functions
      # We verify implementations provide the required functions
      assert function_exported?(MemoryBackend, :query, 2)
      assert function_exported?(MemoryBackend, :update, 3)
      assert function_exported?(MemoryBackend, :explore, 2)
    end
  end

  describe "MemoryBackend" do
    test "has required callbacks" do
      assert function_exported?(MemoryBackend, :start_link, 0)
      assert function_exported?(MemoryBackend, :stop_link, 0)
    end

    test "query returns results" do
      {:ok, _pid} = MemoryBackend.start_link()
      {:ok, results} = MemoryBackend.query("SELECT *", limit: 10)
      MemoryBackend.stop_link()

      assert is_list(results)
    end

    test "update accepts operations" do
      {:ok, _pid} = MemoryBackend.start_link()
      assert :ok = MemoryBackend.update(:add_facts, [{"file", "type", "module"}], [])
      MemoryBackend.stop_link()
    end
  end

  describe "MockAdapter" do
    test "has required callbacks" do
      assert function_exported?(JidoCode.KG.MockAdapter, :start_link, 0)
      assert function_exported?(JidoCode.KG.MockAdapter, :stop_link, 0)
    end

    test "query returns mock results" do
      assert {:ok, _pid} = JidoCode.KG.MockAdapter.start_link()

      {:ok, results} = JidoCode.KG.MockAdapter.query("SELECT *", file: "test.ex")
      assert is_list(results)

      JidoCode.KG.MockAdapter.stop_link()
    end

    test "update always succeeds" do
      assert {:ok, _pid} = JidoCode.KG.MockAdapter.start_link()
      assert {:ok, _, _} = JidoCode.KG.MockAdapter.update(:index, [], [])
      JidoCode.KG.MockAdapter.stop_link()
    end
  end
end
