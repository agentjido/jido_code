defmodule JidoCode.Memory.LongTerm.SPARQLQueries do
  @moduledoc """
  SPARQL query and update templates for memory operations.

  All queries use the jido: namespace prefix bound to https://jido.ai/ontology#

  ## Query Categories

  ### Insert Operations
  - `insert_memory/1` - Insert a new memory item

  ### Select Queries
  - `query_by_session/2` - Query memories for a session
  - `query_by_type/3` - Query memories filtered by type
  - `query_by_id/1` - Query a single memory by ID

  ### Update Operations
  - `supersede_memory/2` - Mark a memory as superseded
  - `record_access/1` - Update access timestamp for a memory
  - `delete_memory/1` - Soft delete via supersession marker

  ### Relationship Queries
  - `query_related/2` - Find related memories by relationship
  - `query_by_evidence/1` - Find memories linked to evidence
  - `query_decisions_with_alternatives/1` - Find decisions with their alternatives
  - `query_lessons_for_error/1` - Find lessons learned for an error

  ## SPARQL Prefixes

  Standard prefixes used in all queries:
  - `jido:` - Jido ontology namespace
  - `rdf:` - RDF syntax namespace
  - `rdfs:` - RDF Schema namespace
  - `xsd:` - XML Schema datatypes
  - `owl:` - OWL namespace
  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # SPARQL Prefixes
  # =============================================================================

  @jido_ns "https://jido.ai/ontology#"
  @jido_prefix "PREFIX jido: <#{@jido_ns}>"
  @rdf_prefix "PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>"
  @rdfs_prefix "PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>"
  @xsd_prefix "PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>"
  @owl_prefix "PREFIX owl: <http://www.w3.org/2002/07/owl#>"

  @doc """
  Returns the Jido namespace IRI.
  """
  @spec namespace() :: String.t()
  def namespace, do: @jido_ns

  @doc """
  Returns all standard SPARQL prefixes as a single string.
  """
  @spec prefixes() :: String.t()
  def prefixes do
    """
    #{@jido_prefix}
    #{@rdf_prefix}
    #{@rdfs_prefix}
    #{@xsd_prefix}
    #{@owl_prefix}
    """
  end

  @doc """
  Returns the default query limit for SPARQL queries.

  This limit prevents excessive memory consumption and ensures
  reasonable query response times.
  """
  @spec default_query_limit() :: pos_integer()
  def default_query_limit, do: 1000

  # =============================================================================
  # Validation Functions
  # =============================================================================

  @doc """
  Validates a memory ID format.

  Valid memory IDs are:
  - 1-128 characters long
  - Contain only alphanumeric characters, hyphens, and underscores

  ## Examples

      iex> SPARQLQueries.valid_memory_id?("mem_123")
      true

      iex> SPARQLQueries.valid_memory_id?("")
      false

      iex> SPARQLQueries.valid_memory_id?("invalid@id")
      false

  """
  @spec valid_memory_id?(String.t() | nil) :: boolean()
  def valid_memory_id?(id) when is_binary(id) do
    len = byte_size(id)
    len > 0 and len <= 128 and Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, id)
  end

  def valid_memory_id?(_), do: false

  @doc """
  Validates a session ID format.

  Session IDs must be valid memory IDs. This provides defense-in-depth
  alongside StoreManager's validation.
  """
  @spec valid_session_id?(String.t() | nil) :: boolean()
  def valid_session_id?(id), do: valid_memory_id?(id)

  # =============================================================================
  # Insert Operations
  # =============================================================================

  @doc """
  Generates a SPARQL INSERT DATA query for a memory item.

  ## Parameters

  - `memory` - A map with the following keys:
    - `:id` - Unique identifier for the memory
    - `:content` - The content/summary of the memory
    - `:memory_type` - The type of memory (atom matching Types.memory_type())
    - `:confidence` - Confidence level (:high, :medium, :low) or float
    - `:source_type` - Source type (:user, :agent, :tool, :external_document)
    - `:session_id` - Session this memory belongs to
    - `:created_at` - DateTime when created (optional, defaults to now)
    - `:rationale` - Optional rationale for this memory
    - `:evidence_refs` - Optional list of evidence reference IDs

  ## Example

      memory = %{
        id: "mem_123",
        content: "The project uses Phoenix 1.7",
        memory_type: :fact,
        confidence: :high,
        source_type: :agent,
        session_id: "session_456"
      }
      SPARQLQueries.insert_memory(memory)

  """
  @spec insert_memory(map()) :: String.t()
  def insert_memory(memory) do
    id = memory[:id] || generate_id()
    memory_type = memory[:memory_type] || :fact
    confidence = normalize_confidence(memory[:confidence] || :medium)
    source_type = memory[:source_type] || :agent
    session_id = memory[:session_id] || "unknown"
    created_at = memory[:created_at] || DateTime.utc_now()
    content = memory[:content] || ""
    rationale = memory[:rationale]
    evidence_refs = memory[:evidence_refs] || []

    evidence_triples =
      evidence_refs
      |> Enum.map(fn ref -> "jido:memory_#{id} jido:derivedFrom jido:evidence_#{ref} ." end)
      |> Enum.join("\n        ")

    rationale_triple =
      if rationale do
        "jido:memory_#{id} jido:rationale #{escape_string(rationale)} ."
      else
        ""
      end

    """
    #{prefixes()}

    INSERT DATA {
      jido:memory_#{id} rdf:type jido:#{memory_type_to_class(memory_type)} ;
        jido:summary #{escape_string(content)} ;
        jido:hasConfidence jido:#{confidence_to_individual(confidence)} ;
        jido:hasSourceType jido:#{source_type_to_individual(source_type)} ;
        jido:hasTimestamp "#{DateTime.to_iso8601(created_at)}"^^xsd:dateTime ;
        jido:assertedIn jido:session_#{session_id} ;
        jido:accessCount "0"^^xsd:integer .
      #{rationale_triple}
      #{evidence_triples}
    }
    """
  end

  # =============================================================================
  # Select Queries
  # =============================================================================

  @doc """
  Generates a SPARQL SELECT query for memories in a session.

  ## Options

  - `:limit` - Maximum number of results (default: no limit)
  - `:min_confidence` - Minimum confidence level (:high, :medium, :low)
  - `:include_superseded` - Include superseded memories (default: false)
  - `:order_by` - Field to order by (:timestamp, :access_count) (default: :timestamp)
  - `:order` - Sort order (:asc, :desc) (default: :desc)

  ## Example

      SPARQLQueries.query_by_session("session_123", limit: 10, min_confidence: :medium)

  """
  @spec query_by_session(String.t(), keyword()) :: String.t()
  def query_by_session(session_id, opts \\ []) do
    limit = opts[:limit]
    min_confidence = opts[:min_confidence]
    include_superseded = opts[:include_superseded] || false
    order_by = opts[:order_by] || :timestamp
    order = opts[:order] || :desc

    superseded_filter =
      if include_superseded do
        ""
      else
        "FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }"
      end

    confidence_filter = min_confidence_filter(min_confidence)
    order_clause = order_by_clause(order_by, order)
    limit_clause = limit_clause(limit)

    """
    #{prefixes()}

    SELECT ?mem ?type ?content ?confidence ?source ?timestamp ?rationale ?accessCount
    WHERE {
      ?mem jido:assertedIn jido:session_#{session_id} ;
           rdf:type ?type ;
           jido:summary ?content ;
           jido:hasConfidence ?confidence ;
           jido:hasSourceType ?source ;
           jido:hasTimestamp ?timestamp .

      OPTIONAL { ?mem jido:rationale ?rationale }
      OPTIONAL { ?mem jido:accessCount ?accessCount }

      FILTER(STRSTARTS(STR(?type), "#{@jido_ns}"))
      #{superseded_filter}
      #{confidence_filter}
    }
    #{order_clause}
    #{limit_clause}
    """
  end

  @doc """
  Generates a SPARQL SELECT query for memories of a specific type in a session.

  ## Options

  Same as `query_by_session/2`.

  ## Example

      SPARQLQueries.query_by_type("session_123", :fact, limit: 5)

  """
  @spec query_by_type(String.t(), Types.memory_type(), keyword()) :: String.t()
  def query_by_type(session_id, memory_type, opts \\ []) do
    limit = opts[:limit]
    min_confidence = opts[:min_confidence]
    include_superseded = opts[:include_superseded] || false
    order_by = opts[:order_by] || :timestamp
    order = opts[:order] || :desc

    type_class = memory_type_to_class(memory_type)

    superseded_filter =
      if include_superseded do
        ""
      else
        "FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }"
      end

    confidence_filter = min_confidence_filter(min_confidence)
    order_clause = order_by_clause(order_by, order)
    limit_clause = limit_clause(limit)

    """
    #{prefixes()}

    SELECT ?mem ?content ?confidence ?source ?timestamp ?rationale ?accessCount
    WHERE {
      ?mem jido:assertedIn jido:session_#{session_id} ;
           rdf:type jido:#{type_class} ;
           jido:summary ?content ;
           jido:hasConfidence ?confidence ;
           jido:hasSourceType ?source ;
           jido:hasTimestamp ?timestamp .

      OPTIONAL { ?mem jido:rationale ?rationale }
      OPTIONAL { ?mem jido:accessCount ?accessCount }

      #{superseded_filter}
      #{confidence_filter}
    }
    #{order_clause}
    #{limit_clause}
    """
  end

  @doc """
  Generates a SPARQL SELECT query for a single memory by ID.

  ## Example

      SPARQLQueries.query_by_id("mem_123")

  """
  @spec query_by_id(String.t()) :: String.t()
  def query_by_id(memory_id) do
    """
    #{prefixes()}

    SELECT ?type ?content ?confidence ?source ?timestamp ?rationale ?accessCount ?session ?supersededBy
    WHERE {
      jido:memory_#{memory_id} rdf:type ?type ;
           jido:summary ?content ;
           jido:hasConfidence ?confidence ;
           jido:hasSourceType ?source ;
           jido:hasTimestamp ?timestamp ;
           jido:assertedIn ?session .

      OPTIONAL { jido:memory_#{memory_id} jido:rationale ?rationale }
      OPTIONAL { jido:memory_#{memory_id} jido:accessCount ?accessCount }
      OPTIONAL { jido:memory_#{memory_id} jido:supersededBy ?supersededBy }

      FILTER(STRSTARTS(STR(?type), "#{@jido_ns}"))
    }
    """
  end

  # =============================================================================
  # Update Operations
  # =============================================================================

  @doc """
  Generates a SPARQL UPDATE to mark a memory as superseded by another.

  ## Example

      SPARQLQueries.supersede_memory("old_mem_123", "new_mem_456")

  """
  @spec supersede_memory(String.t(), String.t()) :: String.t()
  def supersede_memory(old_id, new_id) do
    """
    #{prefixes()}

    INSERT DATA {
      jido:memory_#{old_id} jido:supersededBy jido:memory_#{new_id} .
    }
    """
  end

  @doc """
  Generates a SPARQL UPDATE to soft delete a memory by marking it as superseded.

  Uses a special "deleted" marker to indicate the memory was explicitly deleted.

  ## Example

      SPARQLQueries.delete_memory("mem_123")

  """
  @spec delete_memory(String.t()) :: String.t()
  def delete_memory(memory_id) do
    """
    #{prefixes()}

    INSERT DATA {
      jido:memory_#{memory_id} jido:supersededBy jido:DeletedMarker .
    }
    """
  end

  @doc """
  Generates a SPARQL UPDATE to record an access to a memory.

  Updates the access count and last accessed timestamp.

  ## Example

      SPARQLQueries.record_access("mem_123")

  """
  @spec record_access(String.t()) :: String.t()
  def record_access(memory_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    #{prefixes()}

    INSERT {
      jido:memory_#{memory_id} jido:lastAccessed "#{now}"^^xsd:dateTime .
    }
    WHERE {
      jido:memory_#{memory_id} rdf:type ?type .
    }
    """
  end

  # =============================================================================
  # Relationship Queries
  # =============================================================================

  @doc """
  Generates a SPARQL SELECT to find memories related by a specific relationship.

  ## Supported Relationships

  - `:refines` - Find memories that refine another
  - `:confirms` - Find evidence that confirms facts
  - `:contradicts` - Find evidence that contradicts memories
  - `:derived_from` - Find memories derived from evidence
  - `:superseded_by` - Find supersession chain
  - `:has_alternative` - Find alternatives for a decision
  - `:has_root_cause` - Find root causes for errors

  ## Example

      SPARQLQueries.query_related("mem_123", :refines)

  """
  @spec query_related(String.t(), atom()) :: String.t()
  def query_related(memory_id, relationship) do
    property = relationship_to_property(relationship)

    """
    #{prefixes()}

    SELECT ?related ?type ?content ?confidence
    WHERE {
      jido:memory_#{memory_id} jido:#{property} ?related .
      ?related rdf:type ?type ;
               jido:summary ?content ;
               jido:hasConfidence ?confidence .

      FILTER(STRSTARTS(STR(?type), "#{@jido_ns}"))
    }
    """
  end

  @doc """
  Generates a SPARQL SELECT to find memories that have evidence links.

  ## Example

      SPARQLQueries.query_by_evidence("evidence_123")

  """
  @spec query_by_evidence(String.t()) :: String.t()
  def query_by_evidence(evidence_id) do
    """
    #{prefixes()}

    SELECT ?mem ?type ?content ?confidence ?timestamp
    WHERE {
      ?mem jido:derivedFrom jido:evidence_#{evidence_id} ;
           rdf:type ?type ;
           jido:summary ?content ;
           jido:hasConfidence ?confidence ;
           jido:hasTimestamp ?timestamp .

      FILTER(STRSTARTS(STR(?type), "#{@jido_ns}"))
      FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }
    }
    ORDER BY DESC(?timestamp)
    """
  end

  @doc """
  Generates a SPARQL SELECT to find decisions with their alternatives.

  ## Example

      SPARQLQueries.query_decisions_with_alternatives("session_123")

  """
  @spec query_decisions_with_alternatives(String.t()) :: String.t()
  def query_decisions_with_alternatives(session_id) do
    """
    #{prefixes()}

    SELECT ?decision ?content ?alternative ?altContent
    WHERE {
      ?decision jido:assertedIn jido:session_#{session_id} ;
                rdf:type jido:Decision ;
                jido:summary ?content .

      OPTIONAL {
        ?decision jido:hasAlternative ?alternative .
        ?alternative jido:summary ?altContent .
      }

      FILTER NOT EXISTS { ?decision jido:supersededBy ?newer }
    }
    """
  end

  @doc """
  Generates a SPARQL SELECT to find lessons learned for a specific error.

  ## Example

      SPARQLQueries.query_lessons_for_error("error_123")

  """
  @spec query_lessons_for_error(String.t()) :: String.t()
  def query_lessons_for_error(error_id) do
    """
    #{prefixes()}

    SELECT ?lesson ?content ?confidence
    WHERE {
      jido:memory_#{error_id} jido:producedLesson ?lesson .
      ?lesson rdf:type jido:LessonLearned ;
              jido:summary ?content ;
              jido:hasConfidence ?confidence .

      FILTER NOT EXISTS { ?lesson jido:supersededBy ?newer }
    }
    """
  end

  # =============================================================================
  # Helper Functions - Type Mappings
  # =============================================================================

  @doc """
  Converts a memory type atom to its Jido ontology class name.
  """
  @spec memory_type_to_class(Types.memory_type()) :: String.t()
  # Knowledge types (jido-knowledge.ttl)
  def memory_type_to_class(:fact), do: "Fact"
  def memory_type_to_class(:assumption), do: "Assumption"
  def memory_type_to_class(:hypothesis), do: "Hypothesis"
  def memory_type_to_class(:discovery), do: "Discovery"
  def memory_type_to_class(:risk), do: "Risk"
  def memory_type_to_class(:unknown), do: "Unknown"
  # Decision types (jido-decision.ttl)
  def memory_type_to_class(:decision), do: "Decision"
  def memory_type_to_class(:architectural_decision), do: "ArchitecturalDecision"
  def memory_type_to_class(:implementation_decision), do: "ImplementationDecision"
  def memory_type_to_class(:alternative), do: "Alternative"
  def memory_type_to_class(:trade_off), do: "TradeOff"
  # Convention types (jido-convention.ttl)
  def memory_type_to_class(:convention), do: "Convention"
  def memory_type_to_class(:coding_standard), do: "CodingStandard"
  def memory_type_to_class(:architectural_convention), do: "ArchitecturalConvention"
  def memory_type_to_class(:agent_rule), do: "AgentRule"
  def memory_type_to_class(:process_convention), do: "ProcessConvention"
  # Error types (jido-error.ttl)
  def memory_type_to_class(:error), do: "Error"
  def memory_type_to_class(:bug), do: "Bug"
  def memory_type_to_class(:failure), do: "Failure"
  def memory_type_to_class(:incident), do: "Incident"
  def memory_type_to_class(:root_cause), do: "RootCause"
  def memory_type_to_class(:lesson_learned), do: "LessonLearned"
  # Fallback
  def memory_type_to_class(type), do: Macro.camelize(to_string(type))

  @doc """
  Converts a Jido ontology class IRI or name to its memory type atom.
  """
  @spec class_to_memory_type(String.t()) :: Types.memory_type()
  def class_to_memory_type(class) when is_binary(class) do
    # Extract local name if full IRI
    local_name =
      if String.contains?(class, "#") do
        class |> String.split("#") |> List.last()
      else
        class
      end

    case local_name do
      # Knowledge types
      "Fact" -> :fact
      "Assumption" -> :assumption
      "Hypothesis" -> :hypothesis
      "Discovery" -> :discovery
      "Risk" -> :risk
      "Unknown" -> :unknown
      # Decision types
      "Decision" -> :decision
      "ArchitecturalDecision" -> :architectural_decision
      "ImplementationDecision" -> :implementation_decision
      "Alternative" -> :alternative
      "TradeOff" -> :trade_off
      # Convention types
      "Convention" -> :convention
      "CodingStandard" -> :coding_standard
      "ArchitecturalConvention" -> :architectural_convention
      "AgentRule" -> :agent_rule
      "ProcessConvention" -> :process_convention
      # Error types
      "Error" -> :error
      "Bug" -> :bug
      "Failure" -> :failure
      "Incident" -> :incident
      "RootCause" -> :root_cause
      "LessonLearned" -> :lesson_learned
      # Fallback
      _ -> :unknown
    end
  end

  @doc """
  Converts a confidence level to its Jido ontology individual name.
  """
  @spec confidence_to_individual(Types.confidence_level()) :: String.t()
  def confidence_to_individual(:high), do: "High"
  def confidence_to_individual(:medium), do: "Medium"
  def confidence_to_individual(:low), do: "Low"

  @doc """
  Converts a Jido ontology confidence individual to its level atom.
  """
  @spec individual_to_confidence(String.t()) :: Types.confidence_level()
  def individual_to_confidence(individual) when is_binary(individual) do
    local_name =
      if String.contains?(individual, "#") do
        individual |> String.split("#") |> List.last()
      else
        individual
      end

    case local_name do
      "High" -> :high
      "Medium" -> :medium
      "Low" -> :low
      _ -> :low
    end
  end

  @doc """
  Converts a source type to its Jido ontology individual name.
  """
  @spec source_type_to_individual(Types.source_type()) :: String.t()
  def source_type_to_individual(:user), do: "UserSource"
  def source_type_to_individual(:agent), do: "AgentSource"
  def source_type_to_individual(:tool), do: "ToolSource"
  def source_type_to_individual(:external_document), do: "ExternalDocumentSource"

  @doc """
  Converts a Jido ontology source individual to its type atom.
  """
  @spec individual_to_source_type(String.t()) :: Types.source_type()
  def individual_to_source_type(individual) when is_binary(individual) do
    local_name =
      if String.contains?(individual, "#") do
        individual |> String.split("#") |> List.last()
      else
        individual
      end

    case local_name do
      "UserSource" -> :user
      "AgentSource" -> :agent
      "ToolSource" -> :tool
      "ExternalDocumentSource" -> :external_document
      _ -> :agent
    end
  end

  # =============================================================================
  # Helper Functions - String Escaping
  # =============================================================================

  @doc """
  Escapes a string for use in SPARQL queries.

  Handles special characters that could cause injection or syntax errors.
  """
  @spec escape_string(String.t() | nil) :: String.t()
  def escape_string(nil), do: ~s("")
  def escape_string(""), do: ~s("")

  def escape_string(str) when is_binary(str) do
    escaped =
      str
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    ~s("#{escaped}")
  end

  @doc """
  Extracts a memory ID from a full IRI.

  ## Example

      iex> SPARQLQueries.extract_memory_id("https://jido.ai/ontology#memory_abc123")
      "abc123"

  """
  @spec extract_memory_id(String.t()) :: String.t()
  def extract_memory_id(iri) when is_binary(iri) do
    cond do
      String.contains?(iri, "#memory_") ->
        iri |> String.split("#memory_") |> List.last()

      String.contains?(iri, "memory_") ->
        iri |> String.split("memory_") |> List.last()

      true ->
        iri
    end
  end

  @doc """
  Extracts a session ID from a full IRI.
  """
  @spec extract_session_id(String.t()) :: String.t()
  def extract_session_id(iri) when is_binary(iri) do
    cond do
      String.contains?(iri, "#session_") ->
        iri |> String.split("#session_") |> List.last()

      String.contains?(iri, "session_") ->
        iri |> String.split("session_") |> List.last()

      true ->
        iri
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp normalize_confidence(level) when is_atom(level), do: level

  defp normalize_confidence(value) when is_float(value) do
    Types.confidence_to_level(value)
  end

  defp normalize_confidence(_), do: :medium

  defp relationship_to_property(:refines), do: "refines"
  defp relationship_to_property(:confirms), do: "confirms"
  defp relationship_to_property(:contradicts), do: "contradicts"
  defp relationship_to_property(:derived_from), do: "derivedFrom"
  defp relationship_to_property(:superseded_by), do: "supersededBy"
  defp relationship_to_property(:has_alternative), do: "hasAlternative"
  defp relationship_to_property(:has_root_cause), do: "hasRootCause"
  defp relationship_to_property(:produced_lesson), do: "producedLesson"
  defp relationship_to_property(rel), do: Macro.camelize(to_string(rel))

  defp min_confidence_filter(nil), do: ""
  defp min_confidence_filter(:low), do: ""

  defp min_confidence_filter(:medium) do
    "FILTER(?confidence IN (jido:High, jido:Medium))"
  end

  defp min_confidence_filter(:high) do
    "FILTER(?confidence = jido:High)"
  end

  # Handle float values by converting to confidence levels
  defp min_confidence_filter(value) when is_float(value) do
    min_confidence_filter(Types.confidence_to_level(value))
  end

  defp order_by_clause(:timestamp, :desc), do: "ORDER BY DESC(?timestamp)"
  defp order_by_clause(:timestamp, :asc), do: "ORDER BY ASC(?timestamp)"
  defp order_by_clause(:access_count, :desc), do: "ORDER BY DESC(?accessCount)"
  defp order_by_clause(:access_count, :asc), do: "ORDER BY ASC(?accessCount)"
  defp order_by_clause(_, _), do: "ORDER BY DESC(?timestamp)"

  defp limit_clause(nil), do: ""
  defp limit_clause(n) when is_integer(n) and n > 0, do: "LIMIT #{n}"
  defp limit_clause(_), do: ""

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
