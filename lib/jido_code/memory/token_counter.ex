defmodule JidoCode.Memory.TokenCounter do
  @moduledoc """
  Fast token estimation for budget management.

  Uses character-based approximation (4 chars ≈ 1 token for English).
  This is suitable for budget enforcement and context assembly decisions,
  but should not be used for billing or exact token counting.

  ## Estimation Approach

  The 4-character ratio is a commonly used heuristic for English text with
  typical LLM tokenizers. It provides a reasonable estimate without the
  overhead of loading actual tokenizer models.

  ## Usage

      iex> TokenCounter.estimate_tokens("Hello, world!")
      3

      iex> message = %{role: :user, content: "What is Elixir?"}
      iex> TokenCounter.count_message(message)
      7

  ## Overhead Constants

  - Message overhead: 4 tokens (accounts for role markers and structure)
  - Memory overhead: 10 tokens (accounts for type, confidence, timestamps)
  """

  # =============================================================================
  # Constants
  # =============================================================================

  # Average characters per token for English text with typical LLM tokenizers
  @chars_per_token 4

  # Overhead for message structure (role markers, separators)
  @message_overhead 4

  # Overhead for memory metadata (type badge, confidence, timestamp)
  @memory_overhead 10

  # =============================================================================
  # Types
  # =============================================================================

  alias JidoCode.Memory.Types

  # Note: For message type, use Types.message() from the shared types module.

  @typedoc """
  A stored memory with content and metadata.
  """
  @type stored_memory :: %{
          required(:content) => String.t() | nil,
          optional(:memory_type) => atom(),
          optional(:confidence) => float(),
          optional(:created_at) => DateTime.t()
        }

  # =============================================================================
  # Public API - Basic Estimation
  # =============================================================================

  @doc """
  Estimates the number of tokens in a text string.

  Uses a simple character-based approximation (4 chars ≈ 1 token).
  Returns 0 for nil or empty strings.

  ## Examples

      iex> TokenCounter.estimate_tokens("Hello, world!")
      3

      iex> TokenCounter.estimate_tokens("")
      0

      iex> TokenCounter.estimate_tokens(nil)
      0

      iex> TokenCounter.estimate_tokens("This is approximately sixteen tokens or so")
      10

  """
  @spec estimate_tokens(String.t() | nil) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    div(String.length(text), @chars_per_token)
  end

  def estimate_tokens(nil), do: 0

  @doc """
  Returns the characters-per-token ratio used for estimation.
  """
  @spec chars_per_token() :: pos_integer()
  def chars_per_token, do: @chars_per_token

  # =============================================================================
  # Public API - Message Counting
  # =============================================================================

  @doc """
  Counts tokens in a conversation message.

  Adds overhead for message structure (role markers, separators).
  The overhead accounts for tokens used by the message framing.

  ## Parameters

  - `message` - A map with `:role` and `:content` keys

  ## Examples

      iex> TokenCounter.count_message(%{role: :user, content: "Hello!"})
      5

      iex> TokenCounter.count_message(%{role: :assistant, content: nil})
      4

  """
  @spec count_message(Types.message()) :: non_neg_integer()
  def count_message(%{content: content}) do
    estimate_tokens(content) + @message_overhead
  end

  # Handle messages without content key (shouldn't happen but be defensive)
  def count_message(_), do: @message_overhead

  @doc """
  Counts total tokens in a list of messages.

  Sums the token count of each message including overhead.

  ## Examples

      iex> messages = [
      ...>   %{role: :user, content: "Hi"},
      ...>   %{role: :assistant, content: "Hello!"}
      ...> ]
      iex> TokenCounter.count_messages(messages)
      9

  """
  @spec count_messages([Types.message()]) :: non_neg_integer()
  def count_messages(messages) when is_list(messages) do
    Enum.reduce(messages, 0, fn msg, acc -> count_message(msg) + acc end)
  end

  def count_messages(_), do: 0

  @doc """
  Returns the overhead added per message.
  """
  @spec message_overhead() :: pos_integer()
  def message_overhead, do: @message_overhead

  # =============================================================================
  # Public API - Memory Counting
  # =============================================================================

  @doc """
  Counts tokens in a stored memory.

  Adds overhead for memory metadata (type badge, confidence level, timestamp).
  The overhead accounts for formatting when memories are included in prompts.

  ## Parameters

  - `memory` - A map with at least a `:content` key

  ## Examples

      iex> memory = %{content: "Uses Phoenix framework", memory_type: :fact, confidence: 0.9}
      iex> TokenCounter.count_memory(memory)
      15

      iex> TokenCounter.count_memory(%{content: nil})
      10

  """
  @spec count_memory(stored_memory()) :: non_neg_integer()
  def count_memory(%{content: content}) do
    estimate_tokens(content) + @memory_overhead
  end

  # Handle memories without content key
  def count_memory(_), do: @memory_overhead

  @doc """
  Counts total tokens in a list of memories.

  Sums the token count of each memory including metadata overhead.

  ## Examples

      iex> memories = [
      ...>   %{content: "Uses Phoenix", memory_type: :fact},
      ...>   %{content: "Prefers Elixir", memory_type: :preference}
      ...> ]
      iex> TokenCounter.count_memories(memories)
      27

  """
  @spec count_memories([stored_memory()]) :: non_neg_integer()
  def count_memories(memories) when is_list(memories) do
    Enum.reduce(memories, 0, fn mem, acc -> count_memory(mem) + acc end)
  end

  def count_memories(_), do: 0

  @doc """
  Returns the overhead added per memory.
  """
  @spec memory_overhead() :: pos_integer()
  def memory_overhead, do: @memory_overhead

  # =============================================================================
  # Public API - Working Context Counting
  # =============================================================================

  @doc """
  Counts tokens in working context key-value pairs.

  Each key-value pair has a small overhead for formatting.

  ## Parameters

  - `context` - A map of context key-value pairs

  ## Examples

      iex> context = %{framework: "Phoenix 1.7", language: "Elixir"}
      iex> TokenCounter.count_working_context(context)
      9

  """
  @spec count_working_context(map()) :: non_neg_integer()
  def count_working_context(context) when is_map(context) do
    Enum.reduce(context, 0, fn {key, value}, acc ->
      key_tokens = estimate_tokens(to_string(key))
      value_tokens = estimate_tokens(to_string(value))
      # 2 tokens overhead per pair for formatting (": ", newline, bullet)
      acc + key_tokens + value_tokens + 2
    end)
  end

  def count_working_context(_), do: 0

  # =============================================================================
  # Public API - Budget Selection
  # =============================================================================

  @doc """
  Selects items from a list that fit within a token budget.

  Uses a counting function to estimate tokens for each item, accumulating
  items until the budget is exceeded. Stops at the first item that would
  exceed the budget (does not try to fit smaller items later).

  ## Parameters

  - `items` - List of items to select from (already sorted by priority)
  - `budget` - Maximum token count allowed
  - `count_fn` - Function that takes an item and returns its token count

  ## Returns

  List of items that fit within the budget, in the same order as input.

  ## Examples

      iex> messages = [%{role: :user, content: "Hello"}]
      iex> TokenCounter.select_within_budget(messages, 100, &TokenCounter.count_message/1)
      [%{role: :user, content: "Hello"}]

  """
  @spec select_within_budget(list(), non_neg_integer(), (any() -> non_neg_integer())) :: list()
  def select_within_budget(items, budget, count_fn) when is_list(items) and is_integer(budget) and budget >= 0 do
    items
    |> Enum.reduce_while({[], 0}, fn item, {acc, tokens} ->
      item_tokens = count_fn.(item)

      if tokens + item_tokens <= budget do
        {:cont, {[item | acc], tokens + item_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def select_within_budget(_, _, _), do: []
end
