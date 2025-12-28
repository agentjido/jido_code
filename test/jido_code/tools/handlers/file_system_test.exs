defmodule JidoCode.Tools.Handlers.FileSystemTest do
  # async: false because we're modifying the shared Manager state
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Handlers.FileSystem.{
    CreateDirectory,
    DeleteFile,
    EditFile,
    FileInfo,
    ListDirectory,
    ReadFile,
    WriteFile
  }

  @moduletag :tmp_dir

  # Set up Manager with tmp_dir as project root for sandboxed operations
  setup %{tmp_dir: tmp_dir} do
    JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)
    :ok
  end

  # ============================================================================
  # Session Context Tests
  # ============================================================================

  describe "session-aware context" do
    setup %{tmp_dir: tmp_dir} do
      # Set dummy API key for test
      System.put_env("ANTHROPIC_API_KEY", "test-key-fs-handler")

      on_exit(fn ->
        System.delete_env("ANTHROPIC_API_KEY")
      end)

      # Start required registries if not already started
      # Use GenServer.whereis for Registry names instead of Process.whereis
      unless GenServer.whereis(JidoCode.SessionProcessRegistry) do
        start_supervised!({Registry, keys: :unique, name: JidoCode.SessionProcessRegistry})
      end

      # Create a session
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "fs-session-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:fs_session_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session}
    end

    test "ReadFile uses session_id for path validation", %{tmp_dir: tmp_dir, session: session} do
      # Create test file
      File.write!(Path.join(tmp_dir, "session_test.txt"), "Session content")

      # Use session_id context
      context = %{session_id: session.id}
      assert {:ok, "Session content"} = ReadFile.execute(%{"path" => "session_test.txt"}, context)
    end

    test "WriteFile uses session_id for path validation", %{tmp_dir: tmp_dir, session: session} do
      context = %{session_id: session.id}

      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "session_output.txt", "content" => "Written via session"},
                 context
               )

      assert File.read!(Path.join(tmp_dir, "session_output.txt")) == "Written via session"
    end

    test "session_id context rejects path traversal", %{session: session} do
      context = %{session_id: session.id}

      assert {:error, error} = ReadFile.execute(%{"path" => "../../../etc/passwd"}, context)
      assert error =~ "Security error"
    end

    test "invalid session_id returns error" do
      context = %{session_id: "not-a-valid-uuid"}
      assert {:error, error} = ReadFile.execute(%{"path" => "test.txt"}, context)
      assert error =~ "invalid_session_id" or error =~ "Invalid session ID"
    end

    test "non-existent session_id returns error" do
      # Valid UUID format but no session exists
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}
      assert {:error, error} = ReadFile.execute(%{"path" => "test.txt"}, context)
      # Session.Manager returns :not_found which gets formatted as "not_found" error
      # The format_error handles :not_found as "File error (not_found): path"
      assert error =~ "not_found" or error =~ "not found"
    end
  end

  # ============================================================================
  # ReadFile Tests
  # ============================================================================

  describe "ReadFile.execute/2" do
    test "reads file contents", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test.txt")
      File.write!(file_path, "Hello, World!")

      context = %{project_root: tmp_dir}
      assert {:ok, "Hello, World!"} = ReadFile.execute(%{"path" => "test.txt"}, context)
    end

    test "reads nested file", %{tmp_dir: tmp_dir} do
      nested_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(nested_dir)
      File.write!(Path.join(nested_dir, "code.ex"), "defmodule Test do\nend")

      context = %{project_root: tmp_dir}
      assert {:ok, content} = ReadFile.execute(%{"path" => "src/code.ex"}, context)
      assert content == "defmodule Test do\nend"
    end

    test "returns error for non-existent file", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = ReadFile.execute(%{"path" => "missing.txt"}, context)
      assert error =~ "File not found"
    end

    test "returns error for path traversal attempt", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = ReadFile.execute(%{"path" => "../../../etc/passwd"}, context)
      assert error =~ "Security error"
    end

    test "returns error for missing path argument", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = ReadFile.execute(%{}, context)
      assert error =~ "requires a path argument"
    end

    test "returns error when reading a directory", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      context = %{project_root: tmp_dir}
      assert {:error, error} = ReadFile.execute(%{"path" => "subdir"}, context)
      assert error =~ "Is a directory"
    end
  end

  # ============================================================================
  # WriteFile Tests
  # ============================================================================

  describe "WriteFile.execute/2" do
    test "writes file contents", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:ok, message} =
               WriteFile.execute(%{"path" => "output.txt", "content" => "Test content"}, context)

      assert message =~ "written successfully"
      assert File.read!(Path.join(tmp_dir, "output.txt")) == "Test content"
    end

    test "creates parent directories", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:ok, _} =
               WriteFile.execute(%{"path" => "a/b/c/file.txt", "content" => "Nested"}, context)

      assert File.read!(Path.join(tmp_dir, "a/b/c/file.txt")) == "Nested"
    end

    test "overwrites existing file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "existing.txt")
      File.write!(file_path, "Old content")

      context = %{project_root: tmp_dir}

      assert {:ok, _} =
               WriteFile.execute(%{"path" => "existing.txt", "content" => "New content"}, context)

      assert File.read!(file_path) == "New content"
    end

    test "returns error for path traversal attempt", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               WriteFile.execute(%{"path" => "../evil.txt", "content" => "Bad"}, context)

      assert error =~ "Security error"
    end

    test "returns error for missing arguments", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = WriteFile.execute(%{"path" => "file.txt"}, context)
      assert error =~ "requires path and content"
    end
  end

  # ============================================================================
  # WriteFile Read-Before-Write Tests (Session Context)
  # ============================================================================

  describe "WriteFile read-before-write safety" do
    setup %{tmp_dir: tmp_dir} do
      # Set dummy API key for test
      System.put_env("ANTHROPIC_API_KEY", "test-key-write-rbw")

      on_exit(fn ->
        System.delete_env("ANTHROPIC_API_KEY")
      end)

      # Start required registries if not already started
      unless GenServer.whereis(JidoCode.SessionProcessRegistry) do
        start_supervised!({Registry, keys: :unique, name: JidoCode.SessionProcessRegistry})
      end

      # Create a session
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "write-rbw-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:write_rbw_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session}
    end

    test "allows writing new file without prior read", %{tmp_dir: tmp_dir, session: session} do
      context = %{session_id: session.id}

      assert {:ok, message} =
               WriteFile.execute(
                 %{"path" => "new_file.txt", "content" => "Brand new content"},
                 context
               )

      assert message =~ "written successfully"
      assert File.read!(Path.join(tmp_dir, "new_file.txt")) == "Brand new content"
    end

    test "rejects overwriting existing file without prior read", %{
      tmp_dir: tmp_dir,
      session: session
    } do
      # Create existing file
      file_path = Path.join(tmp_dir, "existing_no_read.txt")
      File.write!(file_path, "Original content")

      context = %{session_id: session.id}

      # Attempt to overwrite without reading first
      assert {:error, error} =
               WriteFile.execute(
                 %{"path" => "existing_no_read.txt", "content" => "New content"},
                 context
               )

      assert error =~ "must be read before overwriting"

      # Verify original content is preserved
      assert File.read!(file_path) == "Original content"
    end

    test "allows overwriting after file is read", %{tmp_dir: tmp_dir, session: session} do
      # Create existing file
      file_path = Path.join(tmp_dir, "existing_with_read.txt")
      File.write!(file_path, "Original content")

      context = %{session_id: session.id}

      # First read the file
      assert {:ok, "Original content"} =
               ReadFile.execute(%{"path" => "existing_with_read.txt"}, context)

      # Now overwrite should succeed
      assert {:ok, message} =
               WriteFile.execute(
                 %{"path" => "existing_with_read.txt", "content" => "Updated content"},
                 context
               )

      assert message =~ "updated successfully"
      assert File.read!(file_path) == "Updated content"
    end

    test "tracks multiple file reads for write validation", %{tmp_dir: tmp_dir, session: session} do
      # Create multiple files
      File.write!(Path.join(tmp_dir, "file1.txt"), "Content 1")
      File.write!(Path.join(tmp_dir, "file2.txt"), "Content 2")
      File.write!(Path.join(tmp_dir, "file3.txt"), "Content 3")

      context = %{session_id: session.id}

      # Read file1 and file2, but not file3
      assert {:ok, _} = ReadFile.execute(%{"path" => "file1.txt"}, context)
      assert {:ok, _} = ReadFile.execute(%{"path" => "file2.txt"}, context)

      # Can overwrite file1 and file2
      assert {:ok, _} =
               WriteFile.execute(%{"path" => "file1.txt", "content" => "New 1"}, context)

      assert {:ok, _} =
               WriteFile.execute(%{"path" => "file2.txt", "content" => "New 2"}, context)

      # Cannot overwrite file3 (not read)
      assert {:error, error} =
               WriteFile.execute(%{"path" => "file3.txt", "content" => "New 3"}, context)

      assert error =~ "must be read before overwriting"
    end

    test "project_root context bypasses read-before-write check (legacy mode)", %{
      tmp_dir: tmp_dir
    } do
      # Create existing file
      file_path = Path.join(tmp_dir, "legacy_mode.txt")
      File.write!(file_path, "Original content")

      # Use project_root context (legacy mode)
      context = %{project_root: tmp_dir}

      # Should allow overwrite without prior read
      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "legacy_mode.txt", "content" => "New content"},
                 context
               )

      assert File.read!(file_path) == "New content"
    end

    test "creates parent directories for new file", %{tmp_dir: tmp_dir, session: session} do
      context = %{session_id: session.id}

      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "deep/nested/dir/file.txt", "content" => "Nested content"},
                 context
               )

      assert File.read!(Path.join(tmp_dir, "deep/nested/dir/file.txt")) == "Nested content"
    end

    test "rejects content exceeding size limit", %{session: session} do
      context = %{session_id: session.id}

      # Create content larger than 10MB
      large_content = String.duplicate("x", 10 * 1024 * 1024 + 1)

      assert {:error, error} =
               WriteFile.execute(%{"path" => "large_file.txt", "content" => large_content}, context)

      assert error =~ "exceeds maximum file size" or error =~ "content_too_large" or
               error =~ "Content exceeds"
    end

    test "rejects path traversal with session context", %{session: session} do
      context = %{session_id: session.id}

      assert {:error, error} =
               WriteFile.execute(
                 %{"path" => "../../../etc/evil.txt", "content" => "Bad content"},
                 context
               )

      assert error =~ "Security error"
    end

    test "write after read updates file correctly with unicode content", %{
      tmp_dir: tmp_dir,
      session: session
    } do
      # Create file with unicode content
      file_path = Path.join(tmp_dir, "unicode.txt")
      File.write!(file_path, "Hello 世界 🌍")

      context = %{session_id: session.id}

      # Read first
      assert {:ok, "Hello 世界 🌍"} = ReadFile.execute(%{"path" => "unicode.txt"}, context)

      # Write unicode content
      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "unicode.txt", "content" => "Updated 日本語 🎉"},
                 context
               )

      assert File.read!(file_path) == "Updated 日本語 🎉"
    end
  end

  # ============================================================================
  # WriteFile Atomic Write Tests
  # ============================================================================

  describe "WriteFile atomic write behavior" do
    test "writes atomically using Security.atomic_write", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # Write a file
      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "atomic_test.txt", "content" => "Atomic content"},
                 context
               )

      # Verify content
      assert File.read!(Path.join(tmp_dir, "atomic_test.txt")) == "Atomic content"
    end

    test "validates path after write (TOCTOU protection)", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # Normal write should succeed and be validated
      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "safe_file.txt", "content" => "Safe content"},
                 context
               )

      # Verify file exists at expected location
      assert File.exists?(Path.join(tmp_dir, "safe_file.txt"))
    end

    test "handles concurrent writes to same file", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # Perform multiple writes - last one should win
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            WriteFile.execute(
              %{"path" => "concurrent.txt", "content" => "Content #{i}"},
              context
            )
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, fn result ->
               match?({:ok, _}, result)
             end)

      # File should exist with one of the contents
      content = File.read!(Path.join(tmp_dir, "concurrent.txt"))
      assert content =~ "Content"
    end
  end

  # ============================================================================
  # WriteFile Permission and Error Tests
  # ============================================================================

  describe "WriteFile error handling" do
    test "returns error for missing path argument", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} = WriteFile.execute(%{"content" => "No path"}, context)
      assert error =~ "requires path and content"
    end

    test "returns error for missing content argument", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} = WriteFile.execute(%{"path" => "file.txt"}, context)
      assert error =~ "requires path and content"
    end

    test "returns error for empty arguments", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} = WriteFile.execute(%{}, context)
      assert error =~ "requires path and content"
    end

    @tag :tmp_dir
    test "handles permission denied gracefully", %{tmp_dir: tmp_dir} do
      # Create a read-only directory
      readonly_dir = Path.join(tmp_dir, "readonly")
      File.mkdir_p!(readonly_dir)
      File.chmod!(readonly_dir, 0o444)

      context = %{project_root: tmp_dir}

      result =
        WriteFile.execute(
          %{"path" => "readonly/file.txt", "content" => "Cannot write"},
          context
        )

      # Restore permissions for cleanup
      File.chmod!(readonly_dir, 0o755)

      case result do
        {:error, error} ->
          assert error =~ "Permission denied" or error =~ "eacces" or error =~ "Error"

        {:ok, _} ->
          # Some systems may allow root to write anyway
          :ok
      end
    end

    test "handles symlink in path correctly", %{tmp_dir: tmp_dir} do
      # Create a real directory
      real_dir = Path.join(tmp_dir, "real_dir")
      File.mkdir_p!(real_dir)

      # Create a symlink to it
      symlink_path = Path.join(tmp_dir, "link_dir")
      File.ln_s!(real_dir, symlink_path)

      context = %{project_root: tmp_dir}

      # Write through symlink should work (symlink stays within boundary)
      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => "link_dir/file.txt", "content" => "Via symlink"},
                 context
               )

      # Verify file was created in real location
      assert File.read!(Path.join(real_dir, "file.txt")) == "Via symlink"
    end
  end

  # ============================================================================
  # EditFile Tests
  # ============================================================================

  describe "EditFile.execute/2" do
    test "replaces single occurrence", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "edit_test.txt")
      File.write!(file_path, "Hello, World!")

      context = %{project_root: tmp_dir}

      assert {:ok, message} =
               EditFile.execute(
                 %{"path" => "edit_test.txt", "old_string" => "World", "new_string" => "Elixir"},
                 context
               )

      assert message =~ "Successfully replaced 1 occurrence"
      assert File.read!(file_path) == "Hello, Elixir!"
    end

    test "replaces all occurrences with replace_all", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "multi.txt")
      File.write!(file_path, "foo bar foo baz foo")

      context = %{project_root: tmp_dir}

      assert {:ok, message} =
               EditFile.execute(
                 %{
                   "path" => "multi.txt",
                   "old_string" => "foo",
                   "new_string" => "qux",
                   "replace_all" => true
                 },
                 context
               )

      assert message =~ "Successfully replaced 3 occurrence"
      assert File.read!(file_path) == "qux bar qux baz qux"
    end

    test "replaces multiline strings", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "multiline.ex")

      File.write!(file_path, """
      defmodule Test do
        def hello do
          :world
        end
      end
      """)

      context = %{project_root: tmp_dir}

      assert {:ok, _} =
               EditFile.execute(
                 %{
                   "path" => "multiline.ex",
                   "old_string" => "def hello do\n    :world\n  end",
                   "new_string" => "def hello do\n    :elixir\n  end"
                 },
                 context
               )

      content = File.read!(file_path)
      assert content =~ ":elixir"
      refute content =~ ":world"
    end

    test "returns error when string not found", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "notfound.txt")
      File.write!(file_path, "Hello, World!")

      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditFile.execute(
                 %{"path" => "notfound.txt", "old_string" => "missing", "new_string" => "found"},
                 context
               )

      assert error =~ "String not found"
    end

    test "returns error for ambiguous match without replace_all", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "ambiguous.txt")
      File.write!(file_path, "foo foo foo")

      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditFile.execute(
                 %{"path" => "ambiguous.txt", "old_string" => "foo", "new_string" => "bar"},
                 context
               )

      assert error =~ "Found 3 occurrences"
      assert error =~ "replace_all: true"
      # File should remain unchanged
      assert File.read!(file_path) == "foo foo foo"
    end

    test "returns error for non-existent file", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditFile.execute(
                 %{"path" => "missing.txt", "old_string" => "foo", "new_string" => "bar"},
                 context
               )

      assert error =~ "File not found"
    end

    test "returns error for path traversal attempt", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditFile.execute(
                 %{
                   "path" => "../../../etc/passwd",
                   "old_string" => "root",
                   "new_string" => "hacked"
                 },
                 context
               )

      assert error =~ "Security error"
    end

    test "returns error for missing arguments", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} = EditFile.execute(%{"path" => "file.txt"}, context)
      assert error =~ "requires path, old_string, and new_string"

      assert {:error, error} =
               EditFile.execute(%{"path" => "file.txt", "old_string" => "foo"}, context)

      assert error =~ "requires path, old_string, and new_string"
    end

    test "handles empty replacement string", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "delete_word.txt")
      File.write!(file_path, "Hello, beautiful World!")

      context = %{project_root: tmp_dir}

      assert {:ok, _} =
               EditFile.execute(
                 %{"path" => "delete_word.txt", "old_string" => "beautiful ", "new_string" => ""},
                 context
               )

      assert File.read!(file_path) == "Hello, World!"
    end

    test "handles special regex characters in old_string", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "special.txt")
      File.write!(file_path, "function(arg1, arg2)")

      context = %{project_root: tmp_dir}

      assert {:ok, _} =
               EditFile.execute(
                 %{
                   "path" => "special.txt",
                   "old_string" => "function(arg1, arg2)",
                   "new_string" => "func(a, b)"
                 },
                 context
               )

      assert File.read!(file_path) == "func(a, b)"
    end
  end

  # ============================================================================
  # ListDirectory Tests
  # ============================================================================

  describe "ListDirectory.execute/2" do
    test "lists directory contents", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.write!(Path.join(tmp_dir, "b.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      context = %{project_root: tmp_dir}
      assert {:ok, json} = ListDirectory.execute(%{"path" => ""}, context)

      entries = Jason.decode!(json)
      names = Enum.map(entries, & &1["name"])
      assert "a.txt" in names
      assert "b.txt" in names
      assert "subdir" in names
    end

    test "includes type information", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "dir"))

      context = %{project_root: tmp_dir}
      {:ok, json} = ListDirectory.execute(%{"path" => ""}, context)

      entries = Jason.decode!(json)
      file_entry = Enum.find(entries, &(&1["name"] == "file.txt"))
      dir_entry = Enum.find(entries, &(&1["name"] == "dir"))

      assert file_entry["type"] == "file"
      assert dir_entry["type"] == "directory"
    end

    test "lists subdirectory", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "src")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "main.ex"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = ListDirectory.execute(%{"path" => "src"}, context)

      entries = Jason.decode!(json)
      assert [%{"name" => "main.ex", "type" => "file"}] = entries
    end

    test "returns empty list for empty directory", %{tmp_dir: tmp_dir} do
      empty_dir = Path.join(tmp_dir, "empty")
      File.mkdir_p!(empty_dir)

      context = %{project_root: tmp_dir}
      {:ok, json} = ListDirectory.execute(%{"path" => "empty"}, context)

      assert Jason.decode!(json) == []
    end

    test "lists recursively when flag is true", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "a/b"))
      File.write!(Path.join(tmp_dir, "root.txt"), "")
      File.write!(Path.join(tmp_dir, "a/level1.txt"), "")
      File.write!(Path.join(tmp_dir, "a/b/level2.txt"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = ListDirectory.execute(%{"path" => "", "recursive" => true}, context)

      entries = Jason.decode!(json)
      names = Enum.map(entries, & &1["name"])

      assert "root.txt" in names
      assert "a" in names
      assert "a/level1.txt" in names
      assert "a/b" in names
      assert "a/b/level2.txt" in names
    end

    test "returns error for non-existent directory", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = ListDirectory.execute(%{"path" => "missing"}, context)
      assert error =~ "File not found" or error =~ "Not a directory"
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = ListDirectory.execute(%{"path" => "../.."}, context)
      assert error =~ "Security error"
    end
  end

  # ============================================================================
  # FileInfo Tests
  # ============================================================================

  describe "FileInfo.execute/2" do
    test "returns file metadata", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test.txt"), "Hello")

      context = %{project_root: tmp_dir}
      {:ok, json} = FileInfo.execute(%{"path" => "test.txt"}, context)

      info = Jason.decode!(json)
      assert info["path"] == "test.txt"
      assert info["size"] == 5
      assert info["type"] == "regular"
      assert is_binary(info["mtime"])
    end

    test "returns directory metadata", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      context = %{project_root: tmp_dir}
      {:ok, json} = FileInfo.execute(%{"path" => "subdir"}, context)

      info = Jason.decode!(json)
      assert info["type"] == "directory"
    end

    test "returns error for non-existent path", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = FileInfo.execute(%{"path" => "missing.txt"}, context)
      assert error =~ "File not found"
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = FileInfo.execute(%{"path" => "../../../etc"}, context)
      assert error =~ "Security error"
    end
  end

  # ============================================================================
  # CreateDirectory Tests
  # ============================================================================

  describe "CreateDirectory.execute/2" do
    test "creates a directory", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:ok, message} = CreateDirectory.execute(%{"path" => "newdir"}, context)
      assert message =~ "created successfully"
      assert File.dir?(Path.join(tmp_dir, "newdir"))
    end

    test "creates nested directories", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:ok, _} = CreateDirectory.execute(%{"path" => "a/b/c"}, context)
      assert File.dir?(Path.join(tmp_dir, "a/b/c"))
    end

    test "succeeds if directory already exists", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "existing"))

      context = %{project_root: tmp_dir}
      assert {:ok, _} = CreateDirectory.execute(%{"path" => "existing"}, context)
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      assert {:error, error} = CreateDirectory.execute(%{"path" => "../evil"}, context)
      assert error =~ "Security error"
    end
  end

  # ============================================================================
  # DeleteFile Tests
  # ============================================================================

  describe "DeleteFile.execute/2" do
    test "deletes a file with confirmation", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "to_delete.txt")
      File.write!(file_path, "delete me")

      context = %{project_root: tmp_dir}

      assert {:ok, message} =
               DeleteFile.execute(%{"path" => "to_delete.txt", "confirm" => true}, context)

      assert message =~ "deleted successfully"
      refute File.exists?(file_path)
    end

    test "refuses without confirmation", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "protected.txt")
      File.write!(file_path, "keep me")

      context = %{project_root: tmp_dir}

      assert {:error, error} =
               DeleteFile.execute(%{"path" => "protected.txt", "confirm" => false}, context)

      assert error =~ "requires confirm=true"
      assert File.exists?(file_path)
    end

    test "returns error when confirm is missing", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file.txt"), "")

      context = %{project_root: tmp_dir}
      assert {:error, error} = DeleteFile.execute(%{"path" => "file.txt"}, context)
      assert error =~ "requires confirm"
    end

    test "returns error for non-existent file", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               DeleteFile.execute(%{"path" => "missing.txt", "confirm" => true}, context)

      assert error =~ "File not found"
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               DeleteFile.execute(%{"path" => "../../../etc/passwd", "confirm" => true}, context)

      assert error =~ "Security error"
    end
  end
end
