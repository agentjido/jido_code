defmodule JidoCode.Tools.Handlers.KnowledgeTest do
  @moduledoc """
  Tests for the Knowledge tool handlers.

  Section 7.1.3 and 7.2.3 of Phase 7 planning document.

  Note: These tests run with the full application started (via test_helper.exs).
  The Memory Supervisor and StoreManager must be running from the application supervision tree.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Tools.Handlers.Knowledge
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeRemember
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeRecall

  @moduletag :phase7

  # ============================================================================
  # KnowledgeRemember Handler Tests (Section 7.1.3)
  # ============================================================================

  describe "KnowledgeRemember.execute/2" do
    test "stores fact with high confidence" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "The project uses Phoenix 1.7 framework",
        "type" => "fact",
        "confidence" => 0.95
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "stored"
      assert result["type"] == "fact"
      assert result["confidence"] == 0.95
      assert String.starts_with?(result["memory_id"], "mem-")
    end

    test "stores assumption with default medium confidence" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "Users likely prefer dark mode",
        "type" => "assumption"
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "stored"
      assert result["type"] == "assumption"
      # Default confidence for assumptions is 0.5
      assert result["confidence"] == 0.5
    end

    test "stores decision with rationale" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "Use GenServer for state management",
        "type" => "decision",
        "rationale" => "GenServer provides supervision and OTP benefits"
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "stored"
      assert result["type"] == "decision"
      # Default confidence for decisions is 0.8
      assert result["confidence"] == 0.8
    end

    test "validates memory type enum" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "Some content",
        "type" => "invalid_type"
      }

      {:error, message} = KnowledgeRemember.execute(args, context)

      assert message =~ "Invalid memory type"
      assert message =~ "Valid types"
    end

    test "validates confidence bounds" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Test confidence > 1.0
      args = %{
        "content" => "Some content",
        "type" => "fact",
        "confidence" => 1.5
      }

      {:error, message} = KnowledgeRemember.execute(args, context)
      assert message =~ "Confidence must be between 0.0 and 1.0"

      # Test confidence < 0.0
      args_negative = %{
        "content" => "Some content",
        "type" => "fact",
        "confidence" => -0.5
      }

      {:error, message_neg} = KnowledgeRemember.execute(args_negative, context)
      assert message_neg =~ "Confidence must be between 0.0 and 1.0"
    end

    test "requires session context" do
      args = %{
        "content" => "Some content",
        "type" => "fact"
      }

      {:error, message} = KnowledgeRemember.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "requires content argument" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{"type" => "fact"}

      {:error, message} = KnowledgeRemember.execute(args, context)

      assert message =~ "content is required"
    end

    test "requires type argument" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{"content" => "Some content"}

      {:error, message} = KnowledgeRemember.execute(args, context)

      assert message =~ "type is required"
    end

    test "handles evidence_refs" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "API follows RESTful conventions",
        "type" => "fact",
        "evidence_refs" => ["lib/my_app_web/router.ex", "docs/api.md"]
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "stored"

      # Verify the memory was stored with evidence
      {:ok, memory} = Memory.get(session_id, result["memory_id"])
      assert length(memory.evidence_refs) >= 2
    end

    test "handles related_to linking" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # First, create a memory to link to
      args1 = %{
        "content" => "Original decision",
        "type" => "decision"
      }

      {:ok, json1} = KnowledgeRemember.execute(args1, context)
      result1 = Jason.decode!(json1)
      original_id = result1["memory_id"]

      # Now create a related memory
      args2 = %{
        "content" => "Follow-up insight based on decision",
        "type" => "discovery",
        "related_to" => original_id
      }

      {:ok, json2} = KnowledgeRemember.execute(args2, context)
      result2 = Jason.decode!(json2)

      assert result2["status"] == "stored"

      # Verify the memory was stored with the related_to link
      {:ok, memory} = Memory.get(session_id, result2["memory_id"])
      assert original_id in memory.evidence_refs
    end

    test "applies default confidence by type" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      type_expectations = [
        {"fact", 0.8},
        {"hypothesis", 0.5},
        {"risk", 0.6},
        {"convention", 0.8},
        {"lesson_learned", 0.7}
      ]

      for {type, expected_confidence} <- type_expectations do
        args = %{
          "content" => "Test content for #{type}",
          "type" => type
        }

        {:ok, json} = KnowledgeRemember.execute(args, context)
        result = Jason.decode!(json)

        assert result["confidence"] == expected_confidence,
               "Expected #{expected_confidence} for #{type}, got #{result["confidence"]}"
      end
    end
  end

  # ============================================================================
  # KnowledgeRecall Handler Tests (Section 7.2.3)
  # ============================================================================

  describe "KnowledgeRecall.execute/2" do
    setup do
      session_id = Uniq.UUID.uuid4()

      # Pre-populate some memories for testing recall
      memories = [
        %{
          "content" => "Phoenix is the web framework",
          "type" => "fact",
          "confidence" => 0.95
        },
        %{
          "content" => "Users prefer REST APIs",
          "type" => "assumption",
          "confidence" => 0.6
        },
        %{
          "content" => "Consider GraphQL migration",
          "type" => "decision",
          "confidence" => 0.8
        },
        %{
          "content" => "Risk of memory leaks in GenServer",
          "type" => "risk",
          "confidence" => 0.7
        },
        %{
          "content" => "Low confidence hypothesis",
          "type" => "hypothesis",
          "confidence" => 0.3
        }
      ]

      context = %{session_id: session_id}

      # Store memories synchronously - each execute call completes before returning
      for memory <- memories do
        {:ok, _} = KnowledgeRemember.execute(memory, context)
      end

      {:ok, session_id: session_id, context: context}
    end

    test "retrieves all memories for session", %{context: context} do
      # Set min_confidence to 0 to include all memories
      args = %{"limit" => 20, "min_confidence" => 0}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      # Should include all 5 test memories
      assert result["count"] >= 5
      assert length(result["memories"]) >= 5
    end

    test "filters by single type", %{context: context} do
      args = %{"types" => ["fact"]}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 1
      assert Enum.all?(result["memories"], fn m -> m["type"] == "fact" end)
    end

    test "filters by multiple types", %{context: context} do
      args = %{"types" => ["fact", "decision"]}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 2
      assert Enum.all?(result["memories"], fn m -> m["type"] in ["fact", "decision"] end)
    end

    test "filters by confidence threshold", %{context: context} do
      args = %{"min_confidence" => 0.8}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      # Should include fact (0.95) and decision (0.8), but not assumption (0.6) or hypothesis (0.3)
      assert result["count"] >= 1
      assert Enum.all?(result["memories"], fn m -> m["confidence"] >= 0.8 end)
    end

    test "filters with text search within content", %{context: context} do
      args = %{"query" => "Phoenix"}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 1

      assert Enum.all?(result["memories"], fn m ->
               String.contains?(String.downcase(m["content"]), "phoenix")
             end)
    end

    test "text search is case insensitive", %{context: context} do
      args = %{"query" => "PHOENIX"}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 1
    end

    test "respects limit", %{context: context} do
      args = %{"limit" => 2}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert length(result["memories"]) <= 2
    end

    test "returns empty for no matches", %{context: context} do
      args = %{"query" => "nonexistent_content_xyz123"}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 0
      assert result["memories"] == []
    end

    test "requires session context" do
      args = %{}

      {:error, message} = KnowledgeRecall.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "defaults to min_confidence of 0.5", %{context: context} do
      # The hypothesis with 0.3 confidence should be filtered out by default
      args = %{}

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      # Should not include the low confidence hypothesis (0.3)
      assert Enum.all?(result["memories"], fn m -> m["confidence"] >= 0.5 end)
    end

    test "excludes superseded by default", %{session_id: session_id, context: context} do
      # Create a memory, then supersede it
      args = %{
        "content" => "Old decision to supersede",
        "type" => "decision"
      }

      {:ok, json1} = KnowledgeRemember.execute(args, context)
      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Recall should not include the superseded memory
      recall_args = %{"query" => "supersede"}

      {:ok, json2} = KnowledgeRecall.execute(recall_args, context)
      result2 = Jason.decode!(json2)

      refute Enum.any?(result2["memories"], fn m -> m["id"] == old_id end)
    end

    test "includes superseded when requested", %{session_id: session_id, context: context} do
      # Create a memory, then supersede it
      args = %{
        "content" => "Memory to be superseded for test",
        "type" => "decision"
      }

      {:ok, json1} = KnowledgeRemember.execute(args, context)
      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Recall with include_superseded should include it
      recall_args = %{
        "query" => "superseded for test",
        "include_superseded" => true
      }

      {:ok, json2} = KnowledgeRecall.execute(recall_args, context)
      result2 = Jason.decode!(json2)

      assert Enum.any?(result2["memories"], fn m -> m["id"] == old_id end)
    end

    test "combines multiple filters", %{context: context} do
      args = %{
        "types" => ["fact", "decision"],
        "min_confidence" => 0.8,
        "limit" => 5
      }

      {:ok, json} = KnowledgeRecall.execute(args, context)
      result = Jason.decode!(json)

      assert Enum.all?(result["memories"], fn m ->
               m["type"] in ["fact", "decision"] and m["confidence"] >= 0.8
             end)
    end
  end

  # ============================================================================
  # Tool Definition Tests
  # ============================================================================

  describe "Knowledge.all/0" do
    test "returns list of tool definitions" do
      tools = JidoCode.Tools.Definitions.Knowledge.all()

      assert length(tools) == 2
      assert Enum.any?(tools, fn t -> t.name == "knowledge_remember" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_recall" end)
    end
  end

  # ============================================================================
  # Shared Functions Tests (Added per review suggestions)
  # ============================================================================

  describe "Knowledge.get_session_id/2" do
    test "returns session_id when valid" do
      context = %{session_id: "valid-session-id"}
      assert {:ok, "valid-session-id"} = Knowledge.get_session_id(context, "test_tool")
    end

    test "rejects empty session_id" do
      context = %{session_id: ""}
      assert {:error, message} = Knowledge.get_session_id(context, "test_tool")
      assert message =~ "non-empty session_id"
    end

    test "rejects missing session_id" do
      assert {:error, message} = Knowledge.get_session_id(%{}, "test_tool")
      assert message =~ "requires a session context"
    end
  end

  describe "Knowledge.validate_content/1" do
    test "accepts valid content" do
      assert {:ok, "valid content"} = Knowledge.validate_content("valid content")
    end

    test "rejects nil content" do
      assert {:error, "content is required"} = Knowledge.validate_content(nil)
    end

    test "rejects empty string content" do
      assert {:error, "content cannot be empty"} = Knowledge.validate_content("")
    end

    test "rejects non-string content" do
      assert {:error, "content must be a string"} = Knowledge.validate_content(123)
      assert {:error, "content must be a string"} = Knowledge.validate_content(%{})
    end

    test "rejects content exceeding size limit" do
      large_content = String.duplicate("x", Knowledge.max_content_size() + 1)
      assert {:error, message} = Knowledge.validate_content(large_content)
      assert message =~ "exceeds maximum size"
    end

    test "accepts content at size limit" do
      max_content = String.duplicate("x", Knowledge.max_content_size())
      assert {:ok, ^max_content} = Knowledge.validate_content(max_content)
    end
  end

  describe "Knowledge.safe_to_type_atom/1" do
    test "converts valid type string" do
      assert {:ok, :fact} = Knowledge.safe_to_type_atom("fact")
      assert {:ok, :fact} = Knowledge.safe_to_type_atom("FACT")
      assert {:ok, :fact} = Knowledge.safe_to_type_atom("Fact")
    end

    test "handles hyphenated types" do
      # lesson_learned exists as an atom
      assert {:ok, :lesson_learned} = Knowledge.safe_to_type_atom("lesson-learned")
    end

    test "returns error for non-existent atom" do
      assert :error = Knowledge.safe_to_type_atom("nonexistent_type_xyz")
    end

    test "returns error for non-string input" do
      assert :error = Knowledge.safe_to_type_atom(123)
      assert :error = Knowledge.safe_to_type_atom(nil)
    end
  end

  describe "Knowledge.format_timestamp/1" do
    test "formats DateTime to ISO8601" do
      {:ok, dt, _} = DateTime.from_iso8601("2024-01-15T10:30:00Z")
      assert "2024-01-15T10:30:00Z" = Knowledge.format_timestamp(dt)
    end

    test "handles nil" do
      assert nil == Knowledge.format_timestamp(nil)
    end
  end

  # ============================================================================
  # Edge Case Tests (Added per review suggestions)
  # ============================================================================

  describe "KnowledgeRemember edge cases" do
    test "handles Unicode content" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "日本語テスト content with émojis 🚀 and ñ special chars",
        "type" => "fact"
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "stored"

      # Verify stored correctly
      {:ok, memory} = Memory.get(session_id, result["memory_id"])
      assert memory.content == "日本語テスト content with émojis 🚀 and ñ special chars"
    end

    test "handles confidence boundary value 0.0" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "Zero confidence content",
        "type" => "hypothesis",
        "confidence" => 0.0
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["confidence"] == 0.0
    end

    test "handles confidence boundary value 1.0" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      args = %{
        "content" => "Maximum confidence content",
        "type" => "fact",
        "confidence" => 1.0
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)

      assert result["confidence"] == 1.0
    end

    test "rejects content exceeding size limit" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      large_content = String.duplicate("x", Knowledge.max_content_size() + 1)

      args = %{
        "content" => large_content,
        "type" => "fact"
      }

      {:error, message} = KnowledgeRemember.execute(args, context)
      assert message =~ "exceeds maximum size"
    end
  end

  # ============================================================================
  # Telemetry Tests (Added per review suggestions)
  # ============================================================================

  describe "telemetry emission" do
    test "emits telemetry for successful remember" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Attach telemetry handler
      test_pid = self()
      ref = make_ref()

      handler_id = {:test_remember, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :remember],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{
        "content" => "Telemetry test content",
        "type" => "fact"
      }

      {:ok, _} = KnowledgeRemember.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :remember], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for failed remember" do
      context = %{}

      test_pid = self()
      ref = make_ref()

      handler_id = {:test_remember_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :remember],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{
        "content" => "Test content",
        "type" => "fact"
      }

      {:error, _} = KnowledgeRemember.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :remember], _measurements, metadata}
      assert metadata.status == :error

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for successful recall" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      test_pid = self()
      ref = make_ref()

      handler_id = {:test_recall, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :recall],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}

      {:ok, _} = KnowledgeRecall.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :recall], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end
  end
end
