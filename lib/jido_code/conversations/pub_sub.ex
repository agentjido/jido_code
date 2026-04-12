defmodule JidoCode.Conversations.PubSub do
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  @moduledoc """
  PubSub helpers for conversation events.

  Topics:
  - `"jido_code:conversations"` - Cross-conversation summaries
  - `"jido_code:conversation:<id>"` - Per-conversation sequenced events
  """

  require Logger

  alias JidoCode.Forge.ChannelRedaction

  @pubsub JidoCode.PubSub
  @default_subscriber Phoenix.PubSub
  @default_broadcaster Phoenix.PubSub
  @conversations_topic "jido_code:conversations"

  @spec conversations_topic() :: String.t()
  def conversations_topic, do: @conversations_topic

  @spec conversation_topic(String.t()) :: String.t()
  def conversation_topic(conversation_id), do: "jido_code:conversation:#{conversation_id}"

  @spec subscribe_conversations() :: :ok | {:error, term()}
  def subscribe_conversations do
    subscriber().subscribe(@pubsub, conversations_topic())
  end

  @spec subscribe_conversation(String.t()) :: :ok | {:error, term()}
  def subscribe_conversation(conversation_id) do
    subscriber().subscribe(@pubsub, conversation_topic(conversation_id))
  end

  @spec unsubscribe_conversation(String.t()) :: :ok
  def unsubscribe_conversation(conversation_id) do
    subscriber().unsubscribe(@pubsub, conversation_topic(conversation_id))
  end

  @spec broadcast_conversation_event(String.t(), map()) :: :ok | {:error, map()}
  def broadcast_conversation_event(conversation_id, payload) when is_binary(conversation_id) and is_map(payload) do
    topic = conversation_topic(conversation_id)
    event_name = payload |> Map.get(:name, Map.get(payload, "name", "unknown")) |> normalize_event_name()

    with {:ok, redacted_payload} <-
           ChannelRedaction.redact_pubsub_payload(payload, operation: :broadcast_conversation_event),
         :ok <-
           publish(
             topic,
             {:conversation_event, redacted_payload},
             event_name,
             "conversation_topic",
             "Conversation topic event publication failed."
           ),
         :ok <-
           publish(
             conversations_topic(),
             {:conversation_event, redacted_payload},
             event_name,
             "conversations_topic",
             "Conversation summary topic publication failed."
           ) do
      :ok
    else
      {:error, %{error_type: error_type} = typed_error} ->
        diagnostic =
          typed_diagnostic(
            topic,
            event_name,
            %{error_type: error_type},
            "conversation_topic",
            typed_error.message || "Conversation event publication failed."
          )

        emit_publication_failure(diagnostic)
        {:error, diagnostic}

      {:error, typed_diagnostic} ->
        emit_publication_failure(typed_diagnostic)
        {:error, typed_diagnostic}
    end
  end

  def broadcast_conversation_event(_conversation_id, _payload) do
    {:error,
     typed_diagnostic(
       "jido_code:conversation:unknown",
       "unknown",
       %{error_type: "event_payload_invalid"},
       "conversation_topic",
       "Conversation event publication failed."
     )}
  end

  defp publish(topic, message, event_name, channel, message_text) do
    case broadcaster().broadcast(@pubsub, topic, message) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, typed_diagnostic(topic, event_name, reason, channel, message_text)}

      other ->
        {:error, typed_diagnostic(topic, event_name, %{error_type: inspect(other)}, channel, message_text)}
    end
  end

  defp emit_publication_failure(typed_diagnostic) do
    Logger.error(
      "event_channel_diagnostic error_type=#{typed_diagnostic["error_type"]} channel=#{typed_diagnostic["channel"]} operation=#{typed_diagnostic["operation"]} event=#{typed_diagnostic["event"]} reason_type=#{typed_diagnostic["reason_type"]}"
    )
  end

  defp subscriber do
    Application.get_env(:jido_code, :conversation_pubsub_subscriber, @default_subscriber)
  end

  defp broadcaster do
    Application.get_env(:jido_code, :conversation_event_broadcaster, @default_broadcaster)
  end

  defp typed_diagnostic(topic, event_name, reason, channel, message) do
    %{
      "error_type" => "conversation_event_publication_failed",
      "channel" => channel,
      "operation" => "broadcast_conversation_event",
      "topic" => topic,
      "event" => event_name,
      "reason_type" => reason_type(reason),
      "message" => message,
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp normalize_event_name(value) when is_binary(value) and value != "", do: value
  defp normalize_event_name(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_event_name()
  defp normalize_event_name(_value), do: "unknown"

  defp reason_type(%{error_type: error_type}) when is_binary(error_type),
    do: sanitize_reason_type(error_type)

  defp reason_type(%{"error_type" => error_type}) when is_binary(error_type),
    do: sanitize_reason_type(error_type)

  defp reason_type(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> sanitize_reason_type()

  defp reason_type(reason) when is_binary(reason), do: sanitize_reason_type(reason)
  defp reason_type(_reason), do: "unknown"

  defp sanitize_reason_type(type) do
    String.replace(type, ~r/[^a-zA-Z0-9._-]/, "_")
  end
end
