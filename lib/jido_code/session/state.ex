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

  # Memory modules
  alias JidoCode.Memory.Promotion.Engine, as: PromotionEngine
  alias JidoCode.Memory.Promotion.Triggers, as: PromotionTriggers
  alias JidoCode.Memory.ShortTerm.AccessLog
  alias JidoCode.Memory.ShortTerm.PendingMemories
  alias JidoCode.Memory.ShortTerm.WorkingContext

  # ============================================================================
  # Configuration
  # ============================================================================

  # Maximum list sizes to prevent unbounded memory growth
  @max_messages 1000
  @max_reasoning_steps 100
  @max_tool_calls 500
  @max_prompt_history 100
  # Maximum file operations to track (reads + writes)
  # When limit is exceeded, oldest entries are removed
  @max_file_operations 1000

  # Memory system configuration
  @max_pending_memories 500
  @max_access_log_entries 1000
  @default_context_max_tokens 12_000

  # Promotion timer configuration
  @default_promotion_interval_ms 30_000
  @default_promotion_enabled true

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
  A file operation record for tracking reads and writes.

  - `path` - The file path (relative to project root)
  - `timestamp` - When the operation occurred
  """
  @type file_operation :: %{
          path: String.t(),
          timestamp: DateTime.t()
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
  - `prompt_history` - List of previous user prompts (newest first, max 100)
  - `file_reads` - Map of file paths to read timestamps for read-before-write tracking
  - `file_writes` - Map of file paths to write timestamps for tracking modifications
  - `working_context` - Semantic scratchpad for session context
  - `pending_memories` - Staging area for memories awaiting promotion
  - `access_log` - Usage tracking for importance scoring
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
          is_streaming: boolean(),
          prompt_history: [String.t()],
          file_reads: %{String.t() => DateTime.t()},
          file_writes: %{String.t() => DateTime.t()},
          working_context: WorkingContext.t(),
          pending_memories: PendingMemories.t(),
          access_log: AccessLog.t()
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

  Returns all messages in chronological order (oldest first).

  ## Examples

      iex> {:ok, messages} = State.get_messages("session-123")
      iex> {:error, :not_found} = State.get_messages("unknown")
  """
  @spec get_messages(String.t()) :: {:ok, [message()]} | {:error, :not_found}
  def get_messages(session_id) do
    call_state(session_id, :get_messages)
  end

  @doc """
  Gets a paginated slice of messages for a session by session_id.

  This is more efficient than `get_messages/1` for large conversation histories,
  as it only reverses the requested slice instead of the entire list.

  ## Parameters

  - `session_id` - The session identifier
  - `offset` - Number of messages to skip from the start (oldest messages)
  - `limit` - Maximum number of messages to return (or `:all` for no limit)

  ## Returns

  - `{:ok, messages, metadata}` - Successfully retrieved messages with pagination info
  - `{:error, :not_found}` - Session not found

  The metadata map contains:
  - `total` - Total number of messages in the session
  - `offset` - The offset used for this query
  - `limit` - The limit used for this query
  - `returned` - Number of messages actually returned
  - `has_more` - Whether there are more messages beyond this page

  ## Examples

      # Get first 10 messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 0, 10)
      iex> meta.total
      100
      iex> meta.has_more
      true

      # Get next 10 messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 10, 10)
      iex> length(messages)
      10

      # Get all remaining messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 20, :all)
      iex> meta.has_more
      false

      # Offset beyond available messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 1000, 10)
      iex> messages
      []
      iex> meta.has_more
      false
  """
  @spec get_messages(String.t(), non_neg_integer(), pos_integer() | :all) ::
          {:ok, [message()], map()} | {:error, :not_found}
  def get_messages(session_id, offset, limit)
      when is_binary(session_id) and is_integer(offset) and offset >= 0 and
             ((is_integer(limit) and limit > 0) or limit == :all) do
    call_state(session_id, {:get_messages_paginated, offset, limit})
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
  Gets the tool calls list for a session by session_id.

  ## Examples

      iex> {:ok, tool_calls} = State.get_tool_calls("session-123")
      iex> {:error, :not_found} = State.get_tool_calls("unknown")
  """
  @spec get_tool_calls(String.t()) :: {:ok, [tool_call()]} | {:error, :not_found}
  def get_tool_calls(session_id) do
    call_state(session_id, :get_tool_calls)
  end

  @doc """
  Appends a message to the conversation history.

  ## Examples

      iex> message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.append_message("session-123", message)
      iex> {:error, :not_found} = State.append_message("unknown", message)
  """
  @spec append_message(String.t(), message()) :: {:ok, state()} | {:error, :not_found}
  def append_message(session_id, message)
      when is_binary(session_id) and is_map(message) do
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
  def start_streaming(session_id, message_id)
      when is_binary(session_id) and is_binary(message_id) do
    call_state(session_id, {:start_streaming, message_id})
  end

  @doc """
  Appends a chunk to the streaming message.

  This is an async operation (cast) for performance during high-frequency updates.
  If the session is not found or not streaming, the chunk is silently ignored.

  ## Race Condition Note

  Because `start_streaming/2` uses `call` (synchronous) and `update_streaming/2`
  uses `cast` (asynchronous), there is a potential race condition where chunks
  could arrive before `start_streaming/2` completes. In this case, chunks are
  safely ignored. Callers should ensure `start_streaming/2` has returned before
  sending chunks to avoid lost data.

  ## Examples

      iex> :ok = State.update_streaming("session-123", "Hello ")
      iex> :ok = State.update_streaming("session-123", "world!")
  """
  @spec update_streaming(String.t(), String.t()) :: :ok
  def update_streaming(session_id, chunk)
      when is_binary(session_id) and is_binary(chunk) do
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

  @doc """
  Sets the scroll offset for the UI.

  ## Examples

      iex> {:ok, state} = State.set_scroll_offset("session-123", 10)
      iex> state.scroll_offset
      10
      iex> {:error, :not_found} = State.set_scroll_offset("unknown", 10)
  """
  @spec set_scroll_offset(String.t(), non_neg_integer()) :: {:ok, state()} | {:error, :not_found}
  def set_scroll_offset(session_id, offset)
      when is_binary(session_id) and is_integer(offset) and offset >= 0 do
    call_state(session_id, {:set_scroll_offset, offset})
  end

  @doc """
  Updates the entire todo list.

  ## Examples

      iex> todos = [%{id: "t-1", content: "Task 1", status: :pending}]
      iex> {:ok, state} = State.update_todos("session-123", todos)
      iex> {:error, :not_found} = State.update_todos("unknown", todos)
  """
  @spec update_todos(String.t(), [todo()]) :: {:ok, state()} | {:error, :not_found}
  def update_todos(session_id, todos)
      when is_binary(session_id) and is_list(todos) do
    call_state(session_id, {:update_todos, todos})
  end

  @doc """
  Adds a reasoning step to the list.

  ## Examples

      iex> step = %{id: "r-1", content: "Thinking...", timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.add_reasoning_step("session-123", step)
      iex> {:error, :not_found} = State.add_reasoning_step("unknown", step)
  """
  @spec add_reasoning_step(String.t(), reasoning_step()) :: {:ok, state()} | {:error, :not_found}
  def add_reasoning_step(session_id, step)
      when is_binary(session_id) and is_map(step) do
    call_state(session_id, {:add_reasoning_step, step})
  end

  @doc """
  Clears all reasoning steps.

  ## Examples

      iex> {:ok, []} = State.clear_reasoning_steps("session-123")
      iex> {:error, :not_found} = State.clear_reasoning_steps("unknown")
  """
  @spec clear_reasoning_steps(String.t()) :: {:ok, []} | {:error, :not_found}
  def clear_reasoning_steps(session_id) do
    call_state(session_id, :clear_reasoning_steps)
  end

  @doc """
  Adds a tool call to the list.

  ## Examples

      iex> tool_call = %{id: "tc-1", name: "read_file", arguments: %{}, result: nil, status: :pending, timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.add_tool_call("session-123", tool_call)
      iex> {:error, :not_found} = State.add_tool_call("unknown", tool_call)
  """
  @spec add_tool_call(String.t(), tool_call()) :: {:ok, state()} | {:error, :not_found}
  def add_tool_call(session_id, tool_call)
      when is_binary(session_id) and is_map(tool_call) do
    call_state(session_id, {:add_tool_call, tool_call})
  end

  @doc """
  Updates the session's LLM configuration.

  This merges the provided config with the existing session config using
  `Session.update_config/2`, which validates the config and updates the
  `updated_at` timestamp.

  ## Parameters

  - `session_id` - The session identifier
  - `config` - Map of config options to merge (provider, model, temperature, max_tokens)

  ## Returns

  - `{:ok, session}` - Successfully updated session
  - `{:error, :not_found}` - Session not found
  - `{:error, [reasons]}` - Config validation errors

  ## Examples

      iex> {:ok, session} = State.update_session_config("session-123", %{temperature: 0.5})
      iex> session.config.temperature
      0.5

      iex> {:error, :not_found} = State.update_session_config("unknown", %{temperature: 0.5})
  """
  @spec update_session_config(String.t(), map()) ::
          {:ok, Session.t()} | {:error, :not_found | [atom()]}
  def update_session_config(session_id, config)
      when is_binary(session_id) and is_map(config) do
    call_state(session_id, {:update_session_config, config})
  end

  @doc """
  Updates the session's programming language.

  This sets the language for the session using `Session.set_language/2`,
  which validates and normalizes the language value.

  ## Parameters

  - `session_id` - The session identifier
  - `language` - Language atom, string, or alias (e.g., `:python`, `"python"`, `"py"`)

  ## Returns

  - `{:ok, session}` - Successfully updated session with new language
  - `{:error, :not_found}` - Session not found
  - `{:error, :invalid_language}` - Language is not a supported value

  ## Examples

      iex> {:ok, session} = State.update_language("session-123", :python)
      iex> session.language
      :python

      iex> {:ok, session} = State.update_language("session-123", "js")
      iex> session.language
      :javascript

      iex> {:error, :not_found} = State.update_language("unknown", :python)
  """
  @spec update_language(String.t(), JidoCode.Language.language() | String.t()) ::
          {:ok, Session.t()} | {:error, :not_found | :invalid_language}
  def update_language(session_id, language) when is_binary(session_id) do
    call_state(session_id, {:update_language, language})
  end

  @doc """
  Gets the prompt history for a session.

  Returns prompts in reverse chronological order (newest first).

  ## Examples

      iex> {:ok, history} = State.get_prompt_history("session-123")
      iex> hd(history)
      "most recent prompt"
      iex> {:error, :not_found} = State.get_prompt_history("unknown")
  """
  @spec get_prompt_history(String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def get_prompt_history(session_id) when is_binary(session_id) do
    call_state(session_id, :get_prompt_history)
  end

  @doc """
  Adds a prompt to the history.

  The prompt is prepended to the history list (newest first).
  Empty prompts are ignored.
  History is limited to #{@max_prompt_history} entries.

  ## Examples

      iex> {:ok, history} = State.add_to_prompt_history("session-123", "Hello world")
      iex> hd(history)
      "Hello world"
      iex> {:error, :not_found} = State.add_to_prompt_history("unknown", "Hello")
  """
  @spec add_to_prompt_history(String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def add_to_prompt_history(session_id, prompt)
      when is_binary(session_id) and is_binary(prompt) do
    # Ignore empty prompts
    if String.trim(prompt) == "" do
      get_prompt_history(session_id)
    else
      call_state(session_id, {:add_to_prompt_history, prompt})
    end
  end

  @doc """
  Sets the prompt history for a session.

  Used during session restoration to set the complete history at once.
  The history should be a list of strings in reverse chronological order (newest first).

  ## Examples

      iex> {:ok, history} = State.set_prompt_history("session-123", ["newest", "older", "oldest"])
      iex> hd(history)
      "newest"
      iex> {:error, :not_found} = State.set_prompt_history("unknown", [])
  """
  @spec set_prompt_history(String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def set_prompt_history(session_id, history)
      when is_binary(session_id) and is_list(history) do
    call_state(session_id, {:set_prompt_history, history})
  end

  # ============================================================================
  # File Tracking API (Read-Before-Write Support)
  # ============================================================================

  @doc """
  Records that a file was read in this session.

  This is used to track reads for the read-before-write safety check.
  The path should be the normalized/safe path after validation.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The file path (should be absolute or normalized)

  ## Returns

  - `{:ok, timestamp}` - The timestamp when the read was recorded
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, timestamp} = State.track_file_read("session-123", "/project/src/file.ex")
      iex> {:error, :not_found} = State.track_file_read("unknown", "/project/src/file.ex")
  """
  @spec track_file_read(String.t(), String.t()) ::
          {:ok, DateTime.t()} | {:error, :not_found}
  def track_file_read(session_id, path)
      when is_binary(session_id) and is_binary(path) do
    call_state(session_id, {:track_file_read, path})
  end

  @doc """
  Records that a file was written in this session.

  This tracks write operations for monitoring and potential conflict detection.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The file path (should be absolute or normalized)

  ## Returns

  - `{:ok, timestamp}` - The timestamp when the write was recorded
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, timestamp} = State.track_file_write("session-123", "/project/src/file.ex")
  """
  @spec track_file_write(String.t(), String.t()) ::
          {:ok, DateTime.t()} | {:error, :not_found}
  def track_file_write(session_id, path)
      when is_binary(session_id) and is_binary(path) do
    call_state(session_id, {:track_file_write, path})
  end

  @doc """
  Checks if a file was read in this session.

  Used by write operations to enforce the read-before-write safety check
  for existing files.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The file path to check

  ## Returns

  - `{:ok, true}` - File was read in this session
  - `{:ok, false}` - File was not read in this session
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, true} = State.file_was_read?("session-123", "/project/src/file.ex")
      iex> {:ok, false} = State.file_was_read?("session-123", "/project/unread.ex")
  """
  @spec file_was_read?(String.t(), String.t()) ::
          {:ok, boolean()} | {:error, :not_found}
  def file_was_read?(session_id, path)
      when is_binary(session_id) and is_binary(path) do
    call_state(session_id, {:file_was_read?, path})
  end

  @doc """
  Gets the timestamp when a file was last read in this session.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The file path to check

  ## Returns

  - `{:ok, timestamp}` - The DateTime when the file was read
  - `{:ok, nil}` - File was not read in this session
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, %DateTime{}} = State.get_file_read_time("session-123", "/project/src/file.ex")
      iex> {:ok, nil} = State.get_file_read_time("session-123", "/project/unread.ex")
  """
  @spec get_file_read_time(String.t(), String.t()) ::
          {:ok, DateTime.t() | nil} | {:error, :not_found}
  def get_file_read_time(session_id, path)
      when is_binary(session_id) and is_binary(path) do
    call_state(session_id, {:get_file_read_time, path})
  end

  # ============================================================================
  # Working Context Client API
  # ============================================================================

  @doc """
  Updates a context item in the working context.

  Stores or updates a value in the session's semantic scratchpad. If the key
  already exists, the access_count is incremented and last_accessed is updated.

  ## Parameters

  - `session_id` - The session identifier
  - `key` - The context key (e.g., :framework, :primary_language)
  - `value` - The value to store
  - `opts` - Optional keyword list:
    - `:source` - Source of the value (:inferred, :explicit, :tool)
    - `:confidence` - Confidence level (0.0 to 1.0)
    - `:memory_type` - Override inferred memory type

  ## Returns

  - `:ok` - Successfully updated context
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> :ok = State.update_context("session-123", :framework, "Phoenix")
      iex> :ok = State.update_context("session-123", :primary_language, "Elixir", source: :tool, confidence: 0.95)
      iex> {:error, :not_found} = State.update_context("unknown", :framework, "Phoenix")
  """
  @spec update_context(String.t(), atom(), term(), keyword()) :: :ok | {:error, :not_found}
  def update_context(session_id, key, value, opts \\ [])
      when is_binary(session_id) and is_atom(key) do
    call_state(session_id, {:update_context, key, value, opts})
  end

  @doc """
  Gets a context value from the working context.

  Retrieves the value for a key and updates access tracking (increments
  access_count and updates last_accessed).

  ## Parameters

  - `session_id` - The session identifier
  - `key` - The context key to retrieve

  ## Returns

  - `{:ok, value}` - The value for the key
  - `{:error, :key_not_found}` - Key does not exist in context
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, "Phoenix"} = State.get_context("session-123", :framework)
      iex> {:error, :key_not_found} = State.get_context("session-123", :unknown_key)
      iex> {:error, :not_found} = State.get_context("unknown", :framework)
  """
  @spec get_context(String.t(), atom()) :: {:ok, term()} | {:error, :not_found | :key_not_found}
  def get_context(session_id, key)
      when is_binary(session_id) and is_atom(key) do
    call_state(session_id, {:get_context, key})
  end

  @doc """
  Gets all context items as a simple key-value map.

  Returns the working context as a map without metadata (just keys and values).

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, map}` - Map of context keys to values
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, %{framework: "Phoenix", primary_language: "Elixir"}} = State.get_all_context("session-123")
      iex> {:ok, %{}} = State.get_all_context("empty-session")
      iex> {:error, :not_found} = State.get_all_context("unknown")
  """
  @spec get_all_context(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_all_context(session_id) when is_binary(session_id) do
    call_state(session_id, :get_all_context)
  end

  @doc """
  Clears all items from the working context.

  Resets the working context to empty while preserving max_tokens setting.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `:ok` - Successfully cleared context
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> :ok = State.clear_context("session-123")
      iex> {:error, :not_found} = State.clear_context("unknown")
  """
  @spec clear_context(String.t()) :: :ok | {:error, :not_found}
  def clear_context(session_id) when is_binary(session_id) do
    call_state(session_id, :clear_context)
  end

  # ============================================================================
  # Pending Memories Client API
  # ============================================================================

  @doc """
  Adds a memory item to the pending memories staging area.

  Items added via this function are staged for potential promotion to long-term
  memory. They are added as implicit items (suggested_by: :implicit) and must
  meet the importance threshold to be promoted.

  ## Parameters

  - `session_id` - The session identifier
  - `item` - A map with required fields: :content, :memory_type, :confidence, :source_type
    Optional fields: :id, :evidence, :rationale, :importance_score

  ## Returns

  - `:ok` - Successfully added to pending memories
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> item = %{content: "Uses Phoenix framework", memory_type: :fact, confidence: 0.9, source_type: :tool}
      iex> :ok = State.add_pending_memory("session-123", item)
      iex> {:error, :not_found} = State.add_pending_memory("unknown", item)
  """
  @spec add_pending_memory(String.t(), map()) :: :ok | {:error, :not_found}
  def add_pending_memory(session_id, item)
      when is_binary(session_id) and is_map(item) do
    call_state(session_id, {:add_pending_memory, item})
  end

  @doc """
  Adds a memory item as an explicit agent decision.

  Items added via this function bypass the importance threshold during promotion.
  They are marked with suggested_by: :agent and importance_score: 1.0.

  ## Parameters

  - `session_id` - The session identifier
  - `item` - A map with required fields: :content, :memory_type, :confidence, :source_type

  ## Returns

  - `:ok` - Successfully added as agent decision
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> item = %{content: "Critical pattern discovered", memory_type: :discovery, confidence: 0.95, source_type: :agent}
      iex> :ok = State.add_agent_memory_decision("session-123", item)
  """
  @spec add_agent_memory_decision(String.t(), map()) :: :ok | {:error, :not_found}
  def add_agent_memory_decision(session_id, item)
      when is_binary(session_id) and is_map(item) do
    call_state(session_id, {:add_agent_memory_decision, item})
  end

  @doc """
  Gets all pending memories that are ready for promotion.

  Returns items from both implicit staging (meeting default threshold of 0.6)
  and all agent decisions (which always qualify for promotion).

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, items}` - List of pending items ready for promotion, sorted by importance_score descending
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, items} = State.get_pending_memories("session-123")
      iex> length(items)
      3
  """
  @spec get_pending_memories(String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_pending_memories(session_id) when is_binary(session_id) do
    call_state(session_id, :get_pending_memories)
  end

  @doc """
  Clears promoted memories from the pending staging area.

  After memories have been promoted to long-term storage, this function removes
  them from the pending area. Also clears all agent decisions.

  ## Parameters

  - `session_id` - The session identifier
  - `promoted_ids` - List of item IDs that were promoted

  ## Returns

  - `:ok` - Successfully cleared promoted items
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> :ok = State.clear_promoted_memories("session-123", ["pending-123", "pending-456"])
  """
  @spec clear_promoted_memories(String.t(), [String.t()]) :: :ok | {:error, :not_found}
  def clear_promoted_memories(session_id, promoted_ids)
      when is_binary(session_id) and is_list(promoted_ids) do
    call_state(session_id, {:clear_promoted_memories, promoted_ids})
  end

  # ============================================================================
  # Access Log Client API
  # ============================================================================

  @doc """
  Records an access event in the access log.

  This is an async operation (cast) for performance during high-frequency access.
  If the session is not found, the access event is silently ignored.

  ## Parameters

  - `session_id` - The session identifier
  - `key` - The context key or memory reference (e.g., :framework or {:memory, "mem-123"})
  - `access_type` - Type of access (:read, :write, or :query)

  ## Returns

  - `:ok` - Always returns :ok (async operation)

  ## Examples

      iex> :ok = State.record_access("session-123", :framework, :read)
      iex> :ok = State.record_access("session-123", {:memory, "mem-123"}, :query)
  """
  @spec record_access(String.t(), atom() | {:memory, String.t()}, :read | :write | :query) :: :ok
  def record_access(session_id, key, access_type)
      when is_binary(session_id) and access_type in [:read, :write, :query] do
    cast_state(session_id, {:record_access, key, access_type})
  end

  @doc """
  Gets access statistics for a key.

  Returns frequency (total access count) and recency (most recent access timestamp)
  for the given key.

  ## Parameters

  - `session_id` - The session identifier
  - `key` - The context key or memory reference to look up

  ## Returns

  - `{:ok, %{frequency: integer(), recency: DateTime.t() | nil}}` - Access statistics
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, stats} = State.get_access_stats("session-123", :framework)
      iex> stats.frequency
      5
      iex> stats.recency
      ~U[2025-12-29 12:00:00Z]

      iex> {:ok, stats} = State.get_access_stats("session-123", :unknown_key)
      iex> stats.frequency
      0
      iex> stats.recency
      nil
  """
  @spec get_access_stats(String.t(), atom() | {:memory, String.t()}) ::
          {:ok, %{frequency: non_neg_integer(), recency: DateTime.t() | nil}}
          | {:error, :not_found}
  def get_access_stats(session_id, key) when is_binary(session_id) do
    call_state(session_id, {:get_access_stats, key})
  end

  # ============================================================================
  # Promotion Timer Client API
  # ============================================================================

  @doc """
  Enables the periodic promotion timer.

  When enabled, the session will periodically evaluate and promote worthy
  short-term memories to long-term storage.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `:ok` - Promotion timer enabled
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> :ok = State.enable_promotion("session-123")
  """
  @spec enable_promotion(String.t()) :: :ok | {:error, :not_found}
  def enable_promotion(session_id) when is_binary(session_id) do
    call_state(session_id, :enable_promotion)
  end

  @doc """
  Disables the periodic promotion timer.

  When disabled, no automatic promotion will occur. The timer will be cancelled
  and will not be rescheduled until `enable_promotion/1` is called.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `:ok` - Promotion timer disabled
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> :ok = State.disable_promotion("session-123")
  """
  @spec disable_promotion(String.t()) :: :ok | {:error, :not_found}
  def disable_promotion(session_id) when is_binary(session_id) do
    call_state(session_id, :disable_promotion)
  end

  @doc """
  Gets the current promotion statistics.

  Returns information about promotion activity for this session.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, stats}` - Map containing:
    - `:enabled` - Whether promotion is currently enabled
    - `:interval_ms` - Current promotion interval in milliseconds
    - `:last_run` - DateTime of last promotion run (nil if never run)
    - `:total_promoted` - Total number of memories promoted
    - `:runs` - Total number of promotion runs
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, stats} = State.get_promotion_stats("session-123")
      iex> stats.enabled
      true
      iex> stats.total_promoted
      15
  """
  @spec get_promotion_stats(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_promotion_stats(session_id) when is_binary(session_id) do
    call_state(session_id, :get_promotion_stats)
  end

  @doc """
  Sets the promotion interval.

  Changes the interval between automatic promotion runs. The change takes effect
  on the next scheduled run.

  ## Parameters

  - `session_id` - The session identifier
  - `interval_ms` - New interval in milliseconds (must be positive)

  ## Returns

  - `:ok` - Interval updated
  - `{:error, :invalid_interval}` - Interval is not a positive integer
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> :ok = State.set_promotion_interval("session-123", 60_000)  # 1 minute
  """
  @spec set_promotion_interval(String.t(), pos_integer()) ::
          :ok | {:error, :invalid_interval | :not_found}
  def set_promotion_interval(session_id, interval_ms)
      when is_binary(session_id) and is_integer(interval_ms) and interval_ms > 0 do
    call_state(session_id, {:set_promotion_interval, interval_ms})
  end

  def set_promotion_interval(session_id, _interval_ms) when is_binary(session_id) do
    {:error, :invalid_interval}
  end

  @doc """
  Triggers an immediate promotion run.

  Runs the promotion engine immediately, outside of the normal scheduled interval.
  The scheduled timer continues unaffected.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, count}` - Number of memories promoted
  - `{:error, :not_found}` - Session not found

  ## Examples

      iex> {:ok, 3} = State.run_promotion_now("session-123")
  """
  @spec run_promotion_now(String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def run_promotion_now(session_id) when is_binary(session_id) do
    call_state(session_id, :run_promotion_now)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec call_state(String.t(), atom() | tuple()) :: {:ok, term()} | {:error, :not_found}
  defp call_state(session_id, message) do
    ProcessRegistry.call(:state, session_id, message)
  end

  @spec cast_state(String.t(), term()) :: :ok
  defp cast_state(session_id, message) do
    ProcessRegistry.cast(:state, session_id, message)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(%Session{} = session) do
    Logger.info("Starting Session.State for session #{session.id}")

    # Get promotion configuration from session config or use defaults
    promotion_interval = get_promotion_interval(session)
    promotion_enabled = get_promotion_enabled(session)

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
      is_streaming: false,
      prompt_history: [],
      file_reads: %{},
      file_writes: %{},
      # Memory system fields
      working_context: WorkingContext.new(@default_context_max_tokens),
      pending_memories: PendingMemories.new(@max_pending_memories),
      access_log: AccessLog.new(@max_access_log_entries),
      # Promotion timer fields
      promotion_enabled: promotion_enabled,
      promotion_interval_ms: promotion_interval,
      promotion_timer_ref: nil,
      promotion_stats: %{
        last_run: nil,
        total_promoted: 0,
        runs: 0
      }
    }

    # Schedule promotion timer if enabled
    state =
      if promotion_enabled do
        schedule_promotion(state)
      else
        state
      end

    {:ok, state}
  end

  # Gets promotion interval from session config or defaults
  defp get_promotion_interval(%Session{} = session) do
    case session do
      %{config: %{promotion_interval_ms: interval}} when is_integer(interval) and interval > 0 ->
        interval

      _ ->
        @default_promotion_interval_ms
    end
  end

  # Gets promotion enabled from session config or defaults
  defp get_promotion_enabled(%Session{} = session) do
    case session do
      %{config: %{promotion_enabled: enabled}} when is_boolean(enabled) ->
        enabled

      _ ->
        @default_promotion_enabled
    end
  end

  # Schedules the next promotion timer
  @spec schedule_promotion(state()) :: state()
  defp schedule_promotion(state) do
    # Cancel any existing timer first
    if state.promotion_timer_ref do
      Process.cancel_timer(state.promotion_timer_ref)
    end

    timer_ref = Process.send_after(self(), :run_promotion, state.promotion_interval_ms)
    %{state | promotion_timer_ref: timer_ref}
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
    # Messages stored in reverse order for O(1) prepend, reverse on read
    {:reply, {:ok, Enum.reverse(state.messages)}, state}
  end

  @impl true
  def handle_call({:get_messages_paginated, offset, limit}, _from, state) do
    # Performance optimization: only reverse the requested slice
    # Messages stored in reverse chronological order: [newest, ..., oldest]
    # We want to return in chronological order: [oldest, ..., newest]

    total = length(state.messages)

    # Calculate actual limit (handle :all)
    actual_limit = if limit == :all, do: total, else: limit

    # Calculate slice indices in the reverse-stored list
    # For offset=0, limit=10 with 100 messages:
    #   We want chronological indices 0-9 (msg_1 to msg_10)
    #   In reverse list, these are at indices 90-99
    #   start_index = 100 - 0 - 10 = 90
    start_index = max(0, total - offset - actual_limit)

    # Calculate how many messages we can actually return
    # If offset >= total, this will be 0 (no messages available)
    slice_length = min(actual_limit, max(0, total - offset))

    # Take the slice and reverse it to chronological order
    # This is O(slice_length) instead of O(total)
    messages =
      if slice_length > 0 do
        state.messages
        |> Enum.slice(start_index, slice_length)
        |> Enum.reverse()
      else
        []
      end

    # Build pagination metadata
    metadata = %{
      total: total,
      offset: offset,
      limit: actual_limit,
      returned: length(messages),
      has_more: offset + length(messages) < total
    }

    {:reply, {:ok, messages, metadata}, state}
  end

  @impl true
  def handle_call(:get_reasoning_steps, _from, state) do
    # Reasoning steps stored in reverse order for O(1) prepend, reverse on read
    {:reply, {:ok, Enum.reverse(state.reasoning_steps)}, state}
  end

  @impl true
  def handle_call(:get_todos, _from, state) do
    {:reply, {:ok, state.todos}, state}
  end

  @impl true
  def handle_call({:append_message, message}, _from, state) do
    # Prepend for O(1), will be reversed on read
    # Enforce max size limit, evicting oldest items (at end of reversed list)
    messages = [message | state.messages] |> Enum.take(@max_messages)
    new_state = %{state | messages: messages}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    new_state = %{state | messages: []}
    {:reply, {:ok, []}, new_state}
  end

  @impl true
  def handle_call({:start_streaming, message_id}, _from, state) do
    new_state = %{
      state
      | is_streaming: true,
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

      # Prepend for O(1), will be reversed on read
      new_state = %{
        state
        | messages: [message | state.messages],
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
  def handle_call({:set_scroll_offset, offset}, _from, state) do
    new_state = %{state | scroll_offset: offset}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:update_todos, todos}, _from, state) do
    new_state = %{state | todos: todos}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:add_reasoning_step, step}, _from, state) do
    # Prepend for O(1), will be reversed on read
    # Enforce max size limit, evicting oldest items (at end of reversed list)
    reasoning_steps = [step | state.reasoning_steps] |> Enum.take(@max_reasoning_steps)
    new_state = %{state | reasoning_steps: reasoning_steps}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:clear_reasoning_steps, _from, state) do
    new_state = %{state | reasoning_steps: []}
    {:reply, {:ok, []}, new_state}
  end

  @impl true
  def handle_call({:add_tool_call, tool_call}, _from, state) do
    # Prepend for O(1), will be reversed on read
    # Enforce max size limit, evicting oldest items (at end of reversed list)
    tool_calls = [tool_call | state.tool_calls] |> Enum.take(@max_tool_calls)
    new_state = %{state | tool_calls: tool_calls}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:get_tool_calls, _from, state) do
    # Tool calls stored in reverse order for O(1) prepend, reverse on read
    {:reply, {:ok, Enum.reverse(state.tool_calls)}, state}
  end

  @impl true
  def handle_call({:update_session_config, config}, _from, state) do
    case Session.update_config(state.session, config) do
      {:ok, updated_session} ->
        new_state = %{state | session: updated_session}
        {:reply, {:ok, updated_session}, new_state}

      {:error, reasons} ->
        {:reply, {:error, reasons}, state}
    end
  end

  @impl true
  def handle_call({:update_language, language}, _from, state) do
    case Session.set_language(state.session, language) do
      {:ok, updated_session} ->
        new_state = %{state | session: updated_session}
        {:reply, {:ok, updated_session}, new_state}

      {:error, :invalid_language} ->
        {:reply, {:error, :invalid_language}, state}
    end
  end

  @impl true
  def handle_call(:get_prompt_history, _from, state) do
    {:reply, {:ok, state.prompt_history}, state}
  end

  @impl true
  def handle_call({:add_to_prompt_history, prompt}, _from, state) do
    # Prepend new prompt, enforce max size limit
    history = [prompt | state.prompt_history] |> Enum.take(@max_prompt_history)
    new_state = %{state | prompt_history: history}
    {:reply, {:ok, history}, new_state}
  end

  @impl true
  def handle_call({:set_prompt_history, history}, _from, state) do
    # Set the entire history (for session restoration), enforce max size limit
    limited_history = Enum.take(history, @max_prompt_history)
    new_state = %{state | prompt_history: limited_history}
    {:reply, {:ok, limited_history}, new_state}
  end

  # ============================================================================
  # File Tracking Callbacks
  # ============================================================================

  @impl true
  def handle_call({:track_file_read, path}, _from, state) do
    timestamp = DateTime.utc_now()
    new_file_reads = Map.put(state.file_reads, path, timestamp)
    # Enforce limit to prevent unbounded memory growth
    new_file_reads = enforce_file_tracking_limit(new_file_reads)
    new_state = %{state | file_reads: new_file_reads}
    {:reply, {:ok, timestamp}, new_state}
  end

  @impl true
  def handle_call({:track_file_write, path}, _from, state) do
    timestamp = DateTime.utc_now()
    new_file_writes = Map.put(state.file_writes, path, timestamp)
    # Enforce limit to prevent unbounded memory growth
    new_file_writes = enforce_file_tracking_limit(new_file_writes)
    new_state = %{state | file_writes: new_file_writes}
    {:reply, {:ok, timestamp}, new_state}
  end

  @impl true
  def handle_call({:file_was_read?, path}, _from, state) do
    # Normalize the path before checking to ensure consistent matching
    was_read = Map.has_key?(state.file_reads, path)
    {:reply, {:ok, was_read}, state}
  end

  @impl true
  def handle_call({:get_file_read_time, path}, _from, state) do
    timestamp = Map.get(state.file_reads, path)
    {:reply, {:ok, timestamp}, state}
  end

  # Enforce maximum file tracking limit to prevent unbounded memory growth
  # Removes oldest entries when limit is exceeded
  @spec enforce_file_tracking_limit(map()) :: map()
  defp enforce_file_tracking_limit(file_map) when map_size(file_map) <= @max_file_operations do
    file_map
  end

  defp enforce_file_tracking_limit(file_map) do
    # Sort by timestamp (oldest first) and take only the newest entries
    file_map
    |> Enum.sort_by(fn {_path, timestamp} -> timestamp end, {:asc, DateTime})
    |> Enum.drop(map_size(file_map) - @max_file_operations)
    |> Map.new()
  end

  # ============================================================================
  # Working Context Callbacks
  # ============================================================================

  @impl true
  def handle_call({:update_context, key, value, opts}, _from, state) do
    updated_context = WorkingContext.put(state.working_context, key, value, opts)
    new_state = %{state | working_context: updated_context}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_context, key}, _from, state) do
    {updated_context, value} = WorkingContext.get(state.working_context, key)
    new_state = %{state | working_context: updated_context}

    case value do
      nil -> {:reply, {:error, :key_not_found}, new_state}
      val -> {:reply, {:ok, val}, new_state}
    end
  end

  @impl true
  def handle_call(:get_all_context, _from, state) do
    context_map = WorkingContext.to_map(state.working_context)
    {:reply, {:ok, context_map}, state}
  end

  @impl true
  def handle_call(:clear_context, _from, state) do
    cleared_context = WorkingContext.clear(state.working_context)
    new_state = %{state | working_context: cleared_context}
    {:reply, :ok, new_state}
  end

  # ============================================================================
  # Pending Memories Callbacks
  # ============================================================================

  @impl true
  def handle_call({:add_pending_memory, item}, _from, state) do
    updated_pending = PendingMemories.add_implicit(state.pending_memories, item)
    current_count = PendingMemories.size(updated_pending)

    # Check if we hit the memory limit and trigger promotion if needed
    new_state =
      if current_count >= @max_pending_memories do
        # Trigger promotion asynchronously to clear space
        Task.start(fn ->
          PromotionTriggers.on_memory_limit_reached(state.session_id, current_count)
        end)

        %{state | pending_memories: updated_pending}
      else
        %{state | pending_memories: updated_pending}
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:add_agent_memory_decision, item}, _from, state) do
    updated_pending = PendingMemories.add_agent_decision(state.pending_memories, item)

    # Agent decisions are high-priority - trigger immediate promotion asynchronously
    Task.start(fn ->
      PromotionTriggers.on_agent_decision(state.session_id, item)
    end)

    new_state = %{state | pending_memories: updated_pending}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_pending_memories, _from, state) do
    ready_items = PendingMemories.ready_for_promotion(state.pending_memories)
    {:reply, {:ok, ready_items}, state}
  end

  @impl true
  def handle_call({:clear_promoted_memories, promoted_ids}, _from, state) do
    updated_pending = PendingMemories.clear_promoted(state.pending_memories, promoted_ids)
    new_state = %{state | pending_memories: updated_pending}
    {:reply, :ok, new_state}
  end

  # ============================================================================
  # Access Log Callbacks
  # ============================================================================

  @impl true
  def handle_call({:get_access_stats, key}, _from, state) do
    stats = AccessLog.get_stats(state.access_log, key)
    {:reply, {:ok, stats}, state}
  end

  # ============================================================================
  # Promotion Timer Callbacks
  # ============================================================================

  @impl true
  def handle_call(:enable_promotion, _from, state) do
    if state.promotion_enabled do
      # Already enabled
      {:reply, :ok, state}
    else
      # Enable and schedule timer
      new_state =
        %{state | promotion_enabled: true}
        |> schedule_promotion()

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:disable_promotion, _from, state) do
    # Cancel existing timer if any
    if state.promotion_timer_ref do
      Process.cancel_timer(state.promotion_timer_ref)
    end

    new_state = %{state | promotion_enabled: false, promotion_timer_ref: nil}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_promotion_stats, _from, state) do
    stats = %{
      enabled: state.promotion_enabled,
      interval_ms: state.promotion_interval_ms,
      last_run: state.promotion_stats.last_run,
      total_promoted: state.promotion_stats.total_promoted,
      runs: state.promotion_stats.runs
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call({:set_promotion_interval, interval_ms}, _from, state) do
    new_state = %{state | promotion_interval_ms: interval_ms}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:run_promotion_now, _from, state) do
    # Build state map for promotion engine
    promotion_state = %{
      working_context: state.working_context,
      pending_memories: state.pending_memories,
      access_log: state.access_log
    }

    # Run promotion engine
    case PromotionEngine.run_with_state(promotion_state, state.session_id, []) do
      {:ok, count, promoted_ids} when count > 0 ->
        # Clear promoted items from pending memories
        updated_pending = PendingMemories.clear_promoted(state.pending_memories, promoted_ids)

        # Update promotion stats
        updated_stats = %{
          last_run: DateTime.utc_now(),
          total_promoted: state.promotion_stats.total_promoted + count,
          runs: state.promotion_stats.runs + 1
        }

        new_state = %{state | pending_memories: updated_pending, promotion_stats: updated_stats}
        {:reply, {:ok, count}, new_state}

      {:ok, 0} ->
        # Update stats even when nothing promoted
        updated_stats = %{
          state.promotion_stats
          | last_run: DateTime.utc_now(),
            runs: state.promotion_stats.runs + 1
        }

        new_state = %{state | promotion_stats: updated_stats}
        {:reply, {:ok, 0}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # handle_cast Callbacks
  # ============================================================================

  @impl true
  def handle_cast({:streaming_chunk, chunk}, state) do
    if state.is_streaming do
      new_state = %{state | streaming_message: state.streaming_message <> chunk}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:record_access, key, access_type}, state) do
    updated_access_log = AccessLog.record(state.access_log, key, access_type)
    new_state = %{state | access_log: updated_access_log}
    {:noreply, new_state}
  end

  # ============================================================================
  # handle_info Callbacks
  # ============================================================================

  @impl true
  def handle_info(:run_promotion, state) do
    if state.promotion_enabled do
      # Build state map for promotion engine
      promotion_state = %{
        working_context: state.working_context,
        pending_memories: state.pending_memories,
        access_log: state.access_log
      }

      # Run promotion engine
      case PromotionEngine.run_with_state(promotion_state, state.session_id, []) do
        {:ok, count, promoted_ids} when count > 0 ->
          Logger.debug(
            "Session.State #{state.session_id} promoted #{count} memories"
          )

          # Clear promoted items from pending memories
          updated_pending = PendingMemories.clear_promoted(state.pending_memories, promoted_ids)

          # Update promotion stats
          updated_stats = %{
            last_run: DateTime.utc_now(),
            total_promoted: state.promotion_stats.total_promoted + count,
            runs: state.promotion_stats.runs + 1
          }

          # Schedule next run and update state
          new_state =
            %{state | pending_memories: updated_pending, promotion_stats: updated_stats}
            |> schedule_promotion()

          {:noreply, new_state}

        {:ok, 0} ->
          # No candidates to promote, just update stats and reschedule
          updated_stats = %{
            state.promotion_stats
            | last_run: DateTime.utc_now(),
              runs: state.promotion_stats.runs + 1
          }

          new_state =
            %{state | promotion_stats: updated_stats}
            |> schedule_promotion()

          {:noreply, new_state}

        {:error, reason} ->
          Logger.warning(
            "Session.State #{state.session_id} promotion failed: #{inspect(reason)}"
          )

          # Reschedule despite error
          new_state = schedule_promotion(state)
          {:noreply, new_state}
      end
    else
      # Promotion disabled, do nothing (timer won't be rescheduled)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning(
      "Session.State #{state.session_id} received unexpected message: #{inspect(msg)}"
    )

    {:noreply, state}
  end

  # ============================================================================
  # terminate Callback
  # ============================================================================

  @impl true
  def terminate(reason, state) do
    Logger.debug("Session.State #{state.session_id} terminating: #{inspect(reason)}")
    :ok
  end
end
