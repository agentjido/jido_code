defmodule JidoCode.Memory.LongTerm.Vocab.Jido do
  @moduledoc """
  Jido ontology vocabulary namespace for RDF operations.

  This module provides type-safe access to Jido ontology IRIs, enabling proper
  semantic mapping between Elixir memory types and their RDF representations.

  ## Namespace Prefixes

  - `jido:` - Main Jido ontology namespace (`https://jido.ai/ontology#`)
  - `rdf:` - RDF syntax namespace
  - `xsd:` - XML Schema datatypes

  ## Memory Type Classes

  The module maps Elixir memory type atoms to their corresponding Jido ontology
  class IRIs:

  | Elixir Type       | Jido Class IRI                    |
  |-------------------|-----------------------------------|
  | `:fact`           | `jido:Fact`                       |
  | `:assumption`     | `jido:Assumption`                 |
  | `:hypothesis`     | `jido:Hypothesis`                 |
  | `:discovery`      | `jido:Discovery`                  |
  | `:risk`           | `jido:Risk`                       |
  | `:unknown`        | `jido:Unknown`                    |
  | `:decision`       | `jido:Decision`                   |
  | `:convention`     | `jido:Convention`                 |
  | `:lesson_learned` | `jido:LessonLearned`              |

  ## Confidence Levels

  Confidence levels map to Jido ontology individuals:

  - `:high` (>= 0.8) -> `jido:High`
  - `:medium` (>= 0.5) -> `jido:Medium`
  - `:low` (< 0.5) -> `jido:Low`

  ## Example Usage

      iex> Jido.iri("Fact")
      "https://jido.ai/ontology#Fact"

      iex> Jido.memory_type_to_class(:fact)
      "https://jido.ai/ontology#Fact"

      iex> Jido.confidence_to_individual(0.85)
      "https://jido.ai/ontology#High"

      iex> Jido.memory_uri("abc123")
      "https://jido.ai/ontology#memory_abc123"

  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # Namespace Constants
  # =============================================================================

  @jido_ns "https://jido.ai/ontology#"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @xsd_ns "http://www.w3.org/2001/XMLSchema#"

  # =============================================================================
  # Namespace Accessors
  # =============================================================================

  @doc """
  Returns the Jido ontology namespace prefix.

  ## Examples

      iex> Jido.namespace()
      "https://jido.ai/ontology#"

  """
  @spec namespace() :: String.t()
  def namespace, do: @jido_ns

  @doc """
  Returns the XML Schema namespace prefix.

  ## Examples

      iex> Jido.xsd_namespace()
      "http://www.w3.org/2001/XMLSchema#"

  """
  @spec xsd_namespace() :: String.t()
  def xsd_namespace, do: @xsd_ns

  # =============================================================================
  # IRI Construction
  # =============================================================================

  @doc """
  Constructs a full IRI from a local name using the Jido namespace.

  ## Examples

      iex> Jido.iri("Fact")
      "https://jido.ai/ontology#Fact"

      iex> Jido.iri("hasConfidence")
      "https://jido.ai/ontology#hasConfidence"

  """
  @spec iri(String.t()) :: String.t()
  def iri(local_name), do: @jido_ns <> local_name

  @doc """
  Returns the RDF type IRI (`rdf:type`).

  ## Examples

      iex> Jido.rdf_type()
      "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  """
  @spec rdf_type() :: String.t()
  def rdf_type, do: @rdf_type

  # =============================================================================
  # Memory Type Classes
  # =============================================================================

  @doc "Returns the IRI for `jido:MemoryItem` base class."
  @spec memory_item() :: String.t()
  def memory_item, do: iri("MemoryItem")

  @doc "Returns the IRI for `jido:Fact` class."
  @spec fact() :: String.t()
  def fact, do: iri("Fact")

  @doc "Returns the IRI for `jido:Assumption` class."
  @spec assumption() :: String.t()
  def assumption, do: iri("Assumption")

  @doc "Returns the IRI for `jido:Hypothesis` class."
  @spec hypothesis() :: String.t()
  def hypothesis, do: iri("Hypothesis")

  @doc "Returns the IRI for `jido:Discovery` class."
  @spec discovery() :: String.t()
  def discovery, do: iri("Discovery")

  @doc "Returns the IRI for `jido:Risk` class."
  @spec risk() :: String.t()
  def risk, do: iri("Risk")

  @doc "Returns the IRI for `jido:Unknown` class."
  @spec unknown() :: String.t()
  def unknown, do: iri("Unknown")

  @doc "Returns the IRI for `jido:Decision` class."
  @spec decision() :: String.t()
  def decision, do: iri("Decision")

  @doc "Returns the IRI for `jido:ArchitecturalDecision` class."
  @spec architectural_decision() :: String.t()
  def architectural_decision, do: iri("ArchitecturalDecision")

  @doc "Returns the IRI for `jido:Convention` class."
  @spec convention() :: String.t()
  def convention, do: iri("Convention")

  @doc "Returns the IRI for `jido:CodingStandard` class."
  @spec coding_standard() :: String.t()
  def coding_standard, do: iri("CodingStandard")

  @doc "Returns the IRI for `jido:LessonLearned` class."
  @spec lesson_learned() :: String.t()
  def lesson_learned, do: iri("LessonLearned")

  @doc "Returns the IRI for `jido:Error` class."
  @spec error() :: String.t()
  def error, do: iri("Error")

  @doc "Returns the IRI for `jido:Bug` class."
  @spec bug() :: String.t()
  def bug, do: iri("Bug")

  # =============================================================================
  # Memory Type Mapping
  # =============================================================================

  @doc """
  Maps a memory type atom to its corresponding Jido ontology class IRI.

  ## Examples

      iex> Jido.memory_type_to_class(:fact)
      "https://jido.ai/ontology#Fact"

      iex> Jido.memory_type_to_class(:lesson_learned)
      "https://jido.ai/ontology#LessonLearned"

  ## Raises

  Raises `ArgumentError` for unknown memory types.

  """
  @spec memory_type_to_class(atom()) :: String.t()
  def memory_type_to_class(:fact), do: fact()
  def memory_type_to_class(:assumption), do: assumption()
  def memory_type_to_class(:hypothesis), do: hypothesis()
  def memory_type_to_class(:discovery), do: discovery()
  def memory_type_to_class(:risk), do: risk()
  def memory_type_to_class(:unknown), do: unknown()
  def memory_type_to_class(:decision), do: decision()
  def memory_type_to_class(:convention), do: convention()
  def memory_type_to_class(:lesson_learned), do: lesson_learned()

  def memory_type_to_class(type) do
    raise ArgumentError, "Unknown memory type: #{inspect(type)}"
  end

  @doc """
  Maps a Jido ontology class IRI to its corresponding memory type atom.

  Returns `:unknown` for unrecognized class IRIs.

  ## Examples

      iex> Jido.class_to_memory_type("https://jido.ai/ontology#Fact")
      :fact

      iex> Jido.class_to_memory_type("https://jido.ai/ontology#LessonLearned")
      :lesson_learned

      iex> Jido.class_to_memory_type("https://example.org/Unknown")
      :unknown

  """
  @spec class_to_memory_type(String.t()) :: atom()
  def class_to_memory_type(class_iri) do
    case class_iri do
      @jido_ns <> "Fact" -> :fact
      @jido_ns <> "Assumption" -> :assumption
      @jido_ns <> "Hypothesis" -> :hypothesis
      @jido_ns <> "Discovery" -> :discovery
      @jido_ns <> "Risk" -> :risk
      @jido_ns <> "Unknown" -> :unknown
      @jido_ns <> "Decision" -> :decision
      @jido_ns <> "Convention" -> :convention
      @jido_ns <> "LessonLearned" -> :lesson_learned
      _ -> :unknown
    end
  end

  # =============================================================================
  # Confidence Level Individuals
  # =============================================================================

  @doc "Returns the IRI for `jido:High` confidence level individual."
  @spec confidence_high() :: String.t()
  def confidence_high, do: iri("High")

  @doc "Returns the IRI for `jido:Medium` confidence level individual."
  @spec confidence_medium() :: String.t()
  def confidence_medium, do: iri("Medium")

  @doc "Returns the IRI for `jido:Low` confidence level individual."
  @spec confidence_low() :: String.t()
  def confidence_low, do: iri("Low")

  @doc """
  Maps a confidence float to its corresponding Jido ontology individual IRI.

  Delegates threshold logic to `JidoCode.Memory.Types.confidence_to_level/1` to
  ensure consistency across the codebase:

  - Values >= 0.8 map to `jido:High`
  - Values >= 0.5 and < 0.8 map to `jido:Medium`
  - Values < 0.5 map to `jido:Low`

  ## Examples

      iex> Jido.confidence_to_individual(0.9)
      "https://jido.ai/ontology#High"

      iex> Jido.confidence_to_individual(0.8)
      "https://jido.ai/ontology#High"

      iex> Jido.confidence_to_individual(0.6)
      "https://jido.ai/ontology#Medium"

      iex> Jido.confidence_to_individual(0.3)
      "https://jido.ai/ontology#Low"

  """
  @spec confidence_to_individual(float()) :: String.t()
  def confidence_to_individual(confidence) do
    case Types.confidence_to_level(confidence) do
      :high -> confidence_high()
      :medium -> confidence_medium()
      :low -> confidence_low()
    end
  end

  @doc """
  Maps a confidence level IRI to its representative float value.

  Delegates to `JidoCode.Memory.Types.level_to_confidence/1` for the actual
  float values to ensure consistency across the codebase:

  - `jido:High` -> 0.9
  - `jido:Medium` -> 0.6
  - `jido:Low` -> 0.3

  Returns 0.5 for unrecognized IRIs (medium confidence as a safe default).

  ## Examples

      iex> Jido.individual_to_confidence("https://jido.ai/ontology#High")
      0.9

      iex> Jido.individual_to_confidence("https://jido.ai/ontology#Medium")
      0.6

      iex> Jido.individual_to_confidence("https://jido.ai/ontology#Low")
      0.3

  """
  @spec individual_to_confidence(String.t()) :: float()
  def individual_to_confidence(iri) do
    case iri do
      @jido_ns <> "High" -> Types.level_to_confidence(:high)
      @jido_ns <> "Medium" -> Types.level_to_confidence(:medium)
      @jido_ns <> "Low" -> Types.level_to_confidence(:low)
      _ -> 0.5
    end
  end

  # =============================================================================
  # Source Type Individuals
  # =============================================================================

  @doc "Returns the IRI for `jido:UserSource` individual."
  @spec source_user() :: String.t()
  def source_user, do: iri("UserSource")

  @doc "Returns the IRI for `jido:AgentSource` individual."
  @spec source_agent() :: String.t()
  def source_agent, do: iri("AgentSource")

  @doc "Returns the IRI for `jido:ToolSource` individual."
  @spec source_tool() :: String.t()
  def source_tool, do: iri("ToolSource")

  @doc "Returns the IRI for `jido:ExternalDocumentSource` individual."
  @spec source_external() :: String.t()
  def source_external, do: iri("ExternalDocumentSource")

  @doc """
  Maps a source type atom to its corresponding Jido ontology individual IRI.

  ## Examples

      iex> Jido.source_type_to_individual(:user)
      "https://jido.ai/ontology#UserSource"

      iex> Jido.source_type_to_individual(:agent)
      "https://jido.ai/ontology#AgentSource"

      iex> Jido.source_type_to_individual(:tool)
      "https://jido.ai/ontology#ToolSource"

      iex> Jido.source_type_to_individual(:external_document)
      "https://jido.ai/ontology#ExternalDocumentSource"

  ## Raises

  Raises `ArgumentError` for unknown source types.

  """
  @spec source_type_to_individual(atom()) :: String.t()
  def source_type_to_individual(:user), do: source_user()
  def source_type_to_individual(:agent), do: source_agent()
  def source_type_to_individual(:tool), do: source_tool()
  def source_type_to_individual(:external_document), do: source_external()

  def source_type_to_individual(type) do
    raise ArgumentError, "Unknown source type: #{inspect(type)}"
  end

  @doc """
  Maps a source type IRI to its corresponding atom.

  Returns `:unknown` for unrecognized IRIs.

  ## Examples

      iex> Jido.individual_to_source_type("https://jido.ai/ontology#UserSource")
      :user

      iex> Jido.individual_to_source_type("https://jido.ai/ontology#AgentSource")
      :agent

      iex> Jido.individual_to_source_type("https://example.org/Unknown")
      :unknown

  """
  @spec individual_to_source_type(String.t()) :: atom()
  def individual_to_source_type(iri) do
    case iri do
      @jido_ns <> "UserSource" -> :user
      @jido_ns <> "AgentSource" -> :agent
      @jido_ns <> "ToolSource" -> :tool
      @jido_ns <> "ExternalDocumentSource" -> :external_document
      _ -> :unknown
    end
  end

  # =============================================================================
  # Property IRIs
  # =============================================================================

  @doc "Returns the IRI for `jido:summary` property."
  @spec summary() :: String.t()
  def summary, do: iri("summary")

  @doc "Returns the IRI for `jido:detailedExplanation` property."
  @spec detailed_explanation() :: String.t()
  def detailed_explanation, do: iri("detailedExplanation")

  @doc "Returns the IRI for `jido:rationale` property."
  @spec rationale() :: String.t()
  def rationale, do: iri("rationale")

  @doc "Returns the IRI for `jido:hasConfidence` property."
  @spec has_confidence() :: String.t()
  def has_confidence, do: iri("hasConfidence")

  @doc "Returns the IRI for `jido:hasSourceType` property."
  @spec has_source_type() :: String.t()
  def has_source_type, do: iri("hasSourceType")

  @doc "Returns the IRI for `jido:hasTimestamp` property."
  @spec has_timestamp() :: String.t()
  def has_timestamp, do: iri("hasTimestamp")

  @doc "Returns the IRI for `jido:assertedBy` property."
  @spec asserted_by() :: String.t()
  def asserted_by, do: iri("assertedBy")

  @doc "Returns the IRI for `jido:assertedIn` property."
  @spec asserted_in() :: String.t()
  def asserted_in, do: iri("assertedIn")

  @doc "Returns the IRI for `jido:appliesToProject` property."
  @spec applies_to_project() :: String.t()
  def applies_to_project, do: iri("appliesToProject")

  @doc "Returns the IRI for `jido:derivedFrom` property."
  @spec derived_from() :: String.t()
  def derived_from, do: iri("derivedFrom")

  @doc "Returns the IRI for `jido:supersededBy` property."
  @spec superseded_by() :: String.t()
  def superseded_by, do: iri("supersededBy")

  @doc "Returns the IRI for `jido:invalidatedBy` property."
  @spec invalidated_by() :: String.t()
  def invalidated_by, do: iri("invalidatedBy")

  @doc "Returns the IRI for `jido:hasAccessCount` property."
  @spec has_access_count() :: String.t()
  def has_access_count, do: iri("hasAccessCount")

  @doc "Returns the IRI for `jido:lastAccessed` property."
  @spec last_accessed() :: String.t()
  def last_accessed, do: iri("lastAccessed")

  # =============================================================================
  # Entity IRI Generators
  # =============================================================================

  @doc """
  Generates a memory entity IRI from an id.

  ## Examples

      iex> Jido.memory_uri("abc123")
      "https://jido.ai/ontology#memory_abc123"

  """
  @spec memory_uri(String.t()) :: String.t()
  def memory_uri(id), do: iri("memory_" <> id)

  @doc """
  Generates a session entity IRI from an id.

  ## Examples

      iex> Jido.session_uri("session-123")
      "https://jido.ai/ontology#session_session-123"

  """
  @spec session_uri(String.t()) :: String.t()
  def session_uri(id), do: iri("session_" <> id)

  @doc """
  Generates an agent entity IRI from an id.

  ## Examples

      iex> Jido.agent_uri("agent-456")
      "https://jido.ai/ontology#agent_agent-456"

  """
  @spec agent_uri(String.t()) :: String.t()
  def agent_uri(id), do: iri("agent_" <> id)

  @doc """
  Generates a project entity IRI from an id.

  ## Examples

      iex> Jido.project_uri("my-project")
      "https://jido.ai/ontology#project_my-project"

  """
  @spec project_uri(String.t()) :: String.t()
  def project_uri(id), do: iri("project_" <> id)

  @doc """
  Generates an evidence entity IRI from a reference string.

  The reference is hashed to create a valid IRI local name.

  ## Examples

      iex> Jido.evidence_uri("file:lib/foo.ex:42")
      "https://jido.ai/ontology#evidence_" <> _hash

  """
  @spec evidence_uri(String.t()) :: String.t()
  def evidence_uri(ref) do
    hash = hash_ref(ref)
    iri("evidence_" <> hash)
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  @doc false
  @spec hash_ref(String.t()) :: String.t()
  def hash_ref(ref) do
    :crypto.hash(:sha256, ref)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end
end
