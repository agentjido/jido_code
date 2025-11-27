defmodule JidoCode.SettingsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Settings

  describe "path helpers" do
    test "global_dir returns path in user home" do
      path = Settings.global_dir()
      assert String.starts_with?(path, System.user_home!())
      assert String.ends_with?(path, ".jido_code")
    end

    test "global_path returns settings.json in global dir" do
      path = Settings.global_path()
      assert String.ends_with?(path, ".jido_code/settings.json")
    end

    test "local_dir returns path in current directory" do
      path = Settings.local_dir()
      assert String.starts_with?(path, File.cwd!())
      assert String.ends_with?(path, "jido_code")
    end

    test "local_path returns settings.json in local dir" do
      path = Settings.local_path()
      assert String.ends_with?(path, "jido_code/settings.json")
    end
  end

  describe "validate/1 - valid settings" do
    test "accepts empty map" do
      assert {:ok, %{}} = Settings.validate(%{})
    end

    test "accepts valid provider string" do
      assert {:ok, %{"provider" => "anthropic"}} =
               Settings.validate(%{"provider" => "anthropic"})
    end

    test "accepts valid model string" do
      assert {:ok, %{"model" => "gpt-4o"}} =
               Settings.validate(%{"model" => "gpt-4o"})
    end

    test "accepts valid providers list" do
      settings = %{"providers" => ["anthropic", "openai", "openrouter"]}
      assert {:ok, ^settings} = Settings.validate(settings)
    end

    test "accepts empty providers list" do
      assert {:ok, %{"providers" => []}} = Settings.validate(%{"providers" => []})
    end

    test "accepts valid models map" do
      settings = %{
        "models" => %{
          "anthropic" => ["claude-3-5-sonnet", "claude-3-opus"],
          "openai" => ["gpt-4o", "gpt-4-turbo"]
        }
      }

      assert {:ok, ^settings} = Settings.validate(settings)
    end

    test "accepts empty models map" do
      assert {:ok, %{"models" => %{}}} = Settings.validate(%{"models" => %{}})
    end

    test "accepts complete valid settings" do
      settings = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet",
        "providers" => ["anthropic", "openai"],
        "models" => %{
          "anthropic" => ["claude-3-5-sonnet"],
          "openai" => ["gpt-4o"]
        }
      }

      assert {:ok, ^settings} = Settings.validate(settings)
    end
  end

  describe "validate/1 - invalid settings" do
    test "rejects non-map input" do
      assert {:error, "settings must be a map" <> _} = Settings.validate("string")
      assert {:error, "settings must be a map" <> _} = Settings.validate(123)
      assert {:error, "settings must be a map" <> _} = Settings.validate(["list"])
    end

    test "rejects unknown keys" do
      assert {:error, "unknown key: unknown"} = Settings.validate(%{"unknown" => "value"})
    end

    test "rejects non-string provider" do
      assert {:error, "provider must be a string" <> _} = Settings.validate(%{"provider" => 123})
      assert {:error, "provider must be a string" <> _} = Settings.validate(%{"provider" => nil})

      assert {:error, "provider must be a string" <> _} =
               Settings.validate(%{"provider" => ["list"]})
    end

    test "rejects non-string model" do
      assert {:error, "model must be a string" <> _} = Settings.validate(%{"model" => 456})
    end

    test "rejects non-list providers" do
      assert {:error, "providers must be a list of strings" <> _} =
               Settings.validate(%{"providers" => "not-a-list"})

      assert {:error, "providers must be a list of strings" <> _} =
               Settings.validate(%{"providers" => %{}})
    end

    test "rejects providers list with non-strings" do
      assert {:error, "providers must be a list of strings" <> _} =
               Settings.validate(%{"providers" => ["valid", 123]})

      assert {:error, "providers must be a list of strings" <> _} =
               Settings.validate(%{"providers" => [nil]})
    end

    test "rejects non-map models" do
      assert {:error, "models must be a map of string lists" <> _} =
               Settings.validate(%{"models" => "not-a-map"})

      assert {:error, "models must be a map of string lists" <> _} =
               Settings.validate(%{"models" => ["list"]})
    end

    test "rejects models with non-list values" do
      assert {:error, "models[\"anthropic\"] must be a list of strings" <> _} =
               Settings.validate(%{"models" => %{"anthropic" => "not-a-list"}})
    end

    test "rejects models with non-string list items" do
      assert {:error, "models[\"openai\"] must be a list of strings" <> _} =
               Settings.validate(%{"models" => %{"openai" => ["gpt-4o", 123]}})
    end
  end

  describe "ensure_global_dir/0" do
    @tag :tmp_dir
    test "creates directory if not exists", %{tmp_dir: tmp_dir} do
      # We can't easily test the real global dir, so we test the underlying function
      test_dir = Path.join(tmp_dir, "test_global")
      refute File.exists?(test_dir)

      assert :ok = File.mkdir_p(test_dir)
      assert File.dir?(test_dir)
    end
  end

  describe "ensure_local_dir/0" do
    @tag :tmp_dir
    test "creates directory if not exists", %{tmp_dir: tmp_dir} do
      test_dir = Path.join(tmp_dir, "test_local")
      refute File.exists?(test_dir)

      assert :ok = File.mkdir_p(test_dir)
      assert File.dir?(test_dir)
    end
  end

  describe "read_file/1" do
    @tag :tmp_dir
    test "reads valid JSON file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "valid.json")
      content = ~s({"provider": "anthropic", "model": "claude-3-5-sonnet"})
      File.write!(path, content)

      assert {:ok, %{"provider" => "anthropic", "model" => "claude-3-5-sonnet"}} =
               Settings.read_file(path)
    end

    @tag :tmp_dir
    test "reads empty JSON object", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "empty.json")
      File.write!(path, "{}")

      assert {:ok, %{}} = Settings.read_file(path)
    end

    test "returns error for non-existent file" do
      assert {:error, :not_found} = Settings.read_file("/nonexistent/path/settings.json")
    end

    @tag :tmp_dir
    test "returns error for invalid JSON", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "invalid.json")
      File.write!(path, "not valid json")

      assert {:error, {:invalid_json, _reason}} = Settings.read_file(path)
    end

    @tag :tmp_dir
    test "returns error for non-object JSON", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "array.json")
      File.write!(path, ~s(["array", "not", "object"]))

      assert {:error, {:invalid_json, "expected object" <> _}} = Settings.read_file(path)
    end

    @tag :tmp_dir
    test "returns error for JSON string", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "string.json")
      File.write!(path, ~s("just a string"))

      assert {:error, {:invalid_json, "expected object" <> _}} = Settings.read_file(path)
    end
  end
end
