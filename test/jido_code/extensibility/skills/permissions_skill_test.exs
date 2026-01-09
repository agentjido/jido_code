defmodule JidoCode.Extensibility.Skills.PermissionsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility.Skills.Permissions, as: PermissionsSkill
  alias JidoCode.Extensibility.{ChannelConfig, Permissions}
  alias JidoCode.Extensibility.Permissions, as: ExtPermissions

  describe "mount/2" do
    setup do
      # Mock agent
      agent = %{
        name: "test_agent",
        state: %{}
      }

      {:ok, agent: agent}
    end

    test "loads default permissions when no config provided", %{agent: agent} do
      assert {:ok, skill_state} = PermissionsSkill.mount(agent, [])

      assert %ExtPermissions{} = skill_state.permissions
      assert is_map(skill_state.channels)
      assert is_nil(skill_state.agent_name)
    end

    test "loads permissions from direct config", %{agent: agent} do
      direct_perms = %{
        "allow" => ["Read:*"],
        "deny" => ["*delete*"]
      }

      assert {:ok, skill_state} = PermissionsSkill.mount(agent, permissions: direct_perms)

      assert "Read:*" in skill_state.permissions.allow
      assert "*delete*" in skill_state.permissions.deny
    end

    test "falls back to defaults for invalid direct permissions", %{agent: agent} do
      invalid_perms = %{
        "allow" => "not_a_list"
      }

      assert {:ok, skill_state} = PermissionsSkill.mount(agent, permissions: invalid_perms)

      # Should have default permissions
      assert "Read:*" in skill_state.permissions.allow
    end

    test "accepts atom agent_name in config", %{agent: agent} do
      assert {:ok, skill_state} = PermissionsSkill.mount(agent, agent_name: :llm_agent)

      assert skill_state.agent_name == :llm_agent
      assert %ExtPermissions{} = skill_state.permissions
    end

    test "accepts string agent_name in config", %{agent: agent} do
      assert {:ok, skill_state} = PermissionsSkill.mount(agent, agent_name: "llm_agent")

      assert skill_state.agent_name == "llm_agent"
      assert %ExtPermissions{} = skill_state.permissions
    end

    test "accepts map-based config", %{agent: agent} do
      config = %{agent_name: :task_agent}

      assert {:ok, skill_state} = PermissionsSkill.mount(agent, config)

      assert skill_state.agent_name == :task_agent
    end
  end

  describe "permission checking through skill state" do
    setup do
      agent = %{name: "test_agent", state: %{}}
      direct_perms = %{"allow" => ["Read:*"], "deny" => ["*delete*"]}

      assert {:ok, skill_state} = PermissionsSkill.mount(agent, permissions: direct_perms)

      {:ok, skill_state: skill_state}
    end

    test "allows matching patterns", %{skill_state: skill_state} do
      decision = ExtPermissions.check_permission(skill_state.permissions, "Read", "file.txt")

      assert decision == :allow
    end

    test "denies matching deny patterns", %{skill_state: skill_state} do
      decision = ExtPermissions.check_permission(skill_state.permissions, "Edit", "delete_file")

      assert decision == :deny
    end

    test "denies unmatched actions (default_mode: :deny)", %{skill_state: skill_state} do
      decision = ExtPermissions.check_permission(skill_state.permissions, "Unknown", "action")

      assert decision == :deny
    end
  end
end

defmodule JidoCode.Extensibility.Skills.Permissions.Actions.CheckPermissionTest do
  use ExUnit.Case, async: true

  alias JidoCode.Extensibility.Skills.Permissions.Actions.CheckPermission

  describe "run/2" do
    setup do
      # Create a context with agent_state that has permissions
      agent_state = %{
        extensibility_permissions: %{
          permissions: %JidoCode.Extensibility.Permissions{
            allow: ["Read:*"],
            deny: ["*delete*"],
            ask: [],
            default_mode: :deny
          },
          channels: %{},
          agent_name: nil
        }
      }

      context = %{agent_state: agent_state}

      {:ok, context: context}
    end

    test "returns :allow for allowed actions", %{context: context} do
      params = %{category: "Read", action: "file.txt"}

      assert {:ok, :allow} = CheckPermission.run(params, context)
    end

    test "returns :deny for denied actions", %{context: context} do
      params = %{category: "Edit", action: "delete_file"}

      assert {:ok, :deny} = CheckPermission.run(params, context)
    end

    test "returns error when category is missing", %{context: context} do
      params = %{action: "file.txt"}

      assert {:error, "category is required"} = CheckPermission.run(params, context)
    end

    test "returns error when action is missing", %{context: context} do
      params = %{category: "Read"}

      assert {:error, "action is required"} = CheckPermission.run(params, context)
    end

    test "returns :deny when no permissions configured" do
      context = %{agent_state: %{}}
      params = %{category: "Read", action: "file.txt"}

      assert {:ok, :deny} = CheckPermission.run(params, context)
    end

    test "returns :deny when extensibility_permissions is nil" do
      context = %{agent_state: %{extensibility_permissions: nil}}
      params = %{category: "Read", action: "file.txt"}

      assert {:ok, :deny} = CheckPermission.run(params, context)
    end

    test "handles string keys in params", %{context: context} do
      params = %{"category" => "Read", "action" => "file.txt"}

      assert {:ok, :allow} = CheckPermission.run(params, context)
    end
  end
end
