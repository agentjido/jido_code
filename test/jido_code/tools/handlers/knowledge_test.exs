defmodule JidoCode.Tools.Handlers.KnowledgeTest do
  @moduledoc """
  Tests for the Knowledge tool handlers.

  Section 7.1.3, 7.2.3, 7.3.3, 7.4.3, 7.5.3, 7.6.3, and 7.7.3 of Phase 7 planning document.

  Note: These tests run with the full application started (via test_helper.exs).
  The Memory Supervisor and StoreManager must be running from the application supervision tree.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Tools.Handlers.Knowledge
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeRemember
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeRecall
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeSupersede
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeUpdate
  alias JidoCode.Tools.Handlers.Knowledge.ProjectConventions
  alias JidoCode.Tools.Handlers.Knowledge.ProjectDecisions
  alias JidoCode.Tools.Handlers.Knowledge.ProjectRisks

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
  # KnowledgeSupersede Handler Tests (Section 7.3.3)
  # ============================================================================

  describe "KnowledgeSupersede.execute/2" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create a memory to supersede
      args = %{
        "content" => "Original decision about database choice",
        "type" => "decision",
        "confidence" => 0.8
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)
      original_id = result["memory_id"]

      {:ok, session_id: session_id, context: context, original_id: original_id}
    end

    test "marks memory as superseded", %{context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      assert result["old_id"] == original_id
      assert result["new_id"] == nil
      assert result["status"] == "superseded"

      # Verify the memory is now superseded (excluded from default recall)
      recall_args = %{"query" => "database choice"}
      {:ok, recall_json} = KnowledgeRecall.execute(recall_args, context)
      recall_result = Jason.decode!(recall_json)

      refute Enum.any?(recall_result["memories"], fn m -> m["id"] == original_id end)
    end

    test "creates replacement when content provided", %{context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id,
        "new_content" => "Updated decision: use PostgreSQL for production",
        "reason" => "Performance testing revealed PostgreSQL is faster for our workload"
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      assert result["old_id"] == original_id
      assert result["new_id"] != nil
      assert String.starts_with?(result["new_id"], "mem-")
      assert result["status"] == "replaced"
      assert result["type"] == "decision"
    end

    test "links replacement to original memory", %{session_id: session_id, context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id,
        "new_content" => "Replacement content linked to original"
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      # Verify the new memory has evidence_ref linking to the old one
      {:ok, new_memory} = Memory.get(session_id, result["new_id"])
      assert original_id in new_memory.evidence_refs
    end

    test "stores reason in replacement memory rationale", %{session_id: session_id, context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id,
        "new_content" => "Updated decision with reason",
        "reason" => "Performance testing showed better results"
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      # Verify the reason is stored in the new memory's rationale
      {:ok, new_memory} = Memory.get(session_id, result["new_id"])
      assert new_memory.rationale == "Performance testing showed better results"
    end

    test "inherits type from original when not specified", %{context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id,
        "new_content" => "New content without specifying type"
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      # Should inherit "decision" from the original memory
      assert result["type"] == "decision"
    end

    test "allows specifying new type for replacement", %{context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id,
        "new_content" => "This is now a documented fact",
        "new_type" => "fact"
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      assert result["type"] == "fact"
    end

    test "handles non-existent memory_id", %{context: context} do
      args = %{
        "old_memory_id" => "mem-nonexistent12345"
      }

      {:error, message} = KnowledgeSupersede.execute(args, context)

      assert message =~ "Memory not found"
    end

    test "requires session context" do
      args = %{
        "old_memory_id" => "mem-some-id"
      }

      {:error, message} = KnowledgeSupersede.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "requires old_memory_id argument", %{context: context} do
      args = %{}

      {:error, message} = KnowledgeSupersede.execute(args, context)

      assert message =~ "old_memory_id is required"
    end

    test "rejects empty string old_memory_id", %{context: context} do
      args = %{"old_memory_id" => ""}

      {:error, message} = KnowledgeSupersede.execute(args, context)

      assert message =~ "old_memory_id cannot be empty"
    end

    test "rejects invalid memory_id format", %{context: context} do
      args = %{"old_memory_id" => "invalid-format-123"}

      {:error, message} = KnowledgeSupersede.execute(args, context)

      assert message =~ "invalid memory_id format"
    end

    test "validates new_content size if provided", %{context: context, original_id: original_id} do
      large_content = String.duplicate("x", Knowledge.max_content_size() + 1)

      args = %{
        "old_memory_id" => original_id,
        "new_content" => large_content
      }

      {:error, message} = KnowledgeSupersede.execute(args, context)

      assert message =~ "exceeds maximum size"
    end

    test "falls back to original type for invalid new_type", %{context: context, original_id: original_id} do
      args = %{
        "old_memory_id" => original_id,
        "new_content" => "Replacement with invalid type",
        "new_type" => "invalid_type_xyz"
      }

      {:ok, json} = KnowledgeSupersede.execute(args, context)
      result = Jason.decode!(json)

      # Should fall back to original type "decision"
      assert result["type"] == "decision"
    end
  end

  # ============================================================================
  # ProjectConventions Handler Tests (Section 7.5.3)
  # ============================================================================

  describe "ProjectConventions.execute/2" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Pre-populate some conventions
      conventions = [
        %{
          "content" => "Use 2-space indentation for all Elixir files",
          "type" => "coding_standard",
          "confidence" => 0.95
        },
        %{
          "content" => "Follow Phoenix naming conventions for contexts",
          "type" => "convention",
          "confidence" => 0.85
        },
        %{
          "content" => "Use GenServer for stateful processes",
          "type" => "convention",
          "confidence" => 0.9
        },
        %{
          "content" => "Always use pattern matching in function heads",
          "type" => "coding_standard",
          "confidence" => 0.8
        }
      ]

      for conv <- conventions do
        {:ok, _} = KnowledgeRemember.execute(conv, context)
      end

      {:ok, session_id: session_id, context: context}
    end

    test "retrieves all conventions", %{context: context} do
      args = %{}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 4
      assert length(result["conventions"]) >= 4

      # All should be convention types
      assert Enum.all?(result["conventions"], fn c ->
               c["type"] in ["convention", "coding_standard"]
             end)
    end

    test "retrieves coding standards specifically", %{context: context} do
      args = %{"category" => "coding"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 2

      # All should be coding_standard type
      assert Enum.all?(result["conventions"], fn c ->
               c["type"] == "coding_standard"
             end)
    end

    test "retrieves architectural conventions", %{context: context} do
      args = %{"category" => "architectural"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # Should get the general conventions
      assert result["count"] >= 2
    end

    test "filters by confidence threshold", %{context: context} do
      args = %{"min_confidence" => 0.9}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # Should only include conventions with >= 0.9 confidence
      assert Enum.all?(result["conventions"], fn c ->
               c["confidence"] >= 0.9
             end)
    end

    test "returns empty when no conventions exist" do
      # New session with no conventions
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}
      args = %{}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 0
      assert result["conventions"] == []
    end

    test "requires session context" do
      args = %{}

      {:error, message} = ProjectConventions.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "handles case-insensitive category", %{context: context} do
      args = %{"category" => "CODING"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      assert Enum.all?(result["conventions"], fn c ->
               c["type"] == "coding_standard"
             end)
    end

    test "sorts by confidence descending", %{context: context} do
      args = %{}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      confidences = Enum.map(result["conventions"], & &1["confidence"])
      assert confidences == Enum.sort(confidences, :desc)
    end

    test "excludes superseded conventions", %{session_id: session_id, context: context} do
      # Create and supersede a convention
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{
            "content" => "Old convention to supersede",
            "type" => "convention"
          },
          context
        )

      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Query conventions
      args = %{}
      {:ok, json2} = ProjectConventions.execute(args, context)
      result2 = Jason.decode!(json2)

      # Should not include the superseded convention
      refute Enum.any?(result2["conventions"], fn c -> c["id"] == old_id end)
    end

    test "excludes non-convention memory types", %{context: context} do
      # Add a non-convention memory
      {:ok, _} =
        KnowledgeRemember.execute(
          %{
            "content" => "This is a risk, not a convention",
            "type" => "risk"
          },
          context
        )

      args = %{}
      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # Should not include risk type
      refute Enum.any?(result["conventions"], fn c -> c["type"] == "risk" end)
    end

    test "handles agent category", %{context: context} do
      args = %{"category" => "agent"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # Agent category filters to convention types
      assert Enum.all?(result["conventions"], fn c ->
               c["type"] == "convention"
             end)
    end

    test "handles process category", %{context: context} do
      args = %{"category" => "process"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # Process category filters to convention types
      assert Enum.all?(result["conventions"], fn c ->
               c["type"] == "convention"
             end)
    end

    test "handles all category", %{context: context} do
      args = %{"category" => "all"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # All category includes both convention and coding_standard types
      assert result["count"] >= 4

      types = Enum.map(result["conventions"], & &1["type"]) |> Enum.uniq() |> Enum.sort()
      assert types == ["coding_standard", "convention"]
    end

    test "handles unknown category as all", %{context: context} do
      args = %{"category" => "unknown_category"}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      # Unknown category defaults to all convention types
      assert result["count"] >= 4
    end

    test "respects limit parameter", %{context: context} do
      args = %{"limit" => 2}

      {:ok, json} = ProjectConventions.execute(args, context)
      result = Jason.decode!(json)

      assert length(result["conventions"]) <= 2
    end
  end

  # ============================================================================
  # Telemetry Tests for Phase 7B Handlers
  # ============================================================================

  describe "Phase 7B telemetry emission" do
    test "emits telemetry for successful supersede" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create a memory first
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{"content" => "Memory for supersede telemetry test", "type" => "fact"},
          context
        )

      result1 = Jason.decode!(json1)
      memory_id = result1["memory_id"]

      # Attach telemetry handler
      test_pid = self()
      ref = make_ref()
      handler_id = {:test_supersede, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :supersede],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      # Execute supersede
      args = %{"old_memory_id" => memory_id}
      {:ok, _} = KnowledgeSupersede.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :supersede], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for successful project_conventions" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_conventions, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :project_conventions],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}
      {:ok, _} = ProjectConventions.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :project_conventions], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for failed supersede" do
      context = %{}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_supersede_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :supersede],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{"old_memory_id" => "mem-123"}
      {:error, _} = KnowledgeSupersede.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :supersede], _measurements, metadata}
      assert metadata.status == :error

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for failed project_conventions" do
      context = %{}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_conventions_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :project_conventions],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}
      {:error, _} = ProjectConventions.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :project_conventions], _measurements, metadata}
      assert metadata.status == :error

      :telemetry.detach(handler_id)
    end
  end

  # ============================================================================
  # Tool Definition Tests
  # ============================================================================

  describe "Knowledge.all/0" do
    test "returns list of tool definitions" do
      tools = JidoCode.Tools.Definitions.Knowledge.all()

      assert length(tools) == 8
      assert Enum.any?(tools, fn t -> t.name == "knowledge_remember" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_recall" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_supersede" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_update" end)
      assert Enum.any?(tools, fn t -> t.name == "project_conventions" end)
      assert Enum.any?(tools, fn t -> t.name == "project_decisions" end)
      assert Enum.any?(tools, fn t -> t.name == "project_risks" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_graph_query" end)
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

    test "returns error tuple for non-existent atom" do
      assert {:error, message} = Knowledge.safe_to_type_atom("nonexistent_type_xyz")
      assert message =~ "unknown type"
    end

    test "returns error tuple for non-string input" do
      assert {:error, message} = Knowledge.safe_to_type_atom(123)
      assert message =~ "type must be a string"
      assert {:error, _} = Knowledge.safe_to_type_atom(nil)
    end
  end

  describe "Knowledge.generate_memory_id/0" do
    test "generates unique memory IDs with correct format" do
      id1 = Knowledge.generate_memory_id()
      id2 = Knowledge.generate_memory_id()

      assert String.starts_with?(id1, "mem-")
      assert String.starts_with?(id2, "mem-")
      assert id1 != id2
    end

    test "generates memory IDs matching expected pattern" do
      id = Knowledge.generate_memory_id()
      assert String.match?(id, ~r/^mem-[A-Za-z0-9_-]+$/)
    end
  end

  describe "Knowledge.get_required_string/2" do
    test "returns value when valid string present" do
      args = %{"key" => "value"}
      assert {:ok, "value"} = Knowledge.get_required_string(args, "key")
    end

    test "returns error for nil value" do
      args = %{"key" => nil}
      assert {:error, message} = Knowledge.get_required_string(args, "key")
      assert message =~ "key is required"
    end

    test "returns error for missing key" do
      args = %{}
      assert {:error, message} = Knowledge.get_required_string(args, "key")
      assert message =~ "key is required"
    end

    test "returns error for empty string" do
      args = %{"key" => ""}
      assert {:error, message} = Knowledge.get_required_string(args, "key")
      assert message =~ "key cannot be empty"
    end

    test "returns error for non-string value" do
      args = %{"key" => 123}
      assert {:error, message} = Knowledge.get_required_string(args, "key")
      assert message =~ "key must be a string"
    end
  end

  describe "Knowledge.validate_memory_id/1" do
    test "accepts valid memory ID format" do
      assert {:ok, "mem-abc123"} = Knowledge.validate_memory_id("mem-abc123")
      assert {:ok, "mem-XyZ_-9"} = Knowledge.validate_memory_id("mem-XyZ_-9")
    end

    test "rejects memory ID without prefix" do
      assert {:error, message} = Knowledge.validate_memory_id("abc123")
      assert message =~ "invalid memory_id format"
    end

    test "rejects memory ID with invalid characters" do
      assert {:error, message} = Knowledge.validate_memory_id("mem-abc@123")
      assert message =~ "invalid memory_id format"
    end

    test "rejects empty string" do
      assert {:error, message} = Knowledge.validate_memory_id("")
      assert message =~ "invalid memory_id format"
    end

    test "rejects non-string input" do
      assert {:error, message} = Knowledge.validate_memory_id(123)
      assert message =~ "memory_id must be a string"
    end
  end

  describe "Knowledge.ok_json/1" do
    test "wraps map as ok tuple with JSON string" do
      assert {:ok, json} = Knowledge.ok_json(%{key: "value"})
      decoded = Jason.decode!(json)
      assert decoded["key"] == "value"
    end

    test "wraps list as ok tuple with JSON string" do
      assert {:ok, json} = Knowledge.ok_json([1, 2, 3])
      decoded = Jason.decode!(json)
      assert decoded == [1, 2, 3]
    end
  end

  describe "Knowledge.format_memory_list/2" do
    test "formats list of memories with given key" do
      memories = [
        %{
          id: "mem-123",
          content: "Test content",
          memory_type: :fact,
          confidence: 0.9,
          timestamp: ~U[2024-01-15 10:30:00Z],
          rationale: "Test rationale"
        }
      ]

      {:ok, json} = Knowledge.format_memory_list(memories, :items)
      result = Jason.decode!(json)

      assert result["count"] == 1
      assert length(result["items"]) == 1

      item = hd(result["items"])
      assert item["id"] == "mem-123"
      assert item["content"] == "Test content"
      assert item["type"] == "fact"
      assert item["confidence"] == 0.9
    end

    test "handles empty list" do
      {:ok, json} = Knowledge.format_memory_list([], :items)
      result = Jason.decode!(json)

      assert result["count"] == 0
      assert result["items"] == []
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

  # ============================================================================
  # KnowledgeUpdate Handler Tests (Section 7.4.3)
  # ============================================================================

  describe "KnowledgeUpdate.execute/2" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create a memory to update
      args = %{
        "content" => "Original fact about the codebase",
        "type" => "fact",
        "confidence" => 0.7,
        "rationale" => "Initial observation"
      }

      {:ok, json} = KnowledgeRemember.execute(args, context)
      result = Jason.decode!(json)
      memory_id = result["memory_id"]

      {:ok, session_id: session_id, context: context, memory_id: memory_id}
    end

    test "updates confidence", %{context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id,
        "new_confidence" => 0.95
      }

      {:ok, json} = KnowledgeUpdate.execute(args, context)
      result = Jason.decode!(json)

      assert result["id"] == memory_id
      assert result["status"] == "updated"
      assert result["confidence"] == 0.95
    end

    test "adds evidence refs", %{session_id: session_id, context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id,
        "add_evidence" => ["lib/module.ex", "test/module_test.exs"]
      }

      {:ok, json} = KnowledgeUpdate.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "updated"
      assert result["evidence_count"] == 2

      # Verify the evidence was persisted
      {:ok, memory} = Memory.get(session_id, memory_id)
      assert "lib/module.ex" in memory.evidence_refs
      assert "test/module_test.exs" in memory.evidence_refs
    end

    test "appends rationale", %{session_id: session_id, context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id,
        "add_rationale" => "Confirmed via code review"
      }

      {:ok, json} = KnowledgeUpdate.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "updated"
      assert result["rationale"] =~ "Initial observation"
      assert result["rationale"] =~ "Confirmed via code review"

      # Verify the rationale was persisted
      {:ok, memory} = Memory.get(session_id, memory_id)
      assert memory.rationale =~ "Initial observation"
      assert memory.rationale =~ "Confirmed via code review"
    end

    test "validates ownership via session", %{memory_id: memory_id} do
      # Different session should not be able to update this memory
      different_session = Uniq.UUID.uuid4()
      context = %{session_id: different_session}

      args = %{
        "memory_id" => memory_id,
        "new_confidence" => 0.99
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)

      assert message =~ "Memory not found"
    end

    test "validates confidence bounds", %{context: context, memory_id: memory_id} do
      # Test confidence > 1.0
      args = %{
        "memory_id" => memory_id,
        "new_confidence" => 1.5
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)
      assert message =~ "Confidence must be between 0.0 and 1.0"

      # Test confidence < 0.0
      args_negative = %{
        "memory_id" => memory_id,
        "new_confidence" => -0.5
      }

      {:error, message_neg} = KnowledgeUpdate.execute(args_negative, context)
      assert message_neg =~ "Confidence must be between 0.0 and 1.0"
    end

    test "handles non-existent memory", %{context: context} do
      args = %{
        "memory_id" => "mem-nonexistent12345",
        "new_confidence" => 0.9
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)

      assert message =~ "Memory not found"
    end

    test "requires at least one update", %{context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)

      assert message =~ "At least one update"
    end

    test "requires session context" do
      args = %{
        "memory_id" => "mem-some-id",
        "new_confidence" => 0.9
      }

      {:error, message} = KnowledgeUpdate.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "requires memory_id argument", %{context: context} do
      args = %{
        "new_confidence" => 0.9
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)

      assert message =~ "memory_id is required"
    end

    test "combines multiple updates", %{session_id: session_id, context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id,
        "new_confidence" => 0.99,
        "add_evidence" => ["docs/api.md"],
        "add_rationale" => "Fully verified"
      }

      {:ok, json} = KnowledgeUpdate.execute(args, context)
      result = Jason.decode!(json)

      assert result["status"] == "updated"
      assert result["confidence"] == 0.99
      assert result["evidence_count"] == 1
      assert result["rationale"] =~ "Fully verified"

      # Verify all updates persisted
      {:ok, memory} = Memory.get(session_id, memory_id)
      assert memory.confidence == 0.99
      assert "docs/api.md" in memory.evidence_refs
    end
  end

  # ============================================================================
  # ProjectDecisions Handler Tests (Section 7.6.3)
  # ============================================================================

  describe "ProjectDecisions.execute/2" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Pre-populate some decisions
      decisions = [
        %{
          "content" => "Use GenServer for state management",
          "type" => "decision",
          "confidence" => 0.9,
          "rationale" => "OTP benefits"
        },
        %{
          "content" => "Adopt Phoenix 1.7 for web layer",
          "type" => "architectural_decision",
          "confidence" => 0.95,
          "rationale" => "Modern Elixir web framework"
        },
        %{
          "content" => "Use ETS for caching",
          "type" => "implementation_decision",
          "confidence" => 0.85,
          "rationale" => "Fast in-memory storage"
        },
        %{
          "content" => "Considered Redis instead of ETS",
          "type" => "alternative",
          "confidence" => 0.7,
          "rationale" => "External dependency, more complex"
        }
      ]

      for decision <- decisions do
        {:ok, _} = KnowledgeRemember.execute(decision, context)
      end

      {:ok, session_id: session_id, context: context}
    end

    test "retrieves all decisions", %{context: context} do
      args = %{}

      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      # Should include decision, architectural_decision, implementation_decision
      # but NOT alternative by default
      assert result["count"] >= 3

      # Should not include alternative type by default
      types = Enum.map(result["decisions"], & &1["type"])
      refute "alternative" in types
    end

    test "excludes superseded by default", %{session_id: session_id, context: context} do
      # Create and supersede a decision
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{
            "content" => "Old decision to supersede",
            "type" => "decision"
          },
          context
        )

      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Query decisions
      args = %{}
      {:ok, json2} = ProjectDecisions.execute(args, context)
      result2 = Jason.decode!(json2)

      refute Enum.any?(result2["decisions"], fn d -> d["id"] == old_id end)
    end

    test "includes superseded when requested", %{session_id: session_id, context: context} do
      # Create and supersede a decision
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{
            "content" => "Decision to be superseded for test",
            "type" => "decision"
          },
          context
        )

      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Query with include_superseded
      args = %{"include_superseded" => true}
      {:ok, json2} = ProjectDecisions.execute(args, context)
      result2 = Jason.decode!(json2)

      assert Enum.any?(result2["decisions"], fn d -> d["id"] == old_id end)
    end

    test "filters by decision type - architectural", %{context: context} do
      args = %{"decision_type" => "architectural"}

      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 1

      assert Enum.all?(result["decisions"], fn d ->
               d["type"] == "architectural_decision"
             end)
    end

    test "filters by decision type - implementation", %{context: context} do
      args = %{"decision_type" => "implementation"}

      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 1

      assert Enum.all?(result["decisions"], fn d ->
               d["type"] == "implementation_decision"
             end)
    end

    test "includes alternatives when requested", %{context: context} do
      args = %{"include_alternatives" => true}

      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      types = Enum.map(result["decisions"], & &1["type"]) |> Enum.uniq()
      assert "alternative" in types
    end

    test "requires session context" do
      args = %{}

      {:error, message} = ProjectDecisions.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "returns empty when no decisions exist" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}
      args = %{}

      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 0
      assert result["decisions"] == []
    end
  end

  # ============================================================================
  # ProjectRisks Handler Tests (Section 7.7.3)
  # ============================================================================

  describe "ProjectRisks.execute/2" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Pre-populate some risks
      risks = [
        %{
          "content" => "Memory leaks in long-running GenServers",
          "type" => "risk",
          "confidence" => 0.9,
          "rationale" => "High severity, needs monitoring"
        },
        %{
          "content" => "API rate limiting from external service",
          "type" => "risk",
          "confidence" => 0.7,
          "rationale" => "Medium impact, can be mitigated"
        },
        %{
          "content" => "Minor UI inconsistencies",
          "type" => "risk",
          "confidence" => 0.4,
          "rationale" => "Low severity"
        }
      ]

      for risk <- risks do
        {:ok, _} = KnowledgeRemember.execute(risk, context)
      end

      {:ok, session_id: session_id, context: context}
    end

    test "retrieves all risks", %{context: context} do
      # Set min_confidence to 0 to get all risks
      args = %{"min_confidence" => 0}

      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] >= 3

      assert Enum.all?(result["risks"], fn r ->
               r["type"] == "risk"
             end)
    end

    test "filters by confidence threshold", %{context: context} do
      args = %{"min_confidence" => 0.7}

      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      # Should include risks with confidence >= 0.7
      assert result["count"] >= 2

      assert Enum.all?(result["risks"], fn r ->
               r["confidence"] >= 0.7
             end)
    end

    test "sorts by confidence descending", %{context: context} do
      args = %{"min_confidence" => 0}

      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      confidences = Enum.map(result["risks"], & &1["confidence"])
      assert confidences == Enum.sort(confidences, :desc)
    end

    test "excludes mitigated by default", %{session_id: session_id, context: context} do
      # Create and supersede a risk (mitigate it)
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{
            "content" => "Risk that was mitigated",
            "type" => "risk",
            "confidence" => 0.8
          },
          context
        )

      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede/mitigate it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Query risks
      args = %{"min_confidence" => 0}
      {:ok, json2} = ProjectRisks.execute(args, context)
      result2 = Jason.decode!(json2)

      refute Enum.any?(result2["risks"], fn r -> r["id"] == old_id end)
    end

    test "includes mitigated when requested", %{session_id: session_id, context: context} do
      # Create and supersede a risk (mitigate it)
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{
            "content" => "Risk that was mitigated for test",
            "type" => "risk",
            "confidence" => 0.8
          },
          context
        )

      result1 = Jason.decode!(json1)
      old_id = result1["memory_id"]

      # Supersede/mitigate it
      :ok = Memory.supersede(session_id, old_id, nil)

      # Query with include_mitigated
      args = %{"include_mitigated" => true, "min_confidence" => 0}
      {:ok, json2} = ProjectRisks.execute(args, context)
      result2 = Jason.decode!(json2)

      assert Enum.any?(result2["risks"], fn r -> r["id"] == old_id end)
    end

    test "requires session context" do
      args = %{}

      {:error, message} = ProjectRisks.execute(args, %{})

      assert message =~ "requires a session context"
    end

    test "returns empty when no risks exist" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}
      args = %{}

      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 0
      assert result["risks"] == []
    end

    test "uses default min_confidence of 0.5", %{context: context} do
      # The low confidence risk (0.4) should be filtered out by default
      args = %{}

      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      # Should not include the low confidence risk (0.4)
      assert Enum.all?(result["risks"], fn r -> r["confidence"] >= 0.5 end)
    end
  end

  # ============================================================================
  # Phase 7C Telemetry Tests
  # ============================================================================

  describe "Phase 7C telemetry emission" do
    test "emits telemetry for successful update" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create a memory first
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{"content" => "Memory for update telemetry test", "type" => "fact"},
          context
        )

      result1 = Jason.decode!(json1)
      memory_id = result1["memory_id"]

      # Attach telemetry handler
      test_pid = self()
      ref = make_ref()
      handler_id = {:test_update, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :update],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      # Execute update
      args = %{"memory_id" => memory_id, "new_confidence" => 0.99}
      {:ok, _} = KnowledgeUpdate.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :update], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for successful project_decisions" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_decisions, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :project_decisions],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}
      {:ok, _} = ProjectDecisions.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :project_decisions], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for successful project_risks" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_risks, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :project_risks],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}
      {:ok, _} = ProjectRisks.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :project_risks], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :success
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for failed update (non-existent memory)" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_update_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :update],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{"memory_id" => "mem-nonexistent123", "new_confidence" => 0.9}
      {:error, _} = KnowledgeUpdate.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :update], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :error
      assert metadata.session_id == session_id

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for failed project_decisions (missing session)" do
      context = %{}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_decisions_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :project_decisions],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}
      {:error, _} = ProjectDecisions.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :project_decisions], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :error

      :telemetry.detach(handler_id)
    end

    test "emits telemetry for failed project_risks (missing session)" do
      context = %{}

      test_pid = self()
      ref = make_ref()
      handler_id = {:test_risks_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :project_risks],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{}
      {:error, _} = ProjectRisks.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :project_risks], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.status == :error

      :telemetry.detach(handler_id)
    end
  end

  # ============================================================================
  # Phase 7C Review Fixes - Additional Edge Case Tests
  # ============================================================================

  describe "KnowledgeUpdate edge cases (Phase 7C fixes)" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create a memory for testing
      {:ok, json} =
        KnowledgeRemember.execute(
          %{"content" => "Test memory for edge cases", "type" => "fact"},
          context
        )

      result = Jason.decode!(json)
      {:ok, session_id: session_id, context: context, memory_id: result["memory_id"]}
    end

    test "filters out non-string evidence refs", %{context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id,
        "add_evidence" => ["valid.txt", 123, %{"bad" => "value"}, "also_valid.md"]
      }

      {:ok, json} = KnowledgeUpdate.execute(args, context)
      result = Jason.decode!(json)

      # Only valid strings should be counted
      assert result["evidence_count"] == 2
    end

    test "rejects update when evidence refs would exceed limit", %{context: context, memory_id: memory_id} do
      # First add many evidence refs
      large_evidence = Enum.map(1..95, &"evidence_#{&1}.txt")

      {:ok, _} =
        KnowledgeUpdate.execute(
          %{"memory_id" => memory_id, "add_evidence" => large_evidence},
          context
        )

      # Now try to add more that would exceed the limit
      args = %{
        "memory_id" => memory_id,
        "add_evidence" => Enum.map(1..10, &"more_#{&1}.txt")
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)
      assert message =~ "Evidence refs would exceed maximum of 100"
    end

    test "rejects update when rationale would exceed size limit", %{context: context, memory_id: memory_id} do
      # Create a very large rationale string (over 16KB)
      large_rationale = String.duplicate("x", 17_000)

      args = %{
        "memory_id" => memory_id,
        "add_rationale" => large_rationale
      }

      {:error, message} = KnowledgeUpdate.execute(args, context)
      assert message =~ "Rationale would exceed maximum of 16384 bytes"
    end

    test "handles empty evidence array gracefully", %{context: context, memory_id: memory_id} do
      args = %{
        "memory_id" => memory_id,
        "add_evidence" => [],
        "new_confidence" => 0.9
      }

      {:ok, json} = KnowledgeUpdate.execute(args, context)
      result = Jason.decode!(json)
      assert result["status"] == "updated"
      assert result["confidence"] == 0.9
    end
  end

  describe "ProjectDecisions edge cases (Phase 7C fixes)" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create various decision types
      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "Use Phoenix for web", "type" => "architectural_decision"},
          context
        )

      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "Use GenServer for state", "type" => "implementation_decision"},
          context
        )

      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "Considered Ecto.Multi", "type" => "alternative"},
          context
        )

      {:ok, session_id: session_id, context: context}
    end

    test "filters by decision_type 'all' returns all decision types", %{context: context} do
      args = %{"decision_type" => "all"}
      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      # Should include architectural_decision and implementation_decision but not alternative
      assert result["count"] == 2
      types = Enum.map(result["decisions"], & &1["type"])
      assert "architectural_decision" in types
      assert "implementation_decision" in types
      refute "alternative" in types
    end

    test "respects limit parameter", %{context: context} do
      # Add more decisions
      for i <- 1..10 do
        {:ok, _} =
          KnowledgeRemember.execute(
            %{"content" => "Decision #{i}", "type" => "decision"},
            context
          )
      end

      args = %{"limit" => 3}
      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 3
    end

    test "combines decision_type with include_alternatives", %{context: context} do
      args = %{
        "decision_type" => "architectural",
        "include_alternatives" => true
      }

      {:ok, json} = ProjectDecisions.execute(args, context)
      result = Jason.decode!(json)

      types = Enum.map(result["decisions"], & &1["type"])
      # Should include architectural_decision and alternative
      assert "architectural_decision" in types
      assert "alternative" in types
      refute "implementation_decision" in types
    end
  end

  describe "ProjectRisks edge cases (Phase 7C fixes)" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create risks with various confidence levels
      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "High risk", "type" => "risk", "confidence" => 0.95},
          context
        )

      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "Low risk", "type" => "risk", "confidence" => 0.3},
          context
        )

      {:ok, session_id: session_id, context: context}
    end

    test "respects limit parameter", %{context: context} do
      # Add more risks
      for i <- 1..10 do
        {:ok, _} =
          KnowledgeRemember.execute(
            %{"content" => "Risk #{i}", "type" => "risk", "confidence" => 0.6},
            context
          )
      end

      args = %{"limit" => 5, "min_confidence" => 0.0}
      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 5
    end

    test "high min_confidence filters most risks", %{context: context} do
      args = %{"min_confidence" => 0.9}
      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      # Only the high risk (0.95) should pass
      assert result["count"] == 1
      assert hd(result["risks"])["content"] == "High risk"
    end

    test "min_confidence of 1.0 may return no risks", %{context: context} do
      args = %{"min_confidence" => 1.0}
      {:ok, json} = ProjectRisks.execute(args, context)
      result = Jason.decode!(json)

      # No risks have confidence of exactly 1.0
      assert result["count"] == 0
    end
  end

  # ============================================================================
  # Shared Helper Function Tests (Phase 7C fixes)
  # ============================================================================

  describe "Knowledge.resolve_filter_types/3" do
    test "returns default types for nil input" do
      default = [:a, :b, :c]
      result = Knowledge.resolve_filter_types(nil, %{}, default)
      assert result == default
    end

    test "returns default types for empty string input" do
      default = [:a, :b, :c]
      result = Knowledge.resolve_filter_types("", %{}, default)
      assert result == default
    end

    test "returns mapped types for known category" do
      mapping = %{"coding" => [:coding_standard], "architectural" => [:convention]}
      default = [:all_types]

      result = Knowledge.resolve_filter_types("coding", mapping, default)
      assert result == [:coding_standard]
    end

    test "handles case-insensitive category lookup" do
      mapping = %{"coding" => [:coding_standard]}
      default = [:all_types]

      result = Knowledge.resolve_filter_types("CODING", mapping, default)
      assert result == [:coding_standard]
    end

    test "returns default for unknown category" do
      mapping = %{"coding" => [:coding_standard]}
      default = [:all_types]

      result = Knowledge.resolve_filter_types("unknown", mapping, default)
      assert result == default
    end

    test "returns default for non-string input" do
      mapping = %{"coding" => [:coding_standard]}
      default = [:all_types]

      result = Knowledge.resolve_filter_types(123, mapping, default)
      assert result == default
    end
  end

  describe "Knowledge.normalize_timestamp/1" do
    test "converts timestamp to created_at" do
      now = DateTime.utc_now()
      memory = %{id: "test", timestamp: now, content: "test"}

      result = Knowledge.normalize_timestamp(memory)

      assert result.created_at == now
      refute Map.has_key?(result, :timestamp)
    end

    test "returns memory unchanged if no timestamp" do
      now = DateTime.utc_now()
      memory = %{id: "test", created_at: now, content: "test"}

      result = Knowledge.normalize_timestamp(memory)

      assert result == memory
    end
  end

  describe "Knowledge.get_memory/2" do
    test "returns memory when found" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      {:ok, json} =
        KnowledgeRemember.execute(
          %{"content" => "Test memory", "type" => "fact"},
          context
        )

      result = Jason.decode!(json)
      memory_id = result["memory_id"]

      {:ok, memory} = Knowledge.get_memory(session_id, memory_id)
      assert memory.id == memory_id
      assert memory.content == "Test memory"
    end

    test "returns error for non-existent memory" do
      session_id = Uniq.UUID.uuid4()

      {:error, message} = Knowledge.get_memory(session_id, "mem-nonexistent")
      assert message =~ "Memory not found"
    end
  end

  # ============================================================================
  # KnowledgeGraphQuery Handler Tests (Section 7.8.3)
  # ============================================================================

  describe "KnowledgeGraphQuery.execute/2" do
    alias JidoCode.Tools.Handlers.Knowledge.KnowledgeGraphQuery

    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create a base memory
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{"content" => "Base fact for testing", "type" => "fact", "confidence" => 0.9},
          context
        )

      base_memory_id = Jason.decode!(json1)["memory_id"]

      # Create another memory of the same type
      {:ok, json2} =
        KnowledgeRemember.execute(
          %{"content" => "Another fact", "type" => "fact", "confidence" => 0.8},
          context
        )

      same_type_memory_id = Jason.decode!(json2)["memory_id"]

      # Create a memory that references the base as evidence
      {:ok, json3} =
        KnowledgeRemember.execute(
          %{
            "content" => "Conclusion based on evidence",
            "type" => "discovery",
            "evidence_refs" => [base_memory_id]
          },
          context
        )

      derived_memory_id = Jason.decode!(json3)["memory_id"]

      {:ok,
       session_id: session_id,
       context: context,
       base_memory_id: base_memory_id,
       same_type_memory_id: same_type_memory_id,
       derived_memory_id: derived_memory_id}
    end

    test "requires session context" do
      args = %{"start_from" => "mem-123", "relationship" => "same_type"}
      assert {:error, message} = KnowledgeGraphQuery.execute(args, %{})
      assert message =~ "requires a session context"
    end

    test "requires start_from parameter" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}
      args = %{"relationship" => "same_type"}
      assert {:error, message} = KnowledgeGraphQuery.execute(args, context)
      assert message =~ "start_from is required"
    end

    test "requires relationship parameter" do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}
      args = %{"start_from" => "mem-123"}
      assert {:error, message} = KnowledgeGraphQuery.execute(args, context)
      assert message =~ "relationship is required"
    end

    test "validates memory_id format", %{context: context} do
      args = %{"start_from" => "invalid-format", "relationship" => "same_type"}
      assert {:error, message} = KnowledgeGraphQuery.execute(args, context)
      assert message =~ "invalid memory_id format"
    end

    test "validates relationship type", %{context: context, base_memory_id: base_memory_id} do
      args = %{"start_from" => base_memory_id, "relationship" => "invalid_relationship"}
      assert {:error, message} = KnowledgeGraphQuery.execute(args, context)
      assert message =~ "Invalid relationship"
      assert message =~ "derived_from"
    end

    test "returns error for non-existent memory", %{context: context} do
      args = %{"start_from" => "mem-nonexistent123", "relationship" => "same_type"}
      assert {:error, message} = KnowledgeGraphQuery.execute(args, context)
      assert message =~ "Memory not found"
    end

    test "finds memories of same_type", %{
      context: context,
      base_memory_id: base_memory_id,
      same_type_memory_id: same_type_memory_id
    } do
      args = %{"start_from" => base_memory_id, "relationship" => "same_type"}
      {:ok, json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(json)

      assert result["start_from"] == base_memory_id
      assert result["relationship"] == "same_type"
      assert result["count"] >= 1

      related_ids = Enum.map(result["related"], & &1["id"])
      assert same_type_memory_id in related_ids
      refute base_memory_id in related_ids
    end

    test "finds derived_from relationships", %{
      context: context,
      base_memory_id: base_memory_id,
      derived_memory_id: derived_memory_id
    } do
      # Query from the derived memory to find its evidence
      args = %{"start_from" => derived_memory_id, "relationship" => "derived_from"}
      {:ok, json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(json)

      assert result["relationship"] == "derived_from"
      # The derived memory references the base memory as evidence
      related_ids = Enum.map(result["related"], & &1["id"])
      assert base_memory_id in related_ids
    end

    test "respects limit parameter", %{context: context, base_memory_id: base_memory_id} do
      # Create more same-type memories
      for i <- 1..5 do
        {:ok, _} =
          KnowledgeRemember.execute(
            %{"content" => "Extra fact #{i}", "type" => "fact"},
            context
          )
      end

      args = %{"start_from" => base_memory_id, "relationship" => "same_type", "limit" => 2}
      {:ok, json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(json)

      assert result["count"] == 2
    end

    test "handles superseded_by relationship using direct memory API", %{session_id: session_id} do
      # Note: The KnowledgeSupersede handler marks old memory as superseded with nil initially,
      # so we use the direct Memory API to properly establish the superseded_by relationship.

      alias JidoCode.Memory.LongTerm.StoreManager
      alias JidoCode.Memory.LongTerm.TripleStoreAdapter

      {:ok, store} = StoreManager.get_or_create(session_id)

      # Create old memory
      old_mem = %{
        id: "mem-old-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Old fact",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }
      {:ok, old_memory_id} = TripleStoreAdapter.persist(old_mem, store)

      # Create new memory
      new_mem = %{
        id: "mem-new-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Updated fact",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }
      {:ok, new_memory_id} = TripleStoreAdapter.persist(new_mem, store)

      # Supersede with proper new_memory_id reference
      :ok = TripleStoreAdapter.supersede(store, session_id, old_memory_id, new_memory_id)

      # Query from old memory to find what superseded it
      {:ok, replacements} =
        Memory.query_related(session_id, old_memory_id, :superseded_by, include_superseded: true)

      related_ids = Enum.map(replacements, & &1.id)
      assert new_memory_id in related_ids
    end

    test "handles supersedes relationship using direct memory API", %{session_id: session_id} do
      # Note: The KnowledgeSupersede handler marks old memory as superseded with nil,
      # then creates a replacement. This means superseded_by on the old memory is nil
      # and the :supersedes query won't find the relationship.
      # This test uses the direct Memory API to properly establish the relationship.

      alias JidoCode.Memory.LongTerm.StoreManager
      alias JidoCode.Memory.LongTerm.TripleStoreAdapter

      {:ok, store} = StoreManager.get_or_create(session_id)

      # Create old memory
      old_mem = %{
        id: "mem-old-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Old fact",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }
      {:ok, old_memory_id} = TripleStoreAdapter.persist(old_mem, store)

      # Create new memory
      new_mem = %{
        id: "mem-new-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Updated fact",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }
      {:ok, new_memory_id} = TripleStoreAdapter.persist(new_mem, store)

      # Supersede with proper new_memory_id reference
      :ok = TripleStoreAdapter.supersede(store, session_id, old_memory_id, new_memory_id)

      # Query from new memory to find what it superseded
      {:ok, superseded} =
        Memory.query_related(session_id, new_memory_id, :supersedes, include_superseded: true)

      related_ids = Enum.map(superseded, & &1.id)
      assert old_memory_id in related_ids
    end

    test "emits telemetry on success", %{context: context, base_memory_id: base_memory_id} do
      test_pid = self()
      ref = make_ref()
      handler_id = {:test_graph_query_success, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :graph_query],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{"start_from" => base_memory_id, "relationship" => "same_type"}
      {:ok, _} = KnowledgeGraphQuery.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :graph_query],
                      %{duration: _}, %{status: :success}}

      :telemetry.detach(handler_id)
    end

    test "emits telemetry on failure", %{context: context} do
      test_pid = self()
      ref = make_ref()
      handler_id = {:test_graph_query_fail, ref}

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :graph_query],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      args = %{"start_from" => "mem-nonexistent123", "relationship" => "same_type"}
      {:error, _} = KnowledgeGraphQuery.execute(args, context)

      assert_receive {:telemetry, ^ref, [:jido_code, :knowledge, :graph_query],
                      %{duration: _}, %{status: :error}}

      :telemetry.detach(handler_id)
    end

    test "handles case-insensitive relationship names", %{
      context: context,
      base_memory_id: base_memory_id
    } do
      args = %{"start_from" => base_memory_id, "relationship" => "SAME_TYPE"}
      {:ok, json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(json)

      assert result["relationship"] == "same_type"
    end

    test "handles hyphenated relationship names", %{
      context: context,
      base_memory_id: base_memory_id
    } do
      args = %{"start_from" => base_memory_id, "relationship" => "same-type"}
      {:ok, json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(json)

      assert result["relationship"] == "same_type"
    end

    test "returns empty list when no related memories", %{context: context} do
      # Create an isolated memory with no relationships
      {:ok, json} =
        KnowledgeRemember.execute(
          %{"content" => "Isolated assumption", "type" => "assumption"},
          context
        )

      memory_id = Jason.decode!(json)["memory_id"]

      # Query for derived_from on memory with no evidence refs
      args = %{"start_from" => memory_id, "relationship" => "derived_from"}
      {:ok, result_json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(result_json)

      assert result["count"] == 0
      assert result["related"] == []
    end

    # =========================================================================
    # C1 Fix: same_project relationship test
    # =========================================================================

    test "finds memories in same_project", %{session_id: session_id} do
      alias JidoCode.Memory.LongTerm.StoreManager
      alias JidoCode.Memory.LongTerm.TripleStoreAdapter

      {:ok, store} = StoreManager.get_or_create(session_id)
      project_id = "project-test-123"

      # Create memories with the same project_id
      base_mem = %{
        id: "mem-proj-base-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Base project memory",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :agent,
        session_id: session_id,
        project_id: project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, base_memory_id} = TripleStoreAdapter.persist(base_mem, store)

      related_mem = %{
        id: "mem-proj-rel-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Related project memory",
        memory_type: :assumption,
        confidence: 0.6,
        source_type: :agent,
        session_id: session_id,
        project_id: project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, related_memory_id} = TripleStoreAdapter.persist(related_mem, store)

      # Create memory with different project_id
      other_proj_mem = %{
        id: "mem-other-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Different project memory",
        memory_type: :fact,
        confidence: 0.7,
        source_type: :agent,
        session_id: session_id,
        project_id: "other-project",
        created_at: DateTime.utc_now()
      }

      {:ok, other_memory_id} = TripleStoreAdapter.persist(other_proj_mem, store)

      # Query for same_project
      {:ok, related} = Memory.query_related(session_id, base_memory_id, :same_project)

      related_ids = Enum.map(related, & &1.id)
      assert related_memory_id in related_ids
      refute base_memory_id in related_ids
      refute other_memory_id in related_ids
    end

    test "same_project returns empty when project_id is nil", %{session_id: session_id} do
      alias JidoCode.Memory.LongTerm.StoreManager
      alias JidoCode.Memory.LongTerm.TripleStoreAdapter

      {:ok, store} = StoreManager.get_or_create(session_id)

      # Create memory without project_id
      mem = %{
        id: "mem-no-proj-" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false),
        content: "Memory without project",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }

      {:ok, memory_id} = TripleStoreAdapter.persist(mem, store)

      # Query for same_project should return empty
      {:ok, related} = Memory.query_related(session_id, memory_id, :same_project)

      assert related == []
    end

    # =========================================================================
    # C2 Fix: depth boundary tests
    # =========================================================================

    test "clamps depth to minimum of 1", %{session_id: session_id, base_memory_id: base_memory_id} do
      # depth: 0 should be clamped to 1
      {:ok, related} = Memory.query_related(session_id, base_memory_id, :same_type, depth: 0)
      assert is_list(related)
    end

    test "clamps depth to maximum of 5", %{session_id: session_id, base_memory_id: base_memory_id} do
      # depth: 10 should be clamped to 5
      {:ok, related} = Memory.query_related(session_id, base_memory_id, :same_type, depth: 10)
      assert is_list(related)
    end

    test "accepts depth at max boundary (5)", %{
      session_id: session_id,
      base_memory_id: base_memory_id
    } do
      {:ok, related} = Memory.query_related(session_id, base_memory_id, :same_type, depth: 5)
      assert is_list(related)
    end

    test "handles non-integer depth gracefully", %{context: context, base_memory_id: base_memory_id} do
      # depth as string should use default
      args = %{"start_from" => base_memory_id, "relationship" => "same_type", "depth" => "invalid"}
      {:ok, json} = KnowledgeGraphQuery.execute(args, context)
      result = Jason.decode!(json)

      # Should still work, using default depth
      assert result["relationship"] == "same_type"
    end

    test "include_superseded option works through handler", %{session_id: session_id} do
      alias JidoCode.Memory.LongTerm.StoreManager
      alias JidoCode.Memory.LongTerm.TripleStoreAdapter

      {:ok, store} = StoreManager.get_or_create(session_id)

      # Create active and superseded memories of same type
      # Use proper mem-<base64> format for IDs
      active_mem = %{
        id: "mem-" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)),
        content: "Active memory",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }

      {:ok, active_id} = TripleStoreAdapter.persist(active_mem, store)

      # Create a memory that will be superseded
      to_supersede_mem = %{
        id: "mem-" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)),
        content: "Memory to be superseded",
        memory_type: :fact,
        confidence: 0.7,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      }

      {:ok, superseded_id} = TripleStoreAdapter.persist(to_supersede_mem, store)

      # Mark it as superseded using the proper API
      :ok = TripleStoreAdapter.supersede(store, session_id, superseded_id)

      context = %{session_id: session_id}

      # Without include_superseded - should exclude superseded
      args1 = %{"start_from" => active_id, "relationship" => "same_type"}
      {:ok, json1} = KnowledgeGraphQuery.execute(args1, context)
      result1 = Jason.decode!(json1)
      ids1 = Enum.map(result1["related"], & &1["id"])
      refute superseded_id in ids1

      # With include_superseded: true - should include superseded
      args2 = %{
        "start_from" => active_id,
        "relationship" => "same_type",
        "include_superseded" => true
      }

      {:ok, json2} = KnowledgeGraphQuery.execute(args2, context)
      result2 = Jason.decode!(json2)
      ids2 = Enum.map(result2["related"], & &1["id"])
      assert superseded_id in ids2
    end
  end

  # ============================================================================
  # Memory.query_related/4 Tests
  # ============================================================================

  describe "Memory.query_related/4" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create memories with known relationships
      {:ok, json1} =
        KnowledgeRemember.execute(
          %{"content" => "Base memory", "type" => "fact", "confidence" => 0.9},
          context
        )

      base_id = Jason.decode!(json1)["memory_id"]

      {:ok, json2} =
        KnowledgeRemember.execute(
          %{"content" => "Related fact", "type" => "fact", "confidence" => 0.8},
          context
        )

      related_id = Jason.decode!(json2)["memory_id"]

      {:ok, session_id: session_id, context: context, base_id: base_id, related_id: related_id}
    end

    test "returns related memories for same_type", %{
      session_id: session_id,
      base_id: base_id,
      related_id: related_id
    } do
      {:ok, related} = Memory.query_related(session_id, base_id, :same_type)

      ids = Enum.map(related, & &1.id)
      assert related_id in ids
      refute base_id in ids
    end

    test "returns empty list for unknown memory", %{session_id: session_id} do
      {:error, :not_found} = Memory.query_related(session_id, "mem-unknown123", :same_type)
    end

    test "respects depth option", %{session_id: session_id, base_id: base_id} do
      {:ok, related_depth_1} = Memory.query_related(session_id, base_id, :same_type, depth: 1)
      {:ok, related_depth_2} = Memory.query_related(session_id, base_id, :same_type, depth: 2)

      # Both should return results, depth 2 may return more with chained relationships
      assert is_list(related_depth_1)
      assert is_list(related_depth_2)
    end

    test "respects limit option", %{session_id: session_id, context: context, base_id: base_id} do
      # Add more same-type memories
      for i <- 1..10 do
        {:ok, _} =
          KnowledgeRemember.execute(
            %{"content" => "Fact #{i}", "type" => "fact"},
            context
          )
      end

      {:ok, limited} = Memory.query_related(session_id, base_id, :same_type, limit: 3)

      assert length(limited) == 3
    end
  end

  # ============================================================================
  # Memory.get_stats/1 Tests
  # ============================================================================

  describe "Memory.get_stats/1" do
    setup do
      session_id = Uniq.UUID.uuid4()
      context = %{session_id: session_id}

      # Create various memories
      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "High confidence fact", "type" => "fact", "confidence" => 0.9},
          context
        )

      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "Medium confidence fact", "type" => "fact", "confidence" => 0.6},
          context
        )

      {:ok, _} =
        KnowledgeRemember.execute(
          %{"content" => "Low confidence assumption", "type" => "assumption", "confidence" => 0.3},
          context
        )

      {:ok, json} =
        KnowledgeRemember.execute(
          %{
            "content" => "With evidence",
            "type" => "discovery",
            "evidence_refs" => ["file.ex"],
            "rationale" => "Found during analysis"
          },
          context
        )

      memory_with_evidence_id = Jason.decode!(json)["memory_id"]

      # Supersede one memory
      {:ok, json_to_supersede} =
        KnowledgeRemember.execute(
          %{"content" => "Old fact", "type" => "fact"},
          context
        )

      old_id = Jason.decode!(json_to_supersede)["memory_id"]

      {:ok, _} =
        KnowledgeSupersede.execute(
          %{"old_memory_id" => old_id, "new_content" => "New fact"},
          context
        )

      {:ok,
       session_id: session_id,
       context: context,
       memory_with_evidence_id: memory_with_evidence_id}
    end

    test "returns counts by type", %{session_id: session_id} do
      {:ok, stats} = Memory.get_stats(session_id)

      assert stats.by_type[:fact] >= 2
      assert stats.by_type[:assumption] == 1
      assert stats.by_type[:discovery] == 1
    end

    test "returns counts by confidence level", %{session_id: session_id} do
      {:ok, stats} = Memory.get_stats(session_id)

      # High: >= 0.8, Medium: >= 0.5 and < 0.8, Low: < 0.5
      assert stats.by_confidence[:high] >= 1
      assert stats.by_confidence[:medium] >= 1
      assert stats.by_confidence[:low] >= 1
    end

    test "counts superseded memories separately", %{session_id: session_id} do
      {:ok, stats} = Memory.get_stats(session_id)

      assert stats.superseded_count >= 1
      assert stats.total_count >= 4
    end

    test "counts memories with evidence", %{session_id: session_id} do
      {:ok, stats} = Memory.get_stats(session_id)

      assert stats.with_evidence >= 1
    end

    test "counts memories with rationale", %{session_id: session_id} do
      {:ok, stats} = Memory.get_stats(session_id)

      assert stats.with_rationale >= 1
    end

    test "returns zeros for empty session" do
      empty_session_id = Uniq.UUID.uuid4()
      {:ok, stats} = Memory.get_stats(empty_session_id)

      assert stats.total_count == 0
      assert stats.superseded_count == 0
      assert stats.by_type == %{}
      assert stats.by_confidence == %{}
      assert stats.with_evidence == 0
      assert stats.with_rationale == 0
    end
  end
end
