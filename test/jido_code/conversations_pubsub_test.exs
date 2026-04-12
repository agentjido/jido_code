defmodule JidoCode.ConversationsPubSubTest do
  use ExUnit.Case, async: true

  alias JidoCode.Conversations.PubSub

  defmodule FailingConversationEventBroadcaster do
    def broadcast(_pubsub, _topic, _message),
      do: {:error, %{error_type: "forced_publish_failure"}}
  end

  setup do
    original_broadcaster =
      Application.get_env(:jido_code, :conversation_event_broadcaster, Phoenix.PubSub)

    on_exit(fn ->
      Application.put_env(:jido_code, :conversation_event_broadcaster, original_broadcaster)
    end)

    :ok
  end

  test "returns a typed diagnostic when conversation event publication fails" do
    Application.put_env(
      :jido_code,
      :conversation_event_broadcaster,
      FailingConversationEventBroadcaster
    )

    assert {:error, diagnostic} =
             PubSub.broadcast_conversation_event("conversation-pubsub-1", %{
               name: "turn.started",
               sequence: 1,
               payload: %{"instruction" => "Inspect the failing broadcaster path."}
             })

    assert diagnostic["error_type"] == "conversation_event_publication_failed"
    assert diagnostic["event"] == "turn.started"
    assert diagnostic["reason_type"] == "forced_publish_failure"
  end
end
