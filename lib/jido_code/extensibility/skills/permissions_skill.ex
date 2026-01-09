require JidoCode.Extensibility.Skills.Permissions.Actions.CheckPermission

defmodule JidoCode.Extensibility.Skills.Permissions do
  @moduledoc """
  Skill for integrating extensibility permissions with Jido agents.

  This skill loads and stores extensibility permissions configuration in the
  agent's state, allowing the permissions to be accessed during agent execution.

  ## Features

  - Loads extensibility permissions from settings during agent mount
  - Provides `extensibility_check_permission` action for permission checking
  - Supports agent-specific permission overrides
  - Integrates with Jido v2's Skill system

  ## Usage

      defmodule MyAgent do
        use Jido.AI.ReActAgent,
          name: "my_agent",
          description: "My agent with extensibility permissions",
          skills: [
            {JidoCode.Extensibility.Skills.Permissions, [agent_name: :my_agent]}
          ]
      end

  ## Agent Configuration

  The skill accepts the following configuration options:

  - `:agent_name` - Optional atom or string name for agent-specific overrides
  - `:permissions` - Optional permissions map to use instead of loading from settings

  ## State

  The skill stores the following in the agent's state under `:extensibility_permissions`:

  - `:permissions` - The `JidoCode.Extensibility.Permissions` struct
  - `:channels` - The channel configuration map
  - `:agent_name` - The agent name used for overrides

  ## Checking Permissions

  To check permissions within the agent:

      # Within an action or other code
      case JidoCode.Extensibility.Permissions.check_permission(
        agent.state.extensibility_permissions.permissions,
        "Read",
        "file.txt"
      ) do
        :allow -> # Proceed
        :deny -> # Block
        :ask -> # Prompt user
      end

  """

  use Jido.Skill,
    name: "extensibility_permissions",
    state_key: :extensibility_permissions,
    actions: [
      JidoCode.Extensibility.Skills.Permissions.Actions.CheckPermission
    ],
    description:
      "Integrates extensibility permission configuration with Jido agents for permission checking"

  alias JidoCode.{Settings, Extensibility}
  alias JidoCode.Extensibility.Skills.ConfigLoader
  alias JidoCode.Extensibility.{Permissions, ChannelConfig, Error}

  @doc """
  Mounts the skill and loads permissions configuration.

  ## Parameters

  - `agent` - The agent struct (not used in current implementation)
  - `config` - Configuration map with optional keys:
    - `:agent_name` - Agent name for agent-specific overrides
    - `:permissions` - Direct permissions map (skips settings load)

  ## Returns

  - `{:ok, skill_state}` - Successfully loaded permissions
  - `{:error, reason}` - Failed to load permissions

  ## Examples

      # Load from settings with agent-specific overrides
      {:ok, state} = Permissions.mount(agent, [agent_name: :llm_agent])

      # Load with direct permissions (for testing)
      {:ok, state} = Permissions.mount(agent,
        permissions: %{"allow" => ["Read:*"]}
      )
  """
  @impl true
  def mount(_agent, config) when is_list(config) do
    agent_name = Keyword.get(config, :agent_name)
    direct_permissions = Keyword.get(config, :permissions)

    {permissions, channels} =
      case direct_permissions do
        nil ->
          # Load from settings
          ext_config = ConfigLoader.load_for_agent(agent_name)
          {ext_config.permissions, ext_config.channels}

        perms_map when is_map(perms_map) ->
          # Use direct permissions (for testing/overrides)
          case Permissions.from_json(perms_map) do
            {:ok, perms} ->
              {perms, ChannelConfig.defaults()}

            {:error, %Error{}} ->
              # Fall back to defaults if direct permissions are invalid
              {Permissions.defaults(), ChannelConfig.defaults()}
          end
      end

    skill_state = %{
      permissions: permissions,
      channels: channels,
      agent_name: agent_name
    }

    {:ok, skill_state}
  end

  @impl true
  def mount(_agent, config) when is_map(config) do
    # Handle map-based config
    mount(_agent, Map.to_list(config))
  end

  @impl true
  def mount(_agent, _config) do
    # Handle no config - use defaults
    skill_state = %{
      permissions: Permissions.defaults(),
      channels: ChannelConfig.defaults(),
      agent_name: nil
    }

    {:ok, skill_state}
  end
end
