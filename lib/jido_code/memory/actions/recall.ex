defmodule JidoCode.Memory.Actions.Recall do
  @moduledoc """
  Search long-term memory for relevant information.

  Use to retrieve previously learned:
  - Facts about the project or codebase
  - Decisions and their rationale
  - Patterns and conventions
  - Lessons learned from past issues

  Supports filtering by memory type and minimum confidence level.
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
        doc: "Search query or keywords (optional, for text matching, max 1000 chars)"
      ],
      type: [
        type:
          {:in,
           [
             :all,
             :fact,
             :assumption,
             :hypothesis,
             :discovery,
             :risk,
             :unknown,
             :decision,
             :architectural_decision,
             :convention,
             :coding_standard,
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
         {:ok, query} <- validate_query(params) do
      {:ok,
       %{
         limit: limit,
         min_confidence: min_confidence,
         type: type,
         query: query
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

  # =============================================================================
  # Private Functions - Query
  # =============================================================================

  defp query_memories(params, session_id) do
    opts = [
      min_confidence: params.min_confidence,
      limit: params.limit
    ]

    result =
      if params.type == :all do
        Memory.query(session_id, opts)
      else
        Memory.query_by_type(session_id, params.type, opts)
      end

    case {result, params.query} do
      {{:ok, memories}, nil} ->
        {:ok, memories}

      {{:ok, memories}, query} ->
        {:ok, filter_by_query(memories, query)}

      {{:error, _} = error, _} ->
        error
    end
  end

  defp filter_by_query(memories, query) do
    query_lower = String.downcase(query)

    Enum.filter(memories, fn mem ->
      String.contains?(String.downcase(mem.content), query_lower)
    end)
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
        has_query: params.query != nil
      }
    )
  end
end
