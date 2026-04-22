defmodule JidoCode.Forge.PubSub do
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  @moduledoc """
  PubSub helpers for Forge session events.

  Topics:
  - `"forge:sessions"` - Global session list changes
  - `"forge:session:<id>"` - Per-session state/output events
  """

  require Logger

  alias JidoCode.Forge.ChannelRedaction

  @pubsub JidoCode.PubSub
  @default_subscriber Phoenix.PubSub
  @default_broadcaster Phoenix.PubSub

  def sessions_topic, do: "forge:sessions"
  def session_topic(id), do: "forge:session:#{id}"

  def subscribe_sessions do
    subscriber().subscribe(@pubsub, sessions_topic())
  end

  def subscribe_session(id) do
    subscriber().subscribe(@pubsub, session_topic(id))
  end

  def unsubscribe_session(id) do
    subscriber().unsubscribe(@pubsub, session_topic(id))
  end

  @spec broadcast_sessions(term()) :: :ok | {:error, ChannelRedaction.typed_security_error()}
  def broadcast_sessions(msg) do
    topic = sessions_topic()

    with {:ok, redacted_msg} <-
           ChannelRedaction.redact_pubsub_payload(msg, operation: :broadcast_sessions) do
      broadcaster().broadcast(@pubsub, topic, redacted_msg)
    else
      {:error, typed_error} = error ->
        emit_redaction_failure(topic, typed_error)
        error
    end
  end

  @spec broadcast_session(term(), term()) ::
          :ok | {:error, ChannelRedaction.typed_security_error()}
  def broadcast_session(id, msg) do
    topic = session_topic(id)

    with {:ok, redacted_msg} <-
           ChannelRedaction.redact_pubsub_payload(msg, operation: :broadcast_session) do
      broadcaster().broadcast(@pubsub, topic, redacted_msg)
    else
      {:error, typed_error} = error ->
        emit_redaction_failure(topic, typed_error)
        error
    end
  end

  defp emit_redaction_failure(topic, typed_error) do
    Logger.error(
      "security_audit=forge_pubsub_redaction_failed severity=high topic=#{topic} action=publication_blocked error_type=#{typed_error.error_type} reason_type=#{typed_error.reason_type}"
    )
  end

  defp subscriber do
    Application.get_env(:jido_code, :forge_pubsub_subscriber, @default_subscriber)
  end

  defp broadcaster do
    Application.get_env(:jido_code, :forge_pubsub_broadcaster, @default_broadcaster)
  end
end
