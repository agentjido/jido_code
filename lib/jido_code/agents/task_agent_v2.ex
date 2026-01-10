defmodule JidoCode.Agents.TaskAgent.V2 do
  @moduledoc """
  TaskAgent for executing isolated sub-tasks with their own LLM context.

  This agent uses `Jido.Agent` as the base with Jido v2 LLM skills.
  It's designed for single-shot task execution with focused prompts.

  ## Usage

      # Using AgentServer directly
      {:ok, pid} = Jido.AgentServer.start(
        agent: JidoCode.Agents.TaskAgent.V2,
        id: "task_abc123",
        initial_state: %{
          task_id: "task_abc123",
          description: "Search for API patterns",
          prompt: "Find all REST API endpoints in the codebase",
          session_id: "session-uuid"  # Optional: for session isolation
        }
      )

      # Execute the task
      {:ok, result} = Jido.AgentServer.call(pid, Jido.Signal.new!("task.execute", %{}, source: "task_agent"))

      # Get status
      {:ok, state} = Jido.AgentServer.state(pid)

  ## Convenience Functions

      # Start with options
      {:ok, pid} = TaskAgent.V2.start_link(
        task_id: "task_abc123",
        description: "Search for API patterns",
        prompt: "Find all REST API endpoints",
        session_id: "session-uuid"
      )

      # Execute and get result
      {:ok, result} = TaskAgent.V2.execute(pid)

  ## Session Context

  When a `session_id` is provided, the TaskAgent:
  - Stores the session_id for tool execution context
  - Broadcasts progress to session-specific topics (`tui.events.{session_id}`)
  - Operates within the same security boundary as the parent session

  ## PubSub Integration

  Progress updates are broadcast to `task.{task_id}` topic and optionally
  to `tui.events.{session_id}` when session context is available:

  - `{:task_started, task_id}` - Task execution began
  - `{:task_progress, task_id, message}` - Progress update
  - `{:task_completed, task_id, result}` - Task finished successfully
  - `{:task_failed, task_id, reason}` - Task failed with error
  """

  use Jido.Agent,
    name: "jido_task_agent",
    description: "JidoCode TaskAgent for isolated sub-task execution",
    strategy: nil,
    schema: [
      # Task Identification
      task_id: [type: :string, default: nil],
      description: [type: :string, default: nil],

      # Task Content
      prompt: [type: :string, default: nil],
      system_prompt: [type: :string, default: nil],

      # LLM Configuration
      provider: [type: :atom, default: :anthropic],
      model: [type: :string, default: "anthropic:claude-sonnet-4-20250514"],
      temperature: [type: :float, default: 0.3],
      max_tokens: [type: :integer, default: 2048],

      # Session Context
      session_id: [type: :string, default: nil],

      # Execution State
      status: [type: :atom, default: :ready],
      result: [type: :string, default: nil],
      error: [type: :string, default: nil],
      started_at: [type: :integer, default: nil],
      completed_at: [type: :integer, default: nil]
    ],
    skills: [
      Jido.AI.Skills.LLM
    ]

  require Logger
  alias Jido.Agent

  @pubsub JidoCode.PubSub
  @default_timeout 60_000

  @task_system_prompt """
  You are a specialized sub-agent executing a specific task within a coding assistant.

  Your focus is narrow - complete only the assigned task and return results concisely.
  Do not ask clarifying questions. Do your best with the information provided.

  Guidelines:
  - Stay focused on the specific task
  - Return results in a clear, structured format
  - If you cannot complete the task, explain what's blocking you
  - Be concise but thorough
  """

  @doc """
  Returns the default system prompt used for task execution.
  """
  def system_prompt, do: @task_system_prompt

  # ============================================================================
  # Convenience API (GenServer-like interface)
  # ============================================================================

  @doc """
  Starts a TaskAgent with the given specification.

  ## Options

  - `:task_id` - (required) Unique identifier for tracking
  - `:description` - (required) Short task description
  - `:prompt` - (required) Detailed task instructions
  - `:provider` - (optional) Override provider (default: :anthropic)
  - `:model` - (optional) Override model
  - `:temperature` - (optional) LLM temperature (default: 0.3)
  - `:max_tokens` - (optional) Max tokens (default: 2048)
  - `:session_id` - (optional) Parent session ID for isolation and routing
  - `:name` - (optional) Registered name for the AgentServer

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    # Validate required options
    with {:ok, task_id} <- validate_required(opts, :task_id),
         {:ok, description} <- validate_required(opts, :description),
         {:ok, prompt} <- validate_required(opts, :prompt) do
      # Build initial state from options
      initial_state = %{
        task_id: task_id,
        description: description,
        prompt: prompt,
        provider: Keyword.get(opts, :provider, :anthropic),
        model: Keyword.get(opts, :model, "anthropic:claude-sonnet-4-20250514"),
        temperature: Keyword.get(opts, :temperature, 0.3),
        max_tokens: Keyword.get(opts, :max_tokens, 2048),
        session_id: Keyword.get(opts, :session_id),
        status: :ready
      }

      # Start AgentServer
      server_opts = [
        agent: __MODULE__,
        id: name || task_id,
        initial_state: initial_state
      ]

      Jido.AgentServer.start_link(server_opts)
    end
  end

  @doc """
  Executes the task and returns the result.

  This is a synchronous call that blocks until the task completes or times out.

  ## Returns

  - `{:ok, result}` - Task completed with result string
  - `{:error, :timeout}` - Task exceeded timeout
  - `{:error, reason}` - Task failed with error
  """
  @spec execute(GenServer.server(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def execute(server, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case Jido.AgentServer.call(
           server,
           Jido.Signal.new!("task.execute", %{}, source: "task_agent"),
           timeout + 5_000
         ) do
      {:ok, %Jido.Signal{data: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %Jido.Signal{data: %{"error" => error}}} ->
        {:error, error}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the current status of the task.
  """
  @spec status(GenServer.server()) :: map()
  def status(server) do
    case Jido.AgentServer.state(server) do
      {:ok, %{agent: agent}} ->
        %{
          task_id: agent.state.task_id,
          description: agent.state.description,
          status: agent.state.status,
          result: agent.state.result,
          session_id: agent.state.session_id
        }

      {:error, _reason} ->
        %{error: :not_found}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _} -> {:error, "Option #{key} must be a non-empty string"}
      :error -> {:error, "Missing required option: #{key}"}
    end
  end

  # ============================================================================
  # Action Modules
  # ============================================================================

  defmodule ExecuteTask do
    @moduledoc """
    Action for executing a task through the TaskAgent.
    """

    use Jido.Action,
      name: "task_execute",
      description: "Execute the task and return the result"

    alias JidoCode.Config

    @impl true
    def run(_action, _params, context) do
      agent = context.agent

      # Mark as running
      started_at = System.system_time(:millisecond)
      task_id = agent.state.task_id
      session_id = agent.state.session_id

      new_agent =
        agent
        |> Agent.set(%{
          status: :running,
          started_at: started_at
        })

      # Broadcast start
      broadcast_started(task_id, session_id)

      # Execute the task
      result = do_execute(new_agent)

      completed_at = System.system_time(:millisecond)
      duration = completed_at - started_at

      case result do
        {:ok, content} ->
          # Update state with result
          final_agent =
            new_agent
            |> Agent.set(%{
              status: :completed,
              result: content,
              completed_at: completed_at
            })

          # Telemetry
          :telemetry.execute(
            [:jido_code, :task_agent, :complete],
            %{duration: duration},
            %{task_id: task_id, success: true}
          )

          # Broadcast completion
          broadcast_completed(task_id, content, session_id)

          {final_agent,
           [
             %Jido.Agent.Directive.Emit{
               signal: Jido.Signal.new!("task.execute.result", %{"result" => content},
                 source: "task_agent"
               )
             }
           ]}

        {:error, reason} ->
          # Update state with error
          error_msg = inspect(reason)
          final_agent = Agent.set(new_agent, %{status: :failed, error: error_msg})

          # Telemetry
          :telemetry.execute(
            [:jido_code, :task_agent, :complete],
            %{duration: duration},
            %{task_id: task_id, success: false, error: reason}
          )

          # Broadcast failure
          broadcast_failed(task_id, reason, session_id)

          {final_agent,
           [
             %Jido.Agent.Directive.Emit{
               signal: Jido.Signal.new!("task.execute.result", %{"error" => error_msg},
                 source: "task_agent"
               )
             }
           ]}
      end
    end

    defp do_execute(agent) do
      # Get LLM config
      llm_config = get_llm_config(agent)

      # Build system prompt with task context
      system_prompt = """
      #{JidoCode.Agents.TaskAgent.V2.system_prompt()}

      ## Current Task

      **Description**: #{agent.state.description}
      """

      # Build LLM parameters
      llm_params = %{
        "model" => llm_config.model,
        "prompt" => agent.state.prompt,
        "system_prompt" => system_prompt,
        "temperature" => llm_config.temperature,
        "max_tokens" => llm_config.max_tokens,
        "stream" => false
      }

      # Use apply to avoid struct expansion issues
      apply(Jido.AI.Skills.LLM.Actions.Chat, :run, [%{}, llm_params, %{}])
    end

    defp get_llm_config(agent) do
      # Try to get from Config, fall back to agent state
      case Config.get_llm_config() do
        {:ok, base_config} ->
          %{
            provider: agent.state.provider || base_config.provider,
            model: agent.state.model || base_config.model,
            temperature: agent.state.temperature || 0.3,
            max_tokens: agent.state.max_tokens || 2048
          }

        {:error, _reason} ->
          # Use agent state defaults
          %{
            provider: agent.state.provider || :anthropic,
            model: agent.state.model || "anthropic:claude-sonnet-4-20250514",
            temperature: agent.state.temperature || 0.3,
            max_tokens: agent.state.max_tokens || 2048
          }
      end
    end

    defp broadcast_started(task_id, session_id) do
      pubsub = JidoCode.PubSub
      message = {:task_started, task_id}

      Phoenix.PubSub.broadcast(pubsub, "task.#{task_id}", message)
      Phoenix.PubSub.broadcast(pubsub, "tui.events", message)

      if session_id do
        Phoenix.PubSub.broadcast(pubsub, "tui.events.#{session_id}", message)
      end
    end

    defp broadcast_completed(task_id, result, session_id) do
      pubsub = JidoCode.PubSub
      message = {:task_completed, task_id, result}

      Phoenix.PubSub.broadcast(pubsub, "task.#{task_id}", message)
      Phoenix.PubSub.broadcast(pubsub, "tui.events", message)

      if session_id do
        Phoenix.PubSub.broadcast(pubsub, "tui.events.#{session_id}", message)
      end
    end

    defp broadcast_failed(task_id, reason, session_id) do
      pubsub = JidoCode.PubSub
      message = {:task_failed, task_id, reason}

      Phoenix.PubSub.broadcast(pubsub, "task.#{task_id}", message)
      Phoenix.PubSub.broadcast(pubsub, "tui.events", message)

      if session_id do
        Phoenix.PubSub.broadcast(pubsub, "tui.events.#{session_id}", message)
      end
    end
  end
end
