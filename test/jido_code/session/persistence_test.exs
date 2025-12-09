defmodule JidoCode.Session.PersistenceTest do
  use ExUnit.Case, async: true

  alias JidoCode.Session.Persistence

  describe "schema_version/0" do
    test "returns current schema version" do
      assert Persistence.schema_version() == 1
    end

    test "returns a positive integer" do
      version = Persistence.schema_version()
      assert is_integer(version)
      assert version > 0
    end
  end

  describe "validate_session/1" do
    test "validates complete session map with atom keys" do
      session = valid_session()
      assert {:ok, ^session} = Persistence.validate_session(session)
    end

    test "validates session map with string keys" do
      session = %{
        "version" => 1,
        "id" => "test-123",
        "name" => "Test Session",
        "project_path" => "/path/to/project",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z",
        "closed_at" => "2024-01-01T00:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      assert {:ok, _} = Persistence.validate_session(session)
    end

    test "returns error for missing required fields" do
      session = %{version: 1, id: "test"}
      assert {:error, {:missing_fields, missing}} = Persistence.validate_session(session)
      assert :name in missing
      assert :project_path in missing
      assert :config in missing
    end

    test "returns error for invalid version" do
      session = valid_session() |> Map.put(:version, 0)
      assert {:error, {:invalid_version, 0}} = Persistence.validate_session(session)
    end

    test "returns error for non-integer version" do
      session = valid_session() |> Map.put(:version, "1")
      assert {:error, {:invalid_version, "1"}} = Persistence.validate_session(session)
    end

    test "returns error for invalid id type" do
      session = valid_session() |> Map.put(:id, 123)
      assert {:error, {:invalid_id, 123}} = Persistence.validate_session(session)
    end

    test "returns error for invalid name type" do
      session = valid_session() |> Map.put(:name, nil)
      assert {:error, {:invalid_name, nil}} = Persistence.validate_session(session)
    end

    test "returns error for invalid project_path type" do
      session = valid_session() |> Map.put(:project_path, 123)
      assert {:error, {:invalid_project_path, 123}} = Persistence.validate_session(session)
    end

    test "returns error for invalid config type" do
      session = valid_session() |> Map.put(:config, "invalid")
      assert {:error, {:invalid_config, "invalid"}} = Persistence.validate_session(session)
    end

    test "returns error for invalid conversation type" do
      session = valid_session() |> Map.put(:conversation, "invalid")
      assert {:error, {:invalid_conversation, "invalid"}} = Persistence.validate_session(session)
    end

    test "returns error for invalid todos type" do
      session = valid_session() |> Map.put(:todos, "invalid")
      assert {:error, {:invalid_todos, "invalid"}} = Persistence.validate_session(session)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Persistence.validate_session("invalid")
      assert {:error, :not_a_map} = Persistence.validate_session(nil)
      assert {:error, :not_a_map} = Persistence.validate_session([])
    end
  end

  describe "validate_message/1" do
    test "validates complete message map" do
      message = valid_message()
      assert {:ok, ^message} = Persistence.validate_message(message)
    end

    test "validates message with string keys" do
      message = %{
        "id" => "msg-1",
        "role" => "user",
        "content" => "Hello",
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:ok, _} = Persistence.validate_message(message)
    end

    test "accepts all valid roles" do
      for role <- ["user", "assistant", "system"] do
        message = valid_message() |> Map.put(:role, role)
        assert {:ok, _} = Persistence.validate_message(message)
      end
    end

    test "returns error for unknown role" do
      message = valid_message() |> Map.put(:role, "unknown")
      assert {:error, {:unknown_role, "unknown"}} = Persistence.validate_message(message)
    end

    test "returns error for missing required fields" do
      message = %{id: "msg-1"}
      assert {:error, {:missing_fields, missing}} = Persistence.validate_message(message)
      assert :role in missing
      assert :content in missing
      assert :timestamp in missing
    end

    test "returns error for invalid id type" do
      message = valid_message() |> Map.put(:id, 123)
      assert {:error, {:invalid_id, 123}} = Persistence.validate_message(message)
    end

    test "returns error for invalid role type" do
      message = valid_message() |> Map.put(:role, :user)
      assert {:error, {:invalid_role, :user}} = Persistence.validate_message(message)
    end

    test "returns error for invalid content type" do
      message = valid_message() |> Map.put(:content, nil)
      assert {:error, {:invalid_content, nil}} = Persistence.validate_message(message)
    end

    test "returns error for invalid timestamp type" do
      message = valid_message() |> Map.put(:timestamp, ~U[2024-01-01 00:00:00Z])
      assert {:error, {:invalid_timestamp, _}} = Persistence.validate_message(message)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Persistence.validate_message("invalid")
    end
  end

  describe "validate_todo/1" do
    test "validates complete todo map" do
      todo = valid_todo()
      assert {:ok, ^todo} = Persistence.validate_todo(todo)
    end

    test "validates todo with string keys" do
      todo = %{
        "content" => "Run tests",
        "status" => "pending",
        "active_form" => "Running tests"
      }

      assert {:ok, _} = Persistence.validate_todo(todo)
    end

    test "accepts all valid statuses" do
      for status <- ["pending", "in_progress", "completed"] do
        todo = valid_todo() |> Map.put(:status, status)
        assert {:ok, _} = Persistence.validate_todo(todo)
      end
    end

    test "returns error for unknown status" do
      todo = valid_todo() |> Map.put(:status, "unknown")
      assert {:error, {:unknown_status, "unknown"}} = Persistence.validate_todo(todo)
    end

    test "returns error for missing required fields" do
      todo = %{content: "Test"}
      assert {:error, {:missing_fields, missing}} = Persistence.validate_todo(todo)
      assert :status in missing
      assert :active_form in missing
    end

    test "returns error for invalid content type" do
      todo = valid_todo() |> Map.put(:content, nil)
      assert {:error, {:invalid_content, nil}} = Persistence.validate_todo(todo)
    end

    test "returns error for invalid status type" do
      todo = valid_todo() |> Map.put(:status, :pending)
      assert {:error, {:invalid_status, :pending}} = Persistence.validate_todo(todo)
    end

    test "returns error for invalid active_form type" do
      todo = valid_todo() |> Map.put(:active_form, 123)
      assert {:error, {:invalid_active_form, 123}} = Persistence.validate_todo(todo)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Persistence.validate_todo(nil)
    end
  end

  describe "new_session/1" do
    test "creates session with current schema version" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert session.version == 1
    end

    test "creates session with required fields" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert session.id == "test-123"
      assert session.name == "Test Session"
      assert session.project_path == "/path/to/project"
    end

    test "uses defaults for optional fields" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert session.config == %{}
      assert session.conversation == []
      assert session.todos == []
      assert is_binary(session.created_at)
      assert is_binary(session.updated_at)
      assert is_binary(session.closed_at)
    end

    test "allows overriding optional fields" do
      config = %{provider: :anthropic, model: "claude-3"}
      conversation = [valid_message()]
      todos = [valid_todo()]

      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project",
          config: config,
          conversation: conversation,
          todos: todos
        })

      assert session.config == config
      assert session.conversation == conversation
      assert session.todos == todos
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Persistence.new_session(%{name: "Test"})
      end
    end
  end

  describe "new_message/1" do
    test "creates message with required fields" do
      message =
        Persistence.new_message(%{
          id: "msg-1",
          role: "user",
          content: "Hello, world!"
        })

      assert message.id == "msg-1"
      assert message.role == "user"
      assert message.content == "Hello, world!"
      assert is_binary(message.timestamp)
    end

    test "allows overriding timestamp" do
      timestamp = "2024-01-01T00:00:00Z"

      message =
        Persistence.new_message(%{
          id: "msg-1",
          role: "user",
          content: "Hello",
          timestamp: timestamp
        })

      assert message.timestamp == timestamp
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Persistence.new_message(%{id: "msg-1"})
      end
    end
  end

  describe "new_todo/1" do
    test "creates todo with required fields" do
      todo =
        Persistence.new_todo(%{
          content: "Run tests",
          active_form: "Running tests"
        })

      assert todo.content == "Run tests"
      assert todo.active_form == "Running tests"
      assert todo.status == "pending"
    end

    test "defaults status to pending" do
      todo =
        Persistence.new_todo(%{
          content: "Test",
          active_form: "Testing"
        })

      assert todo.status == "pending"
    end

    test "allows overriding status" do
      todo =
        Persistence.new_todo(%{
          content: "Test",
          status: "completed",
          active_form: "Testing"
        })

      assert todo.status == "completed"
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Persistence.new_todo(%{content: "Test"})
      end
    end
  end

  describe "schema consistency" do
    test "new_session creates valid session" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert {:ok, _} = Persistence.validate_session(session)
    end

    test "new_message creates valid message" do
      message =
        Persistence.new_message(%{
          id: "msg-1",
          role: "user",
          content: "Hello"
        })

      assert {:ok, _} = Persistence.validate_message(message)
    end

    test "new_todo creates valid todo" do
      todo =
        Persistence.new_todo(%{
          content: "Run tests",
          active_form: "Running tests"
        })

      assert {:ok, _} = Persistence.validate_todo(todo)
    end

    test "session with messages and todos validates" do
      messages = [
        Persistence.new_message(%{id: "1", role: "user", content: "Hello"}),
        Persistence.new_message(%{id: "2", role: "assistant", content: "Hi there!"})
      ]

      todos = [
        Persistence.new_todo(%{content: "Task 1", active_form: "Doing task 1"}),
        Persistence.new_todo(%{
          content: "Task 2",
          status: "completed",
          active_form: "Doing task 2"
        })
      ]

      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project",
          conversation: messages,
          todos: todos
        })

      assert {:ok, _} = Persistence.validate_session(session)
    end
  end

  describe "sessions_dir/0" do
    test "returns path under user home directory" do
      dir = Persistence.sessions_dir()
      home = System.user_home!()

      assert String.starts_with?(dir, home)
    end

    test "returns path ending with .jido_code/sessions" do
      dir = Persistence.sessions_dir()

      assert String.ends_with?(dir, ".jido_code/sessions")
    end

    test "returns absolute path" do
      dir = Persistence.sessions_dir()

      assert Path.type(dir) == :absolute
    end

    test "returns consistent path" do
      dir1 = Persistence.sessions_dir()
      dir2 = Persistence.sessions_dir()

      assert dir1 == dir2
    end
  end

  describe "session_file/1" do
    test "returns path with .json extension" do
      path = Persistence.session_file("test-123")

      assert String.ends_with?(path, ".json")
    end

    test "includes session_id in filename" do
      path = Persistence.session_file("my-session-id")

      assert String.ends_with?(path, "my-session-id.json")
    end

    test "returns path under sessions directory" do
      path = Persistence.session_file("test")
      sessions_dir = Persistence.sessions_dir()

      assert String.starts_with?(path, sessions_dir)
    end

    test "returns absolute path" do
      path = Persistence.session_file("test")

      assert Path.type(path) == :absolute
    end

    test "handles session IDs with special characters" do
      path = Persistence.session_file("test-123_abc")

      assert String.ends_with?(path, "test-123_abc.json")
    end
  end

  describe "ensure_sessions_dir/0" do
    setup do
      # Use a temporary directory for testing
      test_dir =
        Path.join(System.tmp_dir!(), "persistence_test_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(test_dir) end)
      {:ok, test_dir: test_dir}
    end

    test "returns :ok when directory exists" do
      # The actual sessions_dir may or may not exist, but mkdir_p handles both
      result = Persistence.ensure_sessions_dir()

      assert result == :ok
    end

    test "creates directory if it doesn't exist" do
      # Ensure the directory exists after calling ensure_sessions_dir
      :ok = Persistence.ensure_sessions_dir()

      assert File.dir?(Persistence.sessions_dir())
    end

    test "is idempotent" do
      # Can be called multiple times without error
      assert :ok = Persistence.ensure_sessions_dir()
      assert :ok = Persistence.ensure_sessions_dir()
      assert :ok = Persistence.ensure_sessions_dir()
    end
  end

  describe "save/1" do
    test "returns error for non-existent session" do
      result = Persistence.save("non-existent-session-id")

      assert {:error, :not_found} = result
    end
  end

  describe "build_persisted_session/1" do
    test "builds valid persisted session from state" do
      state = mock_session_state()

      result = Persistence.build_persisted_session(state)

      assert result.version == Persistence.schema_version()
      assert result.id == "test-session-id"
      assert result.name == "Test Session"
      assert result.project_path == "/tmp/test-project"
      assert is_binary(result.created_at)
      assert is_binary(result.updated_at)
      assert is_binary(result.closed_at)
      assert is_list(result.conversation)
      assert is_list(result.todos)
    end

    test "serializes messages correctly" do
      state =
        mock_session_state()
        |> Map.put(:messages, [
          %{
            id: "msg-1",
            role: :user,
            content: "Hello",
            timestamp: ~U[2024-01-01 12:00:00Z]
          },
          %{
            id: "msg-2",
            role: :assistant,
            content: "Hi there!",
            timestamp: ~U[2024-01-01 12:01:00Z]
          }
        ])

      result = Persistence.build_persisted_session(state)

      assert length(result.conversation) == 2

      [msg1, msg2] = result.conversation
      assert msg1.id == "msg-1"
      assert msg1.role == "user"
      assert msg1.content == "Hello"
      assert is_binary(msg1.timestamp)

      assert msg2.id == "msg-2"
      assert msg2.role == "assistant"
      assert msg2.content == "Hi there!"
    end

    test "serializes todos correctly" do
      state =
        mock_session_state()
        |> Map.put(:todos, [
          %{content: "Task 1", status: :pending, active_form: "Doing task 1"},
          %{content: "Task 2", status: :completed, active_form: "Doing task 2"}
        ])

      result = Persistence.build_persisted_session(state)

      assert length(result.todos) == 2

      [todo1, todo2] = result.todos
      assert todo1.content == "Task 1"
      assert todo1.status == "pending"
      assert todo1.active_form == "Doing task 1"

      assert todo2.content == "Task 2"
      assert todo2.status == "completed"
    end

    test "serializes config with atom values" do
      state = mock_session_state()
      result = Persistence.build_persisted_session(state)

      assert is_map(result.config)
      # Config should have string keys/values for JSON compatibility
      assert result.config["provider"] == "anthropic"
      assert result.config["model"] == "test-model"
    end

    test "handles todos without active_form" do
      state =
        mock_session_state()
        |> Map.put(:todos, [
          %{content: "Task without active_form", status: :pending}
        ])

      result = Persistence.build_persisted_session(state)

      [todo] = result.todos
      # Falls back to content when active_form missing
      assert todo.active_form == "Task without active_form"
    end
  end

  describe "write_session_file/2" do
    setup do
      # Create a unique temp directory for testing
      test_id = "test-write-#{System.unique_integer([:positive])}"

      on_exit(fn ->
        # Clean up any test files
        path = Persistence.session_file(test_id)
        File.rm(path)
        File.rm("#{path}.tmp")
      end)

      {:ok, test_id: test_id}
    end

    test "writes JSON file to correct location", %{test_id: test_id} do
      persisted = %{
        version: 1,
        id: test_id,
        name: "Test",
        project_path: "/tmp",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      result = Persistence.write_session_file(test_id, persisted)

      assert result == :ok
      assert File.exists?(Persistence.session_file(test_id))
    end

    test "writes valid JSON", %{test_id: test_id} do
      persisted = %{
        version: 1,
        id: test_id,
        name: "Test Session",
        project_path: "/tmp/project",
        config: %{"provider" => "anthropic"},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [
          %{id: "1", role: "user", content: "Hello", timestamp: "2024-01-01T00:00:00Z"}
        ],
        todos: [%{content: "Task", status: "pending", active_form: "Doing task"}]
      }

      :ok = Persistence.write_session_file(test_id, persisted)

      path = Persistence.session_file(test_id)
      {:ok, content} = File.read(path)
      {:ok, decoded} = Jason.decode(content)

      assert decoded["version"] == 1
      assert decoded["id"] == test_id
      assert decoded["name"] == "Test Session"
      assert length(decoded["conversation"]) == 1
      assert length(decoded["todos"]) == 1
    end

    test "cleans up temp file on success", %{test_id: test_id} do
      persisted = %{
        version: 1,
        id: test_id,
        name: "Test",
        project_path: "/tmp",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      :ok = Persistence.write_session_file(test_id, persisted)

      temp_path = "#{Persistence.session_file(test_id)}.tmp"
      refute File.exists?(temp_path)
    end
  end

  describe "list_persisted/0" do
    setup do
      # Ensure sessions directory exists and is clean
      :ok = Persistence.ensure_sessions_dir()
      cleanup_session_files()

      on_exit(fn -> cleanup_session_files() end)
      :ok
    end

    test "returns empty list when no sessions exist" do
      result = Persistence.list_persisted()

      assert result == []
    end

    test "returns list of persisted sessions" do
      # Create two session files
      session1 = %{
        version: 1,
        id: "session-1",
        name: "First Session",
        project_path: "/tmp/proj1",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T12:00:00Z",
        conversation: [],
        todos: []
      }

      session2 = %{
        version: 1,
        id: "session-2",
        name: "Second Session",
        project_path: "/tmp/proj2",
        config: %{},
        created_at: "2024-01-02T00:00:00Z",
        updated_at: "2024-01-02T00:00:00Z",
        closed_at: "2024-01-02T12:00:00Z",
        conversation: [],
        todos: []
      }

      :ok = Persistence.write_session_file("session-1", session1)
      :ok = Persistence.write_session_file("session-2", session2)

      result = Persistence.list_persisted()

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id == "session-1"))
      assert Enum.any?(result, &(&1.id == "session-2"))
    end

    test "returns sessions sorted by closed_at (most recent first)" do
      # Create three sessions with different closed_at times
      session1 = create_test_session("session-1", "Session 1", "2024-01-01T00:00:00Z")
      session2 = create_test_session("session-2", "Session 2", "2024-01-03T00:00:00Z")
      session3 = create_test_session("session-3", "Session 3", "2024-01-02T00:00:00Z")

      :ok = Persistence.write_session_file("session-1", session1)
      :ok = Persistence.write_session_file("session-2", session2)
      :ok = Persistence.write_session_file("session-3", session3)

      result = Persistence.list_persisted()

      assert length(result) == 3
      # Most recent should be first
      assert Enum.at(result, 0).id == "session-2"
      assert Enum.at(result, 1).id == "session-3"
      assert Enum.at(result, 2).id == "session-1"
    end

    test "includes required metadata fields" do
      session = create_test_session("test-session", "Test Session", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file("test-session", session)

      [result] = Persistence.list_persisted()

      assert result.id == "test-session"
      assert result.name == "Test Session"
      assert result.project_path == "/tmp/test-project"
      assert result.closed_at == "2024-01-01T00:00:00Z"
    end

    test "handles corrupted JSON files gracefully" do
      # Create a valid session
      session = create_test_session("valid-session", "Valid", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file("valid-session", session)

      # Create a corrupted JSON file
      corrupted_path = Persistence.session_file("corrupted-session")
      File.write!(corrupted_path, "{invalid json")

      result = Persistence.list_persisted()

      # Should only return the valid session
      assert length(result) == 1
      assert List.first(result).id == "valid-session"
    end

    test "ignores non-JSON files in sessions directory" do
      session = create_test_session("test-session", "Test", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file("test-session", session)

      # Create a non-JSON file
      non_json_path = Path.join(Persistence.sessions_dir(), "readme.txt")
      File.write!(non_json_path, "This is not a session file")

      result = Persistence.list_persisted()

      assert length(result) == 1
      assert List.first(result).id == "test-session"
    end

    test "handles missing sessions directory" do
      # Remove sessions directory
      sessions_dir = Persistence.sessions_dir()
      File.rm_rf!(sessions_dir)

      result = Persistence.list_persisted()

      assert result == []
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp cleanup_session_files do
    sessions_dir = Persistence.sessions_dir()

    if File.dir?(sessions_dir) do
      File.ls!(sessions_dir)
      |> Enum.each(fn file ->
        path = Path.join(sessions_dir, file)
        File.rm(path)
      end)
    end
  end

  defp create_test_session(id, name, closed_at) do
    %{
      version: 1,
      id: id,
      name: name,
      project_path: "/tmp/test-project",
      config: %{},
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z",
      closed_at: closed_at,
      conversation: [],
      todos: []
    }
  end

  defp mock_session_state do
    %{
      session: %{
        id: "test-session-id",
        name: "Test Session",
        project_path: "/tmp/test-project",
        config: %{provider: :anthropic, model: "test-model", temperature: 0.7},
        created_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 12:00:00Z]
      },
      messages: [],
      todos: []
    }
  end

  defp valid_session do
    %{
      version: 1,
      id: "test-123",
      name: "Test Session",
      project_path: "/path/to/project",
      config: %{provider: :anthropic, model: "claude-3"},
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T12:00:00Z",
      closed_at: "2024-01-01T18:00:00Z",
      conversation: [],
      todos: []
    }
  end

  defp valid_message do
    %{
      id: "msg-1",
      role: "user",
      content: "Hello, world!",
      timestamp: "2024-01-01T00:00:00Z"
    }
  end

  defp valid_todo do
    %{
      content: "Run tests",
      status: "pending",
      active_form: "Running tests"
    }
  end
end
