defmodule JidoCode.SessionTest do
  use ExUnit.Case, async: true

  alias JidoCode.Session

  describe "Session struct" do
    test "can be created with all fields" do
      now = DateTime.utc_now()

      session = %Session{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "test-project",
        project_path: "/home/user/projects/test-project",
        config: %{
          provider: "anthropic",
          model: "claude-3-5-sonnet-20241022",
          temperature: 0.7,
          max_tokens: 4096
        },
        created_at: now,
        updated_at: now
      }

      assert session.id == "550e8400-e29b-41d4-a716-446655440000"
      assert session.name == "test-project"
      assert session.project_path == "/home/user/projects/test-project"
      assert session.config.provider == "anthropic"
      assert session.config.model == "claude-3-5-sonnet-20241022"
      assert session.config.temperature == 0.7
      assert session.config.max_tokens == 4096
      assert session.created_at == now
      assert session.updated_at == now
    end

    test "struct has all expected fields" do
      fields = Session.__struct__() |> Map.keys() |> Enum.sort()

      expected_fields =
        [:__struct__, :config, :created_at, :id, :name, :project_path, :updated_at]
        |> Enum.sort()

      assert fields == expected_fields
    end

    test "can be created with nil fields" do
      session = %Session{}

      assert session.id == nil
      assert session.name == nil
      assert session.project_path == nil
      assert session.config == nil
      assert session.created_at == nil
      assert session.updated_at == nil
    end

    test "config can contain provider-specific fields" do
      session = %Session{
        id: "test-id",
        name: "test",
        project_path: "/tmp/test",
        config: %{
          provider: "ollama",
          model: "qwen3:32b",
          temperature: 0.5,
          max_tokens: 2048,
          base_url: "http://localhost:11434"
        },
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      assert session.config[:base_url] == "http://localhost:11434"
    end
  end

  describe "Session type compliance" do
    test "id is a string" do
      session = %Session{id: "uuid-string"}
      assert is_binary(session.id)
    end

    test "name is a string" do
      session = %Session{name: "project-name"}
      assert is_binary(session.name)
    end

    test "project_path is a string" do
      session = %Session{project_path: "/absolute/path"}
      assert is_binary(session.project_path)
    end

    test "config is a map" do
      config = %{provider: "test", model: "test", temperature: 0.5, max_tokens: 1000}
      session = %Session{config: config}
      assert is_map(session.config)
    end

    test "created_at is a DateTime" do
      now = DateTime.utc_now()
      session = %Session{created_at: now}
      assert %DateTime{} = session.created_at
    end

    test "updated_at is a DateTime" do
      now = DateTime.utc_now()
      session = %Session{updated_at: now}
      assert %DateTime{} = session.updated_at
    end
  end
end
