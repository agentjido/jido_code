defmodule JidoCode.Tools.Definitions.Shell do
  @moduledoc """
  Tool definitions for shell execution operations.

  This module defines tools for executing shell commands that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `run_command` - Execute a shell command with arguments
  - `bash_background` - Start a command in the background
  - `bash_output` - Retrieve output from a background process
  - `kill_shell` - Terminate a background process

  ## Security

  The run_command tool enforces several security measures:
  - **Command allowlist**: Only pre-approved commands can be executed
  - **Shell interpreter blocking**: bash, sh, zsh, etc. are blocked
  - **Path argument validation**: Path traversal and absolute paths are blocked
  - **Output truncation**: Output limited to 1MB to prevent memory exhaustion

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
      run_command(),
      bash_background(),
      bash_output(),
      kill_shell()
    ]
  end

  @doc """
  Returns the run_command tool definition.

  Executes a shell command in the project directory with security validation,
  timeout enforcement, and output size limits.

  ## Parameters

  - `command` (required, string) - Command to execute (must be in allowlist)
  - `args` (optional, array) - Command arguments
  - `timeout` (optional, integer) - Timeout in milliseconds (default: 25000)

  ## Security

  Commands must be in the allowed list: mix, git, npm, ls, cat, grep, etc.
  Shell interpreters (bash, sh, zsh) are blocked to prevent command injection.
  Arguments with path traversal patterns (..) or absolute paths outside
  the project root are rejected.

  ## Output

  Returns JSON with exit_code and stdout. Note: stderr is merged into stdout
  for simplicity. Output is truncated at 1MB.
  """
  @spec run_command() :: Tool.t()
  def run_command do
    Tool.new!(%{
      name: "run_command",
      description:
        "Execute a shell command in the project directory. Returns exit code and output (stderr merged into stdout). " <>
          "Only allowed commands can be executed (mix, git, npm, ls, cat, grep, etc.). " <>
          "Shell interpreters (bash, sh) are blocked. Path traversal in arguments is blocked. " <>
          "Commands timeout after 25 seconds by default. Output is truncated at 1MB.",
      handler: Handlers.RunCommand,
      parameters: [
        %{
          name: "command",
          type: :string,
          description:
            "Command to execute (must be in allowlist: mix, git, npm, ls, cat, grep, find, etc.)",
          required: true
        },
        %{
          name: "args",
          type: :array,
          description:
            "Command arguments as array (e.g., ['test', '--trace']). Path traversal (..) is blocked.",
          required: false
        },
        %{
          name: "timeout",
          type: :integer,
          description: "Timeout in milliseconds (default: 25000, i.e., 25 seconds)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the bash_background tool definition.

  Starts a command in the background and returns a shell_id for tracking.
  Use bash_output to retrieve the output and kill_shell to terminate.

  ## Parameters

  - `command` (required, string) - Command to execute (must be in allowlist)
  - `args` (optional, array) - Command arguments
  - `description` (optional, string) - Description for tracking

  ## Security

  Commands must be in the allowed list: mix, git, npm, ls, cat, grep, etc.
  Shell interpreters (bash, sh, zsh) are blocked to prevent command injection.

  ## Output

  Returns JSON with shell_id and description.
  """
  @spec bash_background() :: Tool.t()
  def bash_background do
    Tool.new!(%{
      name: "bash_background",
      description:
        "Start a command in the background. Returns a shell_id for tracking. " <>
          "Use bash_output to retrieve output later or kill_shell to terminate. " <>
          "Only allowed commands can be executed (mix, git, npm, etc.). " <>
          "Shell interpreters (bash, sh) are blocked.",
      handler: Handlers.BashBackground,
      parameters: [
        %{
          name: "command",
          type: :string,
          description:
            "Command to execute (must be in allowlist: mix, git, npm, ls, cat, grep, etc.)",
          required: true
        },
        %{
          name: "args",
          type: :array,
          description:
            "Command arguments as array (e.g., ['test', '--trace'])",
          required: false
        },
        %{
          name: "description",
          type: :string,
          description: "Optional description for tracking the background process",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the bash_output tool definition.

  Retrieves output from a background shell process started with bash_background.

  ## Parameters

  - `shell_id` (required, string) - Shell ID returned by bash_background
  - `block` (optional, boolean) - Wait for completion (default: true)
  - `timeout` (optional, integer) - Max wait time in ms (default: 30000)

  ## Output

  Returns JSON with output, status (running/completed/failed/killed), and exit_code.
  """
  @spec bash_output() :: Tool.t()
  def bash_output do
    Tool.new!(%{
      name: "bash_output",
      description:
        "Get output from a background shell process. " <>
          "Returns output, status (running/completed/failed/killed), and exit_code. " <>
          "Use block=true (default) to wait for completion, or block=false for immediate status.",
      handler: Handlers.BashOutput,
      parameters: [
        %{
          name: "shell_id",
          type: :string,
          description: "Shell ID returned by bash_background",
          required: true
        },
        %{
          name: "block",
          type: :boolean,
          description: "Wait for completion (default: true)",
          required: false
        },
        %{
          name: "timeout",
          type: :integer,
          description: "Max wait time in ms when blocking (default: 30000)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the kill_shell tool definition.

  Terminates a background shell process.

  ## Parameters

  - `shell_id` (required, string) - Shell ID returned by bash_background

  ## Output

  Returns JSON with success status and message.
  """
  @spec kill_shell() :: Tool.t()
  def kill_shell do
    Tool.new!(%{
      name: "kill_shell",
      description:
        "Terminate a background shell process. " <>
          "Returns success status. Use this to stop long-running processes.",
      handler: Handlers.KillShell,
      parameters: [
        %{
          name: "shell_id",
          type: :string,
          description: "Shell ID returned by bash_background",
          required: true
        }
      ]
    })
  end
end
