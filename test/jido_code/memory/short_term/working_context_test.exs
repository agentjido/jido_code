defmodule JidoCode.Memory.ShortTerm.WorkingContextTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.ShortTerm.WorkingContext

  describe "new/0" do
    test "creates empty context with default max_tokens (12_000)" do
      ctx = WorkingContext.new()

      assert ctx.max_tokens == 12_000
      assert ctx.items == %{}
      assert ctx.current_tokens == 0
    end
  end

  describe "new/1" do
    test "accepts custom max_tokens value" do
      ctx = WorkingContext.new(8_000)

      assert ctx.max_tokens == 8_000
      assert ctx.items == %{}
    end

    test "creates context with various max_tokens values" do
      assert WorkingContext.new(1_000).max_tokens == 1_000
      assert WorkingContext.new(50_000).max_tokens == 50_000
    end
  end

  describe "put/4" do
    test "creates new context item with all required fields" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.7")

      item = ctx.items[:framework]

      assert item.key == :framework
      assert item.value == "Phoenix 1.7"
      assert item.source == :explicit
      assert item.confidence == 0.8
      assert item.access_count == 1
      assert %DateTime{} = item.first_seen
      assert %DateTime{} = item.last_accessed
    end

    test "sets first_seen and last_accessed to current time for new items" do
      before = DateTime.utc_now()
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      after_put = DateTime.utc_now()

      item = ctx.items[:framework]

      assert DateTime.compare(item.first_seen, before) in [:gt, :eq]
      assert DateTime.compare(item.first_seen, after_put) in [:lt, :eq]
      assert DateTime.compare(item.last_accessed, before) in [:gt, :eq]
      assert DateTime.compare(item.last_accessed, after_put) in [:lt, :eq]
    end

    test "updates existing item, incrementing access_count" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.6")
      assert ctx.items[:framework].access_count == 1

      ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.7")
      assert ctx.items[:framework].access_count == 2
      assert ctx.items[:framework].value == "Phoenix 1.7"
    end

    test "updates last_accessed but preserves first_seen on update" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.6")
      original_first_seen = ctx.items[:framework].first_seen

      # Small delay to ensure time difference
      Process.sleep(10)

      ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.7")

      assert ctx.items[:framework].first_seen == original_first_seen
      assert DateTime.compare(ctx.items[:framework].last_accessed, original_first_seen) == :gt
    end

    test "accepts source option (:inferred, :explicit, :tool)" do
      ctx = WorkingContext.new()

      ctx = WorkingContext.put(ctx, :framework, "Phoenix", source: :tool)
      assert ctx.items[:framework].source == :tool

      ctx = WorkingContext.put(ctx, :user_intent, "refactoring", source: :inferred)
      assert ctx.items[:user_intent].source == :inferred

      ctx = WorkingContext.put(ctx, :current_task, "fix bug", source: :explicit)
      assert ctx.items[:current_task].source == :explicit
    end

    test "accepts confidence option (0.0 to 1.0)" do
      ctx = WorkingContext.new()

      ctx = WorkingContext.put(ctx, :framework, "Phoenix", confidence: 0.95)
      assert ctx.items[:framework].confidence == 0.95

      ctx = WorkingContext.put(ctx, :user_intent, "maybe refactoring", confidence: 0.5)
      assert ctx.items[:user_intent].confidence == 0.5
    end

    test "clamps confidence to valid range" do
      ctx = WorkingContext.new()

      ctx = WorkingContext.put(ctx, :framework, "Phoenix", confidence: 1.5)
      assert ctx.items[:framework].confidence == 1.0

      ctx = WorkingContext.put(ctx, :user_intent, "something", confidence: -0.5)
      assert ctx.items[:user_intent].confidence == 0.0
    end

    test "accepts memory_type option overriding inference" do
      ctx = WorkingContext.new()

      # Without override, :framework from :tool would infer :fact
      ctx = WorkingContext.put(ctx, :framework, "Phoenix", source: :tool)
      assert ctx.items[:framework].suggested_type == :fact

      # With override
      ctx = WorkingContext.put(ctx, :framework, "Phoenix", source: :tool, memory_type: :discovery)
      assert ctx.items[:framework].suggested_type == :discovery
    end

    test "infers suggested_type based on key and source" do
      ctx = WorkingContext.new()

      ctx = WorkingContext.put(ctx, :framework, "Phoenix", source: :tool)
      assert ctx.items[:framework].suggested_type == :fact

      ctx = WorkingContext.put(ctx, :user_intent, "refactoring", source: :inferred)
      assert ctx.items[:user_intent].suggested_type == :assumption

      ctx = WorkingContext.put(ctx, :discovered_patterns, ["pattern1"], source: :tool)
      assert ctx.items[:discovered_patterns].suggested_type == :discovery
    end
  end

  describe "get/2" do
    test "returns {context, value} for existing key" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")

      {_new_ctx, value} = WorkingContext.get(ctx, :framework)
      assert value == "Phoenix"
    end

    test "increments access_count on retrieval" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      assert ctx.items[:framework].access_count == 1

      {ctx, _value} = WorkingContext.get(ctx, :framework)
      assert ctx.items[:framework].access_count == 2

      {ctx, _value} = WorkingContext.get(ctx, :framework)
      assert ctx.items[:framework].access_count == 3
    end

    test "updates last_accessed on retrieval" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      original_last_accessed = ctx.items[:framework].last_accessed

      Process.sleep(10)

      {ctx, _value} = WorkingContext.get(ctx, :framework)
      assert DateTime.compare(ctx.items[:framework].last_accessed, original_last_accessed) == :gt
    end

    test "returns {context, nil} for missing keys" do
      ctx = WorkingContext.new()

      {returned_ctx, value} = WorkingContext.get(ctx, :nonexistent)
      assert value == nil
      assert returned_ctx == ctx
    end
  end

  describe "peek/2" do
    test "returns value without updating access tracking" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      original_access_count = ctx.items[:framework].access_count

      value = WorkingContext.peek(ctx, :framework)

      assert value == "Phoenix"
      assert ctx.items[:framework].access_count == original_access_count
    end

    test "returns nil for missing keys" do
      ctx = WorkingContext.new()
      assert WorkingContext.peek(ctx, :nonexistent) == nil
    end
  end

  describe "delete/2" do
    test "removes item from context" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      assert WorkingContext.has_key?(ctx, :framework)

      ctx = WorkingContext.delete(ctx, :framework)
      refute WorkingContext.has_key?(ctx, :framework)
    end

    test "handles non-existent keys gracefully" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")

      # Should not raise
      ctx = WorkingContext.delete(ctx, :nonexistent)
      assert WorkingContext.has_key?(ctx, :framework)
    end
  end

  describe "to_list/1" do
    test "returns all items as list" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      ctx = WorkingContext.put(ctx, :primary_language, "Elixir")

      items = WorkingContext.to_list(ctx)

      assert length(items) == 2
      keys = Enum.map(items, & &1.key)
      assert :framework in keys
      assert :primary_language in keys
    end

    test "returns empty list for empty context" do
      ctx = WorkingContext.new()
      assert WorkingContext.to_list(ctx) == []
    end
  end

  describe "to_map/1" do
    test "returns key-value pairs without metadata" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      ctx = WorkingContext.put(ctx, :primary_language, "Elixir")

      map = WorkingContext.to_map(ctx)

      assert map == %{framework: "Phoenix", primary_language: "Elixir"}
    end

    test "returns empty map for empty context" do
      ctx = WorkingContext.new()
      assert WorkingContext.to_map(ctx) == %{}
    end
  end

  describe "size/1" do
    test "returns correct count" do
      ctx = WorkingContext.new()
      assert WorkingContext.size(ctx) == 0

      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      assert WorkingContext.size(ctx) == 1

      ctx = WorkingContext.put(ctx, :primary_language, "Elixir")
      assert WorkingContext.size(ctx) == 2

      # Updating existing key doesn't increase size
      ctx = WorkingContext.put(ctx, :framework, "Phoenix 1.7")
      assert WorkingContext.size(ctx) == 2
    end
  end

  describe "clear/1" do
    test "resets to empty context" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")
      ctx = WorkingContext.put(ctx, :primary_language, "Elixir")
      assert WorkingContext.size(ctx) == 2

      ctx = WorkingContext.clear(ctx)
      assert WorkingContext.size(ctx) == 0
      assert ctx.items == %{}
    end

    test "preserves max_tokens setting" do
      ctx = WorkingContext.new(8_000)
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")

      ctx = WorkingContext.clear(ctx)
      assert ctx.max_tokens == 8_000
    end

    test "resets current_tokens to 0" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")

      ctx = WorkingContext.clear(ctx)
      assert ctx.current_tokens == 0
    end
  end

  describe "has_key?/2" do
    test "returns true for existing keys" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix")

      assert WorkingContext.has_key?(ctx, :framework)
    end

    test "returns false for non-existent keys" do
      ctx = WorkingContext.new()

      refute WorkingContext.has_key?(ctx, :nonexistent)
    end
  end

  describe "get_item/2" do
    test "returns full context item with metadata" do
      ctx = WorkingContext.new()
      ctx = WorkingContext.put(ctx, :framework, "Phoenix", source: :tool, confidence: 0.95)

      item = WorkingContext.get_item(ctx, :framework)

      assert item.key == :framework
      assert item.value == "Phoenix"
      assert item.source == :tool
      assert item.confidence == 0.95
      assert item.suggested_type == :fact
    end

    test "returns nil for non-existent keys" do
      ctx = WorkingContext.new()

      assert WorkingContext.get_item(ctx, :nonexistent) == nil
    end
  end

  describe "infer_memory_type/2" do
    test "assigns :fact for :framework from :tool source" do
      assert WorkingContext.infer_memory_type(:framework, :tool) == :fact
    end

    test "assigns :fact for :primary_language from :tool source" do
      assert WorkingContext.infer_memory_type(:primary_language, :tool) == :fact
    end

    test "assigns :fact for :project_root from :tool source" do
      assert WorkingContext.infer_memory_type(:project_root, :tool) == :fact
    end

    test "assigns :assumption for :user_intent from :inferred source" do
      assert WorkingContext.infer_memory_type(:user_intent, :inferred) == :assumption
    end

    test "assigns :discovery for :discovered_patterns from any source" do
      assert WorkingContext.infer_memory_type(:discovered_patterns, :tool) == :discovery
      assert WorkingContext.infer_memory_type(:discovered_patterns, :inferred) == :discovery
      assert WorkingContext.infer_memory_type(:discovered_patterns, :explicit) == :discovery
    end

    test "assigns nil for ephemeral keys like :active_errors" do
      assert WorkingContext.infer_memory_type(:active_errors, :tool) == nil
      assert WorkingContext.infer_memory_type(:active_errors, :inferred) == nil
    end

    test "assigns :unknown for :pending_questions" do
      assert WorkingContext.infer_memory_type(:pending_questions, :tool) == :unknown
      assert WorkingContext.infer_memory_type(:pending_questions, :inferred) == :unknown
    end

    test "returns nil for unrecognized key/source combinations" do
      # :framework from :inferred doesn't have a specific rule
      assert WorkingContext.infer_memory_type(:framework, :inferred) == nil
    end
  end
end
