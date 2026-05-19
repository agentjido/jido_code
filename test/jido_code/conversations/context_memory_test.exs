defmodule JidoCode.Conversations.ContextMemoryTest do
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first
  # covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections
  use ExUnit.Case, async: false

  alias JidoCode.Conversations.ContextMemory
  alias JidoCode.MemoryGraph.ConversationMemoryAdoption

  setup do
    prompt_memory_store = JidoCode.PromptMemoryTestStore.setup!(prefix: :jido_code_context_memory_test)

    {:ok, prompt_memory_store: prompt_memory_store}
  end

  describe "Phase 77.3 - prompt memory adapter foundation" do
    test "resolves repo-intake and work-item namespaces without conversation id siloing" do
      assert {:ok, "repo:repo-77:intake"} =
               ContextMemory.namespace(%{managed_repo_id: "repo-77", conversation_id: "conversation-77"})

      assert {:ok,
              %{
                primary: "repo:repo-77:work_item:work-77",
                previous: ["repo:repo-77:intake"],
                metadata: %{
                  "managed_repo_id" => "repo-77",
                  "work_item_id" => "work-77",
                  "conversation_id" => "conversation-77",
                  "turn_id" => "turn-77",
                  "workflow" => "plan"
                }
              }} =
               ContextMemory.namespaces(%{
                 managed_repo_id: "repo-77",
                 work_item_id: "work-77",
                 conversation_id: "conversation-77",
                 turn_id: "turn-77",
                 workflow: :plan
               })
    end

    test "disabled config returns bounded non-fatal retrieval projection" do
      assert {:ok,
              %{
                state: :disabled,
                namespace: "repo:repo-77:work_item:work-77",
                items: [],
                instruction_lines: [],
                diagnostics: %{}
              }} =
               ContextMemory.retrieve(%{
                 managed_repo_id: "repo-77",
                 work_item_id: "work-77",
                 conversation_id: "conversation-77"
               })
    end

    test "enabled adapter writes and retrieves bounded prompt-memory records", %{
      prompt_memory_store: prompt_memory_store
    } do
      enable_context_memory!(prompt_memory_store)

      scope = %{
        managed_repo_id: "repo-77",
        work_item_id: "work-77",
        conversation_id: "conversation-77",
        turn_id: "turn-77",
        workflow: :review,
        source: :conversation_runtime
      }

      assert {:ok, %{state: :ready, namespace: "repo:repo-77:work_item:work-77", record_id: record_id}} =
               ContextMemory.remember(scope, %{
                 kind: :active_constraint,
                 text: "Keep the prompt-memory adapter behind the conversation boundary.",
                 tags: ["boundary"]
               })

      assert is_binary(record_id)

      assert {:ok,
              %{
                state: :ready,
                namespace: "repo:repo-77:work_item:work-77",
                items: [
                  %{
                    class: :working,
                    kind: :active_constraint,
                    text: "Keep the prompt-memory adapter behind the conversation boundary.",
                    tags: tags,
                    metadata: metadata
                  }
                ],
                instruction_lines: [
                  "- active_constraint: Keep the prompt-memory adapter behind the conversation boundary."
                ]
              }} = ContextMemory.retrieve(scope)

      assert "prompt-memory" in tags
      assert "constraint" in tags
      assert "boundary" in tags
      assert metadata["managed_repo_id"] == "repo-77"
      assert metadata["work_item_id"] == "work-77"
      assert metadata["conversation_id"] == "conversation-77"
      assert metadata["turn_id"] == "turn-77"
      assert metadata["workflow"] == "review"
      assert metadata["source"] == "conversation_runtime"
    end

    test "unsupported record kinds degrade instead of storing raw transcript-like memory", %{
      prompt_memory_store: prompt_memory_store
    } do
      enable_context_memory!(prompt_memory_store)

      assert {:ok, %{state: :degraded, record_id: nil, diagnostics: %{reason: reason}}} =
               ContextMemory.remember(
                 %{managed_repo_id: "repo-77", work_item_id: "work-77"},
                 %{kind: :raw_transcript, text: "User: dump the whole transcript"}
               )

      assert reason =~ "unsupported_prompt_memory_kind"

      assert {:ok, %{state: :ready, items: []}} =
               ContextMemory.retrieve(%{managed_repo_id: "repo-77", work_item_id: "work-77"})
    end

    test "provider setup failures return degraded retrieval projection" do
      Application.put_env(:jido_code, :conversation_context_memory,
        enabled?: true,
        provider: :basic,
        store: {JidoCode.Conversations.MissingPromptMemoryStore, []}
      )

      assert {:ok,
              %{
                state: :degraded,
                namespace: "repo:repo-77:work_item:work-77",
                items: [],
                instruction_lines: [],
                diagnostics: %{reason: reason}
              }} =
               ContextMemory.retrieve(%{
                 managed_repo_id: "repo-77",
                 work_item_id: "work-77"
               })

      assert reason =~ "store_not_loaded"
    end
  end

  describe "Phase 79.3 - lifecycle and boundary hardening" do
    test "expired records are pruned while active bounded context remains retrievable", %{
      prompt_memory_store: prompt_memory_store
    } do
      enable_context_memory!(prompt_memory_store)

      scope = %{
        managed_repo_id: "repo-79",
        work_item_id: "work-79",
        conversation_id: "conversation-79",
        turn_id: "turn-79",
        workflow: :execute,
        source: :context_memory_test
      }

      seed_memory_record!(prompt_memory_store, scope, %{
        class: :working,
        kind: :active_constraint,
        text: "Expired prompt memory must not reach future prompts.",
        tags: ["prompt-memory", "constraint"],
        observed_at: System.system_time(:millisecond) - 2_000,
        expires_at: System.system_time(:millisecond) - 1_000
      })

      assert {:ok, %{state: :ready}} =
               ContextMemory.remember(scope, %{
                 kind: :next_step,
                 text: "Active prompt memory remains available."
               })

      assert {:ok, %{state: :ready, pruned_count: pruned_count}} = ContextMemory.prune_expired(scope)
      assert pruned_count >= 1

      assert {:ok, %{state: :ready, items: items, instruction_lines: instruction_lines}} =
               ContextMemory.retrieve(scope)

      refute Enum.any?(items, &(&1.text == "Expired prompt memory must not reach future prompts."))
      assert Enum.any?(items, &(&1.text == "Active prompt memory remains available."))
      assert "- next_step: Active prompt memory remains available." in instruction_lines
    end

    test "invalid provider configuration degrades retrieval and validates explicitly", %{
      prompt_memory_store: prompt_memory_store
    } do
      JidoCode.PromptMemoryTestStore.configure!(prompt_memory_store,
        enabled?: true,
        provider: :not_supported,
        timeout_ms: 250,
        retrieval_limit: 4,
        max_instruction_lines: 4,
        max_instruction_bytes: 1_000,
        ttl_ms: 60_000
      )

      assert {:error, {:unsupported_provider, :not_supported}} = ContextMemory.validate_config()

      assert {:ok,
              %{
                state: :degraded,
                namespace: "repo:repo-79:work_item:work-79",
                items: [],
                instruction_lines: [],
                diagnostics: %{reason: reason}
              }} =
               ContextMemory.retrieve(%{
                 managed_repo_id: "repo-79",
                 work_item_id: "work-79"
               })

      assert reason =~ "unsupported_provider"
    end

    test "prompt-memory projections are not durable conversation-memory adoption inputs", %{
      prompt_memory_store: prompt_memory_store
    } do
      enable_context_memory!(prompt_memory_store)

      scope = %{
        managed_repo_id: "repo-79",
        work_item_id: "work-79",
        conversation_id: "conversation-79",
        turn_id: "turn-79",
        workflow: :review,
        source: :context_memory_test
      }

      assert {:ok, %{state: :ready}} =
               ContextMemory.remember(scope, %{
                 kind: :stable_preference,
                 text: "Prefer bounded prompt memory for the next turn only."
               })

      assert {:ok, %{state: :ready} = projection} = ContextMemory.retrieve(scope)

      assert {:error, :invalid_conversation_recall_projection} =
               ConversationMemoryAdoption.adopt(projection,
                 kind: :fact,
                 workspace_path: "/tmp/jido-code-context-memory-test",
                 revision: "test-revision",
                 classification: %{source: "test", reason: "should require conversation recall projection"}
               )
    end
  end

  describe "Phase 84 - hermetic prompt-memory test fixtures" do
    test "fixture cleanup is idempotent when ETS tables are missing or already removed", %{
      prompt_memory_store: prompt_memory_store
    } do
      enable_context_memory!(prompt_memory_store)

      scope = %{
        managed_repo_id: "repo-84",
        work_item_id: "work-84-cleanup",
        conversation_id: "conversation-84-cleanup"
      }

      assert {:ok, %{state: :ready}} =
               ContextMemory.remember(scope, %{
                 kind: :next_step,
                 text: "Cleanup can run more than once."
               })

      assert Enum.any?(JidoCode.PromptMemoryTestStore.table_names(prompt_memory_store.table), fn table ->
               :ets.whereis(table) != :undefined
             end)

      assert :ok = JidoCode.PromptMemoryTestStore.cleanup_store!(prompt_memory_store)
      assert :ok = JidoCode.PromptMemoryTestStore.cleanup_store!(prompt_memory_store)
    end

    test "one fixture cleanup does not delete another fixture's active store" do
      first =
        JidoCode.PromptMemoryTestStore.setup!(
          prefix: :jido_code_context_memory_isolation_test,
          config: [enabled?: true]
        )

      first_scope = %{
        managed_repo_id: "repo-84",
        work_item_id: "work-84-first",
        conversation_id: "conversation-84-first"
      }

      assert {:ok, %{state: :ready}} =
               ContextMemory.remember(first_scope, %{
                 kind: :next_step,
                 text: "First fixture memory."
               })

      second =
        JidoCode.PromptMemoryTestStore.setup!(
          prefix: :jido_code_context_memory_isolation_test,
          config: [enabled?: true]
        )

      second_scope = %{
        managed_repo_id: "repo-84",
        work_item_id: "work-84-second",
        conversation_id: "conversation-84-second"
      }

      assert first.table != second.table

      assert {:ok, %{state: :ready}} =
               ContextMemory.remember(second_scope, %{
                 kind: :next_step,
                 text: "Second fixture memory."
               })

      assert :ok = JidoCode.PromptMemoryTestStore.cleanup_store!(first)

      assert {:ok, %{state: :ready, items: [%{text: "Second fixture memory."}]}} =
               ContextMemory.retrieve(second_scope)
    end

    test "disabled and degraded projections stay bounded after fixture cleanup", %{
      prompt_memory_store: prompt_memory_store
    } do
      assert :ok = JidoCode.PromptMemoryTestStore.cleanup_store!(prompt_memory_store)

      assert {:ok, %{state: :disabled, items: [], instruction_lines: []}} =
               ContextMemory.retrieve(%{
                 managed_repo_id: "repo-84",
                 work_item_id: "work-84-disabled"
               })

      Application.put_env(:jido_code, :conversation_context_memory,
        enabled?: true,
        provider: :basic,
        store: {JidoCode.Conversations.MissingPromptMemoryStore, []}
      )

      assert {:ok, %{state: :degraded, items: [], instruction_lines: [], diagnostics: %{reason: reason}}} =
               ContextMemory.retrieve(%{
                 managed_repo_id: "repo-84",
                 work_item_id: "work-84-degraded"
               })

      assert reason =~ "store_not_loaded"
    end
  end

  defp enable_context_memory!(prompt_memory_store) do
    JidoCode.PromptMemoryTestStore.configure!(prompt_memory_store,
      enabled?: true,
      retrieval_limit: 4,
      max_instruction_lines: 4,
      max_instruction_bytes: 1_000,
      ttl_ms: 60_000
    )
  end

  defp seed_memory_record!(prompt_memory_store, scope, attrs) do
    {:ok, namespace} = ContextMemory.namespace(scope)

    {:ok, _record} =
      Jido.Memory.Runtime.remember(
        %{id: "context-memory-test"},
        attrs
        |> Map.put(:namespace, namespace)
        |> Map.put_new(:source, "context_memory_test"),
        provider: :basic,
        namespace: namespace,
        store: prompt_memory_store.store,
        store_opts: []
      )
  end
end
