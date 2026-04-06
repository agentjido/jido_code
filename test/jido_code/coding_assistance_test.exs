defmodule JidoCode.CodingAssistanceTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: coding_assistance.boundary.session_prepared_before_assist
  # covers: coding_assistance.boundary.product_local_driver_api
  use ExUnit.Case, async: true

  alias JidoCode.CodingAssistance

  describe "session management" do
    test "ensure_session creates a new session" do
      actor_id = "user-1"
      session_id = "thread-1"

      assert {:ok, session} = CodingAssistance.ensure_session(session_id, actor_id)
      assert is_map(session)
    end

    test "lookup_session returns an existing session" do
      actor_id = "user-2"
      session_id = "thread-2"

      assert {:ok, _session} = CodingAssistance.ensure_session(session_id, actor_id)
      assert {:ok, session} = CodingAssistance.lookup_session(session_id, actor_id)
      assert is_map(session)
    end
  end

  describe "project binding" do
    test "bind_project binds a session to a project" do
      actor_id = "user-3"
      session_id = "thread-3"
      project_id = "project-a"

      assert {:ok, result} = CodingAssistance.bind_project(session_id, actor_id, project_id)
      assert is_map(result)
    end

    test "unbind_project unbinds a session from its project" do
      actor_id = "user-4"
      session_id = "thread-4"

      assert {:ok, result} = CodingAssistance.unbind_project(session_id, actor_id)
      assert is_map(result)
    end
  end

  describe "AI selection" do
    test "update_ai_selection updates AI preferences" do
      actor_id = "user-5"
      session_id = "thread-5"

      assert {:ok, result} =
               CodingAssistance.update_ai_selection(session_id, actor_id, %{
                 preferred_model_profile: "balanced"
               })

      assert is_map(result)
    end

    test "get_ai_selection returns AI preferences" do
      actor_id = "user-6"
      session_id = "thread-6"

      assert {:ok, selection} = CodingAssistance.get_ai_selection(session_id, actor_id)
      assert is_map(selection)
    end
  end

  describe "turn lifecycle" do
    test "start_turn creates and returns a turn" do
      actor_id = "user-7"
      session_id = "thread-7"

      assert {:ok, turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "Implement a feature",
                 operation: "implement"
               })

      assert turn.session_id == session_id
      assert turn.state == "completed"
      assert is_binary(turn.turn_id)
    end

    test "get_turn retrieves an existing turn" do
      actor_id = "user-8"
      session_id = "thread-8"

      assert {:ok, turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "Test feature",
                 operation: "implement"
               })

      assert {:ok, fetched_turn} =
               CodingAssistance.get_turn(actor_id, %{
                 session_id: session_id,
                 turn_id: turn.turn_id
               })

      assert fetched_turn.turn_id == turn.turn_id
    end

    test "list_turns returns turns for a session" do
      actor_id = "user-9"
      session_id = "thread-9"

      assert {:ok, _turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "List turns test",
                 operation: "plan"
               })

      assert {:ok, turns} = CodingAssistance.list_turns(actor_id, %{session_id: session_id})
      assert is_list(turns)
    end

    test "cancel_turn cancels a turn" do
      actor_id = "user-10"
      session_id = "thread-10"

      assert {:ok, turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "Cancel test",
                 operation: "plan"
               })

      assert {:ok, cancelled_turn} =
               CodingAssistance.cancel_turn(actor_id, %{
                 session_id: session_id,
                 turn_id: turn.turn_id
               })

      assert cancelled_turn.state == "cancelled"
    end
  end

  describe "assist compatibility wrapper" do
    test "assist provides a simple wrapper for starting turns" do
      actor_id = "user-11"
      session_id = "thread-11"

      assert {:ok, envelope} =
               CodingAssistance.assist(actor_id, %{
                 session_id: session_id,
                 objective: "Plan a refactor",
                 operation: "plan"
               })

      assert is_map(envelope)
    end
  end

  describe "turn events" do
    test "list_turn_events returns events for a turn" do
      actor_id = "user-12"
      session_id = "thread-12"

      assert {:ok, turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "Events test",
                 operation: "plan"
               })

      assert {:ok, events} =
               CodingAssistance.list_turn_events(actor_id, %{
                 session_id: session_id,
                 turn_id: turn.turn_id
               })

      assert is_list(events)
    end
  end

  describe "turn artifacts" do
    test "list_turn_artifacts returns artifacts for a turn" do
      actor_id = "user-13"
      session_id = "thread-13"

      assert {:ok, turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "Artifacts test",
                 operation: "implement"
               })

      assert {:ok, artifacts} =
               CodingAssistance.list_turn_artifacts(actor_id, %{
                 session_id: session_id,
                 turn_id: turn.turn_id
               })

      assert is_list(artifacts)
    end
  end

  describe "turn review" do
    test "review_turn returns review information" do
      actor_id = "user-14"
      session_id = "thread-14"

      assert {:ok, turn} =
               CodingAssistance.start_turn(actor_id, %{
                 session_id: session_id,
                 objective: "Review test",
                 operation: "review"
               })

      assert {:ok, review} =
               CodingAssistance.review_turn(actor_id, %{
                 session_id: session_id,
                 turn_id: turn.turn_id
               })

      assert is_map(review)
    end
  end

  describe "live subscription" do
    test "subscribe_turn_events returns a subscription acknowledgment" do
      actor_id = "user-15"
      session_id = "thread-15"

      assert {:ok, ack} =
               CodingAssistance.subscribe_turn_events(actor_id, %{
                 session_id: session_id,
                 turn_id: "test-turn"
               })

      assert ack.status == "subscribed"
      assert is_binary(ack.subscription_id)
    end

    test "unsubscribe_turn_events detaches a subscription" do
      actor_id = "user-16"
      session_id = "thread-16"

      assert {:ok, ack} =
               CodingAssistance.unsubscribe_turn_events(actor_id, %{
                 session_id: session_id,
         turn_id: "test-turn"
       })

      assert ack.status == "detached"
    end
  end
end
