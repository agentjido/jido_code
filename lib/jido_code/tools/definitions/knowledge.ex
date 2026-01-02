defmodule JidoCode.Tools.Definitions.Knowledge do
  @moduledoc """
  Tool definitions for knowledge graph operations.

  This module defines tools for storing and querying knowledge in the
  long-term memory system using the Jido ontology.

  ## Available Tools

  - `knowledge_remember` - Store new knowledge with ontology typing
  - `knowledge_recall` - Query knowledge with semantic filters

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
      knowledge_recall()
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
end
