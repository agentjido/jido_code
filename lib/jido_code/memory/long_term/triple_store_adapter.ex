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

    try do
      :ets.insert(store, {memory.id, stored_record})
      {:ok, memory.id}
    rescue
      ArgumentError -> {:error, :invalid_store}
    end
  end

  @doc """
  Builds the RDF triple representations for a memory.

  This function is provided for compatibility with RDF-based systems.
  Returns a list of {subject, predicate, object} tuples.

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

    try do
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
    rescue
      ArgumentError -> {:error, :invalid_store}
    end
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

    try do
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
    rescue
      ArgumentError -> {:error, :invalid_store}
    end
  end

  @doc """
  Retrieves a specific memory by ID.

  ## Examples

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "mem-123")
      {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "unknown")

  """
  @spec query_by_id(store_ref(), String.t()) :: {:ok, stored_memory()} | {:error, :not_found}
  def query_by_id(store, memory_id) do
    try do
      case :ets.lookup(store, memory_id) do
        [{^memory_id, record}] -> {:ok, to_stored_memory(record)}
        [] -> {:error, :not_found}
      end
    rescue
      ArgumentError -> {:error, :not_found}
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
    try do
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
    rescue
      ArgumentError -> {:error, :invalid_store}
    end
  end

  @doc """
  Deletes a memory from the store.

  This permanently removes the memory. For soft-delete, use `supersede/4`.

  ## Examples

      :ok = TripleStoreAdapter.delete(store, "session-123", "mem-123")

  """
  @spec delete(store_ref(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(store, session_id, memory_id) do
    try do
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
    rescue
      ArgumentError -> {:error, :invalid_store}
    end
  end

  @doc """
  Records an access to a memory, updating access tracking.

  Increments the access count and updates the last_accessed timestamp.

  ## Examples

      :ok = TripleStoreAdapter.record_access(store, "session-123", "mem-123")

  """
  @spec record_access(store_ref(), String.t(), String.t()) :: :ok
  def record_access(store, session_id, memory_id) do
    try do
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
    rescue
      ArgumentError -> :ok
    end
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

    try do
      count =
        store
        |> ets_to_list()
        |> Enum.count(fn {_id, record} ->
          record.session_id == session_id and
            (include_superseded or record.superseded_at == nil)
        end)

      {:ok, count}
    rescue
      ArgumentError -> {:ok, 0}
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
end
