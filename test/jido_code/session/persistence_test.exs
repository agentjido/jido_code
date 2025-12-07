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

  # ============================================================================
  # Test Helpers
  # ============================================================================

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
