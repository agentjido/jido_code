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

  describe "Session.new/1" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = Path.join(System.tmp_dir!(), "session_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      %{tmp_dir: tmp_dir}
    end

    test "creates session with valid project_path", %{tmp_dir: tmp_dir} do
      assert {:ok, session} = Session.new(project_path: tmp_dir)

      assert session.project_path == tmp_dir
      assert is_binary(session.id)
      assert is_binary(session.name)
      assert is_map(session.config)
      assert %DateTime{} = session.created_at
      assert %DateTime{} = session.updated_at
    end

    test "uses folder name as default name", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert session.name == Path.basename(tmp_dir)
    end

    test "accepts custom name override", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir, name: "My Custom Project")

      assert session.name == "My Custom Project"
    end

    test "accepts custom config override", %{tmp_dir: tmp_dir} do
      custom_config = %{
        provider: "ollama",
        model: "qwen3:32b",
        temperature: 0.5,
        max_tokens: 2048
      }

      {:ok, session} = Session.new(project_path: tmp_dir, config: custom_config)

      assert session.config == custom_config
    end

    test "loads default config from Settings when not provided", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Should have default config values
      assert is_binary(session.config.provider)
      assert is_binary(session.config.model)
      assert is_float(session.config.temperature)
      assert is_integer(session.config.max_tokens)
    end

    test "returns error for non-existent path" do
      assert {:error, :path_not_found} = Session.new(project_path: "/nonexistent/path/12345")
    end

    test "returns error for file path (not directory)", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test_file.txt")
      File.write!(file_path, "test content")

      assert {:error, :path_not_directory} = Session.new(project_path: file_path)
    end

    test "returns error when project_path is missing" do
      assert {:error, :missing_project_path} = Session.new([])
    end

    test "returns error when project_path is not a string", %{tmp_dir: _tmp_dir} do
      assert {:error, :invalid_project_path} = Session.new(project_path: 123)
    end

    test "sets created_at and updated_at to same value", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert session.created_at == session.updated_at
    end

    test "generates unique ids for each session", %{tmp_dir: tmp_dir} do
      {:ok, session1} = Session.new(project_path: tmp_dir)
      {:ok, session2} = Session.new(project_path: tmp_dir)

      assert session1.id != session2.id
    end
  end

  describe "Session.generate_id/0" do
    test "generates valid UUID v4 format" do
      id = Session.generate_id()

      # UUID format: 8-4-4-4-12 hex chars
      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               id
             )
    end

    test "version nibble is 4" do
      id = Session.generate_id()

      # Extract the version nibble (13th character, after second hyphen)
      version_char = String.at(id, 14)
      assert version_char == "4"
    end

    test "variant bits are correct (8, 9, a, or b)" do
      id = Session.generate_id()

      # Extract the variant nibble (first char after third hyphen, position 19)
      variant_char = String.at(id, 19)
      assert variant_char in ["8", "9", "a", "b"]
    end

    test "generates unique ids" do
      ids = for _ <- 1..100, do: Session.generate_id()

      assert length(Enum.uniq(ids)) == 100
    end

    test "id is 36 characters (including hyphens)" do
      id = Session.generate_id()

      assert String.length(id) == 36
    end
  end
end
