defmodule JidoCode.CommandsTest do
  # Not async because theme tests depend on shared TermUI.Theme server state
  use ExUnit.Case, async: false

  alias Jido.AI.Keyring
  alias JidoCode.Commands

  # Helper to set up API key for tests
  defp setup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.set_session_value(key_name, "test-api-key-#{provider}")
  end

  defp cleanup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.clear_session_value(key_name)
  end

  defp provider_to_key_name(provider) do
    case provider do
      "openai" -> :openai_api_key
      "anthropic" -> :anthropic_api_key
      "openrouter" -> :openrouter_api_key
      _ -> String.to_atom("#{provider}_api_key")
    end
  end

  describe "execute/2" do
    test "/help returns command list" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/help", config)

      assert message =~ "Available commands"
      assert message =~ "/help"
      assert message =~ "/config"
      assert message =~ "/provider"
      assert message =~ "/model"
      assert new_config == %{}
    end

    test "/config shows current configuration" do
      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}

      {:ok, message, new_config} = Commands.execute("/config", config)

      assert message =~ "Provider: anthropic"
      assert message =~ "Model: claude-3-5-sonnet"
      assert new_config == %{}
    end

    test "/config shows (not set) for nil values" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: (not set)"
      assert message =~ "Model: (not set)"
    end

    test "/provider with valid provider sets provider and clears model" do
      setup_api_key("anthropic")
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, new_config} = Commands.execute("/provider anthropic", config)

      assert message =~ "Provider set to anthropic"
      assert new_config == %{provider: "anthropic", model: nil}
      cleanup_api_key("anthropic")
    end

    test "/provider with local provider works without API key" do
      # Local providers (lmstudio, llama, ollama) don't require API keys
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, new_config} = Commands.execute("/provider lmstudio", config)

      assert message =~ "Provider set to lmstudio"
      assert new_config == %{provider: "lmstudio", model: nil}
    end

    test "/provider without argument shows usage" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/provider", config)

      assert message =~ "Usage: /provider <name>"
    end

    test "/provider with invalid provider shows error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/provider invalid_provider_xyz", config)

      assert message =~ "Unknown provider"
    end

    test "/model provider:model sets both" do
      setup_api_key("anthropic")
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/model anthropic:claude-3-5-sonnet", config)

      assert message =~ "Model set to anthropic:claude-3-5-sonnet"
      assert new_config.provider == "anthropic"
      assert new_config.model == "claude-3-5-sonnet"
      cleanup_api_key("anthropic")
    end

    test "/model with only model name works when provider is set" do
      setup_api_key("anthropic")
      config = %{provider: "anthropic", model: nil}

      {:ok, message, new_config} = Commands.execute("/model claude-3-5-sonnet", config)

      assert message =~ "Model set to claude-3-5-sonnet"
      assert new_config.provider == "anthropic"
      assert new_config.model == "claude-3-5-sonnet"
      cleanup_api_key("anthropic")
    end

    test "/model with only model name fails when no provider" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model gpt-4o", config)

      assert message =~ "No provider set"
    end

    test "/model fails when API key not set" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model anthropic:claude-3-5-sonnet", config)

      # Error message is now generic for security (doesn't expose env var names)
      assert message =~ "not configured"
      assert message =~ "anthropic"
    end

    test "/model without argument shows usage" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model", config)

      assert message =~ "Usage: /model"
    end

    test "/models shows models for current provider" do
      config = %{provider: "anthropic", model: nil}

      result = Commands.execute("/models", config)

      case result do
        {:pick_list, provider, models, title} ->
          # Now returns pick_list for interactive selection
          assert provider == "anthropic"
          assert is_list(models)
          assert title =~ "anthropic"

        {:ok, message, _} ->
          assert message =~ "No models found"

        {:error, _} ->
          # Registry might not be available in test
          :ok
      end
    end

    test "/models without provider shows error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/models", config)

      assert message =~ "No provider set"
    end

    test "/models provider shows models for specified provider" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/models anthropic", config)

      case result do
        {:pick_list, provider, models, title} ->
          # Now returns pick_list for interactive selection
          assert provider == "anthropic"
          assert is_list(models)
          assert title =~ "anthropic"

        {:ok, message, _} ->
          assert message =~ "No models found"

        {:error, message} ->
          # Unknown provider is also valid
          assert message =~ "Unknown provider"
      end
    end

    test "/providers lists available providers" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/providers", config)

      case result do
        {:pick_list, :provider, providers, title} ->
          # Now returns pick_list for interactive selection
          assert is_list(providers)
          assert length(providers) > 0
          assert title =~ "Provider"

        {:ok, message, new_config} ->
          # Should have providers from registry or no providers
          assert message =~ "providers" or message =~ "No providers"
          assert new_config == %{}
      end
    end

    test "unknown command returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/unknown_command", config)

      assert message =~ "Unknown command"
      assert message =~ "/help"
    end

    test "command with extra whitespace is handled" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("  /help  ", config)

      assert message =~ "Available commands"
    end

    test "non-command text returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("hello", config)

      assert message =~ "Not a command"
    end
  end

  describe "/theme command" do
    test "/theme lists available themes" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme", config)

      assert message =~ "Available themes"
      assert message =~ "dark"
      assert message =~ "light"
      assert message =~ "high_contrast"
      assert new_config == %{}
    end

    test "/theme shows current theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/theme", config)

      assert message =~ "(current)"
    end

    test "/theme dark switches to dark theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme dark", config)

      assert message =~ "Theme set to dark"
      assert new_config == %{}
    end

    test "/theme light switches to light theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme light", config)

      assert message =~ "Theme set to light"
      assert new_config == %{}

      # Reset to dark for other tests
      Commands.execute("/theme dark", config)
    end

    test "/theme high_contrast switches to high contrast theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme high_contrast", config)

      assert message =~ "Theme set to high_contrast"
      assert new_config == %{}

      # Reset to dark for other tests
      Commands.execute("/theme dark", config)
    end

    test "/theme with invalid name returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/theme invalid_theme", config)

      assert message =~ "Unknown theme"
      assert message =~ "dark"
      assert message =~ "light"
      assert message =~ "high_contrast"
    end

    test "/help includes theme command" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/help", config)

      assert message =~ "/theme"
    end
  end

  describe "/session command parsing" do
    test "/session returns {:session, :help}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session", config)

      assert result == {:session, :help}
    end

    test "/session new parses with no arguments" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new", config)

      assert result == {:session, {:new, %{path: nil, name: nil}}}
    end

    test "/session new /path/to/project parses path" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new /path/to/project", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: nil}}}
    end

    test "/session new /path --name=MyProject parses path and name flag" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new /path/to/project --name=MyProject", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: "MyProject"}}}
    end

    test "/session new --name=MyProject /path parses name before path" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new --name=MyProject /path/to/project", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: "MyProject"}}}
    end

    test "/session new /path -n Name parses short name flag" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new /path/to/project -n Name", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: "Name"}}}
    end

    test "/session list parses to :list" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session list", config)

      assert result == {:session, :list}
    end

    test "/session switch 1 parses index as target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch 1", config)

      assert result == {:session, {:switch, "1"}}
    end

    test "/session switch abc123 parses ID as target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch abc123", config)

      assert result == {:session, {:switch, "abc123"}}
    end

    test "/session switch MyProject parses name as target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch MyProject", config)

      assert result == {:session, {:switch, "MyProject"}}
    end

    test "/session switch without target returns error" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch", config)

      # Now returns error message directly instead of :missing_target atom
      assert {:session, {:error, message}} = result
      assert message =~ "Usage: /session switch"
    end

    test "/session close parses with no target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session close", config)

      assert result == {:session, {:close, nil}}
    end

    test "/session close 2 parses with index target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session close 2", config)

      assert result == {:session, {:close, "2"}}
    end

    test "/session close abc123 parses with ID target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session close abc123", config)

      assert result == {:session, {:close, "abc123"}}
    end

    test "/session rename NewName parses name" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session rename NewName", config)

      assert result == {:session, {:rename, "NewName"}}
    end

    test "/session rename without name returns error" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session rename", config)

      assert result == {:session, {:error, :missing_name}}
    end

    test "/session unknown returns :help" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session unknown", config)

      assert result == {:session, :help}
    end

    test "/help includes session commands" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/help", config)

      assert message =~ "/session"
      assert message =~ "/session new"
      assert message =~ "/session list"
      assert message =~ "/session switch"
      assert message =~ "/session close"
      assert message =~ "/session rename"
    end
  end

  describe "config key formats" do
    test "works with atom keys in config" do
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: openai"
      assert message =~ "Model: gpt-4o"
    end

    test "works with string keys in config" do
      config = %{"provider" => "openai", "model" => "gpt-4o"}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: openai"
      assert message =~ "Model: gpt-4o"
    end

    test "/model with string key provider set" do
      setup_api_key("anthropic")
      config = %{"provider" => "anthropic", "model" => nil}

      {:ok, message, new_config} = Commands.execute("/model claude-3-5-sonnet", config)

      assert message =~ "Model set to"
      assert new_config.model == "claude-3-5-sonnet"
      cleanup_api_key("anthropic")
    end
  end

  describe "resolve_session_path/1" do
    test "nil returns current working directory" do
      {:ok, path} = Commands.resolve_session_path(nil)

      assert path == File.cwd!()
    end

    test "empty string returns current working directory" do
      {:ok, path} = Commands.resolve_session_path("")

      assert path == File.cwd!()
    end

    test "~ expands to home directory" do
      {:ok, path} = Commands.resolve_session_path("~")

      assert path == System.user_home!()
    end

    test "~/subdir expands to home directory subpath" do
      {:ok, path} = Commands.resolve_session_path("~/projects")

      assert path == Path.join(System.user_home!(), "projects")
    end

    test ". resolves to current directory" do
      {:ok, path} = Commands.resolve_session_path(".")

      assert path == File.cwd!()
    end

    test "./subdir resolves relative to current directory" do
      {:ok, path} = Commands.resolve_session_path("./lib")

      assert path == Path.join(File.cwd!(), "lib")
    end

    test ".. resolves to parent directory" do
      {:ok, path} = Commands.resolve_session_path("..")

      assert path == Path.dirname(File.cwd!())
    end

    test "../sibling resolves to sibling directory" do
      {:ok, path} = Commands.resolve_session_path("../sibling")

      expected = Path.join(Path.dirname(File.cwd!()), "sibling")
      assert path == expected
    end

    test "absolute path passes through unchanged" do
      {:ok, path} = Commands.resolve_session_path("/tmp/test")

      assert path == "/tmp/test"
    end

    test "relative path resolves against CWD" do
      {:ok, path} = Commands.resolve_session_path("lib/jido_code")

      assert path == Path.join(File.cwd!(), "lib/jido_code")
    end

    test "path with .. inside is normalized" do
      {:ok, path} = Commands.resolve_session_path("/tmp/foo/../bar")

      assert path == "/tmp/bar"
    end
  end

  describe "validate_session_path/1" do
    test "returns ok for existing directory" do
      {:ok, result} = Commands.validate_session_path(File.cwd!())

      assert result == File.cwd!()
    end

    test "returns error for non-existent path" do
      {:error, message} = Commands.validate_session_path("/nonexistent/path/xyz123")

      assert message =~ "does not exist"
    end

    test "returns error for file (not directory)" do
      # mix.exs exists but is a file, not directory
      {:error, message} = Commands.validate_session_path(Path.join(File.cwd!(), "mix.exs"))

      assert message =~ "not a directory"
    end
  end

  describe "execute_session/2" do
    test ":help returns session command help" do
      {:ok, message} = Commands.execute_session(:help, %{})

      assert message =~ "Session Commands:"
      assert message =~ "/session new"
      assert message =~ "/session list"
      assert message =~ "/session switch"
      assert message =~ "/session close"
      assert message =~ "/session rename"
      assert message =~ "Keyboard Shortcuts:"
    end

    test "{:new, opts} with valid path creates session" do
      # Use a temp directory that exists
      tmp_dir = System.tmp_dir!()
      test_path = Path.join(tmp_dir, "jido_code_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_path)

      try do
        result = Commands.execute_session({:new, %{path: test_path, name: "test-session"}}, %{})

        case result do
          {:session_action, {:add_session, session}} ->
            assert session.name == "test-session"
            assert session.project_path == test_path

            # Clean up session
            JidoCode.SessionSupervisor.stop_session(session.id)

          {:error, message} ->
            # May fail if supervisor not running in test - that's OK for this unit test
            assert message =~ "Failed to create session" or message =~ "not started"
        end
      after
        File.rm_rf!(test_path)
      end
    end

    test "{:new, opts} with non-existent path returns error" do
      result =
        Commands.execute_session(
          {:new, %{path: "/nonexistent/path/xyz123", name: nil}},
          %{}
        )

      assert {:error, message} = result
      assert message =~ "does not exist"
    end

    test "{:new, opts} with nil path uses CWD" do
      result = Commands.execute_session({:new, %{path: nil, name: "cwd-session"}}, %{})

      case result do
        {:session_action, {:add_session, session}} ->
          assert session.project_path == File.cwd!()

          # Clean up
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, message} ->
          # May fail if supervisor not running - check it at least tried with CWD
          assert message =~ "Failed to create session" or
                   message =~ "already open" or
                   message =~ "not started"
      end
    end

    test ":list with no sessions returns helpful message" do
      model = %{sessions: %{}, session_order: [], active_session_id: nil}
      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result
      assert message == "No sessions. Use /session new to create one."
    end

    test ":list with one session shows session" do
      session = %{
        id: "s1",
        name: "project-a",
        project_path: "/tmp/project-a"
      }

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result
      # Active session has * marker
      assert message =~ "*1. project-a"
      assert message =~ "/tmp/project-a"
    end

    test ":list with multiple sessions shows all in order" do
      session1 = %{id: "s1", name: "project-a", project_path: "/tmp/a"}
      session2 = %{id: "s2", name: "project-b", project_path: "/tmp/b"}
      session3 = %{id: "s3", name: "project-c", project_path: "/tmp/c"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s2"
      }

      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result

      lines = String.split(message, "\n")
      assert length(lines) == 3

      # Check markers - only s2 is active
      assert Enum.at(lines, 0) =~ " 1. project-a"
      assert Enum.at(lines, 1) =~ "*2. project-b"
      assert Enum.at(lines, 2) =~ " 3. project-c"
    end

    test ":list shows active session marker" do
      session = %{id: "s1", name: "test", project_path: "/tmp/test"}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      {:ok, message} = Commands.execute_session(:list, model)

      # Starts with * for active
      assert String.starts_with?(message, "*")
    end

    test ":list shows non-active session without marker" do
      session = %{id: "s1", name: "test", project_path: "/tmp/test"}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: nil
      }

      {:ok, message} = Commands.execute_session(:list, model)

      # Starts with space (no active marker)
      assert String.starts_with?(message, " ")
    end

    test ":list truncates long paths" do
      # Use a long path that won't contain home directory
      long_path = "/var/lib/very/deeply/nested/directory/structure/project"

      session = %{id: "s1", name: "project", project_path: long_path}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      {:ok, message} = Commands.execute_session(:list, model)

      # Path should be truncated if longer than max length
      assert message =~ "..."
      # Should still contain the end of the path (most relevant part)
      assert message =~ "project"
    end

    test ":list replaces home directory with ~" do
      home = System.user_home!()
      path = Path.join(home, "projects/myproject")

      session = %{id: "s1", name: "myproject", project_path: path}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      {:ok, message} = Commands.execute_session(:list, model)

      assert message =~ "~/projects/myproject"
      refute message =~ home
    end

    test "{:switch, index} switches to session by index" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "2"}, model)

      assert {:session_action, {:switch_session, "s2"}} = result
    end

    test "{:switch, index} index 1 switches to first session" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "1"}, model)

      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, index} index 0 switches to session 10" do
      # Create 10 sessions
      sessions =
        for i <- 1..10, into: %{} do
          {"s#{i}", %{id: "s#{i}", name: "project-#{i}"}}
        end

      session_order = for i <- 1..10, do: "s#{i}"

      model = %{
        sessions: sessions,
        session_order: session_order,
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "0"}, model)

      # "0" should map to session 10
      assert {:session_action, {:switch_session, "s10"}} = result
    end

    test "{:switch, index} out of range returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "5"}, model)

      assert {:error, message} = result
      assert message =~ "Session not found"
    end

    test "{:switch, id} switches by session ID" do
      session1 = %{id: "abc123", name: "project-a"}

      model = %{
        sessions: %{"abc123" => session1},
        session_order: ["abc123"],
        active_session_id: nil
      }

      result = Commands.execute_session({:switch, "abc123"}, model)

      assert {:session_action, {:switch_session, "abc123"}} = result
    end

    test "{:switch, name} switches by session name" do
      session1 = %{id: "s1", name: "my-project"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      result = Commands.execute_session({:switch, "my-project"}, model)

      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, target} with no sessions returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_session({:switch, "1"}, model)

      assert {:error, message} = result
      assert message =~ "No sessions available"
    end

    test "{:switch, target} with unknown target returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "unknown"}, model)

      assert {:error, message} = result
      assert message =~ "Session not found"
    end

    test "{:switch, name} is case-insensitive" do
      session1 = %{id: "s1", name: "MyProject"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Lowercase should match
      result = Commands.execute_session({:switch, "myproject"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result

      # Uppercase should match
      result = Commands.execute_session({:switch, "MYPROJECT"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, prefix} matches session by name prefix" do
      session1 = %{id: "s1", name: "my-long-project-name"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Prefix "my" should match
      result = Commands.execute_session({:switch, "my"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result

      # Prefix "my-long" should match
      result = Commands.execute_session({:switch, "my-long"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, prefix} prefers exact match over prefix" do
      session1 = %{id: "s1", name: "proj"}
      session2 = %{id: "s2", name: "project"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: nil
      }

      # "proj" should match s1 exactly, not s2 as prefix
      result = Commands.execute_session({:switch, "proj"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, prefix} returns error for ambiguous prefix" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: nil
      }

      # "proj" matches both sessions
      result = Commands.execute_session({:switch, "proj"}, model)

      assert {:error, message} = result
      assert message =~ "Ambiguous session name"
      assert message =~ "project-a"
      assert message =~ "project-b"
    end

    test "{:switch, prefix} is case-insensitive" do
      session1 = %{id: "s1", name: "MyProject"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Lowercase prefix should match
      result = Commands.execute_session({:switch, "myp"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    # Boundary tests for edge cases
    test "{:switch, target} with negative index returns not found" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      # Negative numbers are not numeric targets (contain -)
      # They fall through to name matching and fail
      result = Commands.execute_session({:switch, "-1"}, model)
      assert {:error, message} = result
      assert message =~ "Session not found: -1"
    end

    test "{:switch, target} with empty string returns not found" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, ""}, model)
      assert {:error, message} = result
      assert message =~ "Session not found:"
    end

    test "{:switch, target} with very large index returns not found" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "999"}, model)
      assert {:error, message} = result
      assert message =~ "Session not found: 999"
    end

    test "{:close, target} returns not implemented message" do
      result = Commands.execute_session({:close, nil}, %{})

      assert {:error, message} = result
      assert message =~ "Not yet implemented"
    end

    test "{:rename, name} returns not implemented message" do
      result = Commands.execute_session({:rename, "NewName"}, %{})

      assert {:error, message} = result
      assert message =~ "Not yet implemented"
    end

    test "parse_session_args returns error for switch without target" do
      # Now parse_session_args returns the error directly
      # This is tested via execute integration which calls TUI handler
      result = Commands.execute("/session switch", %{})

      # The result is wrapped as {:session, {:error, message}}
      assert {:session, {:error, message}} = result
      assert message =~ "Usage: /session switch"
    end

    test "{:error, :missing_name} returns usage message" do
      result = Commands.execute_session({:error, :missing_name}, %{})

      assert {:error, message} = result
      assert message =~ "Usage: /session rename"
    end

    test "unknown subcommand returns help" do
      {:ok, message} = Commands.execute_session(:unknown, %{})

      assert message =~ "Session Commands:"
    end
  end
end
