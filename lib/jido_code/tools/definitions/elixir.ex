defmodule JidoCode.Tools.Definitions.Elixir do
  @moduledoc """
  Tool definitions for Elixir-specific operations.

  This module defines tools for Elixir and BEAM runtime operations that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `mix_task` - Run Mix tasks with security controls
  - `run_exunit` - Run ExUnit tests with filtering options
  - `get_process_state` - Inspect GenServer and process state
  - `inspect_supervisor` - View supervisor tree structure

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
      mix_task(),
      run_exunit(),
      get_process_state(),
      inspect_supervisor()
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
          "The prod environment is blocked. Tasks timeout after 60 seconds by default (max 5 minutes). " <>
          "Output is truncated at 1MB.",
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
            "Task arguments as array (e.g., ['--trace'] for test, ['--check'] for format). " <>
              "Path traversal patterns (../) are blocked for security.",
          required: false
        },
        %{
          name: "env",
          type: :string,
          description:
            "Mix environment to use ('dev' or 'test'). The 'prod' environment is blocked for safety.",
          required: false,
          enum: ["dev", "test"]
        },
        %{
          name: "timeout",
          type: :integer,
          description:
            "Timeout in milliseconds (default: 60000, max: 300000). Task is killed if it exceeds the timeout.",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the run_exunit tool definition.

  Runs ExUnit tests with comprehensive filtering and configuration options.
  This provides more granular control than the generic mix_task tool.

  ## Parameters

  - `path` (optional, string) - Test file or directory path (relative to project root)
  - `line` (optional, integer) - Run test at specific line number (requires path)
  - `tag` (optional, string) - Run only tests with specific tag
  - `exclude_tag` (optional, string) - Exclude tests with specific tag
  - `max_failures` (optional, integer) - Stop after N test failures
  - `seed` (optional, integer) - Random seed for test ordering
  - `timeout` (optional, integer) - Timeout in milliseconds (default: 120000, max: 300000)

  ## Security

  - Path traversal patterns (../) are blocked
  - prod environment is always blocked
  - Uses same security model as mix_task

  ## Output

  Returns JSON with output, exit_code, and parsed test summary when available.
  """
  @spec run_exunit() :: Tool.t()
  def run_exunit do
    Tool.new!(%{
      name: "run_exunit",
      description:
        "Run ExUnit tests with filtering options. Provides granular control over test execution " <>
          "including file/line targeting, tag filtering, and failure limits. " <>
          "Tests timeout after 120 seconds by default (max 5 minutes). Output is truncated at 1MB.",
      handler: Handlers.RunExunit,
      parameters: [
        %{
          name: "path",
          type: :string,
          description:
            "Test file or directory path relative to project root (e.g., 'test/my_test.exs' or 'test/unit'). " <>
              "Path traversal patterns (../) are blocked.",
          required: false
        },
        %{
          name: "line",
          type: :integer,
          description:
            "Run test at specific line number. Requires 'path' to be specified. " <>
              "Useful for running a single test or describe block.",
          required: false
        },
        %{
          name: "tag",
          type: :string,
          description:
            "Run only tests with specific tag (e.g., 'integration', 'slow'). " <>
              "Use @tag :tagname in test files to mark tests.",
          required: false
        },
        %{
          name: "exclude_tag",
          type: :string,
          description:
            "Exclude tests with specific tag (e.g., 'skip', 'pending'). " <>
              "Useful for excluding slow or flaky tests.",
          required: false
        },
        %{
          name: "max_failures",
          type: :integer,
          description:
            "Stop test run after N failures. Useful for fast feedback during development.",
          required: false
        },
        %{
          name: "seed",
          type: :integer,
          description:
            "Random seed for test ordering. Use 0 for deterministic order. " <>
              "Reproduce a specific test order by providing the seed from a previous run.",
          required: false
        },
        %{
          name: "trace",
          type: :boolean,
          description:
            "Enable verbose trace output for each test. Shows test name as it runs.",
          required: false
        },
        %{
          name: "timeout",
          type: :integer,
          description:
            "Timeout in milliseconds (default: 120000, max: 300000). " <>
              "Test run is killed if it exceeds the timeout.",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the get_process_state tool definition.

  Inspects the state of a GenServer or other OTP process. Only processes in the
  project namespace can be inspected - system and internal processes are blocked.

  ## Parameters

  - `process` (required, string) - Registered name of the process (e.g., 'MyApp.Worker')
  - `timeout` (optional, integer) - Timeout in milliseconds (default: 5000)

  ## Security

  - Only registered names are allowed (raw PIDs are blocked)
  - System-critical processes are blocked (kernel, stdlib, init)
  - JidoCode internal processes are blocked
  - Sensitive fields (passwords, tokens, keys) are redacted from output

  ## Output

  Returns JSON with state and process_info. State is formatted with inspect
  for readability. Non-OTP processes return process_info only.
  """
  @spec get_process_state() :: Tool.t()
  def get_process_state do
    Tool.new!(%{
      name: "get_process_state",
      description:
        "Get state of a GenServer or process. Only project processes can be inspected. " <>
          "System processes and JidoCode internals are blocked for security. " <>
          "Sensitive fields (passwords, tokens, keys) are redacted.",
      handler: Handlers.ProcessState,
      parameters: [
        %{
          name: "process",
          type: :string,
          description:
            "Registered name of the process (e.g., 'MyApp.Worker', 'MyApp.Cache'). " <>
              "Raw PIDs are not allowed for security reasons.",
          required: true
        },
        %{
          name: "timeout",
          type: :integer,
          description:
            "Timeout in milliseconds for getting state (default: 5000). " <>
              "Useful for slow-responding processes.",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the inspect_supervisor tool definition.

  Views the structure of a supervisor tree, showing its children and their types.
  Only project supervisors can be inspected - system supervisors are blocked.

  ## Parameters

  - `supervisor` (required, string) - Registered name of the supervisor
  - `depth` (optional, integer) - Max tree depth (default: 2, max: 5)

  ## Security

  - Only registered names are allowed (raw PIDs are blocked)
  - System supervisors are blocked (kernel, stdlib, etc.)
  - JidoCode internal supervisors are blocked
  - Depth is limited to prevent excessive recursion

  ## Output

  Returns JSON with tree structure showing children, their types, and restart strategies.
  """
  @spec inspect_supervisor() :: Tool.t()
  def inspect_supervisor do
    Tool.new!(%{
      name: "inspect_supervisor",
      description:
        "View supervisor tree structure. Only project supervisors can be inspected. " <>
          "System supervisors and JidoCode internals are blocked for security. " <>
          "Shows children, types (worker/supervisor), and restart strategies.",
      handler: Handlers.SupervisorTree,
      parameters: [
        %{
          name: "supervisor",
          type: :string,
          description:
            "Registered name of the supervisor (e.g., 'MyApp.Supervisor'). " <>
              "Raw PIDs are not allowed for security reasons.",
          required: true
        },
        %{
          name: "depth",
          type: :integer,
          description:
            "Maximum depth to traverse child supervisors (default: 2, max: 5). " <>
              "Higher depth shows more nested supervisors but takes longer.",
          required: false
        }
      ]
    })
  end
end
