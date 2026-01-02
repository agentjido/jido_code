defmodule JidoCode.Tools.Definitions.Knowledge do
  @moduledoc """
  Tool definitions for knowledge graph operations.

  This module defines tools for storing and querying knowledge in the
  long-term memory system using the Jido ontology.

  ## Available Tools

  - `knowledge_remember` - Store new knowledge with ontology typing
  - `knowledge_recall` - Query knowledge with semantic filters
  - `knowledge_supersede` - Mark knowledge as outdated and optionally replace
  - `knowledge_update` - Update confidence or add evidence to existing knowledge
  - `project_conventions` - Retrieve project conventions and coding standards
  - `project_decisions` - Retrieve architectural and implementation decisions
  - `project_risks` - Retrieve known risks and potential issues

  ## Memory Types

  The following memory types are supported (from the Jido ontology):

  **Knowledge Types:**
  - `:fact` - Verified or strongly established knowledge
  - `:assumption` - Unverified belief held for working purposes
  - `:hypothesis` - Testable theory or explanation
  - `:discovery` - Newly uncovered important information
  - `:risk` - Potential future negative outcome
  - `:unknown` - Known unknown; explicitly acknowledged knowledge gap

  **Convention Types:**
  - `:convention` - General project-wide or system-wide standard
  - `:coding_standard` - Convention related to coding style or structure

  **Decision Types:**
  - `:decision` - General committed choice impacting the project
  - `:architectural_decision` - High-impact structural or architectural choice
  - `:lesson_learned` - Insights gained from past experiences

  ## Usage

      # Register all knowledge tools
      for tool <- Knowledge.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      remember_tool = Knowledge.knowledge_remember()
      :ok = Registry.register(remember_tool)
  """

  alias JidoCode.Tools.Handlers.Knowledge, as: Handlers
  alias JidoCode.Tools.Tool

  @memory_type_description """
  Memory type classification. One of:
  - fact: Verified, objective information
  - assumption: Inferred information that may need verification
  - hypothesis: Proposed explanation being tested
  - discovery: Newly found information worth remembering
  - risk: Potential issue or concern identified
  - unknown: Information gap that needs investigation
  - decision: Choice made with rationale
  - architectural_decision: Significant architectural choice
  - convention: Established pattern or standard
  - coding_standard: Specific coding practice or guideline
  - lesson_learned: Insight gained from experience
  """

  @doc """
  Returns all knowledge tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      knowledge_remember(),
      knowledge_recall(),
      knowledge_supersede(),
      knowledge_update(),
      project_conventions(),
      project_decisions(),
      project_risks()
    ]
  end

  @doc """
  Returns the knowledge_remember tool definition.

  Stores new knowledge in the long-term memory system with full ontology support.

  ## Parameters

  - `content` (required, string) - The knowledge content to store
  - `type` (required, string) - Memory type classification
  - `confidence` (optional, float) - Confidence level 0.0-1.0
  - `rationale` (optional, string) - Explanation for why this is worth remembering
  - `evidence_refs` (optional, array) - References to supporting evidence
  - `related_to` (optional, string) - ID of related memory item for linking

  ## Output

  Returns JSON with memory_id, type, and confidence.
  """
  @spec knowledge_remember() :: Tool.t()
  def knowledge_remember do
    Tool.new!(%{
      name: "knowledge_remember",
      description:
        "Store knowledge for future reference. Use this to remember important facts, " <>
          "decisions, conventions, risks, or discoveries about the project. " <>
          "The knowledge will be persisted and can be recalled later.",
      handler: Handlers.KnowledgeRemember,
      parameters: [
        %{
          name: "content",
          type: :string,
          description: "The knowledge content to store (what you want to remember)",
          required: true
        },
        %{
          name: "type",
          type: :string,
          description: @memory_type_description,
          required: true
        },
        %{
          name: "confidence",
          type: :number,
          description:
            "Confidence level from 0.0 to 1.0. Defaults based on type: " <>
              "facts=0.8, assumptions/hypotheses=0.5, risks=0.6, others=0.7",
          required: false
        },
        %{
          name: "rationale",
          type: :string,
          description: "Explanation for why this knowledge is worth remembering",
          required: false
        },
        %{
          name: "evidence_refs",
          type: :array,
          description:
            "References to supporting evidence (file paths, URLs, or memory IDs)",
          required: false
        },
        %{
          name: "related_to",
          type: :string,
          description: "ID of a related memory item to link this knowledge to",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the knowledge_recall tool definition.

  Queries the knowledge graph with semantic filters to retrieve previously
  stored knowledge.

  ## Parameters

  - `query` (optional, string) - Text search within memory content
  - `types` (optional, array) - Filter by memory types
  - `min_confidence` (optional, float) - Minimum confidence threshold
  - `project_scope` (optional, boolean) - Search across all sessions for this project
  - `include_superseded` (optional, boolean) - Include superseded memories
  - `limit` (optional, integer) - Maximum results to return

  ## Output

  Returns JSON array of memories with id, content, type, confidence, timestamp.
  """
  @spec knowledge_recall() :: Tool.t()
  def knowledge_recall do
    Tool.new!(%{
      name: "knowledge_recall",
      description:
        "Search for previously stored knowledge. Use this to retrieve facts, " <>
          "decisions, conventions, risks, or other knowledge about the project. " <>
          "Can filter by type, confidence, or search within content.",
      handler: Handlers.KnowledgeRecall,
      parameters: [
        %{
          name: "query",
          type: :string,
          description: "Text search within memory content (case-insensitive substring match)",
          required: false
        },
        %{
          name: "types",
          type: :array,
          description:
            "Filter by memory types. Example: [\"fact\", \"decision\"]. " <>
              "See knowledge_remember for valid types.",
          required: false
        },
        %{
          name: "min_confidence",
          type: :number,
          description: "Minimum confidence threshold, 0.0 to 1.0 (default: 0.5)",
          required: false
        },
        %{
          name: "project_scope",
          type: :boolean,
          description:
            "If true, search across all sessions for this project. " <>
              "If false (default), search only current session.",
          required: false
        },
        %{
          name: "include_superseded",
          type: :boolean,
          description: "Include superseded/outdated memories (default: false)",
          required: false
        },
        %{
          name: "limit",
          type: :integer,
          description: "Maximum number of results to return (default: 10)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the knowledge_supersede tool definition.

  Marks existing knowledge as outdated and optionally creates a replacement.
  The old memory is marked as superseded but not deleted, preserving history.

  ## Parameters

  - `old_memory_id` (required, string) - ID of the memory to supersede
  - `new_content` (optional, string) - Content for replacement memory
  - `new_type` (optional, string) - Type for replacement (defaults to original)
  - `reason` (optional, string) - Reason for superseding

  ## Output

  Returns JSON with old_id, new_id (if replacement created), and status.
  """
  @spec knowledge_supersede() :: Tool.t()
  def knowledge_supersede do
    Tool.new!(%{
      name: "knowledge_supersede",
      description:
        "Mark existing knowledge as outdated. Use this when information has changed " <>
          "or a decision has been revised. Optionally provide new content to create " <>
          "a replacement memory that links to the original.",
      handler: Handlers.KnowledgeSupersede,
      parameters: [
        %{
          name: "old_memory_id",
          type: :string,
          description: "ID of the memory to mark as superseded",
          required: true
        },
        %{
          name: "new_content",
          type: :string,
          description:
            "Content for the replacement memory. If provided, a new memory will be " <>
              "created and linked to the superseded one.",
          required: false
        },
        %{
          name: "new_type",
          type: :string,
          description:
            "Type for the replacement memory. Defaults to the same type as the original. " <>
              "See knowledge_remember for valid types.",
          required: false
        },
        %{
          name: "reason",
          type: :string,
          description: "Explanation for why this knowledge is being superseded",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the project_conventions tool definition.

  Retrieves all conventions and coding standards stored for the project.
  Conventions define established patterns, rules, and standards that should
  be followed consistently.

  ## Parameters

  - `category` (optional, string) - Filter by category: coding, architectural, agent, process
  - `min_confidence` (optional, float) - Minimum confidence threshold

  ## Output

  Returns JSON with list of conventions including content, type, and confidence.
  """
  @spec project_conventions() :: Tool.t()
  def project_conventions do
    Tool.new!(%{
      name: "project_conventions",
      description:
        "Retrieve conventions and coding standards for the project. Use this to find " <>
          "established patterns, coding guidelines, architectural rules, or process " <>
          "conventions that should be followed.",
      handler: Handlers.ProjectConventions,
      parameters: [
        %{
          name: "category",
          type: :string,
          description:
            "Filter by convention category: 'coding' for coding_standard, " <>
              "'architectural' for architectural patterns, 'agent' for agent rules, " <>
              "'process' for workflow conventions, or omit for all.",
          required: false
        },
        %{
          name: "min_confidence",
          type: :number,
          description: "Minimum confidence threshold, 0.0 to 1.0 (default: 0.5)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the knowledge_update tool definition.

  Updates confidence level or adds evidence to existing knowledge without
  replacing the entire memory. Use this to strengthen or weaken confidence
  based on new information.

  ## Parameters

  - `memory_id` (required, string) - ID of the memory to update
  - `new_confidence` (optional, float) - New confidence level (0.0-1.0)
  - `add_evidence` (optional, array) - Evidence references to add
  - `add_rationale` (optional, string) - Additional rationale to append

  ## Output

  Returns JSON with the updated memory's id, confidence, and rationale.
  """
  @spec knowledge_update() :: Tool.t()
  def knowledge_update do
    Tool.new!(%{
      name: "knowledge_update",
      description:
        "Update confidence level or add evidence to existing knowledge. " <>
          "Use this to strengthen or weaken confidence based on new information, " <>
          "or to add supporting evidence without replacing the memory.",
      handler: Handlers.KnowledgeUpdate,
      parameters: [
        %{
          name: "memory_id",
          type: :string,
          description: "ID of the memory to update",
          required: true
        },
        %{
          name: "new_confidence",
          type: :number,
          description: "New confidence level, 0.0 to 1.0",
          required: false
        },
        %{
          name: "add_evidence",
          type: :array,
          description: "Evidence references to add (file paths, URLs, or memory IDs)",
          required: false
        },
        %{
          name: "add_rationale",
          type: :string,
          description: "Additional rationale to append to existing rationale",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the project_decisions tool definition.

  Retrieves architectural and implementation decisions recorded for the project.
  Decisions capture important choices made during development along with their
  rationale.

  ## Parameters

  - `include_superseded` (optional, boolean) - Include superseded decisions (default: false)
  - `decision_type` (optional, string) - Filter: architectural, implementation, or all
  - `include_alternatives` (optional, boolean) - Include considered alternatives (default: false)

  ## Output

  Returns JSON with list of decisions including content, type, rationale, and confidence.
  """
  @spec project_decisions() :: Tool.t()
  def project_decisions do
    Tool.new!(%{
      name: "project_decisions",
      description:
        "Retrieve architectural and implementation decisions for the project. " <>
          "Use this to find past decisions, their rationale, and alternatives considered.",
      handler: Handlers.ProjectDecisions,
      parameters: [
        %{
          name: "include_superseded",
          type: :boolean,
          description: "Include superseded/outdated decisions (default: false)",
          required: false
        },
        %{
          name: "decision_type",
          type: :string,
          description:
            "Filter by decision type: 'architectural' for high-level structural choices, " <>
              "'implementation' for lower-level choices, or omit for all decisions.",
          required: false
        },
        %{
          name: "include_alternatives",
          type: :boolean,
          description: "Include alternative options that were considered (default: false)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the project_risks tool definition.

  Retrieves known risks and potential issues identified for the project.
  Risks are sorted by confidence (severity/likelihood) in descending order.

  ## Parameters

  - `min_confidence` (optional, float) - Minimum confidence threshold (default: 0.5)
  - `include_mitigated` (optional, boolean) - Include mitigated/superseded risks (default: false)

  ## Output

  Returns JSON with list of risks including content, confidence, and rationale.
  """
  @spec project_risks() :: Tool.t()
  def project_risks do
    Tool.new!(%{
      name: "project_risks",
      description:
        "Retrieve known risks and potential issues for the project. " <>
          "Use this to review identified risks, their severity, and mitigation status. " <>
          "Risks are sorted by confidence (severity/likelihood) with highest first.",
      handler: Handlers.ProjectRisks,
      parameters: [
        %{
          name: "min_confidence",
          type: :number,
          description: "Minimum confidence threshold, 0.0 to 1.0 (default: 0.5)",
          required: false
        },
        %{
          name: "include_mitigated",
          type: :boolean,
          description: "Include mitigated/superseded risks (default: false)",
          required: false
        }
      ]
    })
  end
end
