defmodule JidoCode.Session.State do
  @moduledoc """
  Session State manages the runtime state for a session.

  This GenServer handles:
  - Conversation history (messages from user, assistant, system, tool)
  - Reasoning steps (chain-of-thought reasoning display)
  - Tool execution tracking (pending, running, completed tool calls)
  - Todo list management (task tracking)
  - UI state (scroll offset, streaming state)

  ## Registry

  Each State process registers in `JidoCode.SessionProcessRegistry` with the key
  `{:state, session_id}` for O(1) lookup.

  ## State Structure

  The state contains:

  - `session` - The Session struct (for backwards compatibility)
  - `session_id` - The unique session identifier
  - `messages` - List of conversation messages
  - `reasoning_steps` - List of chain-of-thought reasoning steps
  - `tool_calls` - List of tool call records
  - `todos` - List of task items
  - `scroll_offset` - Current scroll position in UI
  - `streaming_message` - Content being streamed (nil when not streaming)
  - `is_streaming` - Whether currently receiving streaming response

  ## Usage

  Typically started as a child of Session.Supervisor:

      # In Session.Supervisor.init/1
      children = [
        {JidoCode.Session.State, session: session},
        # ...
      ]

  Direct lookup:

      [{pid, _}] = Registry.lookup(SessionProcessRegistry, {:state, session_id})

  Access via client functions:

      {:ok, state} = Session.State.get_state(session_id)
  """

  use GenServer

  require Logger

  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc """
  A conversation message.

  - `id` - Unique message identifier
  - `role` - Who sent the message (:user, :assistant, :system, :tool)
  - `content` - The message content
  - `timestamp` - When the message was created
  """
  @type message :: %{
          id: String.t(),
          role: :user | :assistant | :system | :tool,
          content: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  A reasoning step from chain-of-thought processing.

  - `id` - Unique step identifier
  - `content` - The reasoning content
  - `timestamp` - When the step was generated
  """
  @type reasoning_step :: %{
          id: String.t(),
          content: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  A tool call record.

  - `id` - Unique tool call identifier (from LLM)
  - `name` - Name of the tool being called
  - `arguments` - Arguments passed to the tool
  - `result` - Result of the tool execution (nil if not yet complete)
  - `status` - Current status of the tool call
  - `timestamp` - When the tool call was initiated
  """
  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map(),
          result: term() | nil,
          status: :pending | :running | :completed | :error,
          timestamp: DateTime.t()
        }

  @typedoc """
  A todo/task item.

  - `id` - Unique todo identifier
  - `content` - Description of the task
  - `status` - Current status (:pending, :in_progress, :completed)
  """
  @type todo :: %{
          id: String.t(),
          content: String.t(),
          status: :pending | :in_progress | :completed
        }

  @typedoc """
  Session State process state.

  - `session` - The Session struct (for backwards compatibility with get_session/1)
  - `session_id` - The unique session identifier
  - `messages` - List of conversation messages in chronological order
  - `reasoning_steps` - List of reasoning steps from current response
  - `tool_calls` - List of tool calls from current response
  - `todos` - List of task items being tracked
  - `scroll_offset` - Current scroll position in UI (lines from bottom)
  - `streaming_message` - Content being streamed (nil when not streaming)
  - `is_streaming` - Whether currently receiving a streaming response
  """
  @type state :: %{
          session: Session.t(),
          session_id: String.t(),
          messages: [message()],
          reasoning_steps: [reasoning_step()],
          tool_calls: [tool_call()],
          todos: [todo()],
          scroll_offset: non_neg_integer(),
          streaming_message: String.t() | nil,
          is_streaming: boolean()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the Session State process.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - State process started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, session, name: ProcessRegistry.via(:state, session.id))
  end

  @doc """
  Returns the child specification for this GenServer.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_state, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Gets the session struct for this state process.

  ## Examples

      iex> {:ok, session} = State.get_session(pid)
  """
  @spec get_session(GenServer.server()) :: {:ok, Session.t()}
  def get_session(server) do
    GenServer.call(server, :get_session)
  end

  @doc """
  Gets the full state for a session by session_id.

  ## Examples

      iex> {:ok, state} = State.get_state("session-123")
      iex> {:error, :not_found} = State.get_state("unknown")
  """
  @spec get_state(String.t()) :: {:ok, state()} | {:error, :not_found}
  def get_state(session_id) do
    call_state(session_id, :get_state)
  end

  @doc """
  Gets the messages list for a session by session_id.

  ## Examples

      iex> {:ok, messages} = State.get_messages("session-123")
      iex> {:error, :not_found} = State.get_messages("unknown")
  """
  @spec get_messages(String.t()) :: {:ok, [message()]} | {:error, :not_found}
  def get_messages(session_id) do
    call_state(session_id, :get_messages)
  end

  @doc """
  Gets the reasoning steps list for a session by session_id.

  ## Examples

      iex> {:ok, steps} = State.get_reasoning_steps("session-123")
      iex> {:error, :not_found} = State.get_reasoning_steps("unknown")
  """
  @spec get_reasoning_steps(String.t()) :: {:ok, [reasoning_step()]} | {:error, :not_found}
  def get_reasoning_steps(session_id) do
    call_state(session_id, :get_reasoning_steps)
  end

  @doc """
  Gets the todos list for a session by session_id.

  ## Examples

      iex> {:ok, todos} = State.get_todos("session-123")
      iex> {:error, :not_found} = State.get_todos("unknown")
  """
  @spec get_todos(String.t()) :: {:ok, [todo()]} | {:error, :not_found}
  def get_todos(session_id) do
    call_state(session_id, :get_todos)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec call_state(String.t(), atom()) :: {:ok, term()} | {:error, :not_found}
  defp call_state(session_id, message) do
    case ProcessRegistry.lookup(:state, session_id) do
      {:ok, pid} -> GenServer.call(pid, message)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(%Session{} = session) do
    Logger.info("Starting Session.State for session #{session.id}")

    state = %{
      session: session,
      session_id: session.id,
      messages: [],
      reasoning_steps: [],
      tool_calls: [],
      todos: [],
      scroll_offset: 0,
      streaming_message: nil,
      is_streaming: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    {:reply, {:ok, state.session}, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, {:ok, state.messages}, state}
  end

  @impl true
  def handle_call(:get_reasoning_steps, _from, state) do
    {:reply, {:ok, state.reasoning_steps}, state}
  end

  @impl true
  def handle_call(:get_todos, _from, state) do
    {:reply, {:ok, state.todos}, state}
  end
end
