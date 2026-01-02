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
    query = SPARQLQueries.insert_memory(memory)

    case TripleStore.update(store, query) do
      {:ok, _} -> {:ok, memory.id}
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
    query = SPARQLQueries.query_by_type(session_id, memory_type, opts)

    case TripleStore.query(store, query) do
      {:ok, results} ->
        memories = Enum.map(results, &map_type_result(&1, session_id, memory_type))
        {:ok, memories}

      {:error, reason} ->
        {:error, reason}
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
    query = SPARQLQueries.query_by_id(memory_id)

    case TripleStore.query(store, query) do
      {:ok, [result | _]} ->
        memory = map_id_result(result, memory_id)
        {:ok, memory}

      {:ok, []} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :not_found}
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
    # First verify the memory exists and belongs to this session
    case query_by_id(store, session_id, old_memory_id) do
      {:ok, _memory} ->
        # Use DeletedMarker if no new_memory_id provided
        superseder = new_memory_id || "DeletedMarker"
        query = SPARQLQueries.supersede_memory(old_memory_id, superseder)

        case TripleStore.update(store, query) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}
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
    # First verify the memory exists and belongs to this session
    case query_by_id(store, session_id, memory_id) do
      {:ok, _memory} ->
        query = SPARQLQueries.delete_memory(memory_id)

        case TripleStore.update(store, query) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        # Already deleted or doesn't exist - success
        :ok
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
    # Verify ownership first
    case query_by_id(store, session_id, memory_id) do
      {:ok, _memory} ->
        query = SPARQLQueries.record_access(memory_id)

        case TripleStore.update(store, query) do
          {:ok, _} -> :ok
          {:error, _reason} -> :ok
        end

      {:error, :not_found} ->
        :ok
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
    # Use query_all and count results
    case query_all(store, session_id, opts) do
      {:ok, memories} -> {:ok, length(memories)}
      {:error, _} -> {:ok, 0}
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

  # Maps a SPARQL result from query_by_type to a stored_memory struct
  defp map_type_result(bindings, session_id, memory_type) do
    %{
      id: extract_memory_id_from_bindings(bindings),
      content: extract_string(bindings["content"]),
      memory_type: memory_type,
      confidence: extract_confidence(bindings["confidence"]),
      source_type: extract_source_type(bindings["source"]),
      session_id: session_id,
      agent_id: nil,
      project_id: nil,
      rationale: extract_optional_string(bindings["rationale"]),
      evidence_refs: [],
      timestamp: extract_datetime(bindings["timestamp"]),
      superseded_by: nil,
      access_count: extract_integer(bindings["accessCount"]),
      last_accessed: nil
    }
  end

  # Maps a SPARQL result from query_by_session to a stored_memory struct
  defp map_session_result(bindings, session_id) do
    %{
      id: extract_memory_id_from_bindings(bindings),
      content: extract_string(bindings["content"]),
      memory_type: extract_memory_type(bindings["type"]),
      confidence: extract_confidence(bindings["confidence"]),
      source_type: extract_source_type(bindings["source"]),
      session_id: session_id,
      agent_id: nil,
      project_id: nil,
      rationale: extract_optional_string(bindings["rationale"]),
      evidence_refs: [],
      timestamp: extract_datetime(bindings["timestamp"]),
      superseded_by: nil,
      access_count: extract_integer(bindings["accessCount"]),
      last_accessed: nil
    }
  end

  # Maps a SPARQL result from query_by_id to a stored_memory struct
  defp map_id_result(bindings, memory_id) do
    %{
      id: memory_id,
      content: extract_string(bindings["content"]),
      memory_type: extract_memory_type(bindings["type"]),
      confidence: extract_confidence(bindings["confidence"]),
      source_type: extract_source_type(bindings["source"]),
      session_id: extract_session_id(bindings["session"]),
      agent_id: nil,
      project_id: nil,
      rationale: extract_optional_string(bindings["rationale"]),
      evidence_refs: [],
      timestamp: extract_datetime(bindings["timestamp"]),
      superseded_by: extract_optional_memory_id(bindings["supersededBy"]),
      access_count: extract_integer(bindings["accessCount"]),
      last_accessed: nil
    }
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
end
