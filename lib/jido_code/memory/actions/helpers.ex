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
  # String Validation Helpers
  # =============================================================================

  @doc """
  Validates that a string is non-empty after trimming.

  Returns the trimmed string if valid, or an error tuple if empty or not a string.

  ## Examples

      iex> Helpers.validate_non_empty_string("hello")
      {:ok, "hello"}

      iex> Helpers.validate_non_empty_string("  ")
      {:error, :empty_string}

      iex> Helpers.validate_non_empty_string(nil)
      {:error, :not_a_string}

  """
  @spec validate_non_empty_string(term()) :: {:ok, String.t()} | {:error, :empty_string | :not_a_string}
  def validate_non_empty_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if byte_size(trimmed) == 0 do
      {:error, :empty_string}
    else
      {:ok, trimmed}
    end
  end

  def validate_non_empty_string(_), do: {:error, :not_a_string}

  @doc """
  Validates a string is non-empty and within a maximum byte length.

  Returns the trimmed string if valid, or an error tuple describing the issue.

  ## Examples

      iex> Helpers.validate_bounded_string("hello", 100)
      {:ok, "hello"}

      iex> Helpers.validate_bounded_string("", 100)
      {:error, :empty_string}

      iex> Helpers.validate_bounded_string("hello", 3)
      {:error, {:too_long, 5, 3}}

  """
  @spec validate_bounded_string(term(), pos_integer()) ::
          {:ok, String.t()} | {:error, :empty_string | :not_a_string | {:too_long, pos_integer(), pos_integer()}}
  def validate_bounded_string(value, max_length) when is_binary(value) and is_integer(max_length) do
    trimmed = String.trim(value)
    size = byte_size(trimmed)

    cond do
      size == 0 ->
        {:error, :empty_string}

      size > max_length ->
        {:error, {:too_long, size, max_length}}

      true ->
        {:ok, trimmed}
    end
  end

  def validate_bounded_string(_, _), do: {:error, :not_a_string}

  @doc """
  Validates an optional string - returns nil for empty/missing, or the trimmed value.

  Useful for optional string fields that should be nil when empty.

  ## Examples

      iex> Helpers.validate_optional_string("hello")
      {:ok, "hello"}

      iex> Helpers.validate_optional_string("  ")
      {:ok, nil}

      iex> Helpers.validate_optional_string(nil)
      {:ok, nil}

  """
  @spec validate_optional_string(term()) :: {:ok, String.t() | nil}
  def validate_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if byte_size(trimmed) == 0 do
      {:ok, nil}
    else
      {:ok, trimmed}
    end
  end

  def validate_optional_string(_), do: {:ok, nil}

  @doc """
  Validates an optional string with a maximum length.

  Returns nil for empty/missing, the trimmed value if valid, or an error if too long.

  ## Examples

      iex> Helpers.validate_optional_bounded_string("hello", 100)
      {:ok, "hello"}

      iex> Helpers.validate_optional_bounded_string("", 100)
      {:ok, nil}

      iex> Helpers.validate_optional_bounded_string("hello", 3)
      {:error, {:too_long, 5, 3}}

  """
  @spec validate_optional_bounded_string(term(), pos_integer()) ::
          {:ok, String.t() | nil} | {:error, {:too_long, pos_integer(), pos_integer()}}
  def validate_optional_bounded_string(value, max_length) when is_binary(value) and is_integer(max_length) do
    trimmed = String.trim(value)
    size = byte_size(trimmed)

    cond do
      size == 0 ->
        {:ok, nil}

      size > max_length ->
        {:error, {:too_long, size, max_length}}

      true ->
        {:ok, trimmed}
    end
  end

  def validate_optional_bounded_string(_, _), do: {:ok, nil}

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
