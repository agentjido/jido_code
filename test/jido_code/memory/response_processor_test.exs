defmodule JidoCode.Memory.ResponseProcessorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory.ResponseProcessor
  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry
  alias JidoCode.Session.State, as: SessionState

  # Helper to start a session for testing
  defp start_test_session(tmp_dir) do
    {:ok, session} = Session.new(project_path: tmp_dir)
    {:ok, _pid} = SessionState.start_link(session: session)
    session.id
  end

  # Helper to stop a session
  defp stop_test_session(session_id) do
    case ProcessRegistry.lookup(:state, session_id) do
      {:error, :not_found} -> :ok
      {:ok, pid} -> GenServer.stop(pid, :normal, 1000)
    end
  catch
    :exit, _ -> :ok
  end

  # =============================================================================
  # extract_context/1 - Active File Extraction Tests
  # =============================================================================

  describe "extract_context/1 active_file extraction" do
    test "finds active_file from 'working on file.ex'" do
      response = "I'm working on lib/my_app.ex to fix this issue."
      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "lib/my_app.ex"
    end

    test "finds active_file from 'editing `config.exs`'" do
      response = "Let me start by editing `config/config.exs` to add the setting."
      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "config/config.exs"
    end

    test "finds active_file from 'looking at file'" do
      response = "Looking at test/app_test.exs, I see the issue."
      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "test/app_test.exs"
    end

    test "finds active_file from 'reading file'" do
      response = "After reading mix.exs, I understand the dependencies."
      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "mix.exs"
    end

    test "finds active_file from 'file: path'" do
      response = "The issue is in file: lib/utils.ex at line 42."
      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "lib/utils.ex"
    end

    test "finds active_file from 'in the file'" do
      response = "The function is defined in the file lib/handler.ex."
      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "lib/handler.ex"
    end

    test "does not extract URLs as files" do
      response = "Check out https://example.com/test.html for more info."
      result = ResponseProcessor.extract_context(response)

      refute Map.has_key?(result, :active_file)
    end

    test "does not extract files with spaces" do
      response = "Working on my file name.ex"
      result = ResponseProcessor.extract_context(response)

      # Should not match due to space in filename
      refute result[:active_file] == "my file name.ex"
    end
  end

  # =============================================================================
  # extract_context/1 - Framework Extraction Tests
  # =============================================================================

  describe "extract_context/1 framework extraction" do
    test "finds framework from 'using Phoenix 1.7'" do
      response = "This project is using Phoenix 1.7 for the web layer."
      result = ResponseProcessor.extract_context(response)

      assert result[:framework] == "Phoenix 1.7"
    end

    test "finds framework from 'built with React'" do
      response = "The frontend is built with React and Redux."
      result = ResponseProcessor.extract_context(response)

      assert result[:framework] == "React"
    end

    test "finds framework from 'project uses Ecto'" do
      response = "The project uses Ecto for database interactions."
      result = ResponseProcessor.extract_context(response)

      assert result[:framework] == "Ecto"
    end

    test "finds framework from 'based on LiveView'" do
      response = "The UI is based on LiveView for real-time updates."
      result = ResponseProcessor.extract_context(response)

      assert result[:framework] == "LiveView"
    end

    test "finds framework from 'This is a Phoenix application'" do
      response = "This is a Phoenix application with LiveView."
      result = ResponseProcessor.extract_context(response)

      assert result[:framework] == "Phoenix"
    end

    test "does not extract lowercase words as frameworks" do
      response = "We're using some library for this."
      result = ResponseProcessor.extract_context(response)

      refute Map.has_key?(result, :framework)
    end
  end

  # =============================================================================
  # extract_context/1 - Current Task Extraction Tests
  # =============================================================================

  describe "extract_context/1 current_task extraction" do
    test "finds current_task from 'implementing user auth'" do
      response = "I'm implementing user authentication with sessions."
      result = ResponseProcessor.extract_context(response)

      assert result[:current_task] == "user authentication with sessions"
    end

    test "finds current_task from 'fixing the bug'" do
      response = "I'm fixing the race condition in the cache module."
      result = ResponseProcessor.extract_context(response)

      assert result[:current_task] == "the race condition in the cache module"
    end

    test "finds current_task from 'creating a new module'" do
      response = "Creating a new GenServer for handling connections."
      result = ResponseProcessor.extract_context(response)

      assert result[:current_task] == "a new GenServer for handling connections"
    end

    test "finds current_task from 'adding tests'" do
      response = "Adding unit tests for the parser module."
      result = ResponseProcessor.extract_context(response)

      assert result[:current_task] == "unit tests for the parser module"
    end

    test "finds current_task from 'updating the config'" do
      response = "Updating the database configuration. Here's what we need."
      result = ResponseProcessor.extract_context(response)

      assert result[:current_task] == "the database configuration"
    end

    test "finds current_task from 'refactoring'" do
      response = "Refactoring the API layer to use contexts."
      result = ResponseProcessor.extract_context(response)

      assert result[:current_task] == "the API layer to use contexts"
    end

    test "truncates very long tasks" do
      long_task = String.duplicate("a", 150)
      response = "Implementing #{long_task}"
      result = ResponseProcessor.extract_context(response)

      assert String.length(result[:current_task]) <= 100
      assert String.ends_with?(result[:current_task], "...")
    end
  end

  # =============================================================================
  # extract_context/1 - Primary Language Extraction Tests
  # =============================================================================

  describe "extract_context/1 primary_language extraction" do
    test "finds primary_language from 'this is an Elixir project'" do
      response = "This is an Elixir project using OTP patterns."
      result = ResponseProcessor.extract_context(response)

      assert result[:primary_language] == "Elixir"
    end

    test "finds primary_language from 'written in Python'" do
      response = "The service is written in Python with FastAPI."
      result = ResponseProcessor.extract_context(response)

      assert result[:primary_language] == "Python"
    end

    test "finds primary_language from 'JavaScript application'" do
      response = "This is a JavaScript application using Node.js."
      result = ResponseProcessor.extract_context(response)

      assert result[:primary_language] == "Javascript"
    end

    test "finds primary_language from 'Rust codebase'" do
      response = "The Rust codebase follows standard conventions."
      result = ResponseProcessor.extract_context(response)

      assert result[:primary_language] == "Rust"
    end

    test "does not extract unknown languages" do
      response = "This is a Foobar project."
      result = ResponseProcessor.extract_context(response)

      refute Map.has_key?(result, :primary_language)
    end

    test "normalizes language names to capitalized form" do
      response = "This is a PYTHON project."
      result = ResponseProcessor.extract_context(response)

      assert result[:primary_language] == "Python"
    end
  end

  # =============================================================================
  # extract_context/1 - Multiple Extractions Tests
  # =============================================================================

  describe "extract_context/1 multiple extractions" do
    test "extracts multiple context items from rich response" do
      response = """
      I'm working on lib/my_app/web/controllers/user_controller.ex.
      This is an Elixir project using Phoenix 1.7 for the web framework.
      I'm implementing user registration with email verification.
      """

      result = ResponseProcessor.extract_context(response)

      assert result[:active_file] == "lib/my_app/web/controllers/user_controller.ex"
      assert result[:primary_language] == "Elixir"
      assert result[:framework] == "Phoenix 1.7"
      assert result[:current_task] == "user registration with email verification"
    end

    test "handles responses without any patterns" do
      response = "Hello! How can I help you today?"
      result = ResponseProcessor.extract_context(response)

      assert result == %{}
    end

    test "handles empty response" do
      result = ResponseProcessor.extract_context("")
      assert result == %{}
    end

    test "handles nil-like input" do
      assert ResponseProcessor.extract_context(nil) == %{}
    end
  end

  # =============================================================================
  # process_response/2 - Integration Tests
  # =============================================================================

  describe "process_response/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      session_id = start_test_session(tmp_dir)
      on_exit(fn -> stop_test_session(session_id) end)
      %{session_id: session_id}
    end

    test "updates working context with extracted values", %{session_id: session_id} do
      response = "I'm looking at lib/app.ex in this Elixir project."

      {:ok, extractions} = ResponseProcessor.process_response(response, session_id)

      assert extractions[:active_file] == "lib/app.ex"
      assert extractions[:primary_language] == "Elixir"

      # Verify context was updated in session (use get_context_item for full metadata)
      {:ok, context} = SessionState.get_context_item(session_id, :active_file)
      assert context.value == "lib/app.ex"
      assert context.source == :inferred
      assert context.confidence == 0.6
    end

    test "assigns inferred source to extracted context", %{session_id: session_id} do
      response = "Working on test/my_test.exs"

      {:ok, _extractions} = ResponseProcessor.process_response(response, session_id)

      {:ok, context} = SessionState.get_context_item(session_id, :active_file)
      assert context.source == :inferred
    end

    test "uses lower confidence (0.6) for inferred context", %{session_id: session_id} do
      response = "This is a Python project"

      {:ok, _extractions} = ResponseProcessor.process_response(response, session_id)

      {:ok, context} = SessionState.get_context_item(session_id, :primary_language)
      assert context.confidence == ResponseProcessor.inferred_confidence()
      assert context.confidence == 0.6
    end

    test "returns empty map for empty response", %{session_id: session_id} do
      {:ok, extractions} = ResponseProcessor.process_response("", session_id)
      assert extractions == %{}
    end

    test "returns empty map for nil response", %{session_id: session_id} do
      {:ok, extractions} = ResponseProcessor.process_response(nil, session_id)
      assert extractions == %{}
    end

    test "handles response without matches gracefully", %{session_id: session_id} do
      response = "Sure, I can help you with that question!"

      {:ok, extractions} = ResponseProcessor.process_response(response, session_id)

      assert extractions == %{}
    end

    test "returns extractions even when context update fails" do
      # Use an invalid session ID that doesn't exist
      response = "Working on lib/app.ex"

      {:ok, extractions} = ResponseProcessor.process_response(response, "nonexistent-session-xyz")

      # Should still return extractions
      assert extractions[:active_file] == "lib/app.ex"
    end
  end

  # =============================================================================
  # Edge Cases and Error Handling Tests
  # =============================================================================

  describe "edge cases and error handling" do
    test "handles malformed regex-like input safely" do
      # Input that could cause regex issues
      response = "Looking at file: [[[invalid regex pattern]]].ex"
      result = ResponseProcessor.extract_context(response)

      # Should not crash
      assert is_map(result)
    end

    test "handles very long responses" do
      # Generate a very long response
      long_response = String.duplicate("Hello world. ", 10_000) <> "Working on lib/app.ex"
      result = ResponseProcessor.extract_context(long_response)

      # Should still find the file at the end
      assert result[:active_file] == "lib/app.ex"
    end

    test "handles unicode characters in responses" do
      response = "I'm working on lib/文件.ex and it's 完美"
      result = ResponseProcessor.extract_context(response)

      # Unicode filename should be extracted
      assert result[:active_file] == "lib/文件.ex"
    end

    test "inferred_confidence/0 returns expected value" do
      assert ResponseProcessor.inferred_confidence() == 0.6
    end

    test "context_patterns/0 returns pattern map" do
      patterns = ResponseProcessor.context_patterns()

      assert is_map(patterns)
      assert Map.has_key?(patterns, :active_file)
      assert Map.has_key?(patterns, :framework)
      assert Map.has_key?(patterns, :current_task)
      assert Map.has_key?(patterns, :primary_language)
    end
  end

  # =============================================================================
  # Validation Tests
  # =============================================================================

  describe "value validation" do
    test "validates file paths have extensions" do
      # No extension
      response = "Working on README"
      result = ResponseProcessor.extract_context(response)

      refute Map.has_key?(result, :active_file)
    end

    test "validates file paths are reasonable length" do
      # Very short path (less than 3 chars)
      response = "Working on a.e"
      result = ResponseProcessor.extract_context(response)

      refute result[:active_file] == "a."
    end

    test "validates known programming languages" do
      # Known language
      response = "This is a Go project"
      result = ResponseProcessor.extract_context(response)
      assert result[:primary_language] == "Go"

      # Unknown language - should not extract
      response2 = "This is a Brainfuck project"
      result2 = ResponseProcessor.extract_context(response2)
      refute Map.has_key?(result2, :primary_language)
    end
  end
end
