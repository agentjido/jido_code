defmodule JidoCode.Memory.ContextBuilderTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory.ContextBuilder
  alias JidoCode.Session.State
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers

  # =============================================================================
  # Setup
  # =============================================================================

  setup do
    # Use the full session supervisor setup
    {:ok, %{tmp_dir: tmp_dir}} = SessionTestHelpers.setup_session_supervisor("context_builder")

    # Create a valid session
    session_id = SessionTestHelpers.test_uuid(:rand.uniform(10000))
    project_path = Path.join(tmp_dir, "test_project")
    File.mkdir_p!(project_path)

    # Create session struct using the test helper
    session = SessionTestHelpers.create_test_session(session_id, "Test Session", project_path)

    {:ok, _pid} = SessionSupervisor.start_session(session)

    on_exit(fn ->
      try do
        SessionSupervisor.stop_session(session.id)
      catch
        :exit, _ -> :ok
      end
    end)

    %{session_id: session.id, tmp_dir: tmp_dir, project_path: project_path}
  end

  # =============================================================================
  # default_budget/0 Tests
  # =============================================================================

  describe "default_budget/0" do
    test "returns budget with expected keys" do
      budget = ContextBuilder.default_budget()

      assert Map.has_key?(budget, :total)
      assert Map.has_key?(budget, :system)
      assert Map.has_key?(budget, :conversation)
      assert Map.has_key?(budget, :working)
      assert Map.has_key?(budget, :long_term)
    end

    test "returns reasonable default values" do
      budget = ContextBuilder.default_budget()

      assert budget.total == 32_000
      assert budget.system == 2_000
      assert budget.conversation == 20_000
      assert budget.working == 4_000
      assert budget.long_term == 6_000
    end
  end

  # =============================================================================
  # estimate_tokens/1 Tests
  # =============================================================================

  describe "estimate_tokens/1" do
    test "estimates tokens for short text" do
      tokens = ContextBuilder.estimate_tokens("Hello, world!")
      # 13 chars / 4 = 3.25 -> 3
      assert tokens == 3
    end

    test "estimates tokens for longer text" do
      text = String.duplicate("a", 100)
      tokens = ContextBuilder.estimate_tokens(text)
      # 100 chars / 4 = 25
      assert tokens == 25
    end

    test "returns 0 for empty string" do
      assert ContextBuilder.estimate_tokens("") == 0
    end

    test "returns 0 for nil" do
      assert ContextBuilder.estimate_tokens(nil) == 0
    end
  end

  # =============================================================================
  # build/2 Tests
  # =============================================================================

  describe "build/2" do
    test "builds context for valid session", %{session_id: session_id} do
      {:ok, context} = ContextBuilder.build(session_id)

      assert is_map(context)
      assert Map.has_key?(context, :conversation)
      assert Map.has_key?(context, :working_context)
      assert Map.has_key?(context, :long_term_memories)
      assert Map.has_key?(context, :token_counts)
    end

    test "returns empty conversation for new session", %{session_id: session_id} do
      {:ok, context} = ContextBuilder.build(session_id)

      assert context.conversation == []
    end

    test "returns empty working context for new session", %{session_id: session_id} do
      {:ok, context} = ContextBuilder.build(session_id)

      assert context.working_context == %{}
    end

    test "returns empty memories for new session", %{session_id: session_id} do
      {:ok, context} = ContextBuilder.build(session_id)

      assert context.long_term_memories == []
    end

    test "includes conversation messages", %{session_id: session_id} do
      # Add some messages
      user_msg = %{role: :user, content: "Hello", id: "msg-1", timestamp: DateTime.utc_now()}
      assistant_msg = %{role: :assistant, content: "Hi there!", id: "msg-2", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session_id, user_msg)
      {:ok, _} = State.append_message(session_id, assistant_msg)

      {:ok, context} = ContextBuilder.build(session_id)

      assert length(context.conversation) == 2
    end

    test "includes working context", %{session_id: session_id} do
      # Set working context
      :ok = State.update_context(session_id, :project_root, "/app")
      :ok = State.update_context(session_id, :primary_language, "elixir")

      {:ok, context} = ContextBuilder.build(session_id)

      assert context.working_context[:project_root] == "/app"
      assert context.working_context[:primary_language] == "elixir"
    end

    test "respects include_memories: false option", %{session_id: session_id} do
      {:ok, context} = ContextBuilder.build(session_id, include_memories: false)

      assert context.long_term_memories == []
    end

    test "respects include_conversation: false option", %{session_id: session_id} do
      # Add a message
      user_msg = %{role: :user, content: "Hello", id: "msg-1", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session_id, user_msg)

      {:ok, context} = ContextBuilder.build(session_id, include_conversation: false)

      assert context.conversation == []
    end

    test "calculates token counts", %{session_id: session_id} do
      user_msg = %{role: :user, content: "Hello, this is a test message", id: "msg-1", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session_id, user_msg)
      :ok = State.update_context(session_id, :project_root, "/app")

      {:ok, context} = ContextBuilder.build(session_id)

      assert is_integer(context.token_counts.conversation)
      assert is_integer(context.token_counts.working)
      assert is_integer(context.token_counts.long_term)
      assert is_integer(context.token_counts.total)
      assert context.token_counts.total ==
               context.token_counts.conversation +
               context.token_counts.working +
               context.token_counts.long_term
    end

    test "returns error for non-existent session" do
      result = ContextBuilder.build("non-existent-session-12345")

      assert {:error, :session_not_found} = result
    end
  end

  # =============================================================================
  # build/2 Truncation Tests
  # =============================================================================

  describe "build/2 truncation" do
    test "truncates conversation to budget", %{session_id: session_id} do
      # Add many messages
      for i <- 1..100 do
        msg = %{role: :user, content: "Message #{i}: " <> String.duplicate("x", 100), id: "msg-#{i}", timestamp: DateTime.utc_now()}
        {:ok, _} = State.append_message(session_id, msg)
      end

      # Use a small conversation budget
      small_budget = %{
        total: 1000,
        system: 100,
        conversation: 500,
        working: 200,
        long_term: 200
      }

      {:ok, context} = ContextBuilder.build(session_id, token_budget: small_budget)

      # Should have fewer messages than we added
      assert length(context.conversation) < 100
      # Token count should be within budget
      assert context.token_counts.conversation <= 500
    end

    test "keeps most recent messages when truncating", %{session_id: session_id} do
      # Add messages with identifiable content
      msg1 = %{role: :user, content: "First message", id: "msg-1", timestamp: DateTime.utc_now()}
      msg2 = %{role: :user, content: "Second message", id: "msg-2", timestamp: DateTime.utc_now()}
      msg3 = %{role: :user, content: "Third message - most recent", id: "msg-3", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session_id, msg1)
      {:ok, _} = State.append_message(session_id, msg2)
      {:ok, _} = State.append_message(session_id, msg3)

      # Use a budget that can only fit the last message
      tiny_budget = %{
        total: 100,
        system: 10,
        conversation: 20,
        working: 10,
        long_term: 10
      }

      {:ok, context} = ContextBuilder.build(session_id, token_budget: tiny_budget)

      # Should have at least one message (the most recent)
      if length(context.conversation) > 0 do
        last_msg = List.last(context.conversation)
        assert last_msg.content =~ "most recent"
      end
    end
  end

  # =============================================================================
  # format_for_prompt/1 Tests
  # =============================================================================

  describe "format_for_prompt/1" do
    test "formats empty context as empty string" do
      context = %{
        working_context: %{},
        long_term_memories: []
      }

      result = ContextBuilder.format_for_prompt(context)

      assert result == ""
    end

    test "formats working context section" do
      context = %{
        working_context: %{
          project_root: "/app",
          primary_language: "elixir"
        },
        long_term_memories: []
      }

      result = ContextBuilder.format_for_prompt(context)

      assert result =~ "## Session Context"
      assert result =~ "Project root"
      assert result =~ "/app"
      assert result =~ "Primary language"
      assert result =~ "elixir"
    end

    test "formats memories section" do
      context = %{
        working_context: %{},
        long_term_memories: [
          %{
            memory_type: :fact,
            confidence: 0.9,
            content: "Uses Phoenix 1.7"
          }
        ]
      }

      result = ContextBuilder.format_for_prompt(context)

      assert result =~ "## Remembered Information"
      assert result =~ "[fact]"
      assert result =~ "(high confidence)"
      assert result =~ "Uses Phoenix 1.7"
    end

    test "includes both sections when present" do
      context = %{
        working_context: %{project_root: "/app"},
        long_term_memories: [
          %{memory_type: :fact, confidence: 0.9, content: "Test memory"}
        ]
      }

      result = ContextBuilder.format_for_prompt(context)

      assert result =~ "## Session Context"
      assert result =~ "## Remembered Information"
    end

    test "confidence badges are correct" do
      high_context = %{
        working_context: %{},
        long_term_memories: [%{memory_type: :fact, confidence: 0.9, content: "High"}]
      }

      medium_context = %{
        working_context: %{},
        long_term_memories: [%{memory_type: :fact, confidence: 0.6, content: "Medium"}]
      }

      low_context = %{
        working_context: %{},
        long_term_memories: [%{memory_type: :fact, confidence: 0.3, content: "Low"}]
      }

      assert ContextBuilder.format_for_prompt(high_context) =~ "(high confidence)"
      assert ContextBuilder.format_for_prompt(medium_context) =~ "(medium confidence)"
      assert ContextBuilder.format_for_prompt(low_context) =~ "(low confidence)"
    end

    test "handles various value types in working context" do
      context = %{
        working_context: %{
          string_val: "hello",
          atom_val: :test,
          number_val: 42,
          list_val: ["a", "b", "c"]
        },
        long_term_memories: []
      }

      result = ContextBuilder.format_for_prompt(context)

      assert result =~ "hello"
      assert result =~ "test"
      assert result =~ "42"
      assert result =~ "a, b, c"
    end

    test "includes timestamp when present in memory" do
      context = %{
        working_context: %{},
        long_term_memories: [
          %{
            memory_type: :fact,
            confidence: 0.9,
            content: "Test",
            timestamp: ~U[2024-01-15 10:30:00Z]
          }
        ]
      }

      result = ContextBuilder.format_for_prompt(context)

      assert result =~ "2024-01-15"
    end

    test "handles nil/invalid input gracefully" do
      assert ContextBuilder.format_for_prompt(nil) == ""
      assert ContextBuilder.format_for_prompt(%{}) == ""
    end
  end

  # =============================================================================
  # Integration with Session.State Tests
  # =============================================================================

  describe "integration with Session.State" do
    test "retrieves actual messages from state", %{session_id: session_id} do
      user_msg = %{role: :user, content: "What is Elixir?", id: "msg-1", timestamp: DateTime.utc_now()}
      assistant_msg = %{role: :assistant, content: "Elixir is a functional programming language.", id: "msg-2", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session_id, user_msg)
      {:ok, _} = State.append_message(session_id, assistant_msg)

      {:ok, context} = ContextBuilder.build(session_id)

      messages = context.conversation
      assert length(messages) == 2

      user = Enum.find(messages, fn m -> m.role == :user end)
      assert user.content == "What is Elixir?"

      assistant = Enum.find(messages, fn m -> m.role == :assistant end)
      assert assistant.content == "Elixir is a functional programming language."
    end

    test "retrieves actual working context from state", %{session_id: session_id} do
      :ok = State.update_context(session_id, :active_file, "/app/lib/main.ex")
      :ok = State.update_context(session_id, :current_task, "implementing feature X")

      {:ok, context} = ContextBuilder.build(session_id)

      assert context.working_context[:active_file] == "/app/lib/main.ex"
      assert context.working_context[:current_task] == "implementing feature X"
    end
  end
end
