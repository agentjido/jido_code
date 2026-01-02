defmodule JidoCode.Tools.Handlers.Knowledge do
  @moduledoc """
  Handler modules for knowledge graph tools.

  This module contains handlers for storing and querying knowledge in the
  long-term memory system using the Jido ontology.

  ## Session Context

  Handlers require a `session_id` in the context map to identify which
  session's memory store to use. The Memory module handles store creation
  and access automatically.

  ## Available Handlers

  - `KnowledgeRemember` - Stores new knowledge with ontology typing
  - `KnowledgeRecall` - Queries knowledge with semantic filters
  - `KnowledgeSupersede` - Marks knowledge as outdated, optionally replaces
  - `KnowledgeUpdate` - Updates confidence/evidence on existing knowledge
  - `ProjectConventions` - Retrieves project conventions and standards
  - `ProjectDecisions` - Retrieves architectural and implementation decisions
  - `ProjectRisks` - Retrieves known risks and issues
  - `KnowledgeGraphQuery` - Traverses knowledge graph relationships

  ## Usage

  These handlers are invoked by the Executor when the LLM calls knowledge tools:

      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "knowledge_remember",
        arguments: %{"content" => "Phoenix uses Elixir", "type" => "fact"}
      }, context: context)

  """

  alias JidoCode.Memory
  alias JidoCode.Memory.Types

  # Default confidence values by memory type
  @default_confidence %{
    fact: 0.8,
    assumption: 0.5,
    hypothesis: 0.5,
    discovery: 0.7,
    risk: 0.6,
    unknown: 0.4,
    decision: 0.8,
    architectural_decision: 0.8,
    convention: 0.8,
    coding_standard: 0.8,
    lesson_learned: 0.7
  }

  # Maximum content size in bytes (64KB)
  @max_content_size 65_536

  # ============================================================================
  # Telemetry
  # ============================================================================

  @doc false
  @spec emit_knowledge_telemetry(atom(), integer(), map(), atom()) :: :ok
  def emit_knowledge_telemetry(operation, start_time, context, status) do
    duration = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      [:jido_code, :knowledge, operation],
      %{duration: duration},
      %{
        status: status,
        session_id: Map.get(context, :session_id)
      }
    )
  end

  @doc """
  Wraps an operation with telemetry emission.

  ## Parameters

  - `operation` - Atom identifying the operation (e.g., :remember, :recall)
  - `context` - Context map containing session_id
  - `fun` - Zero-arity function to execute

  ## Returns

  The result of `fun.()` after emitting telemetry.
  """
  @spec with_telemetry(atom(), map(), (-> any())) :: any()
  def with_telemetry(operation, context, fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    status = if match?({:ok, _}, result), do: :success, else: :error
    emit_knowledge_telemetry(operation, start_time, context, status)
    result
  end

  # ============================================================================
  # Shared Session Validation
  # ============================================================================

  @doc """
  Validates and extracts session_id from context.

  ## Parameters

  - `context` - Context map that should contain `:session_id`
  - `tool_name` - Name of the tool for error messages

  ## Returns

  - `{:ok, session_id}` - Valid non-empty session ID string
  - `{:error, message}` - Error with descriptive message
  """
  @spec get_session_id(map(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_session_id(%{session_id: session_id}, tool_name) when is_binary(session_id) do
    if byte_size(session_id) > 0 do
      {:ok, session_id}
    else
      {:error, "#{tool_name} requires a non-empty session_id"}
    end
  end

  def get_session_id(_context, tool_name) do
    {:error, "#{tool_name} requires a session context"}
  end

  # ============================================================================
  # Shared Type Normalization
  # ============================================================================

  @doc """
  Safely converts a type string to an existing atom.

  Normalizes the string by downcasing and replacing hyphens with underscores.
  Returns `{:error, reason}` if the atom doesn't exist (preventing atom exhaustion).

  ## Parameters

  - `type_str` - String to convert

  ## Returns

  - `{:ok, atom}` - Successfully converted atom
  - `{:error, reason}` - Atom doesn't exist or invalid input
  """
  @spec safe_to_type_atom(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def safe_to_type_atom(type_str) when is_binary(type_str) do
    normalized =
      type_str
      |> String.downcase()
      |> String.replace("-", "_")

    # Check if atom exists without creating it
    if atom_exists?(normalized) do
      {:ok, String.to_existing_atom(normalized)}
    else
      {:error, "unknown type: #{type_str}"}
    end
  end

  def safe_to_type_atom(_), do: {:error, "type must be a string"}

  # Check if an atom exists without creating it
  defp atom_exists?(string) do
    try do
      _ = String.to_existing_atom(string)
      true
    rescue
      ArgumentError -> false
    end
  end

  # ============================================================================
  # Content Validation
  # ============================================================================

  @doc """
  Validates content string is non-empty and within size limits.

  ## Parameters

  - `content` - Content string to validate

  ## Returns

  - `{:ok, content}` - Valid content
  - `{:error, message}` - Error with descriptive message
  """
  @spec validate_content(any()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_content(nil), do: {:error, "content is required"}
  def validate_content(""), do: {:error, "content cannot be empty"}

  def validate_content(content) when is_binary(content) do
    if byte_size(content) > @max_content_size do
      {:error, "content exceeds maximum size of #{@max_content_size} bytes"}
    else
      {:ok, content}
    end
  end

  def validate_content(_), do: {:error, "content must be a string"}

  @doc """
  Returns the maximum allowed content size in bytes.
  """
  @spec max_content_size() :: pos_integer()
  def max_content_size, do: @max_content_size

  # ============================================================================
  # Timestamp Formatting
  # ============================================================================

  @doc """
  Safely formats a DateTime to ISO8601 string, handling nil values.

  ## Parameters

  - `datetime` - DateTime struct or nil

  ## Returns

  - ISO8601 string or nil
  """
  @spec format_timestamp(DateTime.t() | nil) :: String.t() | nil
  def format_timestamp(nil), do: nil
  def format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  # ============================================================================
  # KnowledgeRemember Handler
  # ============================================================================

  defmodule KnowledgeRemember do
    @moduledoc """
    Handler for storing knowledge in long-term memory.

    Validates the memory type against the Jido ontology, applies default
    confidence based on type, and persists to the session's memory store.
    """

    alias JidoCode.Tools.Handlers.Knowledge

    @doc """
    Executes the knowledge_remember tool.

    ## Parameters

    - `args` - Map containing:
      - `"content"` (required) - Knowledge content to store
      - `"type"` (required) - Memory type classification
      - `"confidence"` (optional) - Confidence level 0.0-1.0
      - `"rationale"` (optional) - Explanation for remembering
      - `"evidence_refs"` (optional) - List of evidence references
      - `"related_to"` (optional) - Related memory ID

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier

    ## Returns

    - `{:ok, json}` - JSON with memory_id, type, confidence
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:remember, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "knowledge_remember"),
           {:ok, content} <- Knowledge.validate_content(Map.get(args, "content")),
           {:ok, memory_type} <- parse_memory_type(args),
           {:ok, confidence} <- parse_confidence(args, memory_type) do
        memory_id = Knowledge.generate_memory_id()

        memory_input = %{
          id: memory_id,
          content: content,
          memory_type: memory_type,
          confidence: confidence,
          source_type: :agent,
          session_id: session_id,
          created_at: DateTime.utc_now(),
          rationale: Map.get(args, "rationale"),
          evidence_refs: Map.get(args, "evidence_refs", []),
          project_id: Map.get(context, :project_id)
        }

        # Handle related_to linking (stored as part of evidence for now)
        memory_input =
          case Map.get(args, "related_to") do
            nil -> memory_input
            related_id -> Map.update!(memory_input, :evidence_refs, &[related_id | &1])
          end

        case Memory.persist(memory_input, session_id) do
          {:ok, ^memory_id} ->
            result = %{
              memory_id: memory_id,
              type: Atom.to_string(memory_type),
              confidence: confidence,
              status: "stored"
            }

            {:ok, Jason.encode!(result)}

          {:error, :invalid_memory_type} ->
            {:error, "Invalid memory type: #{args["type"]}. Valid types: #{valid_types_string()}"}

          {:error, :invalid_confidence} ->
            {:error, "Confidence must be between 0.0 and 1.0"}

          {:error, :session_memory_limit_exceeded} ->
            {:error, "Session memory limit exceeded. Consider superseding old memories."}

          {:error, reason} ->
            {:error, "Failed to store memory: #{inspect(reason)}"}
        end
      end
    end

    defp parse_memory_type(args) do
      case Map.get(args, "type") do
        nil ->
          {:error, "type is required"}

        type_string when is_binary(type_string) ->
          case Knowledge.safe_to_type_atom(type_string) do
            {:ok, type_atom} ->
              if Types.valid_memory_type?(type_atom) do
                {:ok, type_atom}
              else
                {:error, "Invalid memory type: #{type_string}. Valid types: #{valid_types_string()}"}
              end

            {:error, _reason} ->
              {:error, "Invalid memory type: #{type_string}. Valid types: #{valid_types_string()}"}
          end

        _ ->
          {:error, "type must be a string"}
      end
    end

    defp parse_confidence(args, memory_type) do
      case Map.get(args, "confidence") do
        nil ->
          {:ok, Map.get(Knowledge.default_confidence(), memory_type, 0.7)}

        confidence when is_number(confidence) and confidence >= 0.0 and confidence <= 1.0 ->
          {:ok, confidence}

        confidence when is_number(confidence) ->
          {:error, "Confidence must be between 0.0 and 1.0, got: #{confidence}"}

        _ ->
          {:error, "Confidence must be a number between 0.0 and 1.0"}
      end
    end

    defp valid_types_string do
      Types.memory_types()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(", ")
    end
  end

  # ============================================================================
  # KnowledgeRecall Handler
  # ============================================================================

  defmodule KnowledgeRecall do
    @moduledoc """
    Handler for querying knowledge from long-term memory.

    Supports filtering by type, confidence threshold, text search,
    and cross-session project queries.
    """

    alias JidoCode.Tools.Handlers.Knowledge

    @doc """
    Executes the knowledge_recall tool.

    ## Parameters

    - `args` - Map containing:
      - `"query"` (optional) - Text search within content
      - `"types"` (optional) - List of memory type strings to filter by
      - `"min_confidence"` (optional) - Minimum confidence threshold
      - `"project_scope"` (optional) - Search across project sessions
      - `"include_superseded"` (optional) - Include superseded memories
      - `"limit"` (optional) - Maximum results (default: 10)

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier
      - `:project_id` (optional) - Project identifier for project_scope

    ## Returns

    - `{:ok, json}` - JSON array of memories
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:recall, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "knowledge_recall"),
           {:ok, opts} <- build_query_opts(args) do
        # Query memories
        case Memory.query(session_id, opts) do
          {:ok, memories} ->
            memories
            |> apply_text_filter(Map.get(args, "query"))
            |> apply_type_filter(Map.get(args, "types"))
            |> apply_limit(Map.get(args, "limit", 10))
            |> format_results()

          {:error, reason} ->
            {:error, "Failed to query memories: #{inspect(reason)}"}
        end
      end
    end

    defp build_query_opts(args) do
      opts =
        []
        |> add_min_confidence(Map.get(args, "min_confidence"))
        |> add_include_superseded(Map.get(args, "include_superseded"))

      {:ok, opts}
    end

    defp add_min_confidence(opts, nil), do: Keyword.put(opts, :min_confidence, 0.5)
    defp add_min_confidence(opts, conf) when is_number(conf), do: Keyword.put(opts, :min_confidence, conf)
    defp add_min_confidence(opts, _), do: opts

    defp add_include_superseded(opts, true), do: Keyword.put(opts, :include_superseded, true)
    defp add_include_superseded(opts, _), do: Keyword.put(opts, :include_superseded, false)

    defp apply_text_filter(memories, nil), do: memories
    defp apply_text_filter(memories, ""), do: memories

    defp apply_text_filter(memories, query_text) do
      query_lower = String.downcase(query_text)

      Enum.filter(memories, fn memory ->
        content_lower = String.downcase(memory.content || "")
        String.contains?(content_lower, query_lower)
      end)
    end

    defp apply_type_filter(memories, nil), do: memories
    defp apply_type_filter(memories, []), do: memories

    defp apply_type_filter(memories, types) when is_list(types) do
      type_atoms =
        types
        |> Enum.reduce(MapSet.new(), fn type_str, acc ->
          case Knowledge.safe_to_type_atom(type_str) do
            {:ok, atom} -> MapSet.put(acc, atom)
            {:error, _} -> acc
          end
        end)

      # If no valid types found, return all memories
      if MapSet.size(type_atoms) == 0 do
        memories
      else
        Enum.filter(memories, fn memory ->
          MapSet.member?(type_atoms, memory.memory_type)
        end)
      end
    end

    defp apply_type_filter(memories, _), do: memories

    defp apply_limit(memories, limit) when is_integer(limit) and limit > 0 do
      Enum.take(memories, limit)
    end

    defp apply_limit(memories, _), do: Enum.take(memories, 10)

    defp format_results(memories) do
      Knowledge.format_memory_list(memories, :memories)
    end
  end

  # ============================================================================
  # KnowledgeSupersede Handler
  # ============================================================================

  defmodule KnowledgeSupersede do
    @moduledoc """
    Handler for marking knowledge as superseded.

    Marks existing memories as outdated and optionally creates a replacement
    memory that is linked to the original. The superseded memory is not deleted,
    preserving history.
    """

    alias JidoCode.Tools.Handlers.Knowledge

    @doc """
    Executes the knowledge_supersede tool.

    ## Parameters

    - `args` - Map containing:
      - `"old_memory_id"` (required) - ID of memory to supersede
      - `"new_content"` (optional) - Content for replacement memory
      - `"new_type"` (optional) - Type for replacement (defaults to original)
      - `"reason"` (optional) - Reason for superseding

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier

    ## Returns

    - `{:ok, json}` - JSON with old_id, new_id (if created), status
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:supersede, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "knowledge_supersede"),
           {:ok, old_memory_id} <- Knowledge.get_required_string(args, "old_memory_id"),
           {:ok, _} <- Knowledge.validate_memory_id(old_memory_id),
           {:ok, old_memory} <- Knowledge.get_memory(session_id, old_memory_id) do
        # Mark the old memory as superseded
        case Memory.supersede(session_id, old_memory_id, nil) do
          :ok ->
            # Check if we need to create a replacement
            case Map.get(args, "new_content") do
              nil ->
                # No replacement, just superseded
                Knowledge.ok_json(%{
                  old_id: old_memory_id,
                  new_id: nil,
                  status: "superseded"
                })

              new_content ->
                create_replacement(args, context, session_id, old_memory, new_content)
            end

          {:error, :not_found} ->
            {:error, "Memory not found: #{old_memory_id}"}

          {:error, reason} ->
            {:error, "Failed to supersede memory: #{inspect(reason)}"}
        end
      end
    end

    defp create_replacement(args, context, session_id, old_memory, new_content) do
      with {:ok, content} <- Knowledge.validate_content(new_content) do
        # Determine type for replacement (default to original type)
        memory_type =
          case Map.get(args, "new_type") do
            nil -> old_memory.memory_type
            type_str -> parse_type_or_default(type_str, old_memory.memory_type)
          end

        memory_id = Knowledge.generate_memory_id()

        # Build replacement memory input
        memory_input = %{
          id: memory_id,
          content: content,
          memory_type: memory_type,
          confidence: old_memory.confidence,
          source_type: :agent,
          session_id: session_id,
          created_at: DateTime.utc_now(),
          rationale: Map.get(args, "reason"),
          # Link to the superseded memory
          evidence_refs: [old_memory.id],
          project_id: Map.get(context, :project_id)
        }

        case Memory.persist(memory_input, session_id) do
          {:ok, ^memory_id} ->
            Knowledge.ok_json(%{
              old_id: old_memory.id,
              new_id: memory_id,
              type: Atom.to_string(memory_type),
              status: "replaced"
            })

          {:error, reason} ->
            {:error, "Failed to create replacement memory: #{inspect(reason)}"}
        end
      end
    end

    defp parse_type_or_default(type_str, default) do
      case Knowledge.safe_to_type_atom(type_str) do
        {:ok, type_atom} ->
          if Types.valid_memory_type?(type_atom), do: type_atom, else: default

        {:error, _} ->
          default
      end
    end
  end

  # ============================================================================
  # ProjectConventions Handler
  # ============================================================================

  defmodule ProjectConventions do
    @moduledoc """
    Handler for retrieving project conventions and coding standards.

    Queries the knowledge graph for convention-type memories including
    coding standards, architectural conventions, agent rules, and process
    conventions.
    """

    alias JidoCode.Tools.Handlers.Knowledge

    # Convention types from the ontology
    @convention_types [:convention, :coding_standard]

    # Default limit for results
    @default_limit 50

    # Category to type mapping
    @category_types %{
      "coding" => [:coding_standard],
      "architectural" => [:convention],
      "agent" => [:convention],
      "process" => [:convention],
      "all" => @convention_types
    }

    @doc """
    Executes the project_conventions tool.

    ## Parameters

    - `args` - Map containing:
      - `"category"` (optional) - Filter by category
      - `"min_confidence"` (optional) - Minimum confidence threshold

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier

    ## Returns

    - `{:ok, json}` - JSON with list of conventions
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:project_conventions, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "project_conventions") do
        # Build query options
        min_confidence = Map.get(args, "min_confidence", 0.5)
        opts = [min_confidence: min_confidence, include_superseded: false]

        # Get types to filter by based on category
        filter_types = Knowledge.resolve_filter_types(
          Map.get(args, "category"),
          @category_types,
          @convention_types
        )

        # Get limit from args
        limit = Map.get(args, "limit", @default_limit)

        # Query all memories and filter to conventions
        case Memory.query(session_id, opts) do
          {:ok, memories} ->
            conventions =
              memories
              |> Enum.filter(fn memory ->
                memory.memory_type in filter_types
              end)
              |> Enum.sort_by(& &1.confidence, :desc)
              |> Enum.take(limit)

            format_conventions(conventions)

          {:error, reason} ->
            {:error, "Failed to query conventions: #{inspect(reason)}"}
        end
      end
    end

    defp format_conventions(conventions) do
      Knowledge.format_memory_list(conventions, :conventions)
    end
  end

  # ============================================================================
  # KnowledgeUpdate Handler
  # ============================================================================

  defmodule KnowledgeUpdate do
    @moduledoc """
    Handler for updating existing knowledge in long-term memory.

    Allows updating confidence levels and adding evidence or rationale to
    existing memories without replacing the entire memory content.
    """

    alias JidoCode.Memory
    alias JidoCode.Tools.Handlers.Knowledge

    @doc """
    Executes the knowledge_update tool.

    ## Parameters

    - `args` - Map containing:
      - `"memory_id"` (required) - ID of the memory to update
      - `"new_confidence"` (optional) - New confidence level 0.0-1.0
      - `"add_evidence"` (optional) - Evidence references to add
      - `"add_rationale"` (optional) - Additional rationale to append

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier

    ## Returns

    - `{:ok, json}` - JSON with updated memory summary
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:update, context, fn ->
        do_execute(args, context)
      end)
    end

    # Maximum evidence references per memory to prevent unbounded growth
    @max_evidence_refs 100

    # Maximum rationale size in bytes (16KB)
    @max_rationale_size 16_384

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "knowledge_update"),
           {:ok, memory_id} <- Knowledge.get_required_string(args, "memory_id"),
           {:ok, _} <- Knowledge.validate_memory_id(memory_id),
           {:ok, memory} <- Knowledge.get_memory(session_id, memory_id),
           {:ok, updates} <- validate_updates(args, memory),
           {:ok, updated_memory} <- apply_updates(memory, updates) do
        # Re-persist the updated memory
        case Memory.persist(updated_memory, session_id) do
          {:ok, ^memory_id} ->
            Knowledge.ok_json(%{
              id: memory_id,
              status: "updated",
              confidence: updated_memory.confidence,
              rationale: updated_memory.rationale,
              evidence_count: length(updated_memory.evidence_refs)
            })

          {:error, reason} ->
            {:error, "Failed to persist updated memory: #{inspect(reason)}"}
        end
      end
    end

    defp validate_updates(args, memory) do
      with {:ok, updates} <- validate_confidence(args),
           {:ok, updates} <- validate_evidence(args, memory, updates),
           {:ok, updates} <- validate_rationale(args, memory, updates),
           :ok <- require_at_least_one(updates) do
        {:ok, updates}
      end
    end

    defp validate_confidence(args) do
      case Map.get(args, "new_confidence") do
        nil ->
          {:ok, %{}}

        confidence when is_number(confidence) and confidence >= 0.0 and confidence <= 1.0 ->
          {:ok, %{confidence: confidence}}

        confidence when is_number(confidence) ->
          {:error, "Confidence must be between 0.0 and 1.0"}

        _ ->
          {:error, "Confidence must be a number"}
      end
    end

    defp validate_evidence(args, memory, updates) do
      case Map.get(args, "add_evidence") do
        nil ->
          {:ok, updates}

        evidence when is_list(evidence) ->
          # Validate each element is a string
          valid_evidence = Enum.filter(evidence, &is_binary/1)
          existing_count = length(Map.get(memory, :evidence_refs, []))
          new_count = length(valid_evidence)

          if existing_count + new_count > @max_evidence_refs do
            {:error, "Evidence refs would exceed maximum of #{@max_evidence_refs}"}
          else
            {:ok, Map.put(updates, :add_evidence, valid_evidence)}
          end

        _ ->
          {:ok, updates}
      end
    end

    defp validate_rationale(args, memory, updates) do
      case Map.get(args, "add_rationale") do
        nil ->
          {:ok, updates}

        rationale when is_binary(rationale) ->
          existing_size = byte_size(Map.get(memory, :rationale) || "")
          new_size = byte_size(rationale)
          # Account for the separator "\n\n"
          separator_size = if existing_size > 0, do: 2, else: 0
          total_size = existing_size + separator_size + new_size

          if total_size > @max_rationale_size do
            {:error, "Rationale would exceed maximum of #{@max_rationale_size} bytes"}
          else
            {:ok, Map.put(updates, :add_rationale, rationale)}
          end

        _ ->
          {:ok, updates}
      end
    end

    defp require_at_least_one(updates) when map_size(updates) == 0 do
      {:error, "At least one update (new_confidence, add_evidence, or add_rationale) is required"}
    end

    defp require_at_least_one(_updates), do: :ok

    defp apply_updates(memory, updates) do
      updated_memory =
        memory
        |> Knowledge.normalize_timestamp()
        |> maybe_update_confidence(Map.get(updates, :confidence))
        |> maybe_add_evidence(Map.get(updates, :add_evidence))
        |> maybe_append_rationale(Map.get(updates, :add_rationale))

      {:ok, updated_memory}
    end

    defp maybe_update_confidence(memory, nil), do: memory
    defp maybe_update_confidence(memory, confidence), do: %{memory | confidence: confidence}

    defp maybe_add_evidence(memory, nil), do: memory
    defp maybe_add_evidence(memory, []), do: memory

    defp maybe_add_evidence(memory, new_evidence) do
      existing = Map.get(memory, :evidence_refs, [])
      %{memory | evidence_refs: existing ++ new_evidence}
    end

    defp maybe_append_rationale(memory, nil), do: memory
    defp maybe_append_rationale(memory, ""), do: memory

    defp maybe_append_rationale(memory, new_rationale) do
      existing = Map.get(memory, :rationale) || ""

      updated_rationale =
        if existing == "" do
          new_rationale
        else
          "#{existing}\n\n#{new_rationale}"
        end

      %{memory | rationale: updated_rationale}
    end
  end

  # ============================================================================
  # ProjectDecisions Handler
  # ============================================================================

  defmodule ProjectDecisions do
    @moduledoc """
    Handler for retrieving project decisions.

    Queries the knowledge graph for decision-type memories including
    general decisions, architectural decisions, and implementation decisions.
    """

    alias JidoCode.Memory
    alias JidoCode.Tools.Handlers.Knowledge

    # Decision types from the ontology
    @decision_types [:decision, :architectural_decision, :implementation_decision]

    # Alternative type for considered options
    @alternative_type :alternative

    # Default limit for results
    @default_limit 50

    # Type mapping for filter
    @type_filter %{
      "architectural" => [:architectural_decision],
      "implementation" => [:implementation_decision],
      "all" => @decision_types
    }

    @doc """
    Executes the project_decisions tool.

    ## Parameters

    - `args` - Map containing:
      - `"include_superseded"` (optional) - Include superseded decisions (default: false)
      - `"decision_type"` (optional) - Filter by type: architectural, implementation, all
      - `"include_alternatives"` (optional) - Include considered alternatives (default: false)
      - `"limit"` (optional) - Maximum results to return (default: 50)

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier

    ## Returns

    - `{:ok, json}` - JSON with list of decisions
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:project_decisions, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "project_decisions") do
        include_superseded = Map.get(args, "include_superseded", false)
        include_alternatives = Map.get(args, "include_alternatives", false)
        opts = [include_superseded: include_superseded]

        # Get types to filter by based on decision_type parameter
        filter_types = Knowledge.resolve_filter_types(
          Map.get(args, "decision_type"),
          @type_filter,
          @decision_types
        )

        # Include alternative type if requested
        filter_types =
          if include_alternatives do
            [@alternative_type | filter_types]
          else
            filter_types
          end

        # Get limit from args
        limit = Map.get(args, "limit", @default_limit)

        case Memory.query(session_id, opts) do
          {:ok, memories} ->
            decisions =
              memories
              |> Enum.filter(fn memory -> memory.memory_type in filter_types end)
              |> Enum.sort_by(& &1.confidence, :desc)
              |> Enum.take(limit)

            format_decisions(decisions)

          {:error, reason} ->
            {:error, "Failed to query decisions: #{inspect(reason)}"}
        end
      end
    end

    defp format_decisions(decisions) do
      Knowledge.format_memory_list(decisions, :decisions)
    end
  end

  # ============================================================================
  # ProjectRisks Handler
  # ============================================================================

  defmodule ProjectRisks do
    @moduledoc """
    Handler for retrieving project risks.

    Queries the knowledge graph for risk-type memories, sorted by confidence
    (severity/likelihood) in descending order.
    """

    alias JidoCode.Memory
    alias JidoCode.Tools.Handlers.Knowledge

    # Default limit for results
    @default_limit 50

    @doc """
    Executes the project_risks tool.

    ## Parameters

    - `args` - Map containing:
      - `"min_confidence"` (optional) - Minimum confidence threshold (default: 0.5)
      - `"include_mitigated"` (optional) - Include mitigated/superseded risks (default: false)
      - `"limit"` (optional) - Maximum results to return (default: 50)

    - `context` - Map containing:
      - `:session_id` (required) - Session identifier

    ## Returns

    - `{:ok, json}` - JSON with list of risks
    - `{:error, reason}` - Error message string
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      Knowledge.with_telemetry(:project_risks, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "project_risks") do
        min_confidence = Map.get(args, "min_confidence", 0.5)
        include_mitigated = Map.get(args, "include_mitigated", false)
        limit = Map.get(args, "limit", @default_limit)
        opts = [include_superseded: include_mitigated, min_confidence: min_confidence]

        case Memory.query(session_id, opts) do
          {:ok, memories} ->
            risks =
              memories
              |> Enum.filter(fn memory -> memory.memory_type == :risk end)
              |> Enum.sort_by(& &1.confidence, :desc)
              |> Enum.take(limit)

            format_risks(risks)

          {:error, reason} ->
            {:error, "Failed to query risks: #{inspect(reason)}"}
        end
      end
    end

    defp format_risks(risks) do
      Knowledge.format_memory_list(risks, :risks)
    end
  end

  # ============================================================================
  # KnowledgeGraphQuery Handler
  # ============================================================================

  defmodule KnowledgeGraphQuery do
    @moduledoc """
    Handler for traversing the knowledge graph to find related memories.

    Supports various relationship types for exploring connections between
    memories, including evidence chains, replacement history, and similarity.
    """

    alias JidoCode.Memory
    alias JidoCode.Tools.Handlers.Knowledge

    @valid_relationships [:derived_from, :superseded_by, :supersedes, :same_type, :same_project]
    @default_depth 1
    @max_depth 5
    @default_limit 10

    @doc """
    Executes the knowledge_graph_query tool.

    ## Parameters

    - `args` - Map containing:
      - `"start_from"` (required) - Memory ID to start traversal from
      - `"relationship"` (required) - Relationship type to follow
      - `"depth"` (optional) - Maximum traversal depth (1-5)
      - `"limit"` (optional) - Maximum results per level
      - `"include_superseded"` (optional) - Include superseded memories
    - `context` - Must contain `:session_id`

    ## Returns

    - `{:ok, json}` - JSON with related memories list
    - `{:error, message}` - Error message string
    """
    def execute(args, context) do
      Knowledge.with_telemetry(:graph_query, context, fn ->
        do_execute(args, context)
      end)
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- Knowledge.get_session_id(context, "knowledge_graph_query"),
           {:ok, start_from} <- Knowledge.get_required_string(args, "start_from"),
           {:ok, _} <- Knowledge.validate_memory_id(start_from),
           {:ok, relationship} <- validate_relationship(Map.get(args, "relationship")),
           {:ok, opts} <- build_query_opts(args) do
        case Memory.query_related(session_id, start_from, relationship, opts) do
          {:ok, memories} ->
            format_results(memories, start_from, relationship)

          {:error, :not_found} ->
            {:error, "Memory not found: #{start_from}"}

          {:error, reason} ->
            {:error, "Failed to query related memories: #{inspect(reason)}"}
        end
      end
    end

    defp validate_relationship(nil), do: {:error, "relationship is required"}
    defp validate_relationship(""), do: {:error, "relationship cannot be empty"}

    defp validate_relationship(rel) when is_binary(rel) do
      normalized =
        rel
        |> String.downcase()
        |> String.replace("-", "_")

      case safe_to_relationship_atom(normalized) do
        {:ok, atom} when atom in @valid_relationships ->
          {:ok, atom}

        _ ->
          valid_list = @valid_relationships |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
          {:error, "Invalid relationship: #{rel}. Must be one of: #{valid_list}"}
      end
    end

    defp validate_relationship(_), do: {:error, "relationship must be a string"}

    defp safe_to_relationship_atom(string) do
      try do
        {:ok, String.to_existing_atom(string)}
      rescue
        ArgumentError -> {:error, :unknown}
      end
    end

    defp build_query_opts(args) do
      depth = args |> Map.get("depth", @default_depth) |> clamp_depth()
      limit = args |> Map.get("limit", @default_limit) |> normalize_limit()
      include_superseded = Map.get(args, "include_superseded", false) == true

      {:ok, [depth: depth, limit: limit, include_superseded: include_superseded]}
    end

    defp clamp_depth(depth) when is_integer(depth), do: depth |> max(1) |> min(@max_depth)
    defp clamp_depth(_), do: @default_depth

    defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
    defp normalize_limit(_), do: @default_limit

    defp format_results(memories, start_from, relationship) do
      results =
        Enum.map(memories, fn memory ->
          %{
            id: memory.id,
            content: memory.content,
            type: Atom.to_string(memory.memory_type),
            confidence: memory.confidence,
            timestamp: Knowledge.format_timestamp(memory.timestamp),
            rationale: memory.rationale
          }
        end)

      Knowledge.ok_json(%{
        start_from: start_from,
        relationship: Atom.to_string(relationship),
        related: results,
        count: length(results)
      })
    end
  end

  # ============================================================================
  # Shared Functions
  # ============================================================================

  @doc false
  def default_confidence, do: @default_confidence

  @doc """
  Generates a unique memory ID with cryptographic randomness.

  ## Returns

  A string in the format "mem-<base64>" where the base64 portion is
  URL-safe encoded random bytes.
  """
  @spec generate_memory_id() :: String.t()
  def generate_memory_id do
    "mem-" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
  end

  @doc """
  Validates a required string argument from args map.

  ## Parameters

  - `args` - Map containing the argument
  - `key` - String key to validate

  ## Returns

  - `{:ok, value}` - Valid non-empty string
  - `{:error, message}` - Error with descriptive message
  """
  @spec get_required_string(map(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_required_string(args, key) do
    case Map.get(args, key) do
      nil -> {:error, "#{key} is required"}
      "" -> {:error, "#{key} cannot be empty"}
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a string"}
    end
  end

  @doc """
  Validates a memory ID format.

  Memory IDs should follow the format "mem-<base64>".

  ## Parameters

  - `memory_id` - String to validate

  ## Returns

  - `{:ok, memory_id}` - Valid memory ID format
  - `{:error, message}` - Error with descriptive message
  """
  @spec validate_memory_id(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_memory_id(memory_id) when is_binary(memory_id) do
    if String.match?(memory_id, ~r/^mem-[A-Za-z0-9_-]+$/) do
      {:ok, memory_id}
    else
      {:error, "invalid memory_id format: expected 'mem-<base64>'"}
    end
  end

  def validate_memory_id(_), do: {:error, "memory_id must be a string"}

  @doc """
  Wraps a result in {:ok, json} format.

  ## Parameters

  - `data` - Map or list to encode as JSON

  ## Returns

  - `{:ok, json_string}` - Encoded JSON
  """
  @spec ok_json(map() | list()) :: {:ok, String.t()}
  def ok_json(data), do: {:ok, Jason.encode!(data)}

  @doc """
  Fetches a memory by ID with session ownership validation.

  ## Parameters

  - `session_id` - Session identifier for ownership validation
  - `memory_id` - Memory ID to fetch

  ## Returns

  - `{:ok, memory}` - Memory map on success
  - `{:error, message}` - Error message string
  """
  @spec get_memory(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_memory(session_id, memory_id) do
    case Memory.get(session_id, memory_id) do
      {:ok, memory} -> {:ok, memory}
      {:error, :not_found} -> {:error, "Memory not found: #{memory_id}"}
      {:error, reason} -> {:error, "Failed to get memory: #{inspect(reason)}"}
    end
  end

  @doc """
  Resolves filter types from a category/type input using a mapping.

  This shared helper handles the common pattern of mapping category strings
  to lists of memory types for filtering queries.

  ## Parameters

  - `input` - Category/type string to resolve (e.g., "architectural", "coding")
  - `type_mapping` - Map of string category names to type lists
  - `default_types` - Default list of types if input is nil/empty/unknown

  ## Returns

  List of memory type atoms to filter by.
  """
  @spec resolve_filter_types(term(), map(), [atom()]) :: [atom()]
  def resolve_filter_types(nil, _type_mapping, default_types), do: default_types
  def resolve_filter_types("", _type_mapping, default_types), do: default_types

  def resolve_filter_types(input, type_mapping, default_types) when is_binary(input) do
    input_lower = String.downcase(input)
    Map.get(type_mapping, input_lower, default_types)
  end

  def resolve_filter_types(_input, _type_mapping, default_types), do: default_types

  @doc """
  Normalizes a memory's timestamp field to created_at for persist compatibility.

  The Memory.get/2 function returns memories with a :timestamp field, but
  Memory.persist/2 expects :created_at. This function handles that conversion.

  ## Parameters

  - `memory` - Memory map to normalize

  ## Returns

  Memory map with :created_at field (and :timestamp removed if present)
  """
  @spec normalize_timestamp(map()) :: map()
  def normalize_timestamp(memory) do
    case Map.get(memory, :timestamp) do
      nil -> memory
      timestamp -> memory |> Map.put(:created_at, timestamp) |> Map.delete(:timestamp)
    end
  end

  @doc """
  Formats a list of memories for JSON output.

  ## Parameters

  - `memories` - List of memory structs
  - `key` - Atom key for the result (e.g., :memories, :conventions)

  ## Returns

  - `{:ok, json}` - JSON with list and count
  """
  @spec format_memory_list([map()], atom()) :: {:ok, String.t()}
  def format_memory_list(memories, key) do
    results =
      Enum.map(memories, fn memory ->
        %{
          id: memory.id,
          content: memory.content,
          type: Atom.to_string(memory.memory_type),
          confidence: memory.confidence,
          timestamp: format_timestamp(memory.timestamp),
          rationale: memory.rationale
        }
      end)

    ok_json(%{key => results, count: length(results)})
  end
end
