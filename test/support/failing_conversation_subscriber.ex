defmodule JidoCodeWeb.FailingConversationSubscriber do
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  @moduledoc false

  def subscribe(_pubsub, _topic), do: {:error, :subscription_unavailable}
  def unsubscribe(_pubsub, _topic), do: :ok
end
