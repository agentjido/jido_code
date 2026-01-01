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
        doc: "Search query or keywords (optional, for text matching)"
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
             :convention,
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
  alias JidoCode.Memory.Types

  # =============================================================================
  # Constants
  # =============================================================================

  @max_limit 50
  @min_limit 1
  @default_limit 10
  @default_min_confidence 0.5

  @valid_types [
    :all,
    :fact,
    :assumption,
    :hypothesis,
    :discovery,
    :risk,
    :unknown,
    :decision,
    :convention,
    :lesson_learned
  ]

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
  Returns the list of valid types for recall queries.
  """
  @spec valid_types() :: [atom()]
  def valid_types, do: @valid_types

  # =============================================================================
  # Action Implementation
  # =============================================================================

  @impl true
  def run(params, context) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, validated} <- validate_recall_params(params),
         {:ok, session_id} <- get_session_id(context),
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

  defp validate_min_confidence(%{min_confidence: conf}) when is_number(conf) do
    {:ok, Types.clamp_to_unit(conf)}
  end

  defp validate_min_confidence(_), do: {:ok, @default_min_confidence}

  defp validate_type(%{type: type}) when type in @valid_types do
    {:ok, type}
  end

  defp validate_type(%{type: type}) do
    {:error, {:invalid_type, type}}
  end

  defp validate_type(_), do: {:ok, :all}

  defp validate_query(%{query: query}) when is_binary(query) do
    trimmed = String.trim(query)

    if byte_size(trimmed) == 0 do
      {:ok, nil}
    else
      {:ok, trimmed}
    end
  end

  defp validate_query(_), do: {:ok, nil}

  # =============================================================================
  # Private Functions - Context
  # =============================================================================

  defp get_session_id(context) do
    case context[:session_id] do
      nil -> {:error, :missing_session_id}
      id when is_binary(id) -> {:ok, id}
      _ -> {:error, :invalid_session_id}
    end
  end

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
      timestamp: format_timestamp(mem.timestamp)
    }
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(nil), do: nil
  defp format_timestamp(other), do: inspect(other)

  defp format_error(:missing_session_id) do
    "Session ID is required in context"
  end

  defp format_error(:invalid_session_id) do
    "Session ID must be a string"
  end

  defp format_error({:limit_too_small, actual, min}) do
    "Limit must be at least #{min}, got #{actual}"
  end

  defp format_error({:limit_too_large, actual, max}) do
    "Limit cannot exceed #{max}, got #{actual}"
  end

  defp format_error({:invalid_type, type}) do
    "Invalid memory type: #{inspect(type)}. Valid types: #{inspect(@valid_types)}"
  end

  defp format_error(reason) do
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
        type_filter: params.type,
        min_confidence: params.min_confidence,
        has_query: params.query != nil
      }
    )
  end
end
