defmodule JidoCode.Extensibility.PermissionsTest do
  use ExUnit.Case, async: true
  doctest JidoCode.Extensibility.Permissions

  alias JidoCode.Extensibility.{Permissions, Error}

  describe "struct creation" do
    test "creates struct with default values" do
      perms = %Permissions{}
      assert perms.allow == []
      assert perms.deny == []
      assert perms.ask == []
      assert perms.default_mode == :deny
    end

    test "creates struct with custom values" do
      perms = %Permissions{
        allow: ["Read:*"],
        deny: ["*delete*"],
        ask: ["run_command:*"],
        default_mode: :allow
      }

      assert perms.allow == ["Read:*"]
      assert perms.deny == ["*delete*"]
      assert perms.ask == ["run_command:*"]
      assert perms.default_mode == :allow
    end

    test "struct type spec is correct" do
      assert %Permissions{}.__struct__ == Permissions
    end
  end

  describe "check_permission/3" do
    test "allows when pattern matches in allow list" do
      perms = %Permissions{allow: ["Read:*"], default_mode: :deny}

      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
    end

    test "denies when pattern matches in deny list (highest priority)" do
      perms = %Permissions{
        allow: ["*"],
        deny: ["*delete*"],
        default_mode: :allow
      }

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "asks when pattern matches in ask list" do
      perms = %Permissions{ask: ["run_command:*"], default_mode: :deny}

      assert Permissions.check_permission(perms, "run_command", "make") == :ask
    end

    test "deny takes precedence over ask" do
      perms = %Permissions{
        deny: ["*delete*"],
        ask: ["Edit:*"],
        default_mode: :allow
      }

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "deny takes precedence over allow" do
      perms = %Permissions{
        allow: ["Edit:*"],
        deny: ["*delete*"],
        default_mode: :allow
      }

      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny
    end

    test "ask takes precedence over allow" do
      perms = %Permissions{
        allow: ["run_command:*"],
        ask: ["run_command:rm*"],
        default_mode: :deny
      }

      assert Permissions.check_permission(perms, "run_command", "rm_file") == :ask
    end

    test "returns default_mode when no patterns match (deny)" do
      perms = %Permissions{default_mode: :deny}

      assert Permissions.check_permission(perms, "Any", "action") == :deny
    end

    test "returns default_mode when no patterns match (allow)" do
      perms = %Permissions{default_mode: :allow}

      assert Permissions.check_permission(perms, "Any", "action") == :allow
    end

    test "handles wildcard patterns" do
      perms = %Permissions{allow: ["*"], default_mode: :deny}

      assert Permissions.check_permission(perms, "Any", "action") == :allow
    end

    test "handles category wildcards" do
      perms = %Permissions{allow: ["Read:*"], default_mode: :deny}

      assert Permissions.check_permission(perms, "Read", "any_file.txt") == :allow
    end

    test "handles action wildcards" do
      perms = %Permissions{deny: ["*:delete"], default_mode: :allow}

      assert Permissions.check_permission(perms, "File", "delete") == :deny
      assert Permissions.check_permission(perms, "User", "delete") == :deny
    end

    test "handles atom category and action" do
      perms = %Permissions{allow: ["Read:*"], default_mode: :deny}

      assert Permissions.check_permission(perms, :Read, :file) == :allow
    end

    test "handles complex glob patterns" do
      perms = %Permissions{allow: ["run_command:git*"], default_mode: :deny}

      assert Permissions.check_permission(perms, "run_command", "git status") == :allow
      assert Permissions.check_permission(perms, "run_command", "git-commit") == :allow
    end

    test "handles question mark wildcard" do
      perms = %Permissions{deny: ["*:rm ??"], default_mode: :allow}

      assert Permissions.check_permission(perms, "run_command", "rm ab") == :deny
      assert Permissions.check_permission(perms, "run_command", "rm abc") == :allow
    end

    test "handles multiple character class patterns" do
      # Character classes are converted to regex character classes
      perms = %Permissions{allow: ["*:??"], default_mode: :deny}

      assert Permissions.check_permission(perms, "run_command", "ab") == :allow
      assert Permissions.check_permission(perms, "run_command", "a") == :deny  # default deny
      assert Permissions.check_permission(perms, "run_command", "abc") == :deny  # default deny
    end

    test "multiple patterns in same list" do
      perms = %Permissions{
        allow: ["Read:*", "Write:*", "Edit:*"],
        default_mode: :deny
      }

      assert Permissions.check_permission(perms, "Read", "file") == :allow
      assert Permissions.check_permission(perms, "Write", "file") == :allow
      assert Permissions.check_permission(perms, "Edit", "file") == :allow
    end

    test "empty patterns don't match" do
      perms = %Permissions{allow: [""], default_mode: :deny}

      # Empty pattern should not match anything
      assert Permissions.check_permission(perms, "Any", "action") == :deny
    end

    test "exact match works" do
      perms = %Permissions{allow: ["Read:file.txt"], default_mode: :deny}

      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
      assert Permissions.check_permission(perms, "Read", "other.txt") == :deny
    end

    test "colon in action is handled correctly" do
      perms = %Permissions{allow: ["run_command:ssh:*"], default_mode: :deny}

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
      assert perms.default_mode == :deny
    end

    test "parses valid JSON with deny list" do
      json = %{"deny" => ["*delete*"]}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == []
      assert perms.deny == ["*delete*"]
      assert perms.ask == []
      assert perms.default_mode == :deny
    end

    test "parses valid JSON with ask list" do
      json = %{"ask" => ["run_command:*"]}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == []
      assert perms.deny == []
      assert perms.ask == ["run_command:*"]
      assert perms.default_mode == :deny
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
      assert perms.default_mode == :deny
    end

    test "parses valid JSON with default_mode as string" do
      json = %{"default_mode" => "allow"}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.default_mode == :allow
    end

    test "parses valid JSON with default_mode as atom" do
      json = %{"default_mode" => :deny}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.default_mode == :deny
    end

    test "rejects invalid default_mode" do
      json = %{"default_mode" => "invalid"}

      assert {:error, %Error{code: :permissions_invalid}} = Permissions.from_json(json)
    end

    test "handles empty JSON" do
      json = %{}

      assert {:ok, perms} = Permissions.from_json(json)
      assert perms.allow == []
      assert perms.deny == []
      assert perms.ask == []
      assert perms.default_mode == :deny
    end

    test "returns error when allow is not a list" do
      json = %{"allow" => "not_a_list"}

      assert {:error, %Error{code: :field_list_invalid}} = Permissions.from_json(json)
    end

    test "returns error when deny is not a list" do
      json = %{"deny" => 123}

      assert {:error, %Error{code: :field_list_invalid}} = Permissions.from_json(json)
    end

    test "returns error when ask is not a list" do
      json = %{"ask" => %{}}

      assert {:error, %Error{code: :field_list_invalid}} = Permissions.from_json(json)
    end

    test "returns error when allow contains non-string" do
      json = %{"allow" => ["Read:*", 123]}

      assert {:error, %Error{code: :pattern_invalid}} = Permissions.from_json(json)
    end

    test "returns error when deny contains empty string" do
      json = %{"deny" => ["", "*delete*"]}

      assert {:error, %Error{code: :pattern_invalid}} = Permissions.from_json(json)
    end

    test "returns error when ask contains empty string" do
      json = %{"ask" => ["  ", "run_command:*"]}

      # Whitespace-only string is treated as empty
      assert {:error, %Error{code: :pattern_invalid}} = Permissions.from_json(json)
    end

    test "accepts list with only whitespace in patterns" do
      # Pattern with content after trimming is valid
      json = %{"allow" => [" Read:* "]}

      assert {:ok, _perms} = Permissions.from_json(json)
    end
  end

  describe "defaults/0" do
    test "returns Permissions struct" do
      assert %Permissions{} = Permissions.defaults()
    end

    test "default_mode is deny (secure by default)" do
      perms = Permissions.defaults()
      assert perms.default_mode == :deny
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
      assert "run_command:mix*" in perms.allow
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

      # other run_commands are denied (fail-closed)
      assert Permissions.check_permission(perms, "run_command", "make") == :deny
    end

    test "web operations are asked by default" do
      perms = Permissions.defaults()

      assert Permissions.check_permission(perms, "web_fetch", "url") == :ask
      assert Permissions.check_permission(perms, "web_search", "query") == :ask
    end

    test "default_mode deny blocks unmatched actions" do
      perms = Permissions.defaults()

      # Actions not in any list are denied
      assert Permissions.check_permission(perms, "Unknown", "action") == :deny
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
        deny: ["*delete*"],
        default_mode: :allow
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

    test "fail-closed mode blocks all unmatched" do
      perms = %Permissions{
        allow: ["Read:*"],
        default_mode: :deny
      }

      # Read is allowed
      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow

      # Everything else is denied
      assert Permissions.check_permission(perms, "Write", "file.txt") == :deny
      assert Permissions.check_permission(perms, "Edit", "file.txt") == :deny
    end

    test "fail-open mode allows all unmatched" do
      perms = %Permissions{
        deny: ["*delete*"],
        default_mode: :allow
      }

      # Delete is denied
      assert Permissions.check_permission(perms, "Edit", "delete_file") == :deny

      # Everything else is allowed
      assert Permissions.check_permission(perms, "Read", "file.txt") == :allow
      assert Permissions.check_permission(perms, "Write", "file.txt") == :allow
    end
  end
end
