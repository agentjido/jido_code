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
      start_time = System.monotonic_time(:microsecond)

      result = do_execute(args, context)

      status = if match?({:ok, _}, result), do: :success, else: :error
      Knowledge.emit_knowledge_telemetry(:remember, start_time, context, status)

      result
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- get_session_id(context),
           {:ok, content} <- get_required_string(args, "content"),
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

    defp get_session_id(%{session_id: session_id}) when is_binary(session_id) do
      {:ok, session_id}
    end

    defp get_session_id(_context) do
      {:error, "knowledge_remember requires a session context"}
    end

    defp get_required_string(args, key) do
      case Map.get(args, key) do
        nil -> {:error, "#{key} is required"}
        "" -> {:error, "#{key} cannot be empty"}
        value when is_binary(value) -> {:ok, value}
        _ -> {:error, "#{key} must be a string"}
      end
    end

    defp parse_memory_type(args) do
      case Map.get(args, "type") do
        nil ->
          {:error, "type is required"}

        type_string when is_binary(type_string) ->
          type_atom =
            type_string
            |> String.downcase()
            |> String.replace("-", "_")
            |> String.to_existing_atom()

          if Types.valid_memory_type?(type_atom) do
            {:ok, type_atom}
          else
            {:error, "Invalid memory type: #{type_string}. Valid types: #{valid_types_string()}"}
          end

        _ ->
          {:error, "type must be a string"}
      end
    rescue
      ArgumentError ->
        {:error,
         "Invalid memory type: #{args["type"]}. Valid types: #{valid_types_string()}"}
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
      start_time = System.monotonic_time(:microsecond)

      result = do_execute(args, context)

      status = if match?({:ok, _}, result), do: :success, else: :error
      Knowledge.emit_knowledge_telemetry(:recall, start_time, context, status)

      result
    end

    defp do_execute(args, context) do
      with {:ok, session_id} <- get_session_id(context),
           {:ok, opts} <- build_query_opts(args) do
        # Query memories
        case Memory.query(session_id, opts) do
          {:ok, memories} ->
            # Apply text search filter if query provided
            filtered =
              case Map.get(args, "query") do
                nil -> memories
                "" -> memories
                query_text -> filter_by_text(memories, query_text)
              end

            # Apply type filter if types provided
            filtered =
              case Map.get(args, "types") do
                nil -> filtered
                [] -> filtered
                types when is_list(types) -> filter_by_types(filtered, types)
                _ -> filtered
              end

            # Apply limit
            limit = Map.get(args, "limit", 10)
            limited = Enum.take(filtered, limit)

            # Format results
            results =
              Enum.map(limited, fn memory ->
                %{
                  id: memory.id,
                  content: memory.content,
                  type: Atom.to_string(memory.memory_type),
                  confidence: memory.confidence,
                  timestamp: DateTime.to_iso8601(memory.timestamp),
                  rationale: memory.rationale
                }
              end)

            {:ok, Jason.encode!(%{memories: results, count: length(results)})}

          {:error, reason} ->
            {:error, "Failed to query memories: #{inspect(reason)}"}
        end
      end
    end

    defp get_session_id(%{session_id: session_id}) when is_binary(session_id) do
      {:ok, session_id}
    end

    defp get_session_id(_context) do
      {:error, "knowledge_recall requires a session context"}
    end

    defp build_query_opts(args) do
      opts = []

      # Add min_confidence option
      opts =
        case Map.get(args, "min_confidence") do
          nil -> Keyword.put(opts, :min_confidence, 0.5)
          conf when is_number(conf) -> Keyword.put(opts, :min_confidence, conf)
          _ -> opts
        end

      # Add include_superseded option
      opts =
        case Map.get(args, "include_superseded") do
          true -> Keyword.put(opts, :include_superseded, true)
          _ -> Keyword.put(opts, :include_superseded, false)
        end

      {:ok, opts}
    end

    defp filter_by_text(memories, query_text) do
      query_lower = String.downcase(query_text)

      Enum.filter(memories, fn memory ->
        content_lower = String.downcase(memory.content || "")
        String.contains?(content_lower, query_lower)
      end)
    end

    defp filter_by_types(memories, types) do
      type_atoms =
        types
        |> Enum.map(fn type_str ->
          type_str
          |> String.downcase()
          |> String.replace("-", "_")
          |> String.to_existing_atom()
        end)
        |> MapSet.new()

      Enum.filter(memories, fn memory ->
        MapSet.member?(type_atoms, memory.memory_type)
      end)
    rescue
      ArgumentError -> memories
    end
  end

  # ============================================================================
  # Shared Functions
  # ============================================================================

  @doc false
  def default_confidence, do: @default_confidence
end
