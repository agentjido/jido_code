defmodule JidoCode.Session.SettingsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Session.Settings

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
