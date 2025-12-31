defmodule JidoCode.Memory.TestHelpers do
  @moduledoc """
  Shared test helpers for memory system tests.

  This module provides factory functions and utilities for creating test data
  consistently across all memory-related test files.

  ## Usage

      import JidoCode.Memory.TestHelpers

      test "example" do
        memory = create_memory("session-123", memory_type: :fact)
        # ... test logic
      end

  """

  # =============================================================================
  # Memory Factory Functions
  # =============================================================================

  @doc """
  Creates a memory map with default values suitable for testing.

  All required fields are populated with sensible defaults that can be
  overridden via the `overrides` parameter.

  ## Parameters

  - `session_id` - Session ID the memory belongs to (default: "test-session")
  - `overrides` - Map of fields to override (default: %{})

  ## Examples

      # Create with defaults
      memory = create_memory()

      # Create for specific session
      memory = create_memory("session-123")

      # Create with specific type
      memory = create_memory("session-123", memory_type: :assumption)

      # Create with multiple overrides
      memory = create_memory("session-123", %{
        memory_type: :discovery,
        confidence: 0.95,
        content: "Custom content"
      })

  """
  @spec create_memory(String.t(), map() | keyword()) :: map()
  def create_memory(session_id \\ "test-session", overrides \\ %{})

  def create_memory(session_id, overrides) when is_list(overrides) do
    create_memory(session_id, Map.new(overrides))
  end

  def create_memory(session_id, overrides) when is_map(overrides) do
    Map.merge(
      %{
        id: "mem-#{:rand.uniform(1_000_000)}",
        content: "Test memory content",
        memory_type: :fact,
        confidence: 0.85,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      },
      overrides
    )
  end

  @doc """
  Creates a memory map with all optional fields populated.

  Useful for testing persistence and retrieval of complete memory records.

  ## Parameters

  - `session_id` - Session ID the memory belongs to (default: "test-session")
  - `overrides` - Map of fields to override (default: %{})

  ## Examples

      memory = create_full_memory("session-123")
      memory = create_full_memory("session-123", agent_id: "custom-agent")

  """
  @spec create_full_memory(String.t(), map() | keyword()) :: map()
  def create_full_memory(session_id \\ "test-session", overrides \\ %{})

  def create_full_memory(session_id, overrides) when is_list(overrides) do
    create_full_memory(session_id, Map.new(overrides))
  end

  def create_full_memory(session_id, overrides) when is_map(overrides) do
    base =
      create_memory(session_id, %{
        agent_id: "test-agent-#{:rand.uniform(1000)}",
        project_id: "test-project",
        rationale: "Test rationale for remembering",
        evidence_refs: ["ref-1", "ref-2"],
        tags: ["test", "memory"],
        related_ids: ["related-1"],
        metadata: %{"key" => "value"}
      })

    Map.merge(base, overrides)
  end

  @doc """
  Creates multiple memories for batch testing.

  ## Parameters

  - `count` - Number of memories to create
  - `session_id` - Session ID for all memories (default: "test-session")
  - `overrides` - Map of fields to override for all memories (default: %{})

  ## Examples

      memories = create_memories(10)
      memories = create_memories(5, "session-123")
      memories = create_memories(5, "session-123", memory_type: :assumption)

  """
  @spec create_memories(pos_integer(), String.t(), map() | keyword()) :: [map()]
  def create_memories(count, session_id \\ "test-session", overrides \\ %{}) do
    Enum.map(1..count, fn _ -> create_memory(session_id, overrides) end)
  end

  # =============================================================================
  # Pending Memory Factory Functions
  # =============================================================================

  @doc """
  Creates a pending memory item suitable for short-term memory testing.

  ## Parameters

  - `overrides` - Map of fields to override (default: %{})

  ## Examples

      item = create_pending_item()
      item = create_pending_item(memory_type: :discovery, importance_score: 0.9)

  """
  @spec create_pending_item(map() | keyword()) :: map()
  def create_pending_item(overrides \\ %{})

  def create_pending_item(overrides) when is_list(overrides) do
    create_pending_item(Map.new(overrides))
  end

  def create_pending_item(overrides) when is_map(overrides) do
    Map.merge(
      %{
        content: "Test pending content",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        evidence: [],
        rationale: nil,
        importance_score: 0.5,
        created_at: DateTime.utc_now(),
        access_count: 0
      },
      overrides
    )
  end

  # =============================================================================
  # Store Setup Helpers
  # =============================================================================

  @doc """
  Generates unique names for isolated store testing.

  Returns a map with unique supervisor and store_manager names to avoid
  conflicts between tests.

  ## Examples

      names = unique_names()
      {:ok, sup_pid} = JidoCode.Memory.Supervisor.start_link(
        name: names.supervisor,
        store_name: names.store_manager
      )

  """
  @spec unique_names() :: %{supervisor: atom(), store_manager: atom()}
  def unique_names do
    rand = :rand.uniform(1_000_000)

    %{
      supervisor: :"memory_supervisor_test_#{rand}",
      store_manager: :"store_manager_test_#{rand}"
    }
  end

  @doc """
  Generates a unique session ID for testing.

  ## Examples

      session_id = unique_session_id()
      # => "test-session-482931"

  """
  @spec unique_session_id() :: String.t()
  def unique_session_id do
    "test-session-#{:rand.uniform(1_000_000)}"
  end

  @doc """
  Creates a temporary base path for store testing.

  ## Parameters

  - `prefix` - Prefix for the temp directory (default: "memory_test")

  ## Examples

      base_path = create_temp_base_path()
      # Creates directory and returns path

  """
  @spec create_temp_base_path(String.t()) :: String.t()
  def create_temp_base_path(prefix \\ "memory_test") do
    base_path = Path.join(System.tmp_dir!(), "#{prefix}_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(base_path)
    base_path
  end

  # =============================================================================
  # Assertion Helpers
  # =============================================================================

  @doc """
  Asserts that a stored memory contains expected fields.

  ## Examples

      assert_memory_fields(stored_memory, %{
        memory_type: :fact,
        confidence: 0.85
      })

  """
  @spec assert_memory_fields(map(), map()) :: true
  def assert_memory_fields(memory, expected) do
    Enum.each(expected, fn {key, expected_value} ->
      actual_value = Map.get(memory, key)

      unless actual_value == expected_value do
        raise ExUnit.AssertionError,
          message: "Expected #{key} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
      end
    end)

    true
  end
end
