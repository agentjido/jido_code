defmodule JidoCode.Extensibility.Skills.Permissions.Actions.CheckPermission do
  @moduledoc """
  Action to check if a permission is granted.

  This action can be called within an agent to verify if a specific
  action is allowed based on the extensibility permissions configuration.

  ## Parameters

  - `category` - The permission category (e.g., "Read", "Edit", "run_command")
  - `action` - The specific action to check (e.g., "file.txt", "delete", "make")

  ## Returns

  - `{:ok, :allow}` - The action is permitted
  - `{:ok, :deny}` - The action is blocked
  - `{:ok, :ask}` - User confirmation is required

  ## Examples

  In an agent prompt or action:
      CheckPermission.run(%{category: "Read", action: "file.txt"}, context)
      # => {:ok, :allow}

      CheckPermission.run(%{category: "Edit", action: "delete_file"}, context)
      # => {:ok, :deny}
  """

  use Jido.Action,
    name: "extensibility_check_permission",
    description: "Check if a permission is granted based on extensibility configuration",
    category: "extensibility",
    tags: ["permissions", "security"],
    vsn: "1.0.0",
    schema: [
      category: [
        type: :string,
        required: true,
        doc: "The permission category (e.g., 'Read', 'Edit', 'run_command')"
      ],
      action: [
        type: :string,
        required: true,
        doc: "The specific action to check (e.g., 'file.txt', 'delete', 'make')"
      ]
    ]

  alias JidoCode.Extensibility.Permissions

  @impl true
  def run(params, context) do
    category = Map.get(params, "category") || Map.get(params, :category)
    action = Map.get(params, "action") || Map.get(params, :action)

    # Get permissions from agent state
    agent_state = Map.get(context, :agent_state, %{})
    ext_perms = Map.get(agent_state, :extensibility_permissions)

    permissions =
      case ext_perms do
        %{permissions: perms} when not is_nil(perms) -> perms
        _ -> nil
      end

    cond do
      is_nil(category) ->
        {:error, "category is required"}

      is_nil(action) ->
        {:error, "action is required"}

      is_nil(permissions) ->
        # No permissions configured, default to deny
        {:ok, :deny}

      true ->
        decision = Permissions.check_permission(permissions, category, action)
        {:ok, decision}
    end
  end
end
