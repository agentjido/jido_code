defmodule JidoCode.Memory.Types do
  @moduledoc """
  Shared type definitions for the JidoCode memory system.

  This module defines the foundational types used across all memory components,
  including short-term working context, pending memories awaiting promotion,
  and long-term persistent storage.

  ## Memory Type System

  The type system maps directly to the Jido ontology classes, providing semantic
  structure for all memory operations:

  - **memory_type** - Classification of memory items (fact, assumption, hypothesis, etc.)
  - **confidence_level** - Discrete confidence levels (high, medium, low)
  - **source_type** - Origin of the memory (user, agent, tool, external_document)
  - **context_key** - Semantic keys for working context items

  ## Jido Ontology Alignment

  Types in this module correspond to Jido ontology classes defined in the TTL files.

  ### Knowledge Types (jido-knowledge.ttl)

  | Elixir Type              | Jido Ontology Class           |
  |--------------------------|-------------------------------|
  | `:fact`                  | `jido:Fact`                   |
  | `:assumption`            | `jido:Assumption`             |
  | `:hypothesis`            | `jido:Hypothesis`             |
  | `:discovery`             | `jido:Discovery`              |
  | `:risk`                  | `jido:Risk`                   |
  | `:unknown`               | `jido:Unknown`                |

  ### Decision Types (jido-decision.ttl)

  | Elixir Type              | Jido Ontology Class           |
  |--------------------------|-------------------------------|
  | `:decision`              | `jido:Decision`               |
  | `:architectural_decision`| `jido:ArchitecturalDecision`  |
  | `:implementation_decision`| `jido:ImplementationDecision`|
  | `:alternative`           | `jido:Alternative`            |
  | `:trade_off`             | `jido:TradeOff`               |

  ### Convention Types (jido-convention.ttl)

  | Elixir Type              | Jido Ontology Class           |
  |--------------------------|-------------------------------|
  | `:convention`            | `jido:Convention`             |
  | `:coding_standard`       | `jido:CodingStandard`         |
  | `:architectural_convention`| `jido:ArchitecturalConvention`|
  | `:agent_rule`            | `jido:AgentRule`              |
  | `:process_convention`    | `jido:ProcessConvention`      |

  ### Error Types (jido-error.ttl)

  | Elixir Type              | Jido Ontology Class           |
  |--------------------------|-------------------------------|
  | `:error`                 | `jido:Error`                  |
  | `:bug`                   | `jido:Bug`                    |
  | `:failure`               | `jido:Failure`                |
  | `:incident`              | `jido:Incident`               |
  | `:root_cause`            | `jido:RootCause`              |
  | `:lesson_learned`        | `jido:LessonLearned`          |

  ## Confidence Level Mapping

  Confidence levels map to float ranges:

  - `:high` - confidence >= 0.8
  - `:medium` - 0.5 <= confidence < 0.8
  - `:low` - confidence < 0.5

  When converting from level to float, representative values are returned:
  - `:high` -> 0.9
  - `:medium` -> 0.6
  - `:low` -> 0.3
  """

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @typedoc """
  Classification of memory items, mapping to Jido ontology MemoryItem subclasses.

  ### Knowledge Types (from jido-knowledge.ttl)

  - `:fact` - Verified, objective information about the project or codebase
  - `:assumption` - Inferred information that may need verification
  - `:hypothesis` - Proposed explanations or theories being tested
  - `:discovery` - Newly found information worth remembering
  - `:risk` - Potential issues or concerns identified
  - `:unknown` - Information gaps that need investigation

  ### Decision Types (from jido-decision.ttl)

  - `:decision` - Choices made with their rationale
  - `:architectural_decision` - Significant architectural choices with rationale
  - `:implementation_decision` - Low-to-medium level implementation-specific choice
  - `:alternative` - A considered option that was not selected
  - `:trade_off` - A compromise relationship between competing goals

  ### Convention Types (from jido-convention.ttl)

  - `:convention` - Established patterns or standards to follow
  - `:coding_standard` - Specific coding practices and style guidelines
  - `:architectural_convention` - A convention governing architectural patterns and structure
  - `:agent_rule` - A rule governing agent behavior and authority
  - `:process_convention` - A convention governing workflow, review, or operational processes

  ### Error Types (from jido-error.ttl)

  - `:error` - A general error encountered during development or execution
  - `:bug` - A defect in code causing incorrect behavior
  - `:failure` - A system-level failure or outage
  - `:incident` - An operational or runtime incident affecting the system
  - `:root_cause` - The underlying cause of an error, bug, or failure
  - `:lesson_learned` - Insights gained from past experiences

  """
  # Knowledge types
  @type memory_type ::
          :fact
          | :assumption
          | :hypothesis
          | :discovery
          | :risk
          | :unknown
          # Decision types
          | :decision
          | :architectural_decision
          | :implementation_decision
          | :alternative
          | :trade_off
          # Convention types
          | :convention
          | :coding_standard
          | :architectural_convention
          | :agent_rule
          | :process_convention
          # Error types
          | :error
          | :bug
          | :failure
          | :incident
          | :root_cause
          | :lesson_learned

  @typedoc """
  Discrete confidence levels mapping to Jido ConfidenceLevel individuals.

  - `:high` - High confidence (>= 0.8)
  - `:medium` - Medium confidence (>= 0.5, < 0.8)
  - `:low` - Low confidence (< 0.5)
  """
  @type confidence_level :: :high | :medium | :low

  @typedoc """
  Source of the memory, matching Jido SourceType individuals.

  - `:user` - Information provided directly by the user
  - `:agent` - Information generated by the AI agent
  - `:tool` - Information obtained from tool execution (file reads, commands, etc.)
  - `:external_document` - Information from external documentation or sources
  """
  @type source_type :: :user | :agent | :tool | :external_document

  @typedoc """
  Semantic keys for working context items.

  These keys represent different aspects of session context:

  - `:active_file` - Currently focused file path
  - `:project_root` - Root directory of the project
  - `:primary_language` - Main programming language of the project
  - `:framework` - Primary framework being used (e.g., Phoenix, Rails)
  - `:current_task` - What the user is currently working on
  - `:user_intent` - Inferred goal or objective of the user
  - `:discovered_patterns` - Code patterns found in the project
  - `:active_errors` - Current errors or issues being addressed
  - `:pending_questions` - Unresolved questions or clarifications needed
  - `:file_relationships` - Dependencies or relationships between files
  - `:conversation_summary` - Cached summarized conversation (internal use)
  """
  @type context_key ::
          :active_file
          | :project_root
          | :primary_language
          | :framework
          | :current_task
          | :user_intent
          | :discovered_patterns
          | :active_errors
          | :pending_questions
          | :file_relationships
          | :conversation_summary

  @typedoc """
  A memory item staged for potential promotion to long-term storage.

  ## Fields

  - `id` - Unique identifier for the pending item
  - `content` - The actual content/value of the memory
  - `memory_type` - Classification of this memory
  - `confidence` - Confidence score (0.0 to 1.0)
  - `source_type` - Where this memory originated
  - `evidence` - List of evidence references supporting this memory
  - `rationale` - Optional explanation for why this is worth remembering
  - `suggested_by` - Whether this was implicitly detected or explicitly requested by agent
  - `importance_score` - Calculated importance for promotion decisions
  - `created_at` - When this pending item was created
  - `access_count` - How many times this item has been accessed
  """
  @type pending_item :: %{
          id: String.t(),
          content: String.t(),
          memory_type: memory_type(),
          confidence: float(),
          source_type: source_type(),
          evidence: [String.t()],
          rationale: String.t() | nil,
          suggested_by: :implicit | :agent,
          importance_score: float(),
          created_at: DateTime.t(),
          access_count: non_neg_integer()
        }

  @typedoc """
  An entry in the access log tracking memory/context usage.

  ## Fields

  - `key` - Either a context_key or a memory reference tuple
  - `timestamp` - When the access occurred
  - `access_type` - Type of access (read, write, or query)
  """
  @type access_entry :: %{
          key: context_key() | {:memory, String.t()},
          timestamp: DateTime.t(),
          access_type: :read | :write | :query
        }

  @typedoc """
  A conversation message used in chat history and context building.

  ## Fields

  - `role` - The role of the message sender (user, assistant, system, tool)
  - `content` - The message content (may be nil for some message types)
  - `timestamp` - When the message was created (optional)
  - `id` - Unique identifier for the message (optional)

  ## Known Roles

  - `:user` - Message from the user
  - `:assistant` - Response from the AI assistant
  - `:system` - System instructions or context
  - `:tool` - Output from tool execution

  Other roles may be used for extensibility.
  """
  @type message :: %{
          required(:role) => atom(),
          required(:content) => String.t() | nil,
          optional(:timestamp) => DateTime.t(),
          optional(:id) => String.t()
        }

  @doc """
  Returns the summary cache key atom for internal use.

  This is used by ContextBuilder to store cached conversation summaries
  in the working context. Exposed here to make the coupling explicit.
  """
  @spec summary_cache_key() :: context_key()
  def summary_cache_key, do: :conversation_summary

  # =============================================================================
  # Helper Functions
  # =============================================================================

  @doc """
  Converts a confidence float value to a discrete confidence level.

  ## Examples

      iex> JidoCode.Memory.Types.confidence_to_level(0.9)
      :high

      iex> JidoCode.Memory.Types.confidence_to_level(0.8)
      :high

      iex> JidoCode.Memory.Types.confidence_to_level(0.7)
      :medium

      iex> JidoCode.Memory.Types.confidence_to_level(0.5)
      :medium

      iex> JidoCode.Memory.Types.confidence_to_level(0.3)
      :low

      iex> JidoCode.Memory.Types.confidence_to_level(0.0)
      :low

  """
  @spec confidence_to_level(float()) :: confidence_level()
  def confidence_to_level(confidence) when confidence >= 0.8, do: :high
  def confidence_to_level(confidence) when confidence >= 0.5, do: :medium
  def confidence_to_level(_confidence), do: :low

  @doc """
  Converts a discrete confidence level to a representative float value.

  Returns representative values for each level:
  - `:high` -> 0.9
  - `:medium` -> 0.6
  - `:low` -> 0.3

  ## Examples

      iex> JidoCode.Memory.Types.level_to_confidence(:high)
      0.9

      iex> JidoCode.Memory.Types.level_to_confidence(:medium)
      0.6

      iex> JidoCode.Memory.Types.level_to_confidence(:low)
      0.3

  """
  @spec level_to_confidence(confidence_level()) :: float()
  def level_to_confidence(:high), do: 0.9
  def level_to_confidence(:medium), do: 0.6
  def level_to_confidence(:low), do: 0.3

  # =============================================================================
  # Type Validation Helpers
  # =============================================================================

  @memory_types [
    # Knowledge types
    :fact,
    :assumption,
    :hypothesis,
    :discovery,
    :risk,
    :unknown,
    # Decision types
    :decision,
    :architectural_decision,
    :implementation_decision,
    :alternative,
    :trade_off,
    # Convention types
    :convention,
    :coding_standard,
    :architectural_convention,
    :agent_rule,
    :process_convention,
    # Error types
    :error,
    :bug,
    :failure,
    :incident,
    :root_cause,
    :lesson_learned
  ]

  @confidence_levels [:high, :medium, :low]

  @source_types [:user, :agent, :tool, :external_document]

  @context_keys [
    :active_file,
    :project_root,
    :primary_language,
    :framework,
    :current_task,
    :user_intent,
    :discovered_patterns,
    :active_errors,
    :pending_questions,
    :file_relationships,
    :conversation_summary
  ]

  @doc """
  Returns all valid memory types.
  """
  @spec memory_types() :: [memory_type()]
  def memory_types, do: @memory_types

  @doc """
  Returns all valid confidence levels.
  """
  @spec confidence_levels() :: [confidence_level()]
  def confidence_levels, do: @confidence_levels

  @doc """
  Returns all valid source types.
  """
  @spec source_types() :: [source_type()]
  def source_types, do: @source_types

  @doc """
  Returns all valid context keys.
  """
  @spec context_keys() :: [context_key()]
  def context_keys, do: @context_keys

  @doc """
  Checks if a value is a valid memory type.
  """
  @spec valid_memory_type?(term()) :: boolean()
  def valid_memory_type?(type), do: type in @memory_types

  @doc """
  Checks if a value is a valid confidence level.
  """
  @spec valid_confidence_level?(term()) :: boolean()
  def valid_confidence_level?(level), do: level in @confidence_levels

  @doc """
  Checks if a value is a valid source type.
  """
  @spec valid_source_type?(term()) :: boolean()
  def valid_source_type?(type), do: type in @source_types

  @doc """
  Checks if a value is a valid context key.
  """
  @spec valid_context_key?(term()) :: boolean()
  def valid_context_key?(key), do: key in @context_keys

  # =============================================================================
  # Session ID Validation
  # =============================================================================

  # Maximum session ID length to prevent excessive atom/path creation
  @max_session_id_length 128

  # Pattern for valid session ID characters (alphanumeric, hyphens, underscores)
  @session_id_pattern ~r/\A[a-zA-Z0-9_-]+\z/

  @doc """
  Validates that a session ID is safe for use in atom names and file paths.

  Session IDs must:
  - Be a non-empty string
  - Contain only alphanumeric characters, hyphens, and underscores
  - Be no longer than #{@max_session_id_length} characters

  This prevents:
  - Atom exhaustion attacks (atoms are never garbage collected)
  - Path traversal attacks (e.g., "../../../etc/passwd")

  ## Examples

      iex> Types.valid_session_id?("session-123")
      true

      iex> Types.valid_session_id?("my_session_456")
      true

      iex> Types.valid_session_id?("../../../etc/passwd")
      false

      iex> Types.valid_session_id?("")
      false

  """
  @spec valid_session_id?(term()) :: boolean()
  def valid_session_id?(session_id) when is_binary(session_id) do
    byte_size(session_id) > 0 and
      byte_size(session_id) <= @max_session_id_length and
      Regex.match?(@session_id_pattern, session_id)
  end

  def valid_session_id?(_), do: false

  @doc """
  Returns the maximum allowed session ID length.
  """
  @spec max_session_id_length() :: pos_integer()
  def max_session_id_length, do: @max_session_id_length

  # Maximum memory ID length to prevent excessive string creation
  @max_memory_id_length 256

  # Pattern for valid memory ID characters (alphanumeric, hyphens, underscores)
  @memory_id_pattern ~r/\A[a-zA-Z0-9_-]+\z/

  @doc """
  Validates that a memory ID is safe for use in SPARQL queries.

  Memory IDs must:
  - Be a non-empty string
  - Contain only alphanumeric characters, hyphens, and underscores
  - Be no longer than #{@max_memory_id_length} characters

  This prevents:
  - SPARQL injection attacks
  - Path/IRI traversal attacks

  ## Examples

      iex> Types.valid_memory_id?("mem-123")
      true

      iex> Types.valid_memory_id?("my_memory_456")
      true

      iex> Types.valid_memory_id?("mem<script>alert(1)</script>")
      false

      iex> Types.valid_memory_id?("")
      false

  """
  @spec valid_memory_id?(term()) :: boolean()
  def valid_memory_id?(memory_id) when is_binary(memory_id) do
    byte_size(memory_id) > 0 and
      byte_size(memory_id) <= @max_memory_id_length and
      Regex.match?(@memory_id_pattern, memory_id)
  end

  def valid_memory_id?(_), do: false

  @doc """
  Returns the maximum allowed memory ID length.
  """
  @spec max_memory_id_length() :: pos_integer()
  def max_memory_id_length, do: @max_memory_id_length

  # =============================================================================
  # Session Memory Limits
  # =============================================================================

  # Maximum memories per session to prevent unbounded memory consumption.
  # This protects against runaway agents or malicious actors creating
  # excessive memories that could exhaust system resources.
  @default_max_memories_per_session 10_000

  @doc """
  Returns the default maximum number of memories allowed per session (10,000).

  This limit prevents unbounded memory growth from runaway agents or abuse.
  When exceeded, new memory creation will fail with `:session_memory_limit_exceeded`.
  """
  @spec default_max_memories_per_session() :: pos_integer()
  def default_max_memories_per_session, do: @default_max_memories_per_session

  # =============================================================================
  # Promotion Constants
  # =============================================================================

  @default_promotion_threshold 0.6
  @default_max_promotions_per_run 20

  @doc """
  Returns the default promotion threshold (0.6).

  Items with importance scores at or above this threshold are candidates
  for promotion to long-term storage.
  """
  @spec default_promotion_threshold() :: float()
  def default_promotion_threshold, do: @default_promotion_threshold

  @doc """
  Returns the default maximum promotions per run (20).
  """
  @spec default_max_promotions_per_run() :: pos_integer()
  def default_max_promotions_per_run, do: @default_max_promotions_per_run

  # =============================================================================
  # Utility Functions
  # =============================================================================

  @doc """
  Clamps a numeric value to the unit interval [0.0, 1.0].

  Used for confidence scores, importance scores, and similar bounded values.

  ## Examples

      iex> Types.clamp_to_unit(0.5)
      0.5

      iex> Types.clamp_to_unit(1.5)
      1.0

      iex> Types.clamp_to_unit(-0.3)
      0.0

  """
  @spec clamp_to_unit(number()) :: float()
  def clamp_to_unit(value) when is_number(value) and value < 0.0, do: 0.0
  def clamp_to_unit(value) when is_number(value) and value > 1.0, do: 1.0
  def clamp_to_unit(value) when is_number(value), do: value / 1

  # =============================================================================
  # Ontology Relationship Types
  # =============================================================================

  @typedoc """
  Ontology-defined relationships between memory items.

  These relationships map to object properties in the Jido ontology:

  - `:refines` - A hypothesis refines another hypothesis (jido-knowledge.ttl)
  - `:confirms` - Evidence confirms a fact (jido-knowledge.ttl)
  - `:contradicts` - Evidence contradicts a memory item (jido-knowledge.ttl)
  - `:has_alternative` - A decision has an alternative option (jido-decision.ttl)
  - `:selected_alternative` - The alternative selected for a decision (jido-decision.ttl)
  - `:has_trade_off` - A decision has a trade-off (jido-decision.ttl)
  - `:justified_by` - A decision is justified by something (jido-decision.ttl)
  - `:has_root_cause` - An error has a root cause (jido-error.ttl)
  - `:produced_lesson` - An error produced a lesson learned (jido-error.ttl)
  - `:related_error` - Links related or cascading errors (jido-error.ttl)
  - `:derived_from` - A memory derived from evidence (jido-code.ttl)
  - `:superseded_by` - A memory superseded by another (jido-code.ttl)
  """
  @type relationship ::
          :refines
          | :confirms
          | :contradicts
          | :has_alternative
          | :selected_alternative
          | :has_trade_off
          | :justified_by
          | :has_root_cause
          | :produced_lesson
          | :related_error
          | :derived_from
          | :superseded_by

  @relationships [
    :refines,
    :confirms,
    :contradicts,
    :has_alternative,
    :selected_alternative,
    :has_trade_off,
    :justified_by,
    :has_root_cause,
    :produced_lesson,
    :related_error,
    :derived_from,
    :superseded_by
  ]

  # Relationship to IRI property mapping (camelCase ontology form)
  @relationship_to_property_map %{
    refines: "refines",
    confirms: "confirms",
    contradicts: "contradicts",
    has_alternative: "hasAlternative",
    selected_alternative: "selectedAlternative",
    has_trade_off: "hasTradeOff",
    justified_by: "justifiedBy",
    has_root_cause: "hasRootCause",
    produced_lesson: "producedLesson",
    related_error: "relatedError",
    derived_from: "derivedFrom",
    superseded_by: "supersededBy"
  }

  @property_to_relationship_map %{
    "refines" => :refines,
    "confirms" => :confirms,
    "contradicts" => :contradicts,
    "hasAlternative" => :has_alternative,
    "selectedAlternative" => :selected_alternative,
    "hasTradeOff" => :has_trade_off,
    "justifiedBy" => :justified_by,
    "hasRootCause" => :has_root_cause,
    "producedLesson" => :produced_lesson,
    "relatedError" => :related_error,
    "derivedFrom" => :derived_from,
    "supersededBy" => :superseded_by
  }

  @doc """
  Returns all valid relationship types.
  """
  @spec relationships() :: [relationship()]
  def relationships, do: @relationships

  @doc """
  Checks if a value is a valid relationship type.
  """
  @spec valid_relationship?(term()) :: boolean()
  def valid_relationship?(rel), do: rel in @relationships

  @doc """
  Converts a relationship atom to its ontology property name (camelCase).

  ## Examples

      iex> Types.relationship_to_property(:has_alternative)
      "hasAlternative"

      iex> Types.relationship_to_property(:refines)
      "refines"

  """
  @spec relationship_to_property(relationship()) :: String.t()
  def relationship_to_property(rel) do
    Map.get(@relationship_to_property_map, rel, Macro.camelize(to_string(rel)))
  end

  @doc """
  Converts an ontology property name to its relationship atom.

  ## Examples

      iex> Types.property_to_relationship("hasAlternative")
      :has_alternative

      iex> Types.property_to_relationship("refines")
      :refines

  """
  @spec property_to_relationship(String.t()) :: relationship()
  def property_to_relationship(prop) when is_binary(prop) do
    Map.get(@property_to_relationship_map, prop)
  end

  # =============================================================================
  # Ontology Individual Types
  # =============================================================================

  @typedoc """
  Evidence strength levels from jido-knowledge.ttl.

  Individuals: WeakEvidence, ModerateEvidence, StrongEvidence
  """
  @type evidence_strength :: :weak | :moderate | :strong

  @evidence_strengths [:weak, :moderate, :strong]

  @doc """
  Returns all valid evidence strength levels.
  """
  @spec evidence_strengths() :: [evidence_strength()]
  def evidence_strengths, do: @evidence_strengths

  @doc """
  Checks if a value is a valid evidence strength.
  """
  @spec valid_evidence_strength?(term()) :: boolean()
  def valid_evidence_strength?(strength), do: strength in @evidence_strengths

  @typedoc """
  Convention scope levels from jido-convention.ttl.

  Individuals: GlobalScope, ProjectScope, AgentScope
  """
  @type convention_scope :: :global | :project | :agent

  @convention_scopes [:global, :project, :agent]

  @doc """
  Returns all valid convention scopes.
  """
  @spec convention_scopes() :: [convention_scope()]
  def convention_scopes, do: @convention_scopes

  @doc """
  Checks if a value is a valid convention scope.
  """
  @spec valid_convention_scope?(term()) :: boolean()
  def valid_convention_scope?(scope), do: scope in @convention_scopes

  @typedoc """
  Enforcement levels from jido-convention.ttl.

  Individuals: Advisory, Required, Strict
  """
  @type enforcement_level :: :advisory | :required | :strict

  @enforcement_levels [:advisory, :required, :strict]

  @doc """
  Returns all valid enforcement levels.
  """
  @spec enforcement_levels() :: [enforcement_level()]
  def enforcement_levels, do: @enforcement_levels

  @doc """
  Checks if a value is a valid enforcement level.
  """
  @spec valid_enforcement_level?(term()) :: boolean()
  def valid_enforcement_level?(level), do: level in @enforcement_levels

  @typedoc """
  Error status levels from jido-error.ttl.

  Individuals: Reported, Investigating, Resolved, Deferred
  """
  @type error_status :: :reported | :investigating | :resolved | :deferred

  @error_statuses [:reported, :investigating, :resolved, :deferred]

  @doc """
  Returns all valid error statuses.
  """
  @spec error_statuses() :: [error_status()]
  def error_statuses, do: @error_statuses

  @doc """
  Checks if a value is a valid error status.
  """
  @spec valid_error_status?(term()) :: boolean()
  def valid_error_status?(status), do: status in @error_statuses

  # =============================================================================
  # Memory Type to IRI Conversions
  # =============================================================================

  @jido_ns "https://jido.ai/ontology#"

  @doc """
  Returns the Jido ontology namespace IRI.
  """
  @spec namespace() :: String.t()
  def namespace, do: @jido_ns

  # Memory type to ontology class name mapping
  @memory_type_to_class_map %{
    # Knowledge types
    fact: "Fact",
    assumption: "Assumption",
    hypothesis: "Hypothesis",
    discovery: "Discovery",
    risk: "Risk",
    unknown: "Unknown",
    # Decision types
    decision: "Decision",
    architectural_decision: "ArchitecturalDecision",
    implementation_decision: "ImplementationDecision",
    alternative: "Alternative",
    trade_off: "TradeOff",
    # Convention types
    convention: "Convention",
    coding_standard: "CodingStandard",
    architectural_convention: "ArchitecturalConvention",
    agent_rule: "AgentRule",
    process_convention: "ProcessConvention",
    # Error types
    error: "Error",
    bug: "Bug",
    failure: "Failure",
    incident: "Incident",
    root_cause: "RootCause",
    lesson_learned: "LessonLearned"
  }

  @class_to_memory_type_map %{
    "Fact" => :fact,
    "Assumption" => :assumption,
    "Hypothesis" => :hypothesis,
    "Discovery" => :discovery,
    "Risk" => :risk,
    "Unknown" => :unknown,
    "Decision" => :decision,
    "ArchitecturalDecision" => :architectural_decision,
    "ImplementationDecision" => :implementation_decision,
    "Alternative" => :alternative,
    "TradeOff" => :trade_off,
    "Convention" => :convention,
    "CodingStandard" => :coding_standard,
    "ArchitecturalConvention" => :architectural_convention,
    "AgentRule" => :agent_rule,
    "ProcessConvention" => :process_convention,
    "Error" => :error,
    "Bug" => :bug,
    "Failure" => :failure,
    "Incident" => :incident,
    "RootCause" => :root_cause,
    "LessonLearned" => :lesson_learned
  }

  @doc """
  Converts a memory type atom to its Jido ontology class name.

  ## Examples

      iex> Types.memory_type_to_class(:fact)
      "Fact"

      iex> Types.memory_type_to_class(:implementation_decision)
      "ImplementationDecision"

  """
  @spec memory_type_to_class(memory_type()) :: String.t()
  def memory_type_to_class(type) do
    Map.get(@memory_type_to_class_map, type, Macro.camelize(to_string(type)))
  end

  @doc """
  Converts a Jido ontology class IRI or name to its memory type atom.

  ## Examples

      iex> Types.class_to_memory_type("https://jido.ai/ontology#Fact")
      :fact

      iex> Types.class_to_memory_type("Fact")
      :fact

  """
  @spec class_to_memory_type(String.t()) :: memory_type()
  def class_to_memory_type(class) when is_binary(class) do
    local_name = extract_local_name(class)
    Map.get(@class_to_memory_type_map, local_name, :unknown)
  end

  @doc """
  Converts a memory type atom to its full Jido ontology IRI.

  ## Examples

      iex> Types.memory_type_to_iri(:fact)
      "https://jido.ai/ontology#Fact"

      iex> Types.memory_type_to_iri(:implementation_decision)
      "https://jido.ai/ontology#ImplementationDecision"

  """
  @spec memory_type_to_iri(memory_type()) :: String.t()
  def memory_type_to_iri(type) do
    @jido_ns <> memory_type_to_class(type)
  end

  @doc """
  Converts a Jido ontology IRI to its memory type atom.

  ## Examples

      iex> Types.iri_to_memory_type("https://jido.ai/ontology#Fact")
      :fact

      iex> Types.iri_to_memory_type("https://jido.ai/ontology#ImplementationDecision")
      :implementation_decision

  """
  @spec iri_to_memory_type(String.t()) :: memory_type()
  def iri_to_memory_type(iri) when is_binary(iri) do
    class_to_memory_type(iri)
  end

  @doc """
  Converts a relationship atom to its full Jido ontology IRI.

  ## Examples

      iex> Types.relationship_to_iri(:has_alternative)
      "https://jido.ai/ontology#hasAlternative"

  """
  @spec relationship_to_iri(relationship()) :: String.t()
  def relationship_to_iri(rel) do
    @jido_ns <> relationship_to_property(rel)
  end

  @doc """
  Converts a Jido ontology property IRI to its relationship atom.

  ## Examples

      iex> Types.iri_to_relationship("https://jido.ai/ontology#hasAlternative")
      :has_alternative

  """
  @spec iri_to_relationship(String.t()) :: relationship()
  def iri_to_relationship(iri) when is_binary(iri) do
    local_name = extract_local_name(iri)
    property_to_relationship(local_name)
  end

  # Extract local name from IRI (after #)
  defp extract_local_name(iri) when is_binary(iri) do
    if String.contains?(iri, "#") do
      iri |> String.split("#") |> List.last()
    else
      iri
    end
  end
end
