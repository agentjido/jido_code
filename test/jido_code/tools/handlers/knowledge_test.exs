defmodule JidoCode.Tools.Handlers.KnowledgeTest do
  @moduledoc """
  Tests for the Knowledge tool handlers.

  Section 7.1.3 and 7.2.3 of Phase 7 planning document.

  Note: These tests run with the full application started (via test_helper.exs).
  The Memory Supervisor and StoreManager must be running from the application supervision tree.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Memory
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

      for memory <- memories do
        {:ok, _} = KnowledgeRemember.execute(memory, context)
      end

      # Small delay to ensure all memories are stored
      Process.sleep(50)

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
end
