defmodule JidoCode.Tools.Definitions.Elixir do
  @moduledoc """
  Tool definitions for Elixir-specific operations.

  This module defines tools for Elixir and BEAM runtime operations that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `mix_task` - Run Mix tasks with security controls

  ## Security

  The mix_task tool enforces several security measures:
  - **Task allowlist**: Only pre-approved tasks can be executed
  - **Task blocklist**: Dangerous tasks are explicitly blocked
  - **Environment restriction**: prod environment is blocked
  - **Timeout enforcement**: Tasks timeout after 60 seconds by default

  ## Usage

      # Register all Elixir tools
      for tool <- Elixir.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      mix_tool = Elixir.mix_task()
      :ok = Registry.register(mix_tool)
  """

  alias JidoCode.Tools.Handlers.Elixir, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all Elixir tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      mix_task()
    ]
  end

  @doc """
  Returns the mix_task tool definition.

  Executes a Mix task in the project directory with security validation,
  timeout enforcement, and output capture.

  ## Parameters

  - `task` (required, string) - Mix task name (e.g., 'compile', 'test')
  - `args` (optional, array) - Task arguments
  - `env` (optional, string) - Mix environment ('dev' or 'test', prod is blocked)

  ## Security

  Tasks must be in the allowed list: compile, test, format, deps.get, etc.
  Dangerous tasks (release, hex.publish, ecto.drop) are explicitly blocked.
  The prod environment is blocked to prevent accidental production operations.

  ## Output

  Returns JSON with output and exit_code. stderr is merged into stdout.
  """
  @spec mix_task() :: Tool.t()
  def mix_task do
    Tool.new!(%{
      name: "mix_task",
      description:
        "Run a Mix task in the project directory. Only allowlisted tasks are permitted. " <>
          "Allowed tasks include: compile, test, format, deps.get, deps.compile, deps.tree, " <>
          "deps.unlock, help, credo, dialyzer, docs, hex.info. " <>
          "The prod environment is blocked. Tasks timeout after 60 seconds by default.",
      handler: Handlers.MixTask,
      parameters: [
        %{
          name: "task",
          type: :string,
          description:
            "Mix task name to execute (e.g., 'compile', 'test', 'format', 'deps.get')",
          required: true
        },
        %{
          name: "args",
          type: :array,
          description:
            "Task arguments as array (e.g., ['--trace'] for test, ['--check'] for format)",
          required: false
        },
        %{
          name: "env",
          type: :string,
          description:
            "Mix environment to use ('dev' or 'test'). The 'prod' environment is blocked for safety.",
          required: false,
          enum: ["dev", "test"]
        }
      ]
    })
  end
end
