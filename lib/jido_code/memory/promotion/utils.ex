defmodule JidoCode.Memory.Promotion.Utils do
  @moduledoc """
  Shared utility functions for the memory promotion system.

  This module provides common functions used by both the Promotion.Engine
  and Promotion.Triggers modules, eliminating code duplication.

  ## Functions

  - `generate_id/0` - Generates cryptographically secure memory IDs
  - `format_content/1` - Converts various content types to strings
  - `build_memory_input/3` - Builds memory input maps for persistence

  """

  # Maximum content size in bytes (64KB)
  @max_content_size 65_536

  # =============================================================================
  # ID Generation
  # =============================================================================

  @doc """
  Generates a cryptographically secure unique ID.

  Uses `:crypto.strong_rand_bytes/1` to generate 16 random bytes,
  then encodes as lowercase hex (32 characters).

  ## Examples

      iex> id = Utils.generate_id()
      iex> String.length(id)
      32

      iex> id1 = Utils.generate_id()
      iex> id2 = Utils.generate_id()
      iex> id1 != id2
      true

  """
  @spec generate_id() :: String.t()
  def generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # =============================================================================
  # Content Formatting
  # =============================================================================

  @doc """
  Formats content for storage in long-term memory.

  Handles various content types:
  - Strings are passed through (with size validation)
  - Maps with `:value` and `:key` keys are formatted as "key: value"
  - Maps with `:value` key (string) extract the value
  - Maps with `:content` key (string) extract the content
  - Other terms are converted using `inspect/1`

  ## Parameters

  - `value` - The content to format

  ## Returns

  A string representation of the content, truncated if necessary.

  ## Examples

      iex> Utils.format_content("hello")
      "hello"

      iex> Utils.format_content(%{value: "test", key: :name})
      "name: \\"test\\""

      iex> Utils.format_content(%{value: "direct"})
      "direct"

      iex> Utils.format_content(123)
      "123"

  """
  @spec format_content(term()) :: String.t()
  def format_content(value) when is_binary(value) do
    truncate_content(value)
  end

  def format_content(%{value: v, key: k}) do
    "#{k}: #{inspect(v)}" |> truncate_content()
  end

  def format_content(%{value: v}) when is_binary(v) do
    truncate_content(v)
  end

  def format_content(%{content: c}) when is_binary(c) do
    truncate_content(c)
  end

  def format_content(value) do
    inspect(value) |> truncate_content()
  end

  @doc """
  Returns the maximum content size in bytes.
  """
  @spec max_content_size() :: pos_integer()
  def max_content_size, do: @max_content_size

  # Truncates content to max size with indicator
  defp truncate_content(content) when byte_size(content) <= @max_content_size do
    content
  end

  defp truncate_content(content) do
    # Truncate and add indicator
    truncated = binary_part(content, 0, @max_content_size - 20)
    truncated <> "\n...[truncated]..."
  end

  # =============================================================================
  # Memory Input Building
  # =============================================================================

  @doc """
  Builds a memory input map for persistence.

  Converts a promotion candidate into the format expected by `Memory.persist/2`.

  ## Parameters

  - `candidate` - The promotion candidate map
  - `session_id` - Session identifier
  - `opts` - Optional parameters:
    - `:agent_id` - Agent identifier
    - `:project_id` - Project identifier

  ## Returns

  A map suitable for `Memory.persist/2`.

  ## Examples

      candidate = %{
        id: nil,
        content: "Test content",
        suggested_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        evidence: [],
        rationale: nil,
        created_at: DateTime.utc_now()
      }

      input = Utils.build_memory_input(candidate, "session-123", agent_id: "agent-1")

  """
  @spec build_memory_input(map(), String.t(), keyword()) :: map()
  def build_memory_input(candidate, session_id, opts \\ []) when is_binary(session_id) do
    id = candidate[:id] || candidate.id || generate_id()
    content = format_content(candidate[:content] || candidate.content)

    %{
      id: id,
      content: content,
      memory_type: candidate[:suggested_type] || candidate.suggested_type,
      confidence: candidate[:confidence] || candidate.confidence,
      source_type: candidate[:source_type] || candidate.source_type,
      session_id: session_id,
      agent_id: Keyword.get(opts, :agent_id),
      project_id: Keyword.get(opts, :project_id),
      evidence: candidate[:evidence] || candidate.evidence || [],
      rationale: candidate[:rationale] || candidate.rationale,
      created_at: candidate[:created_at] || candidate.created_at || DateTime.utc_now()
    }
  end
end
