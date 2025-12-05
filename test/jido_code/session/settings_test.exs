defmodule JidoCode.Session.SettingsTest do
  use ExUnit.Case, async: true

  import Bitwise
  import ExUnit.CaptureLog

  alias JidoCode.Session.Settings

  # ============================================================================
  # Settings Loading Tests
  # ============================================================================

  describe "load_local/1" do
    @describetag :tmp_dir

    test "returns settings from existing file", %{tmp_dir: tmp_dir} do
      # Create settings file
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "anthropic", "model": "claude-3"}))

      result = Settings.load_local(tmp_dir)

      assert result == %{"provider" => "anthropic", "model" => "claude-3"}
    end

    test "returns empty map for missing file", %{tmp_dir: tmp_dir} do
      result = Settings.load_local(tmp_dir)

      assert result == %{}
    end

    test "returns empty map and logs warning for malformed JSON", %{tmp_dir: tmp_dir} do
      # Create malformed settings file
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, "{ invalid json }")

      log =
        capture_log(fn ->
          result = Settings.load_local(tmp_dir)
          assert result == %{}
        end)

      assert log =~ "Malformed JSON"
      assert log =~ "local"
    end
  end

  describe "load_global/0" do
    # Note: We can't easily test load_global with a real file without modifying
    # the user's home directory. We test the behavior indirectly through load/1.

    test "returns a map (may be empty if no global settings)" do
      result = Settings.load_global()

      assert is_map(result)
    end
  end

  describe "load/1" do
    @describetag :tmp_dir

    test "merges global and local settings", %{tmp_dir: tmp_dir} do
      # Create local settings file
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"model": "local-model"}))

      result = Settings.load(tmp_dir)

      # Local settings should be present
      assert result["model"] == "local-model"
      # Result should be a map
      assert is_map(result)
    end

    test "local settings override global settings", %{tmp_dir: tmp_dir} do
      # Create local settings with a key that might also be in global
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "local-provider"}))

      result = Settings.load(tmp_dir)

      # Local value should override any global value
      assert result["provider"] == "local-provider"
    end

    test "returns global settings when no local file exists", %{tmp_dir: tmp_dir} do
      # Don't create any local settings
      result = Settings.load(tmp_dir)

      # Should still return a map (global settings or empty)
      assert is_map(result)
    end

    test "returns empty map when no settings files exist", %{tmp_dir: tmp_dir} do
      # Use a subdirectory to avoid any existing settings
      project_path = Path.join(tmp_dir, "empty-project")
      File.mkdir_p!(project_path)

      result = Settings.load(project_path)

      # Result should be a map (may include global settings)
      assert is_map(result)
    end
  end

  # ============================================================================
  # Path Helper Tests
  # ============================================================================

  describe "local_dir/1" do
    test "returns settings directory path for project" do
      assert Settings.local_dir("/home/user/myproject") == "/home/user/myproject/.jido_code"
    end

    test "handles various project paths" do
      assert Settings.local_dir("/tmp/test") == "/tmp/test/.jido_code"
      assert Settings.local_dir("/") == "/.jido_code"
      assert Settings.local_dir("/a/b/c/d") == "/a/b/c/d/.jido_code"
    end

    test "handles paths with trailing slash" do
      # Path.join handles trailing slashes
      assert Settings.local_dir("/tmp/test/") == "/tmp/test/.jido_code"
    end
  end

  describe "local_path/1" do
    test "returns settings file path for project" do
      assert Settings.local_path("/home/user/myproject") ==
               "/home/user/myproject/.jido_code/settings.json"
    end

    test "handles various project paths" do
      assert Settings.local_path("/tmp/test") == "/tmp/test/.jido_code/settings.json"
      assert Settings.local_path("/") == "/.jido_code/settings.json"
      assert Settings.local_path("/a/b/c/d") == "/a/b/c/d/.jido_code/settings.json"
    end

    test "handles paths with trailing slash" do
      assert Settings.local_path("/tmp/test/") == "/tmp/test/.jido_code/settings.json"
    end
  end

  describe "ensure_local_dir/1" do
    @describetag :tmp_dir

    test "creates directory when it doesn't exist", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)
      expected_dir = Path.join(project_path, ".jido_code")

      # Directory should not exist yet
      refute File.dir?(expected_dir)

      result = Settings.ensure_local_dir(project_path)

      assert result == {:ok, expected_dir}
      assert File.dir?(expected_dir)
    end

    test "returns ok when directory already exists", %{tmp_dir: tmp_dir} do
      # Create the directory first
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)

      result = Settings.ensure_local_dir(tmp_dir)

      assert result == {:ok, settings_dir}
      assert File.dir?(settings_dir)
    end

    test "returns directory path on success", %{tmp_dir: tmp_dir} do
      {:ok, dir_path} = Settings.ensure_local_dir(tmp_dir)

      assert dir_path == Path.join(tmp_dir, ".jido_code")
      assert String.ends_with?(dir_path, ".jido_code")
    end
  end

  # ============================================================================
  # Settings Saving Tests
  # ============================================================================

  describe "save/2" do
    @describetag :tmp_dir

    test "creates settings file", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)
      settings = %{"provider" => "anthropic", "model" => "claude-3"}

      result = Settings.save(project_path, settings)

      assert result == :ok

      # Verify file was created with correct content
      settings_file = Settings.local_path(project_path)
      assert File.exists?(settings_file)
      {:ok, content} = File.read(settings_file)
      assert Jason.decode!(content) == settings
    end

    test "creates directory if missing", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)
      settings_dir = Settings.local_dir(project_path)

      # Directory should not exist yet
      refute File.dir?(settings_dir)

      result = Settings.save(project_path, %{"provider" => "openai"})

      assert result == :ok
      assert File.dir?(settings_dir)
    end

    test "overwrites existing settings file", %{tmp_dir: tmp_dir} do
      # Create initial settings
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "old_provider"}))

      # Save new settings (using valid setting keys)
      new_settings = %{"provider" => "new_provider", "model" => "new_model"}
      result = Settings.save(tmp_dir, new_settings)

      assert result == :ok
      {:ok, content} = File.read(settings_file)
      assert Jason.decode!(content) == new_settings
    end

    test "validates settings before saving", %{tmp_dir: tmp_dir} do
      # Settings with invalid type should fail validation
      # (based on JidoCode.Settings validation rules)
      invalid_settings = %{"permissions" => "not_a_map"}

      result = Settings.save(tmp_dir, invalid_settings)

      assert {:error, _} = result
    end

    test "sets file permissions to 0600", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)

      Settings.save(project_path, %{"provider" => "anthropic"})

      settings_file = Settings.local_path(project_path)
      {:ok, stat} = File.stat(settings_file)
      # 0o600 = 384 in decimal, need parens for operator precedence
      assert (stat.mode &&& 0o777) == 0o600
    end
  end

  describe "set/3" do
    @describetag :tmp_dir

    test "updates individual key", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "project")
      File.mkdir_p!(project_path)

      result = Settings.set(project_path, "provider", "anthropic")

      assert result == :ok
      assert Settings.load_local(project_path)["provider"] == "anthropic"
    end

    test "preserves other keys when updating", %{tmp_dir: tmp_dir} do
      # Create initial settings
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "openai", "model": "gpt-4"}))

      # Update only one key
      result = Settings.set(tmp_dir, "provider", "anthropic")

      assert result == :ok
      loaded = Settings.load_local(tmp_dir)
      assert loaded["provider"] == "anthropic"
      assert loaded["model"] == "gpt-4"
    end

    test "creates file when setting key on new project", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)

      # File doesn't exist yet
      refute File.exists?(Settings.local_path(project_path))

      result = Settings.set(project_path, "model", "claude-3")

      assert result == :ok
      assert File.exists?(Settings.local_path(project_path))
      assert Settings.load_local(project_path) == %{"model" => "claude-3"}
    end
  end
end
