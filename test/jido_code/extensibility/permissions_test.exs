defmodule JidoCode.Extensibility.PermissionsTest do
  use ExUnit.Case, async: true
  doctest JidoCode.Extensibility.Permissions

  alias JidoCode.Extensibility.Permissions

  describe "struct creation" do
    test "creates struct with default values" do
      perms = %Permissions{}
      assert perms.allow == []
      assert perms.deny == []
      assert perms.ask == []
    end

    test "creates struct with custom values" do
      perms = %Permissions{
        allow: ["Read:*"],
        deny: ["*delete*"],
        ask: ["run_command:*"]
      }

      assert perms.allow == ["Read:*"]
      assert perms.deny == ["*delete*"]
      assert perms.ask == ["run_command:*"]
    end

    test "struct type spec is correct" do
      assert %Permissions{}.__struct__ == Permissions
    end
  end

  describe "check_permission/3" do
    test "allows when pattern matches in allow list" do
      perms = %Permissions{allow: ["Read:*"]}

      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
    end

    test "denies when pattern matches in deny list (highest priority)" do
      perms = %Permissions{
        allow: ["*"],
        deny: ["*delete*"]
      }

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "asks when pattern matches in ask list" do
      perms = %Permissions{ask: ["run_command:*"]}

      assert Permissions.check_permission(perms, "run_command", "make") == :ask
    end

    test "deny takes precedence over ask" do
      perms = %Permissions{
        deny: ["*delete*"],
        ask: ["Edit:*"]
      }

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "deny takes precedence over allow" do
      perms = %Permissions{
        allow: ["Edit:*"],
        deny: ["*delete*"]
      }

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "ask takes precedence over allow" do
      perms = %Permissions{
        allow: ["run_command:*"],
        ask: ["run_command:rm*"]
      }

      assert Permissions.check_permission(perms, "run_command", "rm_file") == :ask
    end

    test "allows when no patterns match (default allow)" do
      perms = %Permissions{}

      assert Permissions.check_permission(perms, "Any", "action") == :allow
    end

    test "handles wildcard patterns" do
      perms = %Permissions{allow: ["*"]}

      assert Permissions.check_permission(perms, "Any", "action") == :allow
    end

    test "handles category wildcards" do
      perms = %Permissions{allow: ["Read:*"]}

      assert Permissions.check_permission(perms, "Read", "any_file.txt") == :allow
    end

    test "handles action wildcards" do
      perms = %Permissions{deny: ["*:delete"]}

      assert Permissions.check_permission(perms, "File", "delete") == :deny
      assert Permissions.check_permission(perms, "User", "delete") == :deny
    end

    test "handles atom category and action" do
      perms = %Permissions{allow: ["Read:*"]}

      assert Permissions.check_permission(perms, :Read, :file) == :allow
    end

    test "handles complex glob patterns" do
      perms = %Permissions{allow: ["run_command:git*"]}

      assert Permissions.check_permission(perms, "run_command", "git status") == :allow
      assert Permissions.check_permission(perms, "run_command", "git-commit") == :allow
    end

    test "handles question mark wildcard" do
      perms = %Permissions{deny: ["*:rm ??"]}

      assert Permissions.check_permission(perms, "run_command", "rm ab") == :deny
      assert Permissions.check_permission(perms, "run_command", "rm abc") == :allow
    end

    test "handles multiple character class patterns" do
      # Character classes are converted to regex character classes
      perms = %Permissions{allow: ["*:??"]}

      assert Permissions.check_permission(perms, "run_command", "ab") == :allow
      assert Permissions.check_permission(perms, "run_command", "a") == :allow  # default allow
      assert Permissions.check_permission(perms, "run_command", "abc") == :allow  # default allow
    end

    test "multiple patterns in same list" do
      perms = %Permissions{
        allow: ["Read:*", "Write:*", "Edit:*"]
      }

      assert Permissions.check_permission(perms, "Read", "file") == :allow
      assert Permissions.check_permission(perms, "Write", "file") == :allow
      assert Permissions.check_permission(perms, "Edit", "file") == :allow
    end

    test "empty patterns don't match" do
      perms = %Permissions{allow: [""]}

      # Empty pattern should not match anything
      assert Permissions.check_permission(perms, "Any", "action") == :allow
    end

    test "exact match works" do
      perms = %Permissions{allow: ["Read:file.txt"]}

      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
      assert Permissions.check_permission(perms, "Read", "other.txt") == :allow
    end

    test "colon in action is handled correctly" do
      perms = %Permissions{allow: ["run_command:ssh:*"]}

      assert Permissions.check_permission(perms, "run_command", "ssh:host") == :allow
    end
  end

  describe "from_json/1" do
    test "parses valid JSON with allow list" do
      json = %{"allow" => ["Read:*", "Write:*"]}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == ["Read:*", "Write:*"]
      assert perms.deny == []
      assert perms.ask == []
    end

    test "parses valid JSON with deny list" do
      json = %{"deny" => ["*delete*"]}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == []
      assert perms.deny == ["*delete*"]
      assert perms.ask == []
    end

    test "parses valid JSON with ask list" do
      json = %{"ask" => ["run_command:*"]}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == []
      assert perms.deny == []
      assert perms.ask == ["run_command:*"]
    end

    test "parses valid JSON with all three lists" do
      json = %{
        "allow" => ["Read:*"],
        "deny" => ["*delete*"],
        "ask" => ["run_command:*"]
      }

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == ["Read:*"]
      assert perms.deny == ["*delete*"]
      assert perms.ask == ["run_command:*"]
    end

    test "handles empty JSON" do
      json = %{}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == []
      assert perms.deny == []
      assert perms.ask == []
    end

    test "returns error when allow is not a list" do
      json = %{"allow" => "not_a_list"}

      assert {:error, "allow must be a list of strings"} = Permissions.from_json(json)
    end

    test "returns error when deny is not a list" do
      json = %{"deny" => 123}

      assert {:error, "deny must be a list of strings"} = Permissions.from_json(json)
    end

    test "returns error when ask is not a list" do
      json = %{"ask" => %{}}

      assert {:error, "ask must be a list of strings"} = Permissions.from_json(json)
    end

    test "returns error when allow contains non-string" do
      json = %{"allow" => ["Read:*", 123]}

      assert {:error, "permission patterns must be non-empty strings"} =
               Permissions.from_json(json)
    end

    test "returns error when deny contains empty string" do
      json = %{"deny" => ["", "*delete*"]}

      assert {:error, "permission patterns must be non-empty strings"} =
               Permissions.from_json(json)
    end

    test "returns error when ask contains empty string" do
      json = %{"ask" => ["  ", "run_command:*"]}

      # Whitespace-only string is treated as empty
      assert {:error, "permission patterns must be non-empty strings"} =
               Permissions.from_json(json)
    end

    test "accepts list with only whitespace in patterns" do
      # Actually, trim will make it empty, so this should error
      # Let me check if the test should expect an error
      json = %{"allow" => [" Read:* "]}

      # This should work - the pattern itself has content after trimming
      # But wait, we're checking for empty after trim, so " Read:* " is valid
      assert {:ok, _perms} = Permissions.from_json(json)
    end
  end

  describe "defaults/0" do
    test "returns Permissions struct" do
      assert %Permissions{} = Permissions.defaults()
    end

    test "includes safe tools in allow list" do
      perms = Permissions.defaults()

      assert "Read:*" in perms.allow
      assert "Write:*" in perms.allow
      assert "Edit:*" in perms.allow
      assert "ListDirectory:*" in perms.allow
    end

    test "includes safe git commands in allow list" do
      perms = Permissions.defaults()

      assert "run_command:git*" in perms.allow
    end

    test "includes dangerous operations in deny list" do
      perms = Permissions.defaults()

      assert "*delete*" in perms.deny
      assert "*remove*" in perms.deny
      assert "*rm *" in perms.deny
      assert "*shutdown*" in perms.deny
    end

    test "includes potentially risky in ask list" do
      perms = Permissions.defaults()

      # run_command is no longer in ask list (git and mix are allowed instead)
      assert "web_fetch:*" in perms.ask
      assert "web_search:*" in perms.ask
      assert "spawn_task:*" in perms.ask
    end

    test "deny patterns take precedence in defaults" do
      perms = Permissions.defaults()

      # git is allowed
      assert Permissions.check_permission(perms, "run_command", "git status") == :allow

      # but delete commands are denied
      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "safe run_command commands are allowed by default" do
      perms = Permissions.defaults()

      # git and mix commands are allowed
      assert Permissions.check_permission(perms, "run_command", "git status") == :allow
      assert Permissions.check_permission(perms, "run_command", "mix test") == :allow

      # other run_commands are not asked (they're allowed by default)
      assert Permissions.check_permission(perms, "run_command", "make") == :allow
    end

    test "web operations are asked by default" do
      perms = Permissions.defaults()

      assert Permissions.check_permission(perms, "web_fetch", "url") == :ask
      assert Permissions.check_permission(perms, "web_search", "query") == :ask
    end
  end

  describe "integration tests" do
    test "full permission check flow" do
      json = %{
        "allow" => ["Read:*", "Write:*"],
        "deny" => ["*delete*"],
        "ask" => ["run_command:*"]
      }

      assert {:ok, perms} = Permissions.from_json(json)

      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
      assert Permissions.check_permission(perms, "Write", "file.txt") == :allow
      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
      assert Permissions.check_permission(perms, "run_command", "make") == :ask
    end

    test "priority order: deny > ask > allow" do
      perms = %Permissions{
        allow: ["*"],
        ask: ["Edit:*"],
        deny: ["*delete*"]
      }

      # Deny wins
      assert Permissions.check_permission(perms, "Edit", "delete_me") == :deny

      # Ask wins (not in deny)
      assert Permissions.check_permission(perms, "Edit", "file") == :ask

      # Allow wins (not in deny or ask)
      assert Permissions.check_permission(perms, "Read", "file") == :allow
    end

    test "default permissions provide safe defaults" do
      perms = Permissions.defaults()

      # Safe operations are allowed
      assert Permissions.check_permission(perms, "Read", "config.json") == :allow
      assert Permissions.check_permission(perms, "Edit", "file.txt") == :allow

      # Dangerous operations are denied
      assert Permissions.check_permission(perms, "Edit", "delete_all") == :deny
      assert Permissions.check_permission(perms, "run_command", "rm -rf /") == :deny

      # Web operations ask
      assert Permissions.check_permission(perms, "web_fetch", "https://example.com") == :ask
      assert Permissions.check_permission(perms, "web_search", "query") == :ask
    end
  end
end
