defmodule JidoCode.Memory.ContextBuilder do
  @moduledoc """
  Builds memory-enhanced context for LLM prompts.

  Combines:
  - Working context (current session state)
  - Long-term memories (relevant persisted knowledge)

  Respects token budget allocation and prioritizes content
  based on relevance and recency.

  ## Usage

      # Build context for a session
      {:ok, context} = ContextBuilder.build(session_id)

      # Build with custom token budget
      {:ok, context} = ContextBuilder.build(session_id,
        token_budget: %{total: 16_000, ...}
      )

      # Build with query hint for better memory retrieval
      {:ok, context} = ContextBuilder.build(session_id,
        query_hint: "user asked about Phoenix patterns"
      )

      # Format context for inclusion in system prompt
      prompt_text = ContextBuilder.format_for_prompt(context)

  ## Token Budget

  The builder respects token budgets for each context component:
  - `system`: Reserved for system instructions
  - `conversation`: Message history
  - `working`: Current session working context
  - `long_term`: Memories from long-term storage

  When a component exceeds its budget, content is truncated with
  priority given to more recent/relevant items.
  """

  alias JidoCode.Memory
  alias JidoCode.Session.State

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  A message in the conversation history.
  """
  @type message :: %{
          role: :user | :assistant | :system,
          content: String.t(),
          timestamp: DateTime.t() | nil
        }

  @typedoc """
  A memory item from long-term storage.
  """
  @type stored_memory :: Memory.stored_memory()

  @typedoc """
  Token budget allocation for context components.
  """
  @type token_budget :: %{
          total: pos_integer(),
          system: pos_integer(),
          conversation: pos_integer(),
          working: pos_integer(),
          long_term: pos_integer()
        }

  @typedoc """
  Token counts for each context component.
  """
  @type token_counts :: %{
          conversation: non_neg_integer(),
          working: non_neg_integer(),
          long_term: non_neg_integer(),
          total: non_neg_integer()
        }

  @typedoc """
  The assembled context structure.
  """
  @type context :: %{
          conversation: [message()],
          working_context: map(),
          long_term_memories: [stored_memory()],
          system_context: String.t() | nil,
          token_counts: token_counts()
        }

  # =============================================================================
  # Constants
  # =============================================================================

  @default_budget %{
    total: 32_000,
    system: 2_000,
    conversation: 20_000,
    working: 4_000,
    long_term: 6_000
  }

  # Approximate tokens per character (conservative estimate for English)
  @chars_per_token 4

  # Default limits for memory queries
  @default_memory_limit 10
  @high_confidence_limit 5
  @high_confidence_threshold 0.7

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the default token budget configuration.
  """
  @spec default_budget() :: token_budget()
  def default_budget, do: @default_budget

  @doc """
  Builds a memory-enhanced context for the given session.

  ## Options

  - `:token_budget` - Custom token budget (default: `default_budget()`)
  - `:query_hint` - Optional text hint to improve memory retrieval relevance
  - `:include_memories` - Whether to include long-term memories (default: true)
  - `:include_conversation` - Whether to include conversation history (default: true)

  ## Returns

  - `{:ok, context}` - Successfully assembled context
  - `{:error, :session_not_found}` - Session doesn't exist
  - `{:error, reason}` - Other errors

  ## Examples

      {:ok, context} = ContextBuilder.build("session-123")

      {:ok, context} = ContextBuilder.build("session-123",
        query_hint: "how do I configure authentication?",
        token_budget: %{total: 16_000, system: 1_000, conversation: 10_000, working: 2_000, long_term: 3_000}
      )

  """
  @spec build(String.t(), keyword()) :: {:ok, context()} | {:error, term()}
  def build(session_id, opts \\ []) when is_binary(session_id) do
    token_budget = Keyword.get(opts, :token_budget, @default_budget)
    query_hint = Keyword.get(opts, :query_hint)
    include_memories = Keyword.get(opts, :include_memories, true)
    include_conversation = Keyword.get(opts, :include_conversation, true)

    with {:ok, conversation} <- get_conversation(session_id, token_budget.conversation, include_conversation),
         {:ok, working} <- get_working_context(session_id),
         {:ok, long_term} <- get_relevant_memories(session_id, query_hint, include_memories, token_budget.long_term) do
      {:ok, assemble_context(conversation, working, long_term, token_budget)}
    end
  end

  @doc """
  Formats the context for inclusion in an LLM system prompt.

  Produces markdown-formatted text with sections for:
  - Session Context (working context key-value pairs)
  - Remembered Information (long-term memories with type and confidence)

  ## Examples

      context = %{
        working_context: %{project_root: "/app", primary_language: "elixir"},
        long_term_memories: [%{memory_type: :fact, confidence: 0.9, content: "Uses Phoenix 1.7"}]
      }

      ContextBuilder.format_for_prompt(context)
      # => "## Session Context\\n- **Project root**: /app\\n..."

  """
  @spec format_for_prompt(context()) :: String.t()
  def format_for_prompt(%{working_context: working, long_term_memories: memories}) do
    parts = []

    parts =
      if map_size(working) > 0 do
        ["## Session Context\n" <> format_working_context(working) | parts]
      else
        parts
      end

    parts =
      if length(memories) > 0 do
        ["## Remembered Information\n" <> format_memories(memories) | parts]
      else
        parts
      end

    Enum.join(Enum.reverse(parts), "\n\n")
  end

  def format_for_prompt(_), do: ""

  @doc """
  Estimates the token count for a given string.

  Uses a simple character-based estimation (approximately 4 characters per token
  for English text). This is a conservative estimate suitable for budget planning.

  ## Examples

      ContextBuilder.estimate_tokens("Hello, world!")
      # => 4

  """
  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    div(byte_size(text), @chars_per_token)
  end

  def estimate_tokens(_), do: 0

  # =============================================================================
  # Private Functions - Data Retrieval
  # =============================================================================

  defp get_conversation(_session_id, _budget, false) do
    {:ok, []}
  end

  defp get_conversation(session_id, budget, true) do
    case State.get_messages(session_id) do
      {:ok, messages} ->
        truncated = truncate_messages_to_budget(messages, budget)
        {:ok, truncated}

      {:error, :not_found} ->
        {:error, :session_not_found}

      error ->
        error
    end
  end

  defp get_working_context(session_id) do
    case State.get_all_context(session_id) do
      {:ok, context} ->
        {:ok, context}

      {:error, :not_found} ->
        # Session exists but no context set yet
        {:ok, %{}}

      error ->
        error
    end
  end

  defp get_relevant_memories(_session_id, _query_hint, false, _budget) do
    {:ok, []}
  end

  defp get_relevant_memories(session_id, query_hint, true, budget) do
    # Determine query strategy based on whether we have a hint
    opts =
      if query_hint do
        # More memories when we have a query hint for relevance filtering
        [limit: @default_memory_limit]
      else
        # Fewer, higher confidence memories when no hint
        [min_confidence: @high_confidence_threshold, limit: @high_confidence_limit]
      end

    case Memory.query(session_id, opts) do
      {:ok, memories} ->
        truncated = truncate_memories_to_budget(memories, budget)
        {:ok, truncated}

      {:error, _reason} ->
        # Memory query errors shouldn't fail context building
        {:ok, []}
    end
  end

  # =============================================================================
  # Private Functions - Assembly
  # =============================================================================

  defp assemble_context(conversation, working, long_term, _budget) do
    conversation_tokens = estimate_conversation_tokens(conversation)
    working_tokens = estimate_working_tokens(working)
    long_term_tokens = estimate_memories_tokens(long_term)

    %{
      conversation: conversation,
      working_context: working,
      long_term_memories: long_term,
      system_context: nil,
      token_counts: %{
        conversation: conversation_tokens,
        working: working_tokens,
        long_term: long_term_tokens,
        total: conversation_tokens + working_tokens + long_term_tokens
      }
    }
  end

  # =============================================================================
  # Private Functions - Truncation
  # =============================================================================

  defp truncate_messages_to_budget(messages, budget) do
    # Keep most recent messages that fit within budget
    # Process in reverse to prioritize recent messages
    messages
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn msg, {acc, tokens} ->
      msg_tokens = estimate_message_tokens(msg)

      if tokens + msg_tokens <= budget do
        {:cont, {[msg | acc], tokens + msg_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
  end

  defp truncate_memories_to_budget(memories, budget) do
    # Keep memories that fit within budget
    # Already ordered by relevance from the query
    memories
    |> Enum.reduce_while({[], 0}, fn mem, {acc, tokens} ->
      mem_tokens = estimate_memory_tokens(mem)

      if tokens + mem_tokens <= budget do
        {:cont, {acc ++ [mem], tokens + mem_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
  end

  # =============================================================================
  # Private Functions - Token Estimation
  # =============================================================================

  defp estimate_conversation_tokens(messages) do
    Enum.reduce(messages, 0, fn msg, acc ->
      acc + estimate_message_tokens(msg)
    end)
  end

  defp estimate_message_tokens(msg) do
    content = Map.get(msg, :content, "")
    role = Map.get(msg, :role, :user)

    # Add overhead for message structure
    role_overhead = byte_size(Atom.to_string(role)) + 10
    content_tokens = estimate_tokens(content)

    div(role_overhead, @chars_per_token) + content_tokens
  end

  defp estimate_working_tokens(working) do
    working
    |> Enum.reduce(0, fn {key, value}, acc ->
      key_tokens = estimate_tokens(format_key(key))
      value_tokens = estimate_tokens(format_value(value))
      acc + key_tokens + value_tokens + 5
    end)
  end

  defp estimate_memories_tokens(memories) do
    Enum.reduce(memories, 0, fn mem, acc ->
      acc + estimate_memory_tokens(mem)
    end)
  end

  defp estimate_memory_tokens(mem) do
    content = Map.get(mem, :content, "")
    type = Map.get(mem, :memory_type, :unknown)

    # Add overhead for formatting (type badge, confidence badge, bullet)
    overhead = 30
    content_tokens = estimate_tokens(content)
    type_tokens = estimate_tokens(Atom.to_string(type))

    content_tokens + type_tokens + div(overhead, @chars_per_token)
  end

  # =============================================================================
  # Private Functions - Formatting
  # =============================================================================

  defp format_working_context(working) do
    working
    |> Enum.map(fn {key, value} ->
      "- **#{format_key(key)}**: #{format_value(value)}"
    end)
    |> Enum.join("\n")
  end

  defp format_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_key(key), do: to_string(key)

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(value), do: inspect(value)

  defp format_memories(memories) do
    memories
    |> Enum.map(fn mem ->
      confidence_badge = confidence_badge(mem.confidence)
      type_badge = "[#{mem.memory_type}]"
      timestamp = format_timestamp(mem[:timestamp])

      if timestamp do
        "- #{type_badge} #{confidence_badge} #{mem.content} _(#{timestamp})_"
      else
        "- #{type_badge} #{confidence_badge} #{mem.content}"
      end
    end)
    |> Enum.join("\n")
  end

  defp confidence_badge(c) when is_number(c) and c >= 0.8, do: "(high confidence)"
  defp confidence_badge(c) when is_number(c) and c >= 0.5, do: "(medium confidence)"
  defp confidence_badge(_), do: "(low confidence)"

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end

  defp format_timestamp(_), do: nil
end
