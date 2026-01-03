defmodule JidoCode.Memory do
  @moduledoc """
  High-level public API for long-term memory operations.

  This module provides a convenient facade over the underlying store management
  and triple store adapter layers. It handles store lifecycle automatically and
  exposes a clean API for persisting, querying, and managing memories.

  ## Architecture

  ```
  JidoCode.Memory (Public API)
       │
       ├── StoreManager.get_or_create/1
       │        │
       │        └── Returns session-isolated ETS store
       │
       └── TripleStoreAdapter
            ├── persist/2
            ├── query_by_type/4
            ├── query_all/3
            ├── query_by_id/2
            ├── supersede/4
            ├── delete/3
            ├── record_access/3
            └── count/3
  ```

  ## Memory Types

  The system supports the following memory types from the Jido ontology:
  - `:fact` - Verified factual information
  - `:assumption` - Inferred or assumed information
  - `:hypothesis` - Tentative explanations being tested
  - `:discovery` - Newly discovered information
  - `:risk` - Identified risks or concerns
  - `:unknown` - Information with uncertain classification
  - `:decision` - Recorded decisions made
  - `:convention` - Coding standards or conventions
  - `:lesson_learned` - Insights from experience

  ## Example Usage

      # Persist a new memory
      memory = %{
        id: "mem-123",
        content: "The project uses Phoenix 1.7",
        memory_type: :fact,
        confidence: 0.95,
        source_type: :tool,
        session_id: "session-abc",
        created_at: DateTime.utc_now()
      }
      {:ok, "mem-123"} = JidoCode.Memory.persist(memory, "session-abc")

      # Query all memories
      {:ok, memories} = JidoCode.Memory.query("session-abc")

      # Query by type with options
      {:ok, facts} = JidoCode.Memory.query_by_type("session-abc", :fact, limit: 10)

      # Get a specific memory
      {:ok, memory} = JidoCode.Memory.get("session-abc", "mem-123")

      # Mark a memory as superseded
      :ok = JidoCode.Memory.supersede("session-abc", "old-mem", "new-mem")

      # Forget a memory (soft delete)
      :ok = JidoCode.Memory.forget("session-abc", "mem-123")

  ## Session Isolation

  All operations are scoped to a session ID. Each session has its own isolated
  store, ensuring complete separation between different coding sessions.

  """

  alias JidoCode.Memory.LongTerm.StoreManager
  alias JidoCode.Memory.LongTerm.TripleStoreAdapter
  alias JidoCode.Memory.Types

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  Input structure for persisting a memory item.
  See `JidoCode.Memory.LongTerm.TripleStoreAdapter.memory_input()` for details.
  """
  @type memory_input :: TripleStoreAdapter.memory_input()

  @typedoc """
  Structure returned from memory queries.
  See `JidoCode.Memory.LongTerm.TripleStoreAdapter.stored_memory()` for details.
  """
  @type stored_memory :: TripleStoreAdapter.stored_memory()

  # =============================================================================
  # Persist API
  # =============================================================================

  @doc """
  Persists a memory item for a session.

  Automatically creates the session store if it doesn't exist.
  Validates that memory_type, source_type, and confidence are valid.
  Also enforces a per-session memory limit to prevent unbounded growth.

  ## Parameters

  - `memory` - The memory input map (see `memory_input()` type)
  - `session_id` - Session identifier

  ## Returns

  - `{:ok, memory_id}` - Successfully persisted
  - `{:error, :invalid_memory_type}` - Invalid memory type
  - `{:error, :invalid_source_type}` - Invalid source type
  - `{:error, :invalid_confidence}` - Confidence not in range [0.0, 1.0]
  - `{:error, :session_memory_limit_exceeded}` - Session has too many memories
  - `{:error, reason}` - Other persistence failure

  ## Examples

      memory = %{
        id: "mem-123",
        content: "Uses Phoenix 1.7",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        session_id: "session-abc",
        created_at: DateTime.utc_now()
      }

      {:ok, "mem-123"} = JidoCode.Memory.persist(memory, "session-abc")

  """
  @spec persist(memory_input(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def persist(memory, session_id) when is_map(memory) and is_binary(session_id) do
    with :ok <- validate_memory_fields(memory),
         {:ok, store} <- StoreManager.get_or_create(session_id),
         :ok <- check_session_memory_limit(session_id) do
      TripleStoreAdapter.persist(memory, store)
    end
  end

  # Checks if the session has exceeded the maximum memory limit.
  # This prevents runaway agents or malicious actors from consuming unbounded memory.
  defp check_session_memory_limit(session_id) do
    max_memories = Types.default_max_memories_per_session()

    case count(session_id) do
      {:ok, current_count} when current_count >= max_memories ->
        {:error, :session_memory_limit_exceeded}

      {:ok, _} ->
        :ok

      {:error, _reason} ->
        # If we can't count, allow the operation (fail open for availability)
        :ok
    end
  end

  # Validates memory fields before persistence
  defp validate_memory_fields(memory) do
    cond do
      not Types.valid_memory_type?(memory[:memory_type]) ->
        {:error, :invalid_memory_type}

      not Types.valid_source_type?(memory[:source_type]) ->
        {:error, :invalid_source_type}

      not is_number(memory[:confidence]) or memory[:confidence] < 0.0 or
          memory[:confidence] > 1.0 ->
        {:error, :invalid_confidence}

      true ->
        :ok
    end
  end

  # =============================================================================
  # Query API
  # =============================================================================

  @doc """
  Queries memories for a session with optional filters.

  ## Options

  - `:type` - Filter by memory type (e.g., `:fact`, `:assumption`)
  - `:min_confidence` - Minimum confidence threshold (0.0 to 1.0)
  - `:limit` - Maximum number of results
  - `:include_superseded` - Include superseded memories (default: false)

  ## Examples

      # All memories for session
      {:ok, memories} = JidoCode.Memory.query("session-abc")

      # Filter by type
      {:ok, facts} = JidoCode.Memory.query("session-abc", type: :fact)

      # Filter by confidence
      {:ok, confident} = JidoCode.Memory.query("session-abc", min_confidence: 0.8)

      # Combine options
      {:ok, results} = JidoCode.Memory.query("session-abc",
        type: :discovery,
        min_confidence: 0.7,
        limit: 20
      )

  """
  @spec query(String.t(), keyword()) :: {:ok, [stored_memory()]} | {:error, term()}
  def query(session_id, opts \\ []) when is_binary(session_id) and is_list(opts) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.query_all(store, session_id, opts)
    end
  end

  @doc """
  Queries memories by type for a session.

  This is a convenience wrapper around `query/2` for type-specific queries.

  ## Options

  - `:limit` - Maximum number of results

  ## Examples

      {:ok, facts} = JidoCode.Memory.query_by_type("session-abc", :fact)
      {:ok, recent_assumptions} = JidoCode.Memory.query_by_type("session-abc", :assumption, limit: 5)

  """
  @spec query_by_type(String.t(), Types.memory_type(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_by_type(session_id, memory_type, opts \\ [])
      when is_binary(session_id) and is_atom(memory_type) and is_list(opts) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.query_by_type(store, session_id, memory_type, opts)
    end
  end

  @doc """
  Retrieves a specific memory by ID.

  This function verifies that the memory belongs to the specified session,
  preventing cross-session memory access. If the memory exists but belongs
  to a different session, `{:error, :not_found}` is returned.

  ## Examples

      {:ok, memory} = JidoCode.Memory.get("session-abc", "mem-123")
      {:error, :not_found} = JidoCode.Memory.get("session-abc", "unknown")

  """
  @spec get(String.t(), String.t()) :: {:ok, stored_memory()} | {:error, :not_found}
  def get(session_id, memory_id) when is_binary(session_id) and is_binary(memory_id) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      # Use 3-arity version with session ownership verification
      TripleStoreAdapter.query_by_id(store, session_id, memory_id)
    end
  end

  # =============================================================================
  # Lifecycle API
  # =============================================================================

  @doc """
  Marks a memory as superseded by another memory.

  Superseded memories are excluded from normal queries but can be retrieved
  with the `include_superseded: true` option.

  ## Parameters

  - `session_id` - Session identifier
  - `old_memory_id` - ID of the memory being superseded
  - `new_memory_id` - ID of the replacement memory (optional)

  ## Examples

      # Replace old memory with new one
      :ok = JidoCode.Memory.supersede("session-abc", "old-mem", "new-mem")

      # Mark as obsolete without replacement
      :ok = JidoCode.Memory.supersede("session-abc", "obsolete-mem", nil)

  """
  @spec supersede(String.t(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def supersede(session_id, old_memory_id, new_memory_id \\ nil)
      when is_binary(session_id) and is_binary(old_memory_id) and
             (is_binary(new_memory_id) or is_nil(new_memory_id)) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.supersede(store, session_id, old_memory_id, new_memory_id)
    end
  end

  @doc """
  Forgets a memory (soft delete).

  This is equivalent to `supersede(session_id, memory_id, nil)`.
  The memory is marked as superseded without a replacement, effectively
  removing it from normal queries while preserving the history.

  ## Examples

      :ok = JidoCode.Memory.forget("session-abc", "obsolete-mem")

  """
  @spec forget(String.t(), String.t()) :: :ok | {:error, term()}
  def forget(session_id, memory_id) when is_binary(session_id) and is_binary(memory_id) do
    supersede(session_id, memory_id, nil)
  end

  @doc """
  Permanently deletes a memory from the store.

  Unlike `forget/2`, this completely removes the memory with no recovery option.
  Use with caution.

  ## Examples

      :ok = JidoCode.Memory.delete("session-abc", "mem-123")

  """
  @spec delete(String.t(), String.t()) :: :ok | {:error, term()}
  def delete(session_id, memory_id) when is_binary(session_id) and is_binary(memory_id) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.delete(store, session_id, memory_id)
    end
  end

  # =============================================================================
  # Access Tracking API
  # =============================================================================

  @doc """
  Records an access to a memory.

  This updates the access count and last_accessed timestamp for the memory,
  which can be used for relevance ranking and memory management.

  ## Error Handling

  This function intentionally returns `:ok` even when errors occur because:
  1. Access tracking is a non-critical optimization for relevance ranking
  2. Failing on access tracking would disrupt the main workflow
  3. Errors are logged but not propagated to avoid cascading failures

  This is a "best effort" operation - if it fails, the memory system
  continues to function normally, just without updated access statistics.

  ## Examples

      :ok = JidoCode.Memory.record_access("session-abc", "mem-123")

  """
  @spec record_access(String.t(), String.t()) :: :ok
  def record_access(session_id, memory_id)
      when is_binary(session_id) and is_binary(memory_id) do
    case StoreManager.get_or_create(session_id) do
      {:ok, store} ->
        TripleStoreAdapter.record_access(store, session_id, memory_id)

      {:error, _reason} ->
        # Intentionally swallow errors - see @doc for rationale
        :ok
    end
  end

  # =============================================================================
  # Counting API
  # =============================================================================

  @doc """
  Counts the number of memories for a session.

  ## Options

  - `:include_superseded` - Include superseded memories in count (default: false)

  ## Examples

      {:ok, 42} = JidoCode.Memory.count("session-abc")
      {:ok, 50} = JidoCode.Memory.count("session-abc", include_superseded: true)

  """
  @spec count(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(session_id, opts \\ []) when is_binary(session_id) and is_list(opts) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.count(store, session_id, opts)
    end
  end

  # =============================================================================
  # Relationship Traversal API
  # =============================================================================

  @typedoc """
  Supported relationship types for memory traversal.
  See `JidoCode.Memory.LongTerm.TripleStoreAdapter.relationship()` for details.
  """
  @type relationship :: TripleStoreAdapter.relationship()

  @doc """
  Returns the list of valid relationship types for traversal.

  ## Examples

      [:derived_from, :superseded_by, :supersedes, :same_type, :same_project] =
        JidoCode.Memory.relationship_types()

  """
  @spec relationship_types() :: [relationship()]
  def relationship_types, do: TripleStoreAdapter.relationship_types()

  @doc """
  Queries memories related to a starting memory via the specified relationship.

  Traverses the knowledge graph from a starting memory following the specified
  relationship type to find connected memories.

  ## Relationship Types

  - `:derived_from` - Finds memories referenced in the starting memory's evidence_refs
  - `:superseded_by` - Finds the memory that superseded the starting memory
  - `:supersedes` - Finds memories that were superseded by the starting memory
  - `:same_type` - Finds other memories of the same type
  - `:same_project` - Finds memories in the same project

  ## Options

  - `:depth` - Maximum traversal depth (default: 1, max: 5)
  - `:limit` - Maximum results per level (default: 10)
  - `:include_superseded` - Include superseded memories (default: false)

  ## Examples

      # Find evidence chain for a memory
      {:ok, related} = JidoCode.Memory.query_related(
        "session-abc", "mem-456", :derived_from
      )

      # Find replacement chain with depth
      {:ok, chain} = JidoCode.Memory.query_related(
        "session-abc", "mem-123", :superseded_by, depth: 3
      )

      # Find all memories of the same type
      {:ok, similar} = JidoCode.Memory.query_related(
        "session-abc", "mem-789", :same_type, limit: 20
      )

  """
  @spec query_related(String.t(), String.t(), relationship(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_related(session_id, memory_id, relationship, opts \\ [])
      when is_binary(session_id) and is_binary(memory_id) and is_atom(relationship) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.query_related(store, session_id, memory_id, relationship, opts)
    end
  end

  # =============================================================================
  # Statistics API
  # =============================================================================

  @doc """
  Returns statistics about memories for a session.

  Provides aggregated information about the session's memory store including
  counts by type, confidence distribution, and relationship statistics.

  ## Returns

  A map containing:
  - `:total_count` - Total number of active memories
  - `:superseded_count` - Number of superseded memories
  - `:by_type` - Map of memory types to counts
  - `:by_confidence` - Map of confidence levels (:high, :medium, :low) to counts
  - `:with_evidence` - Count of memories with evidence refs
  - `:with_rationale` - Count of memories with rationale

  ## Examples

      {:ok, stats} = JidoCode.Memory.get_stats("session-abc")
      # => {:ok, %{
      #      total_count: 42,
      #      superseded_count: 5,
      #      by_type: %{fact: 20, assumption: 15, decision: 7},
      #      by_confidence: %{high: 30, medium: 10, low: 2},
      #      with_evidence: 25,
      #      with_rationale: 18
      #    }}

  """
  @spec get_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def get_stats(session_id) when is_binary(session_id) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.get_stats(store, session_id)
    end
  end

  @doc """
  Retrieves contextually relevant memories using relevance scoring.

  This function finds memories that are most relevant to the given context hint
  using a multi-factor scoring algorithm that considers:
  - Text similarity between context and memory content
  - Recency of access or creation
  - Memory confidence level
  - Access frequency

  ## Parameters

  - `session_id` - Session identifier
  - `context_hint` - Description of what context is needed
  - `opts` - Keyword list of options:
    - `:max_results` - Maximum results to return (default: 5)
    - `:min_confidence` - Minimum confidence threshold (default: 0.5)
    - `:recency_weight` - Weight for recency in scoring (default: 0.3)
    - `:include_superseded` - Include superseded memories (default: false)
    - `:include_types` - Filter to specific memory types (default: nil, all types)

  ## Returns

  - `{:ok, [{memory, score}, ...]}` - List of {memory, relevance_score} tuples
  - `{:error, reason}` - Error tuple

  ## Examples

      {:ok, scored} = Memory.get_context("session-abc", "authentication flow")
      # Returns memories related to authentication, sorted by relevance

      {:ok, scored} = Memory.get_context("session-abc", "error handling",
        include_types: [:convention, :decision],
        max_results: 3
      )

  """
  @spec get_context(String.t(), String.t(), keyword()) ::
          {:ok, [{map(), float()}]} | {:error, term()}
  def get_context(session_id, context_hint, opts \\ [])
      when is_binary(session_id) and is_binary(context_hint) and is_list(opts) do
    with {:ok, store} <- StoreManager.get_or_create(session_id) do
      TripleStoreAdapter.get_context(store, session_id, context_hint, opts)
    end
  end

  # =============================================================================
  # Ontology API
  # =============================================================================

  @doc """
  Loads the Jido ontology into the session's store.

  This is a placeholder for future ontology loading functionality.
  When implemented, it will load the jido-core.ttl and jido-knowledge.ttl
  files into the store for SPARQL querying.

  Currently returns `{:ok, 0}` as a no-op.

  ## Examples

      {:ok, triple_count} = JidoCode.Memory.load_ontology("session-abc")

  """
  @spec load_ontology(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_ontology(_session_id) do
    # Placeholder for future TTL loading functionality
    # When RDF library is integrated, this will:
    # 1. Get or create the store for session
    # 2. Load jido-core.ttl
    # 3. Load jido-knowledge.ttl
    # 4. Return count of loaded triples
    {:ok, 0}
  end

  # =============================================================================
  # Session Management API
  # =============================================================================

  @doc """
  Lists all currently open session IDs.

  This surfaces the StoreManager's `list_open/0` functionality through
  the Memory facade for convenience.

  ## Examples

      ["session-123", "session-456"] = JidoCode.Memory.list_sessions()

  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    StoreManager.list_open()
  end

  @doc """
  Closes a session's memory store.

  This releases the ETS table and resources associated with the session.
  Future operations on this session will create a new store.

  ## Examples

      :ok = JidoCode.Memory.close_session("session-123")

  """
  @spec close_session(String.t()) :: :ok | {:error, term()}
  def close_session(session_id) when is_binary(session_id) do
    StoreManager.close(session_id)
  end
end
