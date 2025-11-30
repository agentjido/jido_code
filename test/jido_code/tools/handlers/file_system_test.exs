defmodule JidoCode.Tools.Handlers.FileSystemTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Handlers.FileSystem.{
    CreateDirectory,
    DeleteFile,
    FileInfo,
    ListDirectory,
    ReadFile,
    WriteFile
  }

  @moduletag :tmp_dir

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
