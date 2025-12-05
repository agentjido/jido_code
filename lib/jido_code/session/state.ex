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
  - `streaming_message_id` - ID of the message being streamed (nil when not streaming)
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
          streaming_message_id: String.t() | nil,
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

  @doc """
  Appends a message to the conversation history.

  ## Examples

      iex> message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.append_message("session-123", message)
      iex> {:error, :not_found} = State.append_message("unknown", message)
  """
  @spec append_message(String.t(), message()) :: {:ok, state()} | {:error, :not_found}
  def append_message(session_id, message) do
    call_state(session_id, {:append_message, message})
  end

  @doc """
  Clears all messages from the conversation history.

  ## Examples

      iex> {:ok, []} = State.clear_messages("session-123")
      iex> {:error, :not_found} = State.clear_messages("unknown")
  """
  @spec clear_messages(String.t()) :: {:ok, []} | {:error, :not_found}
  def clear_messages(session_id) do
    call_state(session_id, :clear_messages)
  end

  @doc """
  Starts streaming mode for a new message.

  Sets `is_streaming: true`, `streaming_message: ""`, and stores the message_id.

  ## Examples

      iex> {:ok, state} = State.start_streaming("session-123", "msg-1")
      iex> state.is_streaming
      true
      iex> {:error, :not_found} = State.start_streaming("unknown", "msg-1")
  """
  @spec start_streaming(String.t(), String.t()) :: {:ok, state()} | {:error, :not_found}
  def start_streaming(session_id, message_id) do
    call_state(session_id, {:start_streaming, message_id})
  end

  @doc """
  Appends a chunk to the streaming message.

  This is an async operation (cast) for performance during high-frequency updates.
  If the session is not found or not streaming, the chunk is silently ignored.

  ## Examples

      iex> :ok = State.update_streaming("session-123", "Hello ")
      iex> :ok = State.update_streaming("session-123", "world!")
  """
  @spec update_streaming(String.t(), String.t()) :: :ok
  def update_streaming(session_id, chunk) do
    cast_state(session_id, {:streaming_chunk, chunk})
  end

  @doc """
  Ends streaming and finalizes the message.

  Creates a message from the streamed content and appends it to the messages list.
  Resets streaming state to nil/false.

  ## Examples

      iex> {:ok, message} = State.end_streaming("session-123")
      iex> message.role
      :assistant
      iex> {:error, :not_streaming} = State.end_streaming("session-123")
      iex> {:error, :not_found} = State.end_streaming("unknown")
  """
  @spec end_streaming(String.t()) :: {:ok, message()} | {:error, :not_found | :not_streaming}
  def end_streaming(session_id) do
    call_state(session_id, :end_streaming)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec call_state(String.t(), atom() | tuple()) :: {:ok, term()} | {:error, :not_found}
  defp call_state(session_id, message) do
    case ProcessRegistry.lookup(:state, session_id) do
      {:ok, pid} -> GenServer.call(pid, message)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @spec cast_state(String.t(), term()) :: :ok
  defp cast_state(session_id, message) do
    case ProcessRegistry.lookup(:state, session_id) do
      {:ok, pid} -> GenServer.cast(pid, message)
      {:error, :not_found} -> :ok
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
      streaming_message_id: nil,
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

  @impl true
  def handle_call({:append_message, message}, _from, state) do
    new_state = %{state | messages: state.messages ++ [message]}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    new_state = %{state | messages: []}
    {:reply, {:ok, []}, new_state}
  end

  @impl true
  def handle_call({:start_streaming, message_id}, _from, state) do
    new_state = %{state |
      is_streaming: true,
      streaming_message: "",
      streaming_message_id: message_id
    }
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:end_streaming, _from, state) do
    if state.is_streaming do
      message = %{
        id: state.streaming_message_id,
        role: :assistant,
        content: state.streaming_message,
        timestamp: DateTime.utc_now()
      }
      new_state = %{state |
        messages: state.messages ++ [message],
        is_streaming: false,
        streaming_message: nil,
        streaming_message_id: nil
      }
      {:reply, {:ok, message}, new_state}
    else
      {:reply, {:error, :not_streaming}, state}
    end
  end

  @impl true
  def handle_cast({:streaming_chunk, chunk}, state) do
    if state.is_streaming do
      new_state = %{state | streaming_message: state.streaming_message <> chunk}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
end
