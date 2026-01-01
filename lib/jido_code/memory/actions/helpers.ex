defmodule JidoCode.Memory.Actions.Helpers do
  @moduledoc """
  Shared helper functions for memory actions.

  Provides common functionality for:
  - Session ID extraction and validation
  - Error message formatting
  - Confidence/timestamp handling
  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # Session ID Helpers
  # =============================================================================

  @doc """
  Extracts and validates session_id from action context.

  Validates that the session_id:
  - Is present in the context
  - Is a binary string
  - Matches the required format (alphanumeric + hyphens + underscores)
  """
  @spec get_session_id(map()) ::
          {:ok, String.t()} | {:error, :missing_session_id | :invalid_session_id}
  def get_session_id(context) do
    case context[:session_id] do
      nil ->
        {:error, :missing_session_id}

      id when is_binary(id) ->
        if Types.valid_session_id?(id) do
          {:ok, id}
        else
          {:error, :invalid_session_id}
        end

      _ ->
        {:error, :invalid_session_id}
    end
  end

  # =============================================================================
  # Validation Helpers
  # =============================================================================

  @doc """
  Validates a confidence value, clamping to [0.0, 1.0].
  Supports both numeric values and discrete levels (:high, :medium, :low).
  """
  @spec validate_confidence(map(), atom(), float()) :: {:ok, float()}
  def validate_confidence(params, key, default) do
    case Map.get(params, key) do
      conf when is_number(conf) -> {:ok, Types.clamp_to_unit(conf)}
      level when level in [:high, :medium, :low] -> {:ok, Types.level_to_confidence(level)}
      _ -> {:ok, default}
    end
  end

  # =============================================================================
  # Error Formatting
  # =============================================================================

  @doc """
  Formats common error reasons into human-readable messages.
  Returns nil for unrecognized errors (caller should provide fallback).
  """
  @spec format_common_error(term()) :: String.t() | nil
  def format_common_error(:missing_session_id), do: "Session ID is required in context"
  def format_common_error(:invalid_session_id), do: "Session ID must be a valid string"
  def format_common_error(_), do: nil

  # =============================================================================
  # Formatting Helpers
  # =============================================================================

  @doc """
  Formats a timestamp to ISO8601 string, handling nil and invalid values.
  """
  @spec format_timestamp(DateTime.t() | nil | term()) :: String.t() | nil
  def format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def format_timestamp(nil), do: nil
  def format_timestamp(other), do: inspect(other)
end
