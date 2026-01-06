defmodule JidoCode.Memory.LongTerm.TripleStoreAdapter do
  @moduledoc """
  Adapter layer for mapping Elixir memory structs to/from RDF triples.

  This module provides the interface between Elixir memory structs and the
  TripleStore backend, using SPARQL queries aligned with the Jido ontology.

  ## Store Backend

  Uses the TripleStore library for persistent RDF storage. Each session gets
  its own TripleStore instance managed by StoreManager.

  ## Triple Representation

  Memories are stored as RDF triples following the Jido ontology:
  - Each memory has a unique IRI: `jido:memory_<id>`
  - Memory types map to ontology classes (e.g., `jido:Fact`, `jido:Assumption`)
  - Confidence and source types map to ontology individuals
  - Provenance tracked via session IRIs: `jido:session_<id>`

  ## Example Usage

      # Persist a memory
      {:ok, id} = TripleStoreAdapter.persist(memory_input, store)

      # Query memories by type
      {:ok, memories} = TripleStoreAdapter.query_by_type(store, session_id, :fact)

      # Query all memories for a session
      {:ok, memories} = TripleStoreAdapter.query_all(store, session_id)

      # Get a specific memory
      {:ok, memory} = TripleStoreAdapter.query_by_id(store, session_id, memory_id)

      # Mark a memory as superseded
      :ok = TripleStoreAdapter.supersede(store, session_id, old_id, new_id)

  """

  alias JidoCode.Memory.LongTerm.SPARQLQueries
  alias JidoCode.Memory.Types

  require Logger

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  Input structure for persisting a memory item.

  Required fields:
  - `id` - Unique identifier for the memory
  - `content` - The memory content/summary
  - `memory_type` - Classification (:fact, :assumption, etc.)
  - `confidence` - Confidence score (0.0 to 1.0) or level (:high, :medium, :low)
  - `source_type` - Origin (:user, :agent, :tool, :external_document)
  - `session_id` - Session this memory belongs to
  - `created_at` - When the memory was created

  Optional fields:
  - `agent_id` - ID of the agent that created this memory
  - `project_id` - ID of the project this memory applies to
  - `evidence_refs` - List of evidence references
  - `rationale` - Explanation for why this is worth remembering
  """
  @type memory_input :: %{
          required(:id) => String.t(),
          required(:content) => String.t(),
          required(:memory_type) => Types.memory_type(),
          required(:confidence) => float() | Types.confidence_level(),
          required(:source_type) => Types.source_type(),
          required(:session_id) => String.t(),
          required(:created_at) => DateTime.t(),
          optional(:agent_id) => String.t() | nil,
          optional(:project_id) => String.t() | nil,
          optional(:evidence_refs) => [String.t()],
          optional(:rationale) => String.t() | nil
        }

  @typedoc """
  Structure returned from memory queries.

  Contains all persisted memory fields plus lifecycle tracking:
  - `superseded_by` - ID of memory that replaced this one (if superseded)
  - `access_count` - Number of times this memory was accessed
  - `last_accessed` - When this memory was last accessed
  """
  @type stored_memory :: %{
          id: String.t(),
          content: String.t(),
          memory_type: Types.memory_type(),
          confidence: Types.confidence_level(),
          source_type: Types.source_type(),
          session_id: String.t(),
          agent_id: String.t() | nil,
          project_id: String.t() | nil,
          rationale: String.t() | nil,
          evidence_refs: [String.t()],
          timestamp: DateTime.t(),
          superseded_by: String.t() | nil,
          access_count: non_neg_integer(),
          last_accessed: DateTime.t() | nil
        }

  @typedoc """
  Reference to an open TripleStore instance.
  """
  @type store_ref :: TripleStore.store()

  # =============================================================================
  # Persist API
  # =============================================================================

  @doc """
  Persists a memory item to the store.

  Stores the memory as RDF triples using SPARQL INSERT.

  ## Parameters

  - `memory` - The memory input map (see `memory_input()` type)
  - `store` - Reference to the TripleStore

  ## Returns

  - `{:ok, id}` - Successfully persisted with the memory ID
  - `{:error, reason}` - Failed to persist

  ## Examples

      memory = %{
        id: "mem-123",
        content: "The project uses Phoenix 1.7",
        memory_type: :fact,
        confidence: 0.95,
        source_type: :tool,
        session_id: "session-abc",
        created_at: DateTime.utc_now()
      }

      {:ok, "mem-123"} = TripleStoreAdapter.persist(memory, store)

  """
  @spec persist(memory_input(), store_ref()) :: {:ok, String.t()} | {:error, term()}
  def persist(memory, store) do
    with :ok <- validate_memory_id(memory.id),
         :ok <- validate_session_id(memory.session_id),
         query = SPARQLQueries.insert_memory(memory),
         {:ok, _} <- TripleStore.update(store, query) do
      {:ok, memory.id}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Query API
  # =============================================================================

  @doc """
  Queries memories by type for a session.

  ## Options

  - `:limit` - Maximum number of results (default: no limit)
  - `:min_confidence` - Minimum confidence (:high, :medium, :low)
  - `:include_superseded` - Include superseded memories (default: false)

  ## Examples

      {:ok, facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact)
      {:ok, assumptions} = TripleStoreAdapter.query_by_type(store, "session-123", :assumption, limit: 10)

  """
  @spec query_by_type(store_ref(), String.t(), Types.memory_type(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_by_type(store, session_id, memory_type, opts \\ []) do
    with :ok <- validate_session_id(session_id),
         query = SPARQLQueries.query_by_type(session_id, memory_type, opts),
         {:ok, results} <- TripleStore.query(store, query) do
      memories = Enum.map(results, &map_type_result(&1, session_id, memory_type))
      {:ok, memories}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Queries all memories for a session.

  ## Options

  - `:limit` - Maximum number of results (default: no limit)
  - `:min_confidence` - Minimum confidence threshold (:high, :medium, :low)
  - `:include_superseded` - Include superseded memories (default: false)
  - `:type` - Filter by memory type (default: all types)

  ## Examples

      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123")
      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123", min_confidence: :medium)
      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123", include_superseded: true)

  """
  @spec query_all(store_ref(), String.t(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_all(store, session_id, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      # Apply default limit if not specified to prevent unbounded results
      opts = apply_default_limit(opts)

      # Check if type filter is specified
      type_filter = Keyword.get(opts, :type)

      if type_filter do
        # Use type-specific query
        query_by_type(store, session_id, type_filter, opts)
      else
        # Use session query
        query = SPARQLQueries.query_by_session(session_id, opts)

        case TripleStore.query(store, query) do
          {:ok, results} ->
            memories = Enum.map(results, &map_session_result(&1, session_id))
            {:ok, memories}

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_default_limit(opts) do
    if Keyword.has_key?(opts, :limit) do
      opts
    else
      Keyword.put(opts, :limit, SPARQLQueries.default_query_limit())
    end
  end

  @doc """
  Retrieves a specific memory by ID (internal use only).

  **Note:** This function bypasses session ownership verification. For public API use,
  prefer `query_by_id/3` which verifies that the memory belongs to the specified session.

  ## Examples

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "mem-123")
      {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "unknown")

  """
  # Removed inconsistent @doc since: "0.1.0" - not used elsewhere in codebase (C11)
  @spec query_by_id(store_ref(), String.t()) ::
          {:ok, stored_memory()} | {:error, :not_found | :invalid_memory_id}
  def query_by_id(store, memory_id) do
    with :ok <- validate_memory_id(memory_id),
         query = SPARQLQueries.query_by_id(memory_id),
         {:ok, [result | _]} <- TripleStore.query(store, query) do
      memory = map_id_result(result, memory_id)
      {:ok, memory}
    else
      {:error, :invalid_memory_id} -> {:error, :invalid_memory_id}
      {:error, _} -> {:error, :not_found}
    end
  end

  @doc """
  Retrieves a specific memory by ID with session ownership verification.

  Unlike `query_by_id/2`, this function verifies that the memory belongs
  to the specified session, preventing cross-session memory access.

  ## Parameters

  - `store` - Reference to the TripleStore
  - `session_id` - Session ID to verify ownership
  - `memory_id` - ID of the memory to retrieve

  ## Returns

  - `{:ok, stored_memory}` - Memory found and belongs to session
  - `{:error, :not_found}` - Memory not found or doesn't belong to session

  ## Examples

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "session-123", "mem-456")
      {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "session-999", "mem-456")

  """
  @spec query_by_id(store_ref(), String.t(), String.t()) ::
          {:ok, stored_memory()} | {:error, :not_found}
  def query_by_id(store, session_id, memory_id) do
    case query_by_id(store, memory_id) do
      {:ok, memory} ->
        if memory.session_id == session_id do
          {:ok, memory}
        else
          {:error, :not_found}
        end

      error ->
        error
    end
  end

  # =============================================================================
  # Lifecycle API
  # =============================================================================

  @doc """
  Marks a memory as superseded by another memory.

  When a memory is superseded, it's kept in the store but excluded from
  normal queries (unless `include_superseded: true` is specified).

  ## Parameters

  - `store` - Reference to the TripleStore
  - `session_id` - Session ID (for validation)
  - `old_memory_id` - ID of the memory being superseded
  - `new_memory_id` - ID of the replacement memory (optional)

  ## Examples

      :ok = TripleStoreAdapter.supersede(store, "session-123", "old-mem", "new-mem")
      :ok = TripleStoreAdapter.supersede(store, "session-123", "old-mem", nil)

  """
  @spec supersede(store_ref(), String.t(), String.t(), String.t() | nil) ::
          :ok | {:error, term()}
  def supersede(store, session_id, old_memory_id, new_memory_id \\ nil) do
    with :ok <- validate_memory_id(old_memory_id),
         :ok <- if(new_memory_id, do: validate_memory_id(new_memory_id), else: :ok),
         {:ok, _memory} <- query_by_id(store, session_id, old_memory_id) do
      # Use DeletedMarker if no new_memory_id provided
      superseder = new_memory_id || "DeletedMarker"
      query = SPARQLQueries.supersede_memory(old_memory_id, superseder)

      case TripleStore.update(store, query) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a memory from the store (soft delete).

  Uses supersession with a DeletedMarker to mark the memory as deleted.

  ## Examples

      :ok = TripleStoreAdapter.delete(store, "session-123", "mem-123")

  """
  @spec delete(store_ref(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(store, session_id, memory_id) do
    with :ok <- validate_memory_id(memory_id),
         {:ok, _memory} <- query_by_id(store, session_id, memory_id) do
      query = SPARQLQueries.delete_memory(memory_id)

      case TripleStore.update(store, query) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    else
      {:error, :not_found} ->
        # Already deleted or doesn't exist - success
        :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Records an access to a memory, updating access tracking.

  Updates the last_accessed timestamp.

  ## Examples

      :ok = TripleStoreAdapter.record_access(store, "session-123", "mem-123")

  """
  @spec record_access(store_ref(), String.t(), String.t()) :: :ok
  def record_access(store, session_id, memory_id) do
    # Validate ID first (fail fast on invalid input)
    with :ok <- validate_memory_id(memory_id),
         {:ok, _memory} <- query_by_id(store, session_id, memory_id) do
      query = SPARQLQueries.record_access(memory_id)

      case TripleStore.update(store, query) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    else
      _ -> :ok
    end
  end

  # =============================================================================
  # Counting API
  # =============================================================================

  @doc """
  Counts memories for a session using efficient SPARQL COUNT.

  ## Options

  - `:include_superseded` - Include superseded memories (default: false)

  ## Examples

      {:ok, 42} = TripleStoreAdapter.count(store, "session-123")

  """
  @spec count(store_ref(), String.t(), keyword()) :: {:ok, non_neg_integer()}
  def count(store, session_id, opts \\ []) do
    with :ok <- validate_session_id(session_id),
         query = SPARQLQueries.count_query(session_id, opts),
         {:ok, [result | _]} <- TripleStore.query(store, query) do
      {:ok, extract_count(result["count"])}
    else
      {:error, :invalid_session_id} = error -> error
      {:error, _} -> {:ok, 0}
      _ -> {:ok, 0}
    end
  end

  defp extract_count(nil), do: 0
  defp extract_count({:literal, :typed, value, _}), do: parse_integer(value)
  defp extract_count({:literal, :simple, value}), do: parse_integer(value)
  defp extract_count({:literal, _type, value}), do: parse_integer(value)
  defp extract_count({:literal, value}), do: parse_integer(value)
  defp extract_count(value) when is_integer(value), do: value
  defp extract_count(value) when is_binary(value), do: parse_integer(value)
  defp extract_count(_), do: 0

  # =============================================================================
  # Relationship Queries
  # =============================================================================

  @doc """
  Queries memories related to a given memory by a relationship type.

  This function finds all memories that are connected to the specified memory
  via the given relationship property from the Jido ontology.

  ## Parameters

  - `store` - The TripleStore store reference
  - `session_id` - Session identifier for scoping
  - `memory_id` - The ID of the source memory
  - `relationship` - The relationship type (e.g., `:refines`, `:has_alternative`, `:derived_from`)
  - `opts` - Optional parameters (currently unused)

  ## Supported Relationships

  - `:refines` - Memories that refine this one
  - `:confirms` - Memories that confirm this one
  - `:contradicts` - Memories that contradict this one
  - `:has_alternative` - Alternative options for a decision
  - `:selected_alternative` - The alternative selected
  - `:has_trade_off` - Trade-offs for a decision
  - `:justified_by` - Justification evidence
  - `:has_root_cause` - Root causes for errors
  - `:produced_lesson` - Lessons produced from errors
  - `:related_error` - Related errors
  - `:derived_from` - Memories derived from evidence
  - `:superseded_by` - Newer versions that superseded this

  ## Returns

  - `{:ok, [stored_memory()]}` - List of related memories
  - `{:error, reason}` - Query failed

  ## Examples

      # Find alternatives for a decision
      {:ok, alternatives} = TripleStoreAdapter.query_related(store, "session-123", "dec-1", :has_alternative)

      # Find lessons learned from an error
      {:ok, lessons} = TripleStoreAdapter.query_related(store, "session-123", "err-1", :produced_lesson)

  """
  @spec query_related(store_ref(), String.t(), String.t(), atom(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_related(store, session_id, memory_id, relationship, opts \\ [])
      when is_reference(store) and is_binary(session_id) and is_binary(memory_id) and
             is_atom(relationship) and is_list(opts) do
    with :ok <- validate_session_id(session_id),
         :ok <- validate_memory_id(memory_id),
         query = SPARQLQueries.query_related(memory_id, relationship),
         {:ok, results} when is_list(results) <- TripleStore.query(store, query) do
      memories =
        Enum.map(results, fn bindings ->
          map_related_result(bindings, session_id)
        end)

      {:ok, memories}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Maps a SPARQL result from query_related to a stored_memory struct
  defp map_related_result(bindings, session_id) do
    base_memory_map(bindings)
    |> Map.merge(%{
      id: extract_memory_id_from_bindings(bindings),
      memory_type: extract_memory_type(bindings["type"]),
      session_id: session_id,
      superseded_by: nil
    })
  end

  # =============================================================================
  # Statistics API
  # =============================================================================

  @doc """
  Gets statistics for the session's memory store.

  Returns aggregate statistics about the stored triples including:
  - `:triple_count` - Total number of triples
  - `:distinct_subjects` - Number of distinct subjects (memories)
  - `:distinct_predicates` - Number of distinct predicates (relationships)
  - `:distinct_objects` - Number of distinct objects (values)

  ## Parameters

  - `store` - The TripleStore store reference
  - `_session_id` - Session identifier (for logging/scoping, currently unused)

  ## Returns

  - `{:ok, stats_map}` - Statistics map with keys above
  - `{:error, reason}` - Failed to get statistics

  ## Examples

      {:ok, stats} = TripleStoreAdapter.get_stats(store, "session-123")
      # => %{triple_count: 150, distinct_subjects: 10, distinct_predicates: 25, distinct_objects: 80}

  """
  @spec get_stats(store_ref(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_stats(store, session_id) when is_reference(store) do
    with :ok <- validate_session_id(session_id),
         {:ok, stats} <- TripleStore.Statistics.all(store) do
      {:ok, stats}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Relationship Traversal API
  # =============================================================================

  @typedoc """
  Supported relationship types for memory traversal.

  - `:derived_from` - Evidence chain (memory → evidence)
  - `:superseded_by` - Replacement chain (old → new memory)
  - `:supersedes` - Reverse replacement chain (new → old memory)
  - `:same_type` - Memories of the same type
  - `:same_project` - Memories in the same project
  """
  @type relationship ::
          :derived_from
          | :superseded_by
          | :supersedes
          | :same_type
          | :same_project

  @relationship_types [:derived_from, :superseded_by, :supersedes, :same_type, :same_project]

  @doc """
  Returns the list of valid relationship types.
  """
  @spec relationship_types() :: [relationship()]
  def relationship_types, do: @relationship_types

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

      # Find evidence chain
      {:ok, related} = TripleStoreAdapter.query_related(
        store, "session-123", "mem-456", :derived_from
      )

      # Find replacement chain with depth
      {:ok, chain} = TripleStoreAdapter.query_related(
        store, "session-123", "mem-123", :superseded_by, depth: 3
      )

  """
  @spec query_related(store_ref(), String.t(), String.t(), relationship(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_related(store, session_id, start_memory_id, relationship, opts \\ [])
      when relationship in @relationship_types do
    depth = opts |> Keyword.get(:depth, 1) |> min(5) |> max(1)
    limit = Keyword.get(opts, :limit, 10)
    include_superseded = Keyword.get(opts, :include_superseded, false)

    with_ets_store(store, fn ->
      case query_by_id(store, session_id, start_memory_id) do
        {:ok, start_memory} ->
          results = traverse_relationship(
            store,
            session_id,
            start_memory,
            relationship,
            depth,
            limit,
            include_superseded,
            MapSet.new([start_memory_id])
          )
          {:ok, results}

        {:error, :not_found} ->
          {:error, :not_found}
      end
    end)
  end

  # Traverses relationships recursively up to the specified depth
  defp traverse_relationship(_store, _session_id, _memory, _rel, 0, _limit, _include, _visited) do
    []
  end

  defp traverse_relationship(store, session_id, memory, relationship, depth, limit, include_superseded, visited) do
    # Find directly related memories
    related_ids = find_related_ids(store, session_id, memory, relationship, include_superseded)

    # Filter out already visited and resolve to full memories
    new_ids =
      related_ids
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.take(limit)

    current_level =
      new_ids
      |> Enum.map(&query_by_id(store, session_id, &1))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, mem} -> mem end)

    if depth > 1 and length(current_level) > 0 do
      # Recursively traverse for deeper relationships
      new_visited = Enum.reduce(new_ids, visited, &MapSet.put(&2, &1))

      deeper_results =
        current_level
        |> Enum.flat_map(fn mem ->
          traverse_relationship(
            store, session_id, mem, relationship,
            depth - 1, limit, include_superseded, new_visited
          )
        end)

      current_level ++ deeper_results
    else
      current_level
    end
  end

  # Finds IDs of memories related via the specified relationship type
  defp find_related_ids(_store, _session_id, memory, :derived_from, _include_superseded) do
    # Evidence refs can be memory IDs or other references
    # Filter to only those that look like memory IDs
    (memory.evidence_refs || [])
    |> Enum.filter(&String.starts_with?(&1, "mem-"))
  end

  defp find_related_ids(_store, _session_id, memory, :superseded_by, _include_superseded) do
    case memory.superseded_by do
      nil -> []
      id -> [id]
    end
  end

  # For :supersedes relationship, we're finding memories that were superseded BY this memory.
  # These are inherently superseded memories, so include_superseded doesn't apply - we must
  # search superseded memories to find what this memory replaced.
  defp find_related_ids(store, session_id, memory, :supersedes, _include_superseded) do
    store
    |> ets_to_list()
    |> Enum.filter(fn {_id, record} ->
      record.session_id == session_id and record.superseded_by == memory.id
    end)
    |> Enum.map(fn {id, _record} -> id end)
  end

  # NOTE: The following relationship types (:same_type, :same_project) require full ETS table
  # scans via ets_to_list(). For sessions with many memories (up to 10,000 allowed), these
  # queries may have O(n) performance. The `limit` option reduces result processing but the
  # full scan still occurs. Consider adding secondary indices if performance becomes an issue.

  defp find_related_ids(store, session_id, memory, :same_type, include_superseded) do
    # Find memories of the same type (excluding the source memory)
    store
    |> ets_to_list()
    |> Enum.filter(fn {id, record} ->
      id != memory.id and
        record.session_id == session_id and
        record.memory_type == memory.memory_type and
        (include_superseded or record.superseded_at == nil)
    end)
    |> Enum.map(fn {id, _record} -> id end)
  end

  defp find_related_ids(store, session_id, memory, :same_project, include_superseded) do
    # Find memories in the same project (excluding the source memory)
    case memory.project_id do
      nil ->
        []

      project_id ->
        store
        |> ets_to_list()
        |> Enum.filter(fn {id, record} ->
          id != memory.id and
            record.session_id == session_id and
            record.project_id == project_id and
            (include_superseded or record.superseded_at == nil)
        end)
        |> Enum.map(fn {id, _record} -> id end)
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

      {:ok, stats} = TripleStoreAdapter.get_stats(store, "session-123")
      # => {:ok, %{
      #      total_count: 42,
      #      superseded_count: 5,
      #      by_type: %{fact: 20, assumption: 15, decision: 7},
      #      by_confidence: %{high: 30, medium: 10, low: 2},
      #      with_evidence: 25,
      #      with_rationale: 18
      #    }}

  """
  @spec get_stats(store_ref(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_stats(store, session_id) do
    with_ets_store(store, fn ->
      all_records =
        store
        |> ets_to_list()
        |> Enum.filter(fn {_id, record} -> record.session_id == session_id end)
        |> Enum.map(fn {_id, record} -> record end)

      active_records = Enum.filter(all_records, &is_nil(&1.superseded_at))
      superseded_records = Enum.reject(all_records, &is_nil(&1.superseded_at))

      stats = %{
        total_count: length(active_records),
        superseded_count: length(superseded_records),
        by_type: count_by_type(active_records),
        by_confidence: count_by_confidence(active_records),
        with_evidence: Enum.count(active_records, &has_evidence?/1),
        with_rationale: Enum.count(active_records, &has_rationale?/1)
      }

      {:ok, stats}
    end)
  end

  defp count_by_type(records) do
    Enum.frequencies_by(records, & &1.memory_type)
  end

  defp count_by_confidence(records) do
    records
    |> Enum.group_by(fn record ->
      cond do
        record.confidence >= 0.8 -> :high
        record.confidence >= 0.5 -> :medium
        true -> :low
      end
    end)
    |> Enum.map(fn {level, items} -> {level, length(items)} end)
    |> Map.new()
  end

  defp has_evidence?(%{evidence_refs: [_ | _]}), do: true
  defp has_evidence?(_), do: false

  defp has_rationale?(%{rationale: rationale}) when rationale not in [nil, ""], do: true
  defp has_rationale?(_), do: false

  # =============================================================================
  # Context Retrieval
  # =============================================================================

  @doc """
  Retrieves contextually relevant memories using relevance scoring.

  Uses a multi-factor scoring algorithm that considers:
  - Text similarity (40%): Word overlap between context and content
  - Recency (configurable): Time since last access or creation
  - Confidence (20%): Memory's confidence level
  - Access frequency (10%): Normalized access count

  ## Parameters

  - `store` - The ETS store reference
  - `session_id` - Session identifier
  - `context_hint` - Description of what context is needed
  - `opts` - Keyword list of options

  ## Options

  - `:max_results` - Maximum results (default: 5)
  - `:min_confidence` - Minimum confidence threshold (default: 0.5)
  - `:recency_weight` - Weight for recency in scoring (default: 0.3)
  - `:include_superseded` - Include superseded memories (default: false)
  - `:include_types` - Filter to specific memory types (default: nil)

  ## Returns

  - `{:ok, [{memory, score}, ...]}` - List of {memory, relevance_score} tuples
  - `{:error, reason}` - Error tuple
  """
  @spec get_context(store_ref(), String.t(), String.t(), keyword()) ::
          {:ok, [{stored_memory(), float()}]} | {:error, term()}
  def get_context(store, session_id, context_hint, opts \\ []) do
    with_ets_store(store, fn ->
      max_results = Keyword.get(opts, :max_results, 5)
      min_confidence = Keyword.get(opts, :min_confidence, 0.5)
      recency_weight = Keyword.get(opts, :recency_weight, 0.3)
      include_superseded = Keyword.get(opts, :include_superseded, false)
      include_types = Keyword.get(opts, :include_types)

      # Get all session records
      all_records =
        store
        |> ets_to_list()
        |> Enum.filter(fn {_id, record} -> record.session_id == session_id end)
        |> Enum.map(fn {_id, record} -> record end)

      # Filter by superseded status
      records =
        if include_superseded do
          all_records
        else
          Enum.filter(all_records, &is_nil(&1.superseded_at))
        end

      # Filter by confidence
      records = Enum.filter(records, &(&1.confidence >= min_confidence))

      # Filter by types if specified
      records =
        case include_types do
          nil -> records
          types when is_list(types) -> Enum.filter(records, &(&1.memory_type in types))
        end

      # Calculate max access count for normalization
      max_access = records |> Enum.map(& &1.access_count) |> Enum.max(fn -> 1 end) |> max(1)

      # Extract context words for matching
      context_words = extract_words(context_hint)

      # Score each memory
      now = DateTime.utc_now()

      scored =
        records
        |> Enum.map(fn record ->
          score = calculate_relevance_score(record, context_words, max_access, now, recency_weight)
          memory = to_stored_memory(record)
          {memory, score}
        end)
        |> Enum.filter(fn {_memory, score} -> score > 0.0 end)
        |> Enum.sort_by(fn {_memory, score} -> score end, :desc)
        |> Enum.take(max_results)

      {:ok, scored}
    end)
  end

  # Calculates relevance score for a memory based on multiple factors
  # Weights: text_similarity=0.4, recency=configurable, confidence=0.2, access=0.1
  defp calculate_relevance_score(record, context_words, max_access, now, recency_weight) do
    # Text similarity (40%)
    content_words = extract_words(record.content)
    rationale_words = if record.rationale, do: extract_words(record.rationale), else: MapSet.new()
    all_memory_words = MapSet.union(content_words, rationale_words)
    text_score = calculate_text_similarity(context_words, all_memory_words)

    # Recency score (configurable weight, default 30%)
    recency_score = calculate_recency_score(record, now)

    # Confidence score (20%)
    confidence_score = record.confidence

    # Access frequency score (10%)
    # C10 fix: max_access is guaranteed >= 1 by line 872, no need for guard
    access_score = record.access_count / max_access

    # Calculate remaining weight for text, confidence, and access
    # Total = 1.0 = text_weight + recency_weight + confidence_weight + access_weight
    # Given recency_weight, and fixed access_weight=0.1, confidence_weight=0.2
    # text_weight = 1.0 - recency_weight - 0.2 - 0.1 = 0.7 - recency_weight
    # C3 fix: Ensure text_weight doesn't go negative when recency_weight is high
    access_weight = 0.1
    confidence_weight = 0.2
    text_weight = max(0.0, 1.0 - recency_weight - confidence_weight - access_weight)

    text_weight * text_score +
      recency_weight * recency_score +
      confidence_weight * confidence_score +
      access_weight * access_score
  end

  # S5: Common stop words to filter out for better similarity scores
  @stop_words MapSet.new([
    "the", "is", "at", "which", "on", "a", "an", "and", "or", "but",
    "in", "to", "of", "for", "with", "as", "by", "be", "it", "that",
    "this", "was", "are", "been", "have", "has", "had", "will", "would",
    "could", "should", "may", "might", "can", "do", "does", "did", "not",
    "no", "yes", "so", "if", "then", "else", "when", "where", "what",
    "who", "how", "why", "all", "each", "every", "some", "any", "most",
    "other", "into", "over", "such", "up", "down", "out", "about", "from"
  ])

  # S6: Maximum number of words to extract (prevents memory pressure)
  @max_word_count 500

  # Extracts words from text, lowercased and normalized
  # S5: Filters stop words, S6: Limits word count
  defp extract_words(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.filter(&(byte_size(&1) >= 2))
    |> Enum.reject(&MapSet.member?(@stop_words, &1))
    |> Enum.take(@max_word_count)
    |> MapSet.new()
  end

  defp extract_words(_), do: MapSet.new()

  # Calculates text similarity using Jaccard-like overlap
  defp calculate_text_similarity(context_words, memory_words) do
    if MapSet.size(context_words) == 0 or MapSet.size(memory_words) == 0 do
      0.0
    else
      intersection = MapSet.intersection(context_words, memory_words)
      overlap = MapSet.size(intersection)

      # Score based on how many context words appear in memory
      # Plus bonus for memory words that appear in context
      context_coverage = overlap / MapSet.size(context_words)
      memory_coverage = overlap / MapSet.size(memory_words)

      # Weighted average favoring context coverage
      0.7 * context_coverage + 0.3 * memory_coverage
    end
  end

  # Calculates recency score based on last access or creation time
  # More recent = higher score (exponential decay over 7 days)
  defp calculate_recency_score(record, now) do
    reference_time = record.last_accessed || record.created_at

    if reference_time do
      seconds_ago = DateTime.diff(now, reference_time, :second) |> max(0)
      # Decay over 7 days (604800 seconds)
      # After 7 days, score approaches 0
      decay_period = 604_800
      :math.exp(-seconds_ago / decay_period)
    else
      0.5
    end
  end

  # =============================================================================
  # IRI Utilities
  # =============================================================================

  @doc """
  Extracts the memory ID from a memory IRI.

  ## Examples

      "mem-123" = TripleStoreAdapter.extract_id("https://jido.ai/ontology#memory_mem-123")

  """
  @spec extract_id(String.t()) :: String.t()
  def extract_id(memory_iri) do
    SPARQLQueries.extract_memory_id(memory_iri)
  end

  @doc """
  Generates the memory IRI for a given ID.

  ## Examples

      "https://jido.ai/ontology#memory_mem-123" = TripleStoreAdapter.memory_iri("mem-123")

  """
  @spec memory_iri(String.t()) :: String.t()
  def memory_iri(id), do: "#{SPARQLQueries.namespace()}memory_#{id}"

  # =============================================================================
  # Private Functions - Result Mapping
  # =============================================================================

  # C14: Base mapping function for common fields
  defp base_memory_map(bindings) do
    %{
      content: extract_string(bindings["content"]),
      confidence: extract_confidence(bindings["confidence"]),
      source_type: extract_source_type(bindings["source"]),
      agent_id: nil,
      project_id: nil,
      rationale: extract_optional_string(bindings["rationale"]),
      evidence_refs: [],
      timestamp: extract_datetime(bindings["timestamp"]),
      access_count: extract_integer(bindings["accessCount"]),
      last_accessed: nil
    }
  end

  # Maps a SPARQL result from query_by_type to a stored_memory struct
  defp map_type_result(bindings, session_id, memory_type) do
    base_memory_map(bindings)
    |> Map.merge(%{
      id: extract_memory_id_from_bindings(bindings),
      memory_type: memory_type,
      session_id: session_id,
      superseded_by: nil
    })
  end

  # Maps a SPARQL result from query_by_session to a stored_memory struct
  defp map_session_result(bindings, session_id) do
    base_memory_map(bindings)
    |> Map.merge(%{
      id: extract_memory_id_from_bindings(bindings),
      memory_type: extract_memory_type(bindings["type"]),
      session_id: session_id,
      superseded_by: nil
    })
  end

  # Maps a SPARQL result from query_by_id to a stored_memory struct
  defp map_id_result(bindings, memory_id) do
    base_memory_map(bindings)
    |> Map.merge(%{
      id: memory_id,
      memory_type: extract_memory_type(bindings["type"]),
      session_id: extract_session_id(bindings["session"]),
      superseded_by: extract_optional_memory_id(bindings["supersededBy"])
    })
  end

  # =============================================================================
  # Private Functions - Value Extraction
  # =============================================================================

  defp extract_memory_id_from_bindings(bindings) do
    case bindings["mem"] do
      nil -> nil
      iri -> SPARQLQueries.extract_memory_id(extract_iri_string(iri))
    end
  end

  defp extract_string(nil), do: ""
  # TripleStore format: {:literal, :simple, value} or {:literal, :typed, value, datatype}
  defp extract_string({:literal, :simple, value}) when is_binary(value), do: value
  defp extract_string({:literal, :typed, value, _datatype}) when is_binary(value), do: value
  # Legacy formats for compatibility
  defp extract_string({:literal, _type, value}) when is_binary(value), do: value
  defp extract_string({:literal, value}) when is_binary(value), do: value
  defp extract_string(value) when is_binary(value), do: value
  defp extract_string(_), do: ""

  defp extract_optional_string(nil), do: nil
  # TripleStore format
  defp extract_optional_string({:literal, :simple, value}), do: value
  defp extract_optional_string({:literal, :typed, value, _datatype}), do: value
  # Legacy formats
  defp extract_optional_string({:literal, _type, value}), do: value
  defp extract_optional_string({:literal, value}), do: value
  defp extract_optional_string(value) when is_binary(value), do: value
  defp extract_optional_string(_), do: nil

  # TripleStore format: {:named_node, iri}
  defp extract_iri_string({:named_node, iri}), do: iri
  # Legacy formats for compatibility
  defp extract_iri_string({:iri, iri}), do: iri
  defp extract_iri_string(iri) when is_binary(iri), do: iri
  defp extract_iri_string(_), do: ""

  defp extract_memory_type(nil), do: :unknown

  defp extract_memory_type(type_value) do
    iri = extract_iri_string(type_value)
    SPARQLQueries.class_to_memory_type(iri)
  end

  defp extract_confidence(nil), do: :medium

  defp extract_confidence(confidence_value) do
    iri = extract_iri_string(confidence_value)
    SPARQLQueries.individual_to_confidence(iri)
  end

  defp extract_source_type(nil), do: :agent

  defp extract_source_type(source_value) do
    iri = extract_iri_string(source_value)
    SPARQLQueries.individual_to_source_type(iri)
  end

  defp extract_session_id(nil), do: "unknown"

  defp extract_session_id(session_value) do
    iri = extract_iri_string(session_value)
    SPARQLQueries.extract_session_id(iri)
  end

  defp extract_datetime(nil), do: DateTime.utc_now()
  # TripleStore format: {:literal, :typed, value, datatype}
  defp extract_datetime({:literal, :typed, value, _datatype}) when is_binary(value) do
    parse_datetime(value)
  end

  defp extract_datetime({:literal, :simple, value}) when is_binary(value) do
    parse_datetime(value)
  end

  # Legacy formats for compatibility
  defp extract_datetime({:literal, {:xsd, :dateTime}, value}) when is_binary(value) do
    parse_datetime(value)
  end

  defp extract_datetime({:literal, _type, value}) when is_binary(value) do
    parse_datetime(value)
  end

  defp extract_datetime({:literal, value}) when is_binary(value) do
    parse_datetime(value)
  end

  defp extract_datetime(value) when is_binary(value) do
    parse_datetime(value)
  end

  defp extract_datetime(_), do: DateTime.utc_now()

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp extract_integer(nil), do: 0
  # TripleStore format
  defp extract_integer({:literal, :typed, value, _datatype}), do: parse_integer(value)
  defp extract_integer({:literal, :simple, value}), do: parse_integer(value)
  # Legacy formats
  defp extract_integer({:literal, {:xsd, :integer}, value}), do: parse_integer(value)
  defp extract_integer({:literal, _type, value}), do: parse_integer(value)
  defp extract_integer({:literal, value}), do: parse_integer(value)
  defp extract_integer(value) when is_integer(value), do: value
  defp extract_integer(value) when is_binary(value), do: parse_integer(value)
  defp extract_integer(_), do: 0

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: 0

  defp extract_optional_memory_id(nil), do: nil

  defp extract_optional_memory_id(value) do
    iri = extract_iri_string(value)

    if String.contains?(iri, "DeletedMarker") do
      "deleted"
    else
      SPARQLQueries.extract_memory_id(iri)
    end
  end

  # =============================================================================
  # Validation Functions
  # =============================================================================

  @doc """
  Validates a memory ID format before using it in SPARQL queries.

  This prevents injection attacks and ensures IDs are safe to embed
  directly in SPARQL query strings.

  ## Valid ID Format

  - 1-128 characters
  - Only alphanumeric characters, hyphens, and underscores

  Returns `:ok` if valid, `{:error, :invalid_memory_id}` if not.
  """
  @spec validate_memory_id(String.t() | nil) :: :ok | {:error, :invalid_memory_id}
  defp validate_memory_id(id) when is_binary(id) do
    if SPARQLQueries.valid_memory_id?(id) do
      :ok
    else
      {:error, :invalid_memory_id}
    end
  end

  defp validate_memory_id(_), do: {:error, :invalid_memory_id}

  @doc """
  Validates a session ID format before using it in SPARQL queries.

  Uses the same validation as memory IDs since session IDs are embedded
  in SPARQL queries and must be safe.

  Returns `:ok` if valid, `{:error, :invalid_session_id}` if not.
  """
  @spec validate_session_id(String.t() | nil) :: :ok | {:error, :invalid_session_id}
  defp validate_session_id(id) when is_binary(id) do
    if SPARQLQueries.valid_session_id?(id) do
      :ok
    else
      {:error, :invalid_session_id}
    end
  end

  defp validate_session_id(_), do: {:error, :invalid_session_id}
end
