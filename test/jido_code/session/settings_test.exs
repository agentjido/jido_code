defmodule JidoCode.Session.SettingsTest do
  use ExUnit.Case, async: true

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
end
