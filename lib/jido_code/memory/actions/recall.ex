defmodule JidoCode.Memory.Actions.Recall do
  @moduledoc """
  Search long-term memory for relevant information.

  Use to retrieve previously learned information from all 22 memory types.

  ## Memory Type Categories

  Knowledge types: fact, assumption, hypothesis, discovery, risk, unknown
  Decision types: decision, architectural_decision, implementation_decision, alternative, trade_off
  Convention types: convention, coding_standard, architectural_convention, agent_rule, process_convention
  Error types: error, bug, failure, incident, root_cause, lesson_learned

  ## Search Modes

  - `:text` - Simple substring matching (fast, exact matches)
  - `:semantic` - TF-IDF based semantic similarity (finds related content)
  - `:hybrid` - Combines text matches with semantic ranking (default when query provided)

  Semantic search uses TF-IDF embeddings to find memories with similar meaning,
  even if they don't contain the exact search terms.
  """

  use Jido.Action,
    name: "recall",
    description:
      "Search long-term memory for relevant information. " <>
        "Use to retrieve previously learned facts, decisions, patterns, or lessons.",
    schema: [
      query: [
        type: :string,
        required: false,
        doc: "Search query or keywords (optional, max 1000 chars)"
      ],
      search_mode: [
        type: {:in, [:text, :semantic, :hybrid]},
        default: :hybrid,
        doc: "Search mode: :text (substring), :semantic (TF-IDF similarity), :hybrid (both)"
      ],
      type: [
        type:
          {:in,
           [
             :all,
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
           ]},
        default: :all,
        doc: "Filter by memory type (default: all)"
      ],
      min_confidence: [
        type: :float,
        default: 0.5,
        doc: "Minimum confidence threshold 0.0-1.0"
      ],
      limit: [
        type: :integer,
        default: 10,
        doc: "Maximum memories to return (default: 10, max: 50)"
      ]
    ]

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions.Helpers
  alias JidoCode.Memory.Embeddings
  alias JidoCode.Memory.Types

  # =============================================================================
  # Constants
  # =============================================================================

  @max_limit 50
  @min_limit 1
  @default_limit 10
  @default_min_confidence 0.5
  @max_query_length 1000

  # Valid types for recall queries (includes :all as a filter option)
  # Note: :all is a pseudo-type for query purposes, not a memory type
  @valid_memory_types Types.memory_types()
  @valid_filter_types [:all | @valid_memory_types]

  # Semantic search settings
  @valid_search_modes [:text, :semantic, :hybrid]
  @default_search_mode :hybrid
  @semantic_similarity_threshold 0.2

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the maximum allowed limit.
  """
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  @doc """
  Returns the minimum allowed limit.
  """
  @spec min_limit() :: pos_integer()
  def min_limit, do: @min_limit

  @doc """
  Returns the default limit.
  """
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  Returns the maximum allowed query length.
  """
  @spec max_query_length() :: pos_integer()
  def max_query_length, do: @max_query_length

  @doc """
  Returns the list of valid filter types for recall queries.
  Includes :all as a filter option plus all valid memory types.
  """
  @spec valid_types() :: [atom()]
  def valid_types, do: @valid_filter_types

  # =============================================================================
  # Action Implementation
  # =============================================================================

  @impl true
  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(params, context) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, validated} <- validate_recall_params(params),
         {:ok, session_id} <- Helpers.get_session_id(context),
         {:ok, memories} <- query_memories(validated, session_id),
         :ok <- record_access(memories, session_id) do
      emit_telemetry(session_id, validated, length(memories), start_time)
      {:ok, format_results(memories)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  # =============================================================================
  # Private Functions - Validation
  # =============================================================================

  defp validate_recall_params(params) do
    with {:ok, limit} <- validate_limit(params),
         {:ok, min_confidence} <- validate_min_confidence(params),
         {:ok, type} <- validate_type(params),
         {:ok, query} <- validate_query(params),
         {:ok, search_mode} <- validate_search_mode(params) do
      {:ok,
       %{
         limit: limit,
         min_confidence: min_confidence,
         type: type,
         query: query,
         search_mode: search_mode
       }}
    end
  end

  defp validate_limit(%{limit: limit}) when is_integer(limit) do
    cond do
      limit < @min_limit ->
        {:error, {:limit_too_small, limit, @min_limit}}

      limit > @max_limit ->
        {:error, {:limit_too_large, limit, @max_limit}}

      true ->
        {:ok, limit}
    end
  end

  defp validate_limit(_), do: {:ok, @default_limit}

  defp validate_min_confidence(params) do
    Helpers.validate_confidence(params, :min_confidence, @default_min_confidence)
  end

  defp validate_type(%{type: type}) when type in @valid_filter_types do
    {:ok, type}
  end

  defp validate_type(%{type: type}) do
    {:error, {:invalid_memory_type, type}}
  end

  defp validate_type(_), do: {:ok, :all}

  defp validate_query(%{query: query}) do
    case Helpers.validate_optional_bounded_string(query, @max_query_length) do
      {:ok, result} -> {:ok, result}
      {:error, {:too_long, actual, max}} -> {:error, {:query_too_long, actual, max}}
    end
  end

  defp validate_query(_), do: {:ok, nil}

  defp validate_search_mode(%{search_mode: mode}) when mode in @valid_search_modes do
    {:ok, mode}
  end

  defp validate_search_mode(%{search_mode: mode}) do
    {:error, {:invalid_search_mode, mode}}
  end

  defp validate_search_mode(_), do: {:ok, @default_search_mode}

  # =============================================================================
  # Private Functions - Query
  # =============================================================================

  defp query_memories(params, session_id) do
    # Fetch more memories than limit when using semantic search,
    # since we'll rank and filter them
    fetch_limit =
      if params.query != nil and params.search_mode in [:semantic, :hybrid] do
        min(params.limit * 3, @max_limit)
      else
        params.limit
      end

    opts = [
      min_confidence: params.min_confidence,
      limit: fetch_limit
    ]

    result =
      if params.type == :all do
        Memory.query(session_id, opts)
      else
        Memory.query_by_type(session_id, params.type, opts)
      end

    case {result, params.query} do
      {{:ok, memories}, nil} ->
        # No query - just return memories (already limited)
        {:ok, Enum.take(memories, params.limit)}

      {{:ok, memories}, query} ->
        # Apply search mode
        filtered = search_memories(memories, query, params.search_mode, params.limit)
        {:ok, filtered}

      {{:error, _} = error, _} ->
        error
    end
  end

  # =============================================================================
  # Private Functions - Search Modes
  # =============================================================================

  defp search_memories(memories, query, :text, limit) do
    memories
    |> filter_by_text(query)
    |> Enum.take(limit)
  end

  defp search_memories(memories, query, :semantic, limit) do
    case Embeddings.generate(query) do
      {:ok, query_embedding} ->
        memories
        |> rank_by_semantic_similarity(query_embedding)
        |> Enum.map(fn {mem, _score} -> mem end)
        |> Enum.take(limit)

      {:error, _} ->
        # Fallback to text search if query produces no tokens
        search_memories(memories, query, :text, limit)
    end
  end

  defp search_memories(memories, query, :hybrid, limit) do
    # Hybrid search: combine text matches with semantic ranking
    # First, get text matches
    text_matches = MapSet.new(filter_by_text(memories, query), & &1.id)

    case Embeddings.generate(query) do
      {:ok, query_embedding} ->
        # Rank all memories by semantic similarity
        ranked = rank_by_semantic_similarity(memories, query_embedding)

        # Boost text matches by moving them to the front within their similarity tier
        ranked
        |> Enum.sort_by(fn {mem, score} ->
          # Text matches get a significant boost
          boost = if MapSet.member?(text_matches, mem.id), do: 0.5, else: 0.0
          -(score + boost)
        end)
        |> Enum.map(fn {mem, _score} -> mem end)
        |> Enum.take(limit)

      {:error, _} ->
        # Fallback to text search
        search_memories(memories, query, :text, limit)
    end
  end

  defp filter_by_text(memories, query) do
    query_lower = String.downcase(query)

    Enum.filter(memories, fn mem ->
      String.contains?(String.downcase(mem.content), query_lower)
    end)
  end

  defp rank_by_semantic_similarity(memories, query_embedding) do
    memories
    |> Enum.map(fn mem ->
      mem_embedding = Embeddings.generate!(mem.content)
      score = Embeddings.cosine_similarity(query_embedding, mem_embedding)
      {mem, score}
    end)
    |> Enum.filter(fn {_, score} -> score >= @semantic_similarity_threshold end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
  end

  # =============================================================================
  # Private Functions - Access Tracking
  # =============================================================================

  # Access tracking is best-effort; errors are swallowed intentionally
  # (see Memory.record_access/2 documentation)
  defp record_access(memories, session_id) do
    Enum.each(memories, fn mem ->
      Memory.record_access(session_id, mem.id)
    end)

    :ok
  end

  # =============================================================================
  # Private Functions - Formatting
  # =============================================================================

  defp format_results(memories) do
    %{
      count: length(memories),
      memories: Enum.map(memories, &format_memory/1)
    }
  end

  defp format_memory(mem) do
    %{
      id: mem.id,
      content: mem.content,
      type: mem.memory_type,
      confidence: mem.confidence,
      timestamp: Helpers.format_timestamp(mem.timestamp)
    }
  end

  defp format_error(reason) do
    Helpers.format_common_error(reason) || format_action_error(reason)
  end

  defp format_action_error({:limit_too_small, actual, min}) do
    "Limit must be at least #{min}, got #{actual}"
  end

  defp format_action_error({:limit_too_large, actual, max}) do
    "Limit cannot exceed #{max}, got #{actual}"
  end

  defp format_action_error({:invalid_memory_type, type}) do
    "Invalid memory type: #{inspect(type)}. Valid types: #{inspect(@valid_filter_types)}"
  end

  defp format_action_error({:query_too_long, actual, max}) do
    "Query exceeds maximum length (#{actual} > #{max} bytes)"
  end

  defp format_action_error({:invalid_search_mode, mode}) do
    "Invalid search mode: #{inspect(mode)}. Valid modes: #{inspect(@valid_search_modes)}"
  end

  defp format_action_error(reason) do
    "Failed to recall: #{inspect(reason)}"
  end

  # =============================================================================
  # Private Functions - Telemetry
  # =============================================================================

  defp emit_telemetry(session_id, params, result_count, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:jido_code, :memory, :recall],
      %{duration: duration_ms, result_count: result_count},
      %{
        session_id: session_id,
        memory_type: params.type,
        min_confidence: params.min_confidence,
        has_query: params.query != nil,
        search_mode: params.search_mode
      }
    )
  end
end
