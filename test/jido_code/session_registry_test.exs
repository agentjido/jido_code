defmodule JidoCode.SessionRegistryTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
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

  # Helper to create a valid session for testing
  defp create_test_session(opts \\ []) do
    now = DateTime.utc_now()
    id = Keyword.get(opts, :id, Session.generate_id())
    name = Keyword.get(opts, :name, "test-project")
    project_path = Keyword.get(opts, :project_path, "/tmp/test-project-#{:rand.uniform(100_000)}")

    %Session{
      id: id,
      name: name,
      project_path: project_path,
      config: %{
        provider: "anthropic",
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      },
      created_at: now,
      updated_at: now
    }
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

  describe "count/0" do
    test "returns 0 when table is empty" do
      SessionRegistry.create_table()
      assert SessionRegistry.count() == 0
    end

    test "returns 0 when table does not exist" do
      assert SessionRegistry.count() == 0
    end

    test "returns correct count after registrations" do
      SessionRegistry.create_table()

      {:ok, _} = SessionRegistry.register(create_test_session())
      assert SessionRegistry.count() == 1

      {:ok, _} = SessionRegistry.register(create_test_session())
      assert SessionRegistry.count() == 2

      {:ok, _} = SessionRegistry.register(create_test_session())
      assert SessionRegistry.count() == 3
    end
  end

  describe "register/1" do
    setup do
      SessionRegistry.create_table()
      :ok
    end

    test "registers a valid session successfully" do
      session = create_test_session()

      assert {:ok, registered} = SessionRegistry.register(session)
      assert registered.id == session.id
      assert registered.name == session.name
      assert registered.project_path == session.project_path
    end

    test "returns the same session struct on success" do
      session = create_test_session()

      {:ok, registered} = SessionRegistry.register(session)
      assert registered == session
    end

    test "increments count after successful registration" do
      session = create_test_session()

      assert SessionRegistry.count() == 0
      {:ok, _} = SessionRegistry.register(session)
      assert SessionRegistry.count() == 1
    end

    test "session can be found in ETS table after registration" do
      session = create_test_session()

      {:ok, _} = SessionRegistry.register(session)

      [{id, stored}] = :ets.lookup(JidoCode.SessionRegistry, session.id)
      assert id == session.id
      assert stored == session
    end

    test "returns error for duplicate session ID" do
      session1 = create_test_session(id: "same-id", project_path: "/tmp/project1")
      session2 = create_test_session(id: "same-id", project_path: "/tmp/project2")

      {:ok, _} = SessionRegistry.register(session1)
      assert {:error, :session_exists} = SessionRegistry.register(session2)
    end

    test "returns error for duplicate project_path" do
      session1 = create_test_session(project_path: "/tmp/same-project")
      session2 = create_test_session(project_path: "/tmp/same-project")

      {:ok, _} = SessionRegistry.register(session1)
      assert {:error, :project_already_open} = SessionRegistry.register(session2)
    end

    test "returns error when session limit (10) is reached" do
      # Register 10 sessions
      for i <- 1..10 do
        session = create_test_session(project_path: "/tmp/project-#{i}")
        {:ok, _} = SessionRegistry.register(session)
      end

      assert SessionRegistry.count() == 10

      # 11th session should fail
      session11 = create_test_session(project_path: "/tmp/project-11")
      assert {:error, :session_limit_reached} = SessionRegistry.register(session11)
    end

    test "does not increment count when registration fails" do
      session1 = create_test_session(id: "same-id", project_path: "/tmp/project1")
      session2 = create_test_session(id: "same-id", project_path: "/tmp/project2")

      {:ok, _} = SessionRegistry.register(session1)
      assert SessionRegistry.count() == 1

      {:error, :session_exists} = SessionRegistry.register(session2)
      assert SessionRegistry.count() == 1
    end

    test "allows different sessions with same name" do
      session1 = create_test_session(name: "same-name", project_path: "/tmp/project1")
      session2 = create_test_session(name: "same-name", project_path: "/tmp/project2")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)

      assert SessionRegistry.count() == 2
    end

    test "can register up to exactly 10 sessions" do
      sessions =
        for i <- 1..10 do
          session = create_test_session(project_path: "/tmp/project-#{i}")
          {:ok, registered} = SessionRegistry.register(session)
          registered
        end

      assert length(sessions) == 10
      assert SessionRegistry.count() == 10
    end

    test "checks session limit before duplicate ID" do
      # Fill up to limit
      for i <- 1..10 do
        session = create_test_session(project_path: "/tmp/project-#{i}")
        {:ok, _} = SessionRegistry.register(session)
      end

      # Get the ID of an existing session
      [{existing_id, _}] = :ets.lookup(JidoCode.SessionRegistry, :ets.first(JidoCode.SessionRegistry))

      # Try to register with same ID - should hit limit first
      session = create_test_session(id: existing_id, project_path: "/tmp/project-11")
      assert {:error, :session_limit_reached} = SessionRegistry.register(session)
    end

    test "checks duplicate ID before duplicate path" do
      session1 = create_test_session(id: "same-id", project_path: "/tmp/same-path")

      {:ok, _} = SessionRegistry.register(session1)

      # Same ID and same path - should report ID error first
      session2 = create_test_session(id: "same-id", project_path: "/tmp/same-path")
      assert {:error, :session_exists} = SessionRegistry.register(session2)
    end
  end
end
