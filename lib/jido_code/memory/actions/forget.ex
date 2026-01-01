defmodule JidoCode.Memory.Actions.Forget do
  @moduledoc """
  Mark a memory as superseded (soft delete).

  The memory remains in storage for provenance tracking but won't
  appear in normal recall queries. Use when information is outdated
  or incorrect.

  Optionally specify a replacement memory that supersedes the old one.
  """

  use Jido.Action,
    name: "forget",
    description:
      "Mark a memory as superseded (soft delete). " <>
        "The memory remains for provenance but won't be retrieved in normal queries.",
    schema: [
      memory_id: [
        type: :string,
        required: true,
        doc: "ID of memory to supersede"
      ],
      reason: [
        type: :string,
        required: false,
        doc: "Why this memory is being superseded"
      ],
      replacement_id: [
        type: :string,
        required: false,
        doc: "ID of memory that supersedes this one (optional)"
      ]
    ]

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions.Helpers

  # =============================================================================
  # Constants
  # =============================================================================

  @max_reason_length 500

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the maximum allowed reason length.
  """
  @spec max_reason_length() :: pos_integer()
  def max_reason_length, do: @max_reason_length

  # =============================================================================
  # Action Implementation
  # =============================================================================

  @impl true
  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(params, context) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, validated} <- validate_forget_params(params),
         {:ok, session_id} <- Helpers.get_session_id(context),
         {:ok, _memory} <- verify_memory_exists(validated.memory_id, session_id),
         :ok <- maybe_verify_replacement(validated, session_id),
         :ok <- supersede_memory(validated, session_id) do
      emit_telemetry(session_id, validated, start_time)
      {:ok, format_success(validated)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  # =============================================================================
  # Private Functions - Validation
  # =============================================================================

  defp validate_forget_params(params) do
    with {:ok, memory_id} <- validate_memory_id(params),
         {:ok, reason} <- validate_reason(params),
         {:ok, replacement_id} <- validate_replacement_id(params) do
      {:ok,
       %{
         memory_id: memory_id,
         reason: reason,
         replacement_id: replacement_id
       }}
    end
  end

  defp validate_memory_id(%{memory_id: memory_id}) when is_binary(memory_id) do
    trimmed = String.trim(memory_id)

    if byte_size(trimmed) == 0 do
      {:error, :empty_memory_id}
    else
      {:ok, trimmed}
    end
  end

  defp validate_memory_id(%{memory_id: _}), do: {:error, :invalid_memory_id}
  defp validate_memory_id(_), do: {:error, :missing_memory_id}

  defp validate_reason(%{reason: reason}) when is_binary(reason) do
    trimmed = String.trim(reason)

    cond do
      byte_size(trimmed) == 0 ->
        {:ok, nil}

      byte_size(trimmed) > @max_reason_length ->
        {:error, {:reason_too_long, byte_size(trimmed), @max_reason_length}}

      true ->
        {:ok, trimmed}
    end
  end

  defp validate_reason(_), do: {:ok, nil}

  defp validate_replacement_id(%{replacement_id: replacement_id}) when is_binary(replacement_id) do
    trimmed = String.trim(replacement_id)

    if byte_size(trimmed) == 0 do
      {:ok, nil}
    else
      {:ok, trimmed}
    end
  end

  defp validate_replacement_id(_), do: {:ok, nil}

  # =============================================================================
  # Private Functions - Memory Verification
  # =============================================================================

  defp verify_memory_exists(memory_id, session_id) do
    case Memory.get(session_id, memory_id) do
      {:ok, memory} -> {:ok, memory}
      {:error, :not_found} -> {:error, {:memory_not_found, memory_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_verify_replacement(%{replacement_id: nil}, _session_id), do: :ok

  defp maybe_verify_replacement(%{replacement_id: replacement_id}, session_id) do
    case Memory.get(session_id, replacement_id) do
      {:ok, _} -> :ok
      {:error, :not_found} -> {:error, {:replacement_not_found, replacement_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Private Functions - Supersession
  # =============================================================================

  defp supersede_memory(params, session_id) do
    Memory.supersede(session_id, params.memory_id, params.replacement_id)
  end

  # =============================================================================
  # Private Functions - Formatting
  # =============================================================================

  defp format_success(params) do
    base = %{
      forgotten: true,
      memory_id: params.memory_id,
      message: build_success_message(params)
    }

    base
    |> maybe_add_reason(params.reason)
    |> maybe_add_replacement(params.replacement_id)
  end

  defp build_success_message(%{replacement_id: nil, memory_id: memory_id}) do
    "Memory #{memory_id} has been superseded"
  end

  defp build_success_message(%{replacement_id: replacement_id, memory_id: memory_id}) do
    "Memory #{memory_id} has been superseded by #{replacement_id}"
  end

  defp maybe_add_reason(result, nil), do: result
  defp maybe_add_reason(result, reason), do: Map.put(result, :reason, reason)

  defp maybe_add_replacement(result, nil), do: result
  defp maybe_add_replacement(result, id), do: Map.put(result, :replacement_id, id)

  defp format_error(reason) do
    Helpers.format_common_error(reason) || format_action_error(reason)
  end

  defp format_action_error(:empty_memory_id) do
    "Memory ID cannot be empty"
  end

  defp format_action_error(:invalid_memory_id) do
    "Memory ID must be a string"
  end

  defp format_action_error(:missing_memory_id) do
    "Memory ID is required"
  end

  defp format_action_error({:memory_not_found, memory_id}) do
    "Memory not found: #{memory_id}"
  end

  defp format_action_error({:replacement_not_found, replacement_id}) do
    "Replacement memory not found: #{replacement_id}"
  end

  defp format_action_error({:reason_too_long, actual, max}) do
    "Reason exceeds maximum length (#{actual} > #{max} bytes)"
  end

  defp format_action_error(reason) do
    "Failed to forget: #{inspect(reason)}"
  end

  # =============================================================================
  # Private Functions - Telemetry
  # =============================================================================

  defp emit_telemetry(session_id, params, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:jido_code, :memory, :forget],
      %{duration: duration_ms},
      %{
        session_id: session_id,
        memory_id: params.memory_id,
        has_replacement: params.replacement_id != nil,
        has_reason: params.reason != nil
      }
    )
  end
end
