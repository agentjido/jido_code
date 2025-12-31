defmodule JidoCode.Memory.ShortTerm.PendingMemories do
  @moduledoc """
  Staging area for memory items awaiting promotion to long-term storage.

  The PendingMemories module manages two types of memory candidates:

  1. **Implicit items** - Discovered through pattern detection or context analysis.
     These are evaluated against an importance threshold during promotion.

  2. **Agent decisions** - Explicit requests from the agent to remember something.
     These bypass the importance threshold and are always promoted.

  ## Importance Scoring

  Items in the implicit staging area have an `importance_score` (0.0 to 1.0)
  calculated based on:
  - Access frequency (how often the item is referenced)
  - Recency (how recently the item was accessed)
  - Confidence level
  - Memory type salience

  ## Promotion Flow

  ```
  Pattern Detection / Context Analysis
            │
            ▼
  ┌─────────────────────┐     ┌─────────────────────┐
  │   Implicit Items    │     │   Agent Decisions   │
  │  (score >= 0.6 to   │     │  (always promoted)  │
  │     promote)        │     │                     │
  └──────────┬──────────┘     └──────────┬──────────┘
             │                           │
             └───────────┬───────────────┘
                         │
                         ▼
               ready_for_promotion/2
                         │
                         ▼
                 Long-term Store
  ```

  ## Memory Limits

  The staging area enforces a maximum item limit (default 500) to prevent
  unbounded memory growth. When the limit is reached, items with the lowest
  importance scores are evicted.

  ## Example Usage

      iex> pending = PendingMemories.new()
      iex> item = %{content: "Phoenix uses Ecto", memory_type: :fact, confidence: 0.9}
      iex> pending = PendingMemories.add_implicit(pending, item)
      iex> ready = PendingMemories.ready_for_promotion(pending, 0.6)

  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  The PendingMemories struct.

  ## Fields

  - `items` - Map of id to pending_item for implicitly staged items
  - `agent_decisions` - List of pending_items explicitly requested by agent
  - `max_items` - Maximum number of implicit items allowed
  """
  @type t :: %__MODULE__{
          items: %{String.t() => Types.pending_item()},
          agent_decisions: [Types.pending_item()],
          max_items: pos_integer(),
          max_agent_decisions: pos_integer()
        }

  @default_max_items 500
  @default_max_agent_decisions 100
  @default_threshold 0.6

  defstruct items: %{},
            agent_decisions: [],
            max_items: @default_max_items,
            max_agent_decisions: @default_max_agent_decisions

  # =============================================================================
  # Constructors
  # =============================================================================

  @doc """
  Creates a new empty PendingMemories with default max_items (500).

  ## Examples

      iex> pending = PendingMemories.new()
      iex> pending.max_items
      500
      iex> pending.items
      %{}

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new empty PendingMemories with custom max_items.

  ## Examples

      iex> pending = PendingMemories.new(100)
      iex> pending.max_items
      100

  """
  @spec new(pos_integer()) :: t()
  def new(max_items) when is_integer(max_items) and max_items > 0 do
    %__MODULE__{max_items: max_items}
  end

  # =============================================================================
  # Core API
  # =============================================================================

  @doc """
  Adds an item to the implicit staging area.

  Items added implicitly are evaluated against the importance threshold
  during promotion. If the item doesn't have an `id`, one is generated.

  When the max_items limit is reached, the item with the lowest
  importance_score is evicted to make room.

  ## Options in item map

  - `:id` - Optional unique identifier (generated if not provided)
  - `:content` - Required content of the memory
  - `:memory_type` - Required type classification
  - `:confidence` - Required confidence score
  - `:source_type` - Required source of the memory
  - `:importance_score` - Optional score (defaults to 0.5)

  ## Examples

      iex> pending = PendingMemories.new()
      iex> item = %{
      ...>   content: "Project uses Phoenix",
      ...>   memory_type: :fact,
      ...>   confidence: 0.9,
      ...>   source_type: :tool,
      ...>   evidence: [],
      ...>   rationale: nil,
      ...>   importance_score: 0.7,
      ...>   created_at: DateTime.utc_now(),
      ...>   access_count: 0
      ...> }
      iex> pending = PendingMemories.add_implicit(pending, item)
      iex> PendingMemories.size(pending)
      1

  """
  @spec add_implicit(t(), map()) :: t()
  def add_implicit(%__MODULE__{} = pending, item) do
    importance = Map.get(item, :importance_score, 0.5)
    pending_item = build_pending_item(item, :implicit, importance)

    updated_items = Map.put(pending.items, pending_item.id, pending_item)
    pending = %{pending | items: updated_items}

    # Enforce max_items limit
    if map_size(pending.items) > pending.max_items do
      evict_lowest(pending)
    else
      pending
    end
  end

  @doc """
  Adds an item as an explicit agent decision.

  Agent decisions bypass the importance threshold during promotion and
  are always included in `ready_for_promotion/2` results.

  The item's `importance_score` is automatically set to 1.0 (maximum)
  and `suggested_by` is set to `:agent`.

  ## Examples

      iex> pending = PendingMemories.new()
      iex> item = %{
      ...>   content: "User prefers tabs over spaces",
      ...>   memory_type: :convention,
      ...>   confidence: 1.0,
      ...>   source_type: :user,
      ...>   evidence: ["User explicitly stated preference"],
      ...>   rationale: "Direct user instruction"
      ...> }
      iex> pending = PendingMemories.add_agent_decision(pending, item)
      iex> length(pending.agent_decisions)
      1

  """
  @spec add_agent_decision(t(), map()) :: t()
  def add_agent_decision(%__MODULE__{} = pending, item) do
    pending_item = build_pending_item(item, :agent, 1.0)
    new_decisions = [pending_item | pending.agent_decisions]

    # Enforce max_agent_decisions limit (drop oldest when exceeded)
    decisions =
      if length(new_decisions) > pending.max_agent_decisions do
        Enum.take(new_decisions, pending.max_agent_decisions)
      else
        new_decisions
      end

    %{pending | agent_decisions: decisions}
  end

  @doc """
  Returns items ready for promotion to long-term storage.

  Returns a list of pending items that meet the promotion criteria:
  - All items from `items` map with importance_score >= threshold
  - All items from `agent_decisions` (regardless of score)

  Results are sorted by importance_score in descending order.

  ## Parameters

  - `pending` - The PendingMemories struct
  - `threshold` - Minimum importance_score for implicit items (default: 0.6)

  ## Examples

      iex> pending = PendingMemories.new()
      iex> pending = PendingMemories.add_implicit(pending, %{
      ...>   content: "High importance",
      ...>   memory_type: :fact,
      ...>   confidence: 0.9,
      ...>   source_type: :tool,
      ...>   importance_score: 0.8
      ...> })
      iex> ready = PendingMemories.ready_for_promotion(pending, 0.6)
      iex> length(ready)
      1

  """
  @spec ready_for_promotion(t(), float()) :: [Types.pending_item()]
  def ready_for_promotion(%__MODULE__{} = pending, threshold \\ @default_threshold) do
    # Get implicit items above threshold
    implicit_ready =
      pending.items
      |> Map.values()
      |> Enum.filter(fn item -> item.importance_score >= threshold end)

    # Combine with agent decisions (always included)
    all_ready = implicit_ready ++ pending.agent_decisions

    # Sort by importance_score descending
    Enum.sort_by(all_ready, & &1.importance_score, :desc)
  end

  @doc """
  Removes promoted items from the staging area.

  Removes the specified ids from the `items` map and clears all
  `agent_decisions` (since they're always promoted together).

  ## Parameters

  - `pending` - The PendingMemories struct
  - `ids` - List of item ids to remove from implicit items

  ## Examples

      iex> pending = PendingMemories.new()
      iex> pending = PendingMemories.add_implicit(pending, %{
      ...>   id: "item-1",
      ...>   content: "Some fact",
      ...>   memory_type: :fact,
      ...>   confidence: 0.9,
      ...>   source_type: :tool
      ...> })
      iex> pending = PendingMemories.clear_promoted(pending, ["item-1"])
      iex> PendingMemories.size(pending)
      0

  """
  @spec clear_promoted(t(), [String.t()]) :: t()
  def clear_promoted(%__MODULE__{} = pending, ids) when is_list(ids) do
    updated_items = Map.drop(pending.items, ids)
    %{pending | items: updated_items, agent_decisions: []}
  end

  @doc """
  Retrieves a pending item by id.

  Searches both the `items` map and `agent_decisions` list.
  Returns `nil` if not found.

  ## Examples

      iex> pending = PendingMemories.new()
      iex> pending = PendingMemories.add_implicit(pending, %{
      ...>   id: "item-1",
      ...>   content: "Some fact",
      ...>   memory_type: :fact,
      ...>   confidence: 0.9,
      ...>   source_type: :tool
      ...> })
      iex> item = PendingMemories.get(pending, "item-1")
      iex> item.content
      "Some fact"

  """
  @spec get(t(), String.t()) :: Types.pending_item() | nil
  def get(%__MODULE__{} = pending, id) do
    case Map.get(pending.items, id) do
      nil ->
        Enum.find(pending.agent_decisions, fn item -> item.id == id end)

      item ->
        item
    end
  end

  @doc """
  Returns the total number of pending items.

  Includes both implicit items and agent decisions.

  ## Examples

      iex> pending = PendingMemories.new()
      iex> PendingMemories.size(pending)
      0

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = pending) do
    map_size(pending.items) + length(pending.agent_decisions)
  end

  @doc """
  Updates the importance_score for an item in the implicit items map.

  Does nothing if the item doesn't exist. Does not affect agent_decisions
  (which always have score 1.0).

  ## Examples

      iex> pending = PendingMemories.new()
      iex> pending = PendingMemories.add_implicit(pending, %{
      ...>   id: "item-1",
      ...>   content: "Some fact",
      ...>   memory_type: :fact,
      ...>   confidence: 0.9,
      ...>   source_type: :tool,
      ...>   importance_score: 0.5
      ...> })
      iex> pending = PendingMemories.update_score(pending, "item-1", 0.8)
      iex> PendingMemories.get(pending, "item-1").importance_score
      0.8

  """
  @spec update_score(t(), String.t(), float()) :: t()
  def update_score(%__MODULE__{} = pending, id, new_score) when is_float(new_score) do
    case Map.get(pending.items, id) do
      nil ->
        pending

      item ->
        updated_item = %{item | importance_score: Types.clamp_to_unit(new_score)}
        %{pending | items: Map.put(pending.items, id, updated_item)}
    end
  end

  @doc """
  Returns all implicit items as a list.

  ## Examples

      iex> pending = PendingMemories.new()
      iex> PendingMemories.list_implicit(pending)
      []

  """
  @spec list_implicit(t()) :: [Types.pending_item()]
  def list_implicit(%__MODULE__{} = pending) do
    Map.values(pending.items)
  end

  @doc """
  Returns all agent decisions as a list.

  ## Examples

      iex> pending = PendingMemories.new()
      iex> PendingMemories.list_agent_decisions(pending)
      []

  """
  @spec list_agent_decisions(t()) :: [Types.pending_item()]
  def list_agent_decisions(%__MODULE__{} = pending) do
    pending.agent_decisions
  end

  @doc """
  Clears all pending items (both implicit and agent decisions).

  ## Examples

      iex> pending = PendingMemories.new()
      iex> pending = PendingMemories.add_implicit(pending, %{
      ...>   content: "Some fact",
      ...>   memory_type: :fact,
      ...>   confidence: 0.9,
      ...>   source_type: :tool
      ...> })
      iex> pending = PendingMemories.clear(pending)
      iex> PendingMemories.size(pending)
      0

  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = pending) do
    %{pending | items: %{}, agent_decisions: []}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @doc false
  @spec generate_id() :: String.t()
  def generate_id do
    # Generate a unique id using timestamp and random component
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(1_000_000)
    "pending-#{timestamp}-#{random}"
  end

  # Builds a pending_item map with common fields extracted
  defp build_pending_item(item, suggested_by, importance_score) do
    now = DateTime.utc_now()
    id = Map.get(item, :id) || generate_id()

    %{
      id: id,
      content: Map.fetch!(item, :content),
      memory_type: Map.fetch!(item, :memory_type),
      confidence: Map.fetch!(item, :confidence),
      source_type: Map.fetch!(item, :source_type),
      evidence: Map.get(item, :evidence, []),
      rationale: Map.get(item, :rationale),
      suggested_by: suggested_by,
      importance_score: importance_score,
      created_at: Map.get(item, :created_at, now),
      access_count: Map.get(item, :access_count, 0)
    }
  end

  defp evict_lowest(%__MODULE__{} = pending) do
    # Find the item with the lowest importance_score
    {lowest_id, _lowest_item} =
      pending.items
      |> Enum.min_by(fn {_id, item} -> item.importance_score end)

    %{pending | items: Map.delete(pending.items, lowest_id)}
  end
end
