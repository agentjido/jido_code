defmodule JidoCode.Tools.Definitions.Shell do
  @moduledoc """
  Tool definitions for shell execution operations.

  This module defines tools for executing shell commands that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `run_command` - Execute a shell command with arguments

  ## Usage

      # Register all shell tools
      for tool <- Shell.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      run_cmd_tool = Shell.run_command()
      :ok = Registry.register(run_cmd_tool)
  """

  alias JidoCode.Tools.Handlers.Shell, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all shell tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      run_command()
    ]
  end

  @doc """
  Returns the run_command tool definition.

  Executes a shell command in the project directory with timeout enforcement.

  ## Parameters

  - `command` (required, string) - Command to execute
  - `args` (optional, array) - Command arguments
  - `timeout` (optional, integer) - Timeout in milliseconds (default: 60000)
  """
  @spec run_command() :: Tool.t()
  def run_command do
    Tool.new!(%{
      name: "run_command",
      description:
        "Execute a shell command in the project directory. Returns exit code and output. " <>
          "Use for running tests (mix test), builds (mix compile), linters, git commands, etc. " <>
          "Commands timeout after 60 seconds by default.",
      handler: Handlers.RunCommand,
      parameters: [
        %{
          name: "command",
          type: :string,
          description: "Command to execute (e.g., 'mix', 'npm', 'git', 'ls')",
          required: true
        },
        %{
          name: "args",
          type: :array,
          description: "Command arguments as array (e.g., ['test', '--trace'])",
          required: false
        },
        %{
          name: "timeout",
          type: :integer,
          description: "Timeout in milliseconds (default: 60000, i.e., 60 seconds)",
          required: false
        }
      ]
    })
  end
end
