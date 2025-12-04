defmodule JidoCode.SessionRegistryTest do
  use ExUnit.Case, async: false

  alias JidoCode.SessionRegistry

  # Note: async: false because ETS tables are shared state

  setup do
    # Clean up any existing table before each test
    if SessionRegistry.table_exists?() do
      :ets.delete(JidoCode.SessionRegistry)
    end

    on_exit(fn ->
      # Clean up after test
      if SessionRegistry.table_exists?() do
        :ets.delete(JidoCode.SessionRegistry)
      end
    end)

    :ok
  end

  describe "table_exists?/0" do
    test "returns false when table does not exist" do
      refute SessionRegistry.table_exists?()
    end

    test "returns true when table exists" do
      SessionRegistry.create_table()
      assert SessionRegistry.table_exists?()
    end
  end

  describe "create_table/0" do
    test "creates ETS table successfully" do
      refute SessionRegistry.table_exists?()

      assert :ok = SessionRegistry.create_table()
      assert SessionRegistry.table_exists?()
    end

    test "is idempotent - can be called multiple times" do
      assert :ok = SessionRegistry.create_table()
      assert :ok = SessionRegistry.create_table()
      assert :ok = SessionRegistry.create_table()

      assert SessionRegistry.table_exists?()
    end

    test "creates table with correct name" do
      SessionRegistry.create_table()

      # Table should be named JidoCode.SessionRegistry
      assert :ets.whereis(JidoCode.SessionRegistry) != :undefined
    end

    test "creates table as :set type" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :type) == :set
    end

    test "creates table as :named_table" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :named_table) == true
    end

    test "creates table with :public protection" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :protection) == :public
    end

    test "creates table with read_concurrency enabled" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :read_concurrency) == true
    end
  end

  describe "max_sessions/0" do
    test "returns 10" do
      assert SessionRegistry.max_sessions() == 10
    end
  end

  describe "table is empty after creation" do
    test "table starts empty" do
      SessionRegistry.create_table()

      entries = :ets.tab2list(JidoCode.SessionRegistry)
      assert entries == []
    end

    test "table size is 0 after creation" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :size) == 0
    end
  end
end
