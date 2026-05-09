defmodule JidoCode.Conversations.ContextMemoryTest do
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first
  # covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections
  use ExUnit.Case, async: false

  alias JidoCode.Conversations.ContextMemory
  alias JidoCode.MemoryGraph.ConversationMemoryAdoption

  @store_table :jido_code_context_memory_test
  @store {Jido.Memory.Store.ETS, [table: @store_table]}

  setup do
    previous = Application.get_env(:jido_code, :conversation_context_memory, [])

    reset_store!()

    Application.put_env(:jido_code, :conversation_context_memory,
      enabled?: false,
      provider: :basic,
      store: @store,
      store_opts: [],
      retrieval_limit: 4,
      max_instruction_lines: 4,
      max_instruction_bytes: 1_000,
      ttl_ms: 60_000
    )

    on_exit(fn ->
      Application.put_env(:jido_code, :conversation_context_memory, previous)
      reset_store!()
    end)

    :ok
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

    test "enabled adapter writes and retrieves bounded prompt-memory records" do
      enable_context_memory!()

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

    test "unsupported record kinds degrade instead of storing raw transcript-like memory" do
      enable_context_memory!()

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
    test "expired records are pruned while active bounded context remains retrievable" do
      enable_context_memory!()

      scope = %{
        managed_repo_id: "repo-79",
        work_item_id: "work-79",
        conversation_id: "conversation-79",
        turn_id: "turn-79",
        workflow: :execute,
        source: :context_memory_test
      }

      seed_memory_record!(scope, %{
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

    test "invalid provider configuration degrades retrieval and validates explicitly" do
      Application.put_env(:jido_code, :conversation_context_memory,
        enabled?: true,
        provider: :not_supported,
        store: @store,
        store_opts: [],
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

    test "prompt-memory projections are not durable conversation-memory adoption inputs" do
      enable_context_memory!()

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

  defp enable_context_memory! do
    Application.put_env(:jido_code, :conversation_context_memory,
      enabled?: true,
      provider: :basic,
      store: @store,
      store_opts: [],
      retrieval_limit: 4,
      max_instruction_lines: 4,
      max_instruction_bytes: 1_000,
      ttl_ms: 60_000
    )
  end

  defp seed_memory_record!(scope, attrs) do
    {:ok, namespace} = ContextMemory.namespace(scope)

    {:ok, _record} =
      Jido.Memory.Runtime.remember(
        %{id: "context-memory-test"},
        attrs
        |> Map.put(:namespace, namespace)
        |> Map.put_new(:source, "context_memory_test"),
        provider: :basic,
        namespace: namespace,
        store: @store,
        store_opts: []
      )
  end

  defp reset_store! do
    for table <- [
          :jido_code_context_memory_test_records,
          :jido_code_context_memory_test_ns_time,
          :jido_code_context_memory_test_ns_class_time,
          :jido_code_context_memory_test_ns_tag
        ] do
      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end
  end
end
