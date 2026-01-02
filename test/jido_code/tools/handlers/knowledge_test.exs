defmodule JidoCode.Tools.Handlers.KnowledgeTest do
  @moduledoc """
  Tests for the Knowledge tool handlers.

  Section 7.1.3, 7.2.3, 7.3.3, and 7.5.3 of Phase 7 planning document.

  Note: These tests run with the full application started (via test_helper.exs).
  The Memory Supervisor and StoreManager must be running from the application supervision tree.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Tools.Handlers.Knowledge
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeRemember
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeRecall
  alias JidoCode.Tools.Handlers.Knowledge.KnowledgeSupersede
  alias JidoCode.Tools.Handlers.Knowledge.ProjectConventions

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

      assert length(tools) == 4
      assert Enum.any?(tools, fn t -> t.name == "knowledge_remember" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_recall" end)
      assert Enum.any?(tools, fn t -> t.name == "knowledge_supersede" end)
      assert Enum.any?(tools, fn t -> t.name == "project_conventions" end)
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
end
