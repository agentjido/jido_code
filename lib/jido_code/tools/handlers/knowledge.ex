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
  Returns :error if the atom doesn't exist (preventing atom exhaustion).

  ## Parameters

  - `type_str` - String to convert

  ## Returns

  - `{:ok, atom}` - Successfully converted atom
  - `:error` - Atom doesn't exist or invalid input
  """
  @spec safe_to_type_atom(String.t()) :: {:ok, atom()} | :error
  def safe_to_type_atom(type_str) when is_binary(type_str) do
    normalized =
      type_str
      |> String.downcase()
      |> String.replace("-", "_")

    {:ok, String.to_existing_atom(normalized)}
  rescue
    ArgumentError -> :error
  end

  def safe_to_type_atom(_), do: :error

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
        memory_id = generate_memory_id()

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

            :error ->
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

    defp generate_memory_id do
      "mem-" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
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
            :error -> acc
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

      {:ok, Jason.encode!(%{memories: results, count: length(results)})}
    end
  end

  # ============================================================================
  # Shared Functions
  # ============================================================================

  @doc false
  def default_confidence, do: @default_confidence
end
