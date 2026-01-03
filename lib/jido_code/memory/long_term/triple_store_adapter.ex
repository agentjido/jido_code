defmodule JidoCode.Memory.LongTerm.TripleStoreAdapter do
  @moduledoc """
  Adapter layer for mapping Elixir memory structs to/from RDF-like triples.

  This module provides the interface between Elixir memory structs and the
  underlying store, using the Jido ontology vocabulary for semantic structure.

  ## Store Format

  The adapter stores memory items as maps in ETS with the structure:
  ```
  {memory_id, %{
    id: String.t(),
    content: String.t(),
    memory_type: atom(),
    confidence: float(),
    source_type: atom(),
    session_id: String.t(),
    agent_id: String.t() | nil,
    project_id: String.t() | nil,
    rationale: String.t() | nil,
    evidence_refs: [String.t()],
    created_at: DateTime.t(),
    superseded_by: String.t() | nil,
    superseded_at: DateTime.t() | nil,
    access_count: non_neg_integer(),
    last_accessed: DateTime.t() | nil
  }}
  ```

  ## Triple Representation

  While using ETS for storage, the adapter maintains RDF-like semantics:
  - Each memory has a unique IRI generated via `Vocab.memory_uri/1`
  - Memory types map to Jido ontology classes
  - Confidence and source types map to ontology individuals
  - Provenance is tracked via session, agent, and project URIs

  ## Example Usage

      # Persist a memory
      {:ok, id} = TripleStoreAdapter.persist(memory_input, store)

      # Query memories by type
      {:ok, memories} = TripleStoreAdapter.query_by_type(store, session_id, :fact)

      # Query all memories for a session
      {:ok, memories} = TripleStoreAdapter.query_all(store, session_id)

      # Get a specific memory
      {:ok, memory} = TripleStoreAdapter.query_by_id(store, memory_id)

      # Mark a memory as superseded
      :ok = TripleStoreAdapter.supersede(store, session_id, old_id, new_id)

  """

  alias JidoCode.Memory.LongTerm.Vocab.Jido, as: Vocab
  alias JidoCode.Memory.Types

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  Input structure for persisting a memory item.

  Required fields:
  - `id` - Unique identifier for the memory
  - `content` - The memory content/summary
  - `memory_type` - Classification (:fact, :assumption, etc.)
  - `confidence` - Confidence score (0.0 to 1.0)
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
          required(:confidence) => float(),
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
          confidence: float(),
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
  Reference to an open store (ETS table).
  """
  @type store_ref :: :ets.tid()

  # =============================================================================
  # Persist API
  # =============================================================================

  @doc """
  Persists a memory item to the store.

  Stores the memory with all its metadata, generating RDF-compatible URIs
  for semantic linking.

  ## Parameters

  - `memory` - The memory input map (see `memory_input()` type)
  - `store` - Reference to the ETS store

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
    stored_record = build_stored_record(memory)

    with_ets_store(store, fn ->
      :ets.insert(store, {memory.id, stored_record})
      {:ok, memory.id}
    end)
  end

  @doc """
  Builds the RDF triple representations for a memory.

  This function generates RDF-compatible triples for future integration with
  semantic web systems and triple stores. While the current storage uses ETS,
  this function maintains RDF semantics for:

  - **Export compatibility**: Enables export to RDF formats (TTL, N-Triples)
  - **SPARQL preparation**: Provides structure for future SPARQL query support
  - **Ontology alignment**: Ensures memories conform to the Jido ontology

  The function is not currently used in the persistence path but is available
  for RDF serialization and validation purposes.

  Returns a list of {subject, predicate, object} tuples where:
  - `subject` is the memory IRI (e.g., `jido:memory-123`)
  - `predicate` is a property IRI from the Jido vocabulary
  - `object` is either an IRI or a `{:literal, value}` tuple

  ## Examples

      triples = TripleStoreAdapter.build_triples(memory)
      # Returns list of {subject_iri, predicate_iri, object} tuples

  """
  @spec build_triples(memory_input()) :: [{String.t(), String.t(), term()}]
  def build_triples(memory) do
    subject = Vocab.memory_uri(memory.id)

    base_triples = [
      # Type assertion
      {subject, Vocab.rdf_type(), Vocab.memory_type_to_class(memory.memory_type)},
      # Content
      {subject, Vocab.summary(), {:literal, memory.content}},
      # Confidence
      {subject, Vocab.has_confidence(), Vocab.confidence_to_individual(memory.confidence)},
      # Source type
      {subject, Vocab.has_source_type(), Vocab.source_type_to_individual(memory.source_type)},
      # Session scoping
      {subject, Vocab.asserted_in(), Vocab.session_uri(memory.session_id)},
      # Timestamp
      {subject, Vocab.has_timestamp(), {:literal, DateTime.to_iso8601(memory.created_at)}}
    ]

    base_triples
    |> add_optional_triple(Map.get(memory, :agent_id), subject, Vocab.asserted_by(), &Vocab.agent_uri/1)
    |> add_optional_triple(Map.get(memory, :project_id), subject, Vocab.applies_to_project(), &Vocab.project_uri/1)
    |> add_optional_triple(Map.get(memory, :rationale), subject, Vocab.rationale(), &wrap_literal/1)
    |> add_evidence_triples(Map.get(memory, :evidence_refs, []), subject)
  end

  # =============================================================================
  # Query API
  # =============================================================================

  @doc """
  Queries memories by type for a session.

  ## Options

  - `:limit` - Maximum number of results (default: no limit)

  ## Examples

      {:ok, facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact)
      {:ok, assumptions} = TripleStoreAdapter.query_by_type(store, "session-123", :assumption, limit: 10)

  """
  @spec query_by_type(store_ref(), String.t(), Types.memory_type(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_by_type(store, session_id, memory_type, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    with_ets_store(store, fn ->
      results =
        store
        |> ets_to_list()
        |> Enum.filter(fn {_id, record} ->
          record.session_id == session_id and
            record.memory_type == memory_type and
            record.superseded_at == nil
        end)
        |> Enum.map(fn {_id, record} -> to_stored_memory(record) end)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
        |> maybe_limit(limit)

      {:ok, results}
    end)
  end

  @doc """
  Queries all memories for a session.

  ## Options

  - `:limit` - Maximum number of results (default: no limit)
  - `:min_confidence` - Minimum confidence threshold (default: 0.0)
  - `:include_superseded` - Include superseded memories (default: false)
  - `:type` - Filter by memory type (default: all types)

  ## Examples

      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123")
      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123", min_confidence: 0.7)
      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123", include_superseded: true)

  """
  @spec query_all(store_ref(), String.t(), keyword()) ::
          {:ok, [stored_memory()]} | {:error, term()}
  def query_all(store, session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)
    include_superseded = Keyword.get(opts, :include_superseded, false)
    type_filter = Keyword.get(opts, :type)

    with_ets_store(store, fn ->
      results =
        store
        |> ets_to_list()
        |> Enum.filter(fn {_id, record} ->
          record.session_id == session_id and
            record.confidence >= min_confidence and
            (include_superseded or record.superseded_at == nil) and
            (type_filter == nil or record.memory_type == type_filter)
        end)
        |> Enum.map(fn {_id, record} -> to_stored_memory(record) end)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
        |> maybe_limit(limit)

      {:ok, results}
    end)
  end

  @doc """
  Retrieves a specific memory by ID (internal use only).

  **Note:** This function bypasses session ownership verification. For public API use,
  prefer `query_by_id/3` which verifies that the memory belongs to the specified session.

  ## Examples

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "mem-123")
      {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "unknown")

  """
  @doc since: "0.1.0"
  @spec query_by_id(store_ref(), String.t()) :: {:ok, stored_memory()} | {:error, :not_found}
  def query_by_id(store, memory_id) do
    with_ets_store(
      store,
      fn ->
        case :ets.lookup(store, memory_id) do
          [{^memory_id, record}] -> {:ok, to_stored_memory(record)}
          [] -> {:error, :not_found}
        end
      end,
      {:error, :not_found}
    )
  end

  @doc """
  Retrieves a specific memory by ID with session ownership verification.

  Unlike `query_by_id/2`, this function verifies that the memory belongs
  to the specified session, preventing cross-session memory access.

  ## Parameters

  - `store` - Reference to the ETS store
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
    with_ets_store(
      store,
      fn ->
        case :ets.lookup(store, memory_id) do
          [{^memory_id, record}] ->
            # Verify session ownership
            if record.session_id == session_id do
              {:ok, to_stored_memory(record)}
            else
              {:error, :not_found}
            end

          [] ->
            {:error, :not_found}
        end
      end,
      {:error, :not_found}
    )
  end

  # =============================================================================
  # Lifecycle API
  # =============================================================================

  @doc """
  Marks a memory as superseded by another memory.

  When a memory is superseded, it's kept in the store but excluded from
  normal queries (unless `include_superseded: true` is specified).

  ## Parameters

  - `store` - Reference to the ETS store
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
    with_ets_store(store, fn ->
      case :ets.lookup(store, old_memory_id) do
        [{^old_memory_id, record}] ->
          if record.session_id == session_id do
            updated_record = %{
              record
              | superseded_by: new_memory_id,
                superseded_at: DateTime.utc_now()
            }

            :ets.insert(store, {old_memory_id, updated_record})
            :ok
          else
            {:error, :session_mismatch}
          end

        [] ->
          {:error, :not_found}
      end
    end)
  end

  @doc """
  Deletes a memory from the store.

  This permanently removes the memory. For soft-delete, use `supersede/4`.

  ## Examples

      :ok = TripleStoreAdapter.delete(store, "session-123", "mem-123")

  """
  @spec delete(store_ref(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(store, session_id, memory_id) do
    with_ets_store(store, fn ->
      case :ets.lookup(store, memory_id) do
        [{^memory_id, record}] ->
          if record.session_id == session_id do
            :ets.delete(store, memory_id)
            :ok
          else
            {:error, :session_mismatch}
          end

        [] ->
          :ok
      end
    end)
  end

  @doc """
  Records an access to a memory, updating access tracking.

  Increments the access count and updates the last_accessed timestamp.

  ## Examples

      :ok = TripleStoreAdapter.record_access(store, "session-123", "mem-123")

  """
  @spec record_access(store_ref(), String.t(), String.t()) :: :ok
  def record_access(store, session_id, memory_id) do
    with_ets_store(
      store,
      fn ->
        case :ets.lookup(store, memory_id) do
          [{^memory_id, record}] ->
            if record.session_id == session_id do
              updated_record = %{
                record
                | access_count: record.access_count + 1,
                  last_accessed: DateTime.utc_now()
              }

              :ets.insert(store, {memory_id, updated_record})
            end

            :ok

          [] ->
            :ok
        end
      end,
      :ok
    )
  end

  # =============================================================================
  # Counting API
  # =============================================================================

  @doc """
  Counts memories for a session.

  ## Options

  - `:include_superseded` - Include superseded memories (default: false)

  ## Examples

      {:ok, 42} = TripleStoreAdapter.count(store, "session-123")

  """
  @spec count(store_ref(), String.t(), keyword()) :: {:ok, non_neg_integer()}
  def count(store, session_id, opts \\ []) do
    include_superseded = Keyword.get(opts, :include_superseded, false)

    with_ets_store(
      store,
      fn ->
        count =
          store
          |> ets_to_list()
          |> Enum.count(fn {_id, record} ->
            record.session_id == session_id and
              (include_superseded or record.superseded_at == nil)
          end)

        {:ok, count}
      end,
      {:ok, 0}
    )
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
    access_score = if max_access > 0, do: record.access_count / max_access, else: 0.0

    # Calculate remaining weight for text, confidence, and access
    # Total = 1.0 = text_weight + recency_weight + confidence_weight + access_weight
    # Given recency_weight, and fixed access_weight=0.1, confidence_weight=0.2
    # text_weight = 1.0 - recency_weight - 0.2 - 0.1 = 0.7 - recency_weight
    access_weight = 0.1
    confidence_weight = 0.2
    text_weight = 1.0 - recency_weight - confidence_weight - access_weight

    text_weight * text_score +
      recency_weight * recency_score +
      confidence_weight * confidence_score +
      access_weight * access_score
  end

  # Extracts words from text, lowercased and normalized
  defp extract_words(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.filter(&(byte_size(&1) >= 2))
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
    prefix = Vocab.namespace() <> "memory_"

    if String.starts_with?(memory_iri, prefix) do
      String.replace_prefix(memory_iri, prefix, "")
    else
      memory_iri
    end
  end

  @doc """
  Generates the memory IRI for a given ID.

  ## Examples

      "https://jido.ai/ontology#memory_mem-123" = TripleStoreAdapter.memory_iri("mem-123")

  """
  @spec memory_iri(String.t()) :: String.t()
  def memory_iri(id), do: Vocab.memory_uri(id)

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp build_stored_record(memory) do
    %{
      id: memory.id,
      content: memory.content,
      memory_type: memory.memory_type,
      confidence: memory.confidence,
      source_type: memory.source_type,
      session_id: memory.session_id,
      agent_id: Map.get(memory, :agent_id),
      project_id: Map.get(memory, :project_id),
      rationale: Map.get(memory, :rationale),
      evidence_refs: Map.get(memory, :evidence_refs, []),
      created_at: memory.created_at,
      superseded_by: nil,
      superseded_at: nil,
      access_count: 0,
      last_accessed: nil
    }
  end

  defp to_stored_memory(record) do
    %{
      id: record.id,
      content: record.content,
      memory_type: record.memory_type,
      confidence: record.confidence,
      source_type: record.source_type,
      session_id: record.session_id,
      agent_id: record.agent_id,
      project_id: record.project_id,
      rationale: record.rationale,
      evidence_refs: record.evidence_refs,
      timestamp: record.created_at,
      superseded_by: record.superseded_by,
      access_count: record.access_count,
      last_accessed: record.last_accessed
    }
  end

  defp add_optional_triple(triples, nil, _subject, _predicate, _value_fn), do: triples

  defp add_optional_triple(triples, value, subject, predicate, value_fn) do
    triples ++ [{subject, predicate, value_fn.(value)}]
  end

  defp add_evidence_triples(triples, [], _subject), do: triples

  defp add_evidence_triples(triples, evidence_refs, subject) do
    evidence_triples =
      Enum.map(evidence_refs, fn ref ->
        {subject, Vocab.derived_from(), Vocab.evidence_uri(ref)}
      end)

    triples ++ evidence_triples
  end

  defp wrap_literal(value), do: {:literal, value}

  defp ets_to_list(store) do
    :ets.tab2list(store)
  end

  defp maybe_limit(results, nil), do: results
  defp maybe_limit(results, limit), do: Enum.take(results, limit)

  # Helper to wrap ETS operations with consistent error handling.
  # This centralizes the try/rescue pattern used throughout the module.
  @spec with_ets_store(store_ref(), (() -> result), result) :: result when result: term()
  defp with_ets_store(store, fun, error_result \\ {:error, :invalid_store}) do
    try do
      fun.()
    rescue
      ArgumentError ->
        # ETS operations raise ArgumentError when table doesn't exist
        # or when given invalid arguments
        error_result
    end
  end
end
