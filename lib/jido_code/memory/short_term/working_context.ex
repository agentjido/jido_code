defmodule JidoCode.Memory.ShortTerm.WorkingContext do
  @moduledoc """
  A semantic scratchpad for holding extracted understanding about the current session.

  The WorkingContext provides fast, in-memory access to session context without
  requiring database queries. It stores context items with metadata for tracking
  access patterns and supporting memory promotion decisions.

  ## Purpose

  During an agent session, various pieces of context are discovered:
  - Active file being worked on
  - Project framework and language
  - Current task or user intent
  - Discovered patterns or errors

  The WorkingContext stores these with:
  - **Access tracking** - How often each item is accessed
  - **Timestamps** - When first seen and last accessed
  - **Source tracking** - Whether inferred, explicit, or from tools
  - **Type inference** - Suggested memory type for promotion

  ## Token Budget

  The context maintains a configurable token budget (default 12,000) for
  managing the amount of context that can be included in LLM prompts.

  ## Example Usage

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.7", source: :tool)
      iex> {ctx, value} = WorkingContext.get(ctx, :framework)
      iex> value
      "Phoenix 1.7"

  ## Memory Type Inference

  Context items are assigned a suggested memory type based on their key and source:

  | Key | Source | Suggested Type |
  |-----|--------|----------------|
  | `:framework` | `:tool` | `:fact` |
  | `:primary_language` | `:tool` | `:fact` |
  | `:project_root` | `:tool` | `:fact` |
  | `:user_intent` | `:inferred` | `:assumption` |
  | `:discovered_patterns` | any | `:discovery` |
  | `:active_errors` | any | `nil` (ephemeral) |
  | `:pending_questions` | any | `:unknown` |
  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  A context item with metadata for tracking and promotion.

  ## Fields

  - `key` - The semantic key identifying this context item
  - `value` - The actual value stored
  - `source` - How this value was determined (:inferred, :explicit, :tool)
  - `confidence` - Confidence score (0.0 to 1.0)
  - `access_count` - Number of times this item has been accessed
  - `first_seen` - When this item was first added
  - `last_accessed` - When this item was last read or updated
  - `suggested_type` - Inferred memory type for promotion decisions
  """
  @type context_item :: %{
          key: Types.context_key(),
          value: term(),
          source: :inferred | :explicit | :tool,
          confidence: float(),
          access_count: non_neg_integer(),
          first_seen: DateTime.t(),
          last_accessed: DateTime.t(),
          suggested_type: Types.memory_type() | nil
        }

  @typedoc """
  The WorkingContext struct.

  ## Fields

  - `items` - Map of context_key to context_item
  - `current_tokens` - Approximate token count (for future budget management)
  - `max_tokens` - Maximum allowed tokens in the context
  """
  @type t :: %__MODULE__{
          items: %{Types.context_key() => context_item()},
          current_tokens: non_neg_integer(),
          max_tokens: pos_integer()
        }

  @default_max_tokens 12_000
  @default_confidence 0.8
  @default_source :explicit

  defstruct items: %{},
            current_tokens: 0,
            max_tokens: @default_max_tokens

  # =============================================================================
  # Constructors
  # =============================================================================

  @doc """
  Creates a new empty WorkingContext with default max_tokens (12,000).

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx.max_tokens
      12_000
      iex> ctx.items
      %{}

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new empty WorkingContext with custom max_tokens.

  ## Examples

      iex> ctx = WorkingContext.new(8_000)
      iex> ctx.max_tokens
      8_000

  """
  @spec new(pos_integer()) :: t()
  def new(max_tokens) when is_integer(max_tokens) and max_tokens > 0 do
    %__MODULE__{max_tokens: max_tokens}
  end

  # =============================================================================
  # Core API
  # =============================================================================

  @doc """
  Adds or updates a context item.

  When adding a new item:
  - Sets `first_seen` and `last_accessed` to current time
  - Sets `access_count` to 1
  - Infers `suggested_type` based on key and source

  When updating an existing item:
  - Preserves `first_seen`
  - Updates `last_accessed` to current time
  - Increments `access_count`
  - Updates value and other metadata

  ## Options

  - `:source` - How the value was determined (`:inferred`, `:explicit`, `:tool`).
    Defaults to `:explicit`.
  - `:confidence` - Confidence score from 0.0 to 1.0. Defaults to 0.8.
  - `:memory_type` - Override the inferred memory type. If not provided,
    the type is inferred from the key and source.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.7", source: :tool)
      iex> ctx.items[:framework].value
      "Phoenix 1.7"
      iex> ctx.items[:framework].source
      :tool

  """
  @spec put(t(), Types.context_key(), term(), keyword()) :: t()
  def put(%__MODULE__{} = ctx, key, value, opts \\ []) do
    # Validate context key to prevent arbitrary atom creation
    unless Types.valid_context_key?(key) do
      raise ArgumentError,
            "Invalid context key: #{inspect(key)}. " <>
              "Valid keys are: #{inspect(Types.context_keys())}"
    end

    source = Keyword.get(opts, :source, @default_source)
    confidence = Keyword.get(opts, :confidence, @default_confidence)
    memory_type = Keyword.get(opts, :memory_type)

    now = DateTime.utc_now()

    new_item =
      case Map.get(ctx.items, key) do
        nil ->
          # New item
          %{
            key: key,
            value: value,
            source: source,
            confidence: Types.clamp_to_unit(confidence),
            access_count: 1,
            first_seen: now,
            last_accessed: now,
            suggested_type: memory_type || infer_memory_type(key, source)
          }

        existing ->
          # Update existing item
          %{
            existing
            | value: value,
              source: source,
              confidence: Types.clamp_to_unit(confidence),
              access_count: existing.access_count + 1,
              last_accessed: now,
              suggested_type: memory_type || infer_memory_type(key, source)
          }
      end

    %{ctx | items: Map.put(ctx.items, key, new_item)}
  end

  @doc """
  Retrieves a context item's value and updates access tracking.

  Returns a tuple of `{updated_context, value}`. If the key doesn't exist,
  returns `{context, nil}` without modification.

  The access tracking updates:
  - Increments `access_count`
  - Updates `last_accessed` to current time

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> {ctx, value} = WorkingContext.get(ctx, :framework)
      iex> value
      "Phoenix"
      iex> ctx.items[:framework].access_count
      2

      iex> ctx = WorkingContext.new()
      iex> {ctx, value} = WorkingContext.get(ctx, :nonexistent)
      iex> value
      nil

  """
  @spec get(t(), Types.context_key()) :: {t(), term() | nil}
  def get(%__MODULE__{} = ctx, key) do
    case Map.get(ctx.items, key) do
      nil ->
        {ctx, nil}

      item ->
        now = DateTime.utc_now()

        updated_item = %{
          item
          | access_count: item.access_count + 1,
            last_accessed: now
        }

        updated_ctx = %{ctx | items: Map.put(ctx.items, key, updated_item)}
        {updated_ctx, item.value}
    end
  end

  @doc """
  Retrieves a context item's value without updating access tracking.

  This is useful when you need to inspect the context without affecting
  the access statistics used for promotion decisions.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> WorkingContext.peek(ctx, :framework)
      "Phoenix"
      iex> ctx.items[:framework].access_count
      1

  """
  @spec peek(t(), Types.context_key()) :: term() | nil
  def peek(%__MODULE__{} = ctx, key) do
    case Map.get(ctx.items, key) do
      nil -> nil
      item -> item.value
    end
  end

  @doc """
  Removes a context item.

  Returns the updated context. If the key doesn't exist, returns the
  context unchanged.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> ctx = WorkingContext.delete(ctx, :framework)
      iex> WorkingContext.peek(ctx, :framework)
      nil

  """
  @spec delete(t(), Types.context_key()) :: t()
  def delete(%__MODULE__{} = ctx, key) do
    %{ctx | items: Map.delete(ctx.items, key)}
  end

  @doc """
  Returns all context items as a list.

  This is useful for context assembly when building LLM prompts.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> [item] = WorkingContext.to_list(ctx)
      iex> item.key
      :framework

  """
  @spec to_list(t()) :: [context_item()]
  def to_list(%__MODULE__{} = ctx) do
    Map.values(ctx.items)
  end

  @doc """
  Returns context items as a simple key-value map without metadata.

  This is useful when you need just the values without access tracking
  information.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> ctx = WorkingContext.put(ctx, :primary_language, "Elixir")
      iex> WorkingContext.to_map(ctx)
      %{framework: "Phoenix", primary_language: "Elixir"}

  """
  @spec to_map(t()) :: %{Types.context_key() => term()}
  def to_map(%__MODULE__{} = ctx) do
    Map.new(ctx.items, fn {key, item} -> {key, item.value} end)
  end

  @doc """
  Returns the number of items in the context.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> WorkingContext.size(ctx)
      0
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> WorkingContext.size(ctx)
      1

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = ctx) do
    map_size(ctx.items)
  end

  @doc """
  Clears all items from the context, resetting to empty.

  Preserves the max_tokens setting.

  ## Examples

      iex> ctx = WorkingContext.new(8_000)
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> ctx = WorkingContext.clear(ctx)
      iex> WorkingContext.size(ctx)
      0
      iex> ctx.max_tokens
      8_000

  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = ctx) do
    %{ctx | items: %{}, current_tokens: 0}
  end

  @doc """
  Checks if the context contains a specific key.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      iex> WorkingContext.has_key?(ctx, :framework)
      true
      iex> WorkingContext.has_key?(ctx, :nonexistent)
      false

  """
  @spec has_key?(t(), Types.context_key()) :: boolean()
  def has_key?(%__MODULE__{} = ctx, key) do
    Map.has_key?(ctx.items, key)
  end

  @doc """
  Returns the full context item (with metadata) for a key.

  Returns `nil` if the key doesn't exist. Does not update access tracking.

  ## Examples

      iex> ctx = WorkingContext.new()
      iex> ctx = WorkingContext.put(ctx, :framework, "Phoenix", source: :tool)
      iex> item = WorkingContext.get_item(ctx, :framework)
      iex> item.source
      :tool

  """
  @spec get_item(t(), Types.context_key()) :: context_item() | nil
  def get_item(%__MODULE__{} = ctx, key) do
    Map.get(ctx.items, key)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @doc false
  @spec infer_memory_type(Types.context_key(), :inferred | :explicit | :tool) ::
          Types.memory_type() | nil
  def infer_memory_type(:framework, :tool), do: :fact
  def infer_memory_type(:primary_language, :tool), do: :fact
  def infer_memory_type(:project_root, :tool), do: :fact
  def infer_memory_type(:active_file, :tool), do: :fact
  def infer_memory_type(:user_intent, :inferred), do: :assumption
  def infer_memory_type(:current_task, :inferred), do: :assumption
  def infer_memory_type(:discovered_patterns, _source), do: :discovery
  def infer_memory_type(:file_relationships, _source), do: :discovery
  def infer_memory_type(:active_errors, _source), do: nil
  def infer_memory_type(:pending_questions, _source), do: :unknown
  def infer_memory_type(_key, _source), do: nil
end
