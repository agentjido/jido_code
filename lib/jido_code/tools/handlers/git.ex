defmodule JidoCode.Tools.Handlers.Git do
  @moduledoc """
  Handler modules for Git operations.

  This module serves as a namespace for Git-related tool handlers.
  The actual implementation will be completed in Phase 3.1.2.

  ## Handlers

  - `Git.Command` - Execute git commands with safety constraints
  """
end

defmodule JidoCode.Tools.Handlers.Git.Command do
  @moduledoc """
  Handler for the git_command tool.

  Executes git commands with security validation including subcommand
  allowlisting and destructive operation guards.

  ## Implementation Status

  This handler is a placeholder. Full implementation will be completed
  in Phase 3.1.2 (Bridge Function Implementation) of the planning document.

  ## Security

  When fully implemented, this handler will:
  - Validate subcommand against allowlist
  - Block destructive operations unless explicitly allowed
  - Execute commands in the session's project directory
  - Parse structured output for common commands
  """

  alias JidoCode.Tools.Definitions.GitCommand

  @doc """
  Executes a git command.

  Currently returns a placeholder response indicating the handler
  is not yet implemented. Full implementation pending Phase 3.1.2.

  ## Parameters

  - `params` - Map with:
    - `"subcommand"` (required) - Git subcommand to execute
    - `"args"` (optional) - Additional arguments
    - `"allow_destructive"` (optional) - Allow destructive operations

  - `context` - Map with:
    - `:project_root` - Project directory (required)
    - `:session_id` - Session identifier (optional)

  ## Returns

  - `{:ok, map}` - Success with output and parsed data
  - `{:error, string}` - Error with message
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def execute(params, context) do
    subcommand = Map.get(params, "subcommand")
    args = Map.get(params, "args", [])
    allow_destructive = Map.get(params, "allow_destructive", false)

    with :ok <- validate_subcommand(subcommand),
         :ok <- validate_destructive(subcommand, args, allow_destructive),
         :ok <- validate_context(context) do
      # Placeholder response - full implementation in 3.1.2
      {:error, "git_command handler not yet implemented (pending Phase 3.1.2)"}
    end
  end

  # Validates the subcommand is in the allowed list
  defp validate_subcommand(nil) do
    {:error, "subcommand is required"}
  end

  defp validate_subcommand(subcommand) when is_binary(subcommand) do
    if GitCommand.subcommand_allowed?(subcommand) do
      :ok
    else
      {:error, "git subcommand '#{subcommand}' is not allowed"}
    end
  end

  defp validate_subcommand(_) do
    {:error, "subcommand must be a string"}
  end

  # Validates destructive operations are explicitly allowed
  defp validate_destructive(subcommand, args, allow_destructive) do
    if GitCommand.destructive?(subcommand, args) and not allow_destructive do
      {:error,
       "destructive operation blocked: 'git #{subcommand} #{Enum.join(args, " ")}' requires allow_destructive: true"}
    else
      :ok
    end
  end

  # Validates required context fields
  defp validate_context(%{project_root: project_root}) when is_binary(project_root) do
    :ok
  end

  defp validate_context(_) do
    {:error, "project_root is required in context"}
  end
end
