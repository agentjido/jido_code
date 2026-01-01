defmodule JidoCode.Memory.Actions.Remember do
  @moduledoc """
  Persist important information to long-term memory.

  Use when you discover something valuable for future sessions:
  - Project facts (framework, dependencies, architecture)
  - User preferences and coding style
  - Successful solutions to problems
  - Important patterns or conventions
  - Risks or known issues

  Agent-initiated memories bypass the normal importance threshold
  and are persisted immediately with maximum importance score.
  """

  use Jido.Action,
    name: "remember",
    description:
      "Persist important information to long-term memory. " <>
        "Use when you discover something valuable for future sessions.",
    schema: [
      content: [
        type: :string,
        required: true,
        doc: "What to remember - concise, factual statement (max 2000 chars)"
      ],
      type: [
        type:
          {:in,
           [
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
        default: :fact,
        doc: "Type of memory (maps to Jido ontology class)"
      ],
      confidence: [
        type: :float,
        default: 0.8,
        doc: "Confidence level (0.0-1.0, maps to jido:ConfidenceLevel)"
      ],
      rationale: [
        type: :string,
        required: false,
        doc: "Why this is worth remembering"
      ]
    ]

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions.Helpers
  alias JidoCode.Memory.Types

  # =============================================================================
  # Constants
  # =============================================================================

  @max_content_length 2000
  @default_confidence 0.8

  # Valid memory types from Types module (single source of truth)
  @valid_memory_types Types.memory_types()

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the maximum allowed content length.
  """
  @spec max_content_length() :: pos_integer()
  def max_content_length, do: @max_content_length

  @doc """
  Returns the list of valid memory types for remember operations.
  """
  @spec valid_memory_types() :: [Types.memory_type()]
  def valid_memory_types, do: @valid_memory_types

  # =============================================================================
  # Action Implementation
  # =============================================================================

  @impl true
  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(params, context) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, validated} <- validate_remember_params(params),
         {:ok, session_id} <- Helpers.get_session_id(context),
         {:ok, memory_item} <- build_memory_item(validated, context),
         {:ok, memory_id} <- promote_immediately(memory_item, session_id) do
      emit_telemetry(session_id, validated.type, start_time)
      {:ok, format_success(memory_id, validated.type)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  # =============================================================================
  # Private Functions - Validation
  # =============================================================================

  defp validate_remember_params(params) do
    with {:ok, content} <- validate_content(params),
         {:ok, type} <- validate_type(params),
         {:ok, confidence} <- validate_confidence(params) do
      {:ok,
       %{
         content: content,
         type: type,
         confidence: confidence,
         rationale: Map.get(params, :rationale)
       }}
    end
  end

  defp validate_content(%{content: content}) when is_binary(content) do
    trimmed = String.trim(content)

    cond do
      byte_size(trimmed) == 0 ->
        {:error, :empty_content}

      byte_size(trimmed) > @max_content_length ->
        {:error, {:content_too_long, byte_size(trimmed), @max_content_length}}

      true ->
        {:ok, trimmed}
    end
  end

  defp validate_content(_), do: {:error, :invalid_content}

  defp validate_type(%{type: type}) when type in @valid_memory_types do
    {:ok, type}
  end

  defp validate_type(%{type: type}) do
    {:error, {:invalid_memory_type, type}}
  end

  defp validate_type(_), do: {:ok, :fact}

  defp validate_confidence(%{confidence: confidence}) when is_number(confidence) do
    {:ok, Types.clamp_to_unit(confidence)}
  end

  defp validate_confidence(%{confidence: level}) when level in [:high, :medium, :low] do
    {:ok, Types.level_to_confidence(level)}
  end

  defp validate_confidence(_), do: {:ok, @default_confidence}

  # =============================================================================
  # Private Functions - Memory Building
  # =============================================================================

  defp build_memory_item(params, _context) do
    {:ok,
     %{
       id: generate_id(),
       content: params.content,
       memory_type: params.type,
       confidence: params.confidence,
       source_type: :agent,
       evidence: [],
       rationale: params.rationale,
       suggested_by: :agent,
       importance_score: 1.0,
       created_at: DateTime.utc_now(),
       access_count: 1
     }}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  # =============================================================================
  # Private Functions - Promotion
  # =============================================================================

  defp promote_immediately(memory_item, session_id) do
    memory_input = %{
      id: memory_item.id,
      content: memory_item.content,
      memory_type: memory_item.memory_type,
      confidence: memory_item.confidence,
      source_type: :agent,
      session_id: session_id,
      agent_id: nil,
      project_id: nil,
      evidence_refs: memory_item.evidence,
      rationale: memory_item.rationale,
      created_at: memory_item.created_at
    }

    Memory.persist(memory_input, session_id)
  end

  # =============================================================================
  # Private Functions - Formatting
  # =============================================================================

  defp format_success(memory_id, type) do
    %{
      remembered: true,
      memory_id: memory_id,
      memory_type: type,
      message: "Successfully stored #{type} memory with id #{memory_id}"
    }
  end

  defp format_error(reason) do
    Helpers.format_common_error(reason) || format_action_error(reason)
  end

  defp format_action_error(:empty_content) do
    "Content cannot be empty"
  end

  defp format_action_error({:content_too_long, actual, max}) do
    "Content exceeds maximum length (#{actual} > #{max} bytes)"
  end

  defp format_action_error(:invalid_content) do
    "Content must be a non-empty string"
  end

  defp format_action_error({:invalid_memory_type, type}) do
    "Invalid memory type: #{inspect(type)}. Valid types: #{inspect(@valid_memory_types)}"
  end

  defp format_action_error(reason) do
    "Failed to remember: #{inspect(reason)}"
  end

  # =============================================================================
  # Private Functions - Telemetry
  # =============================================================================

  defp emit_telemetry(session_id, memory_type, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:jido_code, :memory, :remember],
      %{duration: duration_ms},
      %{session_id: session_id, memory_type: memory_type}
    )
  end
end
