defmodule JidoCode.ConversationsChildWorkTest do
  use ExUnit.Case, async: true

  alias JidoCode.Conversations.ChildWork

  test "runtime updates preserve datetime values while normalizing nested maps" do
    observed_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    child_work = %ChildWork{
      id: "child-work",
      conversation_id: "conversation",
      managed_repo_id: "managed-repo",
      turn_id: "turn",
      tool_call_id: "tool-call",
      kind: "tool_call",
      state: :running,
      inserted_at: observed_at,
      result: %{}
    }

    assert {:ok, updated_child_work} =
             ChildWork.record_update(child_work, :delta, %{
               context_management: %{
                 latest_monitor_decision: %{
                   created_at: observed_at,
                   state: :healthy
                 }
               }
             })

    assert get_in(updated_child_work.result, [
             "last_delta",
             "context_management",
             "latest_monitor_decision",
             "created_at"
           ]) == observed_at

    assert get_in(updated_child_work.result, [
             "last_delta",
             "context_management",
             "latest_monitor_decision",
             "state"
           ]) == :healthy
  end
end
