defmodule Jido.Os.CodingAssist.Service do
  # covers: jido_os.runtime.compatibility.public_runtime_surface
  # covers: jido_os.runtime.compatibility.session_and_envelope_behaviour
  # covers: jido_os.runtime.compatibility.public_turn_runtime_surface
  # covers: jido_os.runtime.compatibility.compatibility_assist_uses_same_turn_model
  # covers: architecture.jido_os_session_turn_runtime.public_turn_event_surface
  # covers: architecture.jido_os_session_turn_runtime.public_turn_live_subscription_surface
  # covers: architecture.jido_os_session_turn_runtime.live_delivery_resume_has_stable_cursor_and_terminal_handoff
  # covers: architecture.jido_os_session_turn_runtime.live_and_replay_release_parity
  @moduledoc false
  @runtime_service_key "coding_assistance_service"

  alias Jido.Os.Session.RuntimeAgent
  alias Jido.Os.State

  def runtime_service_key, do: @runtime_service_key

  def assist(instance_id, request, context)
      when is_binary(instance_id) and is_map(request) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(request, context),
         {:ok, _session} <- RuntimeAgent.load_session(instance_id, session_id, service_context(context, session_id)) do
      {:ok,
       %{
         outcome: "ok",
         context:
           compact_nil_values(%{
             instance_id: instance_id,
             session_id: session_id,
             actor_id: Map.get(context, :actor_id),
             project_id: Map.get(context, :project_id),
             workspace_id: Map.get(context, :workspace_id)
           }),
         payload: assist_payload(request)
       }}
    else
      nil ->
        {:error, :missing_session_id}

      {:error, _reason} = error ->
        error
    end
  end

  def start_turn(instance_id, request, context)
      when is_binary(instance_id) and is_map(request) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(request, context),
         scoped_context <- service_context(context, session_id),
         {:ok, _session} <- RuntimeAgent.load_session(instance_id, session_id, scoped_context) do
      turn = build_turn(instance_id, session_id, request, scoped_context)
      events = build_turn_events(turn)
      review = build_turn_review(turn)

      with {:ok, stored_turn} <-
             RuntimeAgent.store_turn(instance_id, session_id, turn, events, review, scoped_context) do
        {:ok, project_turn(stored_turn)}
      end
    else
      nil -> {:error, :missing_session_id}
      {:error, _reason} = error -> error
    end
  end

  def get_turn(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         {:ok, turn} <- RuntimeAgent.get_turn(instance_id, session_id, turn_id, service_context(context, session_id)) do
      {:ok, project_turn(turn)}
    else
      nil -> {:error, :missing_turn_identifier}
      {:error, _reason} = error -> error
    end
  end

  def list_turns(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         {:ok, turns} <- RuntimeAgent.list_turns(instance_id, session_id, service_context(context, session_id)) do
      {:ok, Enum.map(turns, &project_turn/1)}
    else
      nil -> {:error, :missing_session_id}
      {:error, _reason} = error -> error
    end
  end

  def list_turn_events(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         {:ok, events} <-
           RuntimeAgent.list_turn_events(instance_id, session_id, turn_id, service_context(context, session_id)) do
      {:ok, filter_events_after(events, get_string(payload, :after_event_id))}
    else
      nil -> {:error, :missing_turn_identifier}
      {:error, _reason} = error -> error
    end
  end

  def list_turn_artifacts(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         {:ok, _artifacts} <-
           RuntimeAgent.list_turn_artifacts(
             instance_id,
             session_id,
             turn_id,
             service_context(context, session_id)
           ),
         {:ok, turn} <- RuntimeAgent.get_turn(instance_id, session_id, turn_id, service_context(context, session_id)) do
      {:ok, project_turn_artifacts(turn)}
    else
      nil -> {:error, :missing_turn_identifier}
      {:error, _reason} = error -> error
    end
  end

  def review_turn(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         {:ok, review} <-
           RuntimeAgent.get_turn_review(instance_id, session_id, turn_id, service_context(context, session_id)) do
      {:ok, review}
    else
      nil -> {:error, :missing_turn_identifier}
      {:error, _reason} = error -> error
    end
  end

  def cancel_turn(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         scoped_context <- service_context(context, session_id),
         {:ok, turn} <- RuntimeAgent.cancel_turn(instance_id, session_id, turn_id, scoped_context) do
      updated_turn =
        case Map.get(turn, :state) do
          "cancelled" ->
            ensure_cancelled_event_and_review(instance_id, session_id, turn, scoped_context)

          _other ->
            turn
        end

      {:ok, project_turn(updated_turn)}
    else
      nil -> {:error, :missing_turn_identifier}
      {:error, _reason} = error -> error
    end
  end

  def subscribe_turn_events(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         subscriber when is_pid(subscriber) <- get_pid(payload, :subscriber),
         scoped_context <- service_context(context, session_id),
         {:ok, turn} <- RuntimeAgent.get_turn(instance_id, session_id, turn_id, scoped_context) do
      events = State.list_turn_events(instance_id, session_id, turn_id)
      latest_event_id = latest_event_id(events)

      case validate_resume_cursor(events, get_string(payload, :after_event_id)) do
        {:error, :invalid_after_event_id} ->
          {:ok,
           project_live_ack(%{
             status: "invalid_cursor",
             session_id: session_id,
             conversation_id: session_id,
             turn_id: turn_id,
             latest_event_id: latest_event_id,
             replay_after_event_id: nil,
             reason_code: "invalid_after_event_id",
             terminal_state: Map.get(turn, :state),
             terminal_event_id: latest_event_id
           })}

        {:ok, resume_after_event_id} ->
          subscription_id = unique_id("sub")

          with {:ok, _subscription} <-
                 RuntimeAgent.subscribe_turn_events(
                   instance_id,
                   session_id,
                   turn_id,
                   subscription_id,
                   subscriber,
                   scoped_context
                 ) do
            ack =
              %{
                status: "subscribed",
                subscription_id: subscription_id,
                session_id: session_id,
                conversation_id: session_id,
                turn_id: turn_id,
                resume_after_event_id: resume_after_event_id,
                replay_after_event_id: resume_after_event_id,
                latest_event_id: latest_event_id,
                terminal_state: Map.get(turn, :state),
                terminal_event_id: latest_event_id
              }
              |> compact_nil_values()

            deliver_live_turn_events(
              instance_id,
              session_id,
              turn_id,
              subscription_id,
              subscriber,
              filter_events_after(events, resume_after_event_id),
              turn
            )

            {:ok, project_live_ack(ack)}
          end
      end
    else
      nil -> {:error, :missing_turn_identifier}
      false -> {:error, :invalid_subscriber}
      {:error, _reason} = error -> error
    end
  end

  def unsubscribe_turn_events(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with session_id when is_binary(session_id) <- session_id_from(payload, context),
         turn_id when is_binary(turn_id) <- get_string(payload, :turn_id),
         subscription_id when is_binary(subscription_id) <- get_string(payload, :subscription_id),
         {:ok, detached} <-
           RuntimeAgent.unsubscribe_turn_events(
             instance_id,
             session_id,
             turn_id,
             subscription_id,
             service_context(context, session_id)
           ) do
      status = if is_map(detached), do: "detached", else: "already_detached"

      {:ok,
       project_live_ack(%{
         status: status,
         subscription_id: subscription_id,
         session_id: session_id,
         conversation_id: session_id,
         turn_id: turn_id,
         detached_at: timestamp(),
         reason_code: if(is_map(detached), do: nil, else: "subscription_not_found")
       })}
    else
      nil -> {:error, :missing_turn_identifier}
      {:error, _reason} = error -> error
    end
  end

  defp assist_payload(request) do
    compact_nil_values(%{
      operation: Map.get(request, :operation),
      objective: Map.get(request, :objective),
      requested_capabilities: Map.get(request, :requested_capabilities, []),
      operation_profile: Map.get(request, :operation_profile),
      prompt_ref: Map.get(request, :prompt_ref),
      prompt_variables: Map.get(request, :prompt_variables),
      tool_intent: Map.get(request, :tool_intent),
      artifacts: []
    })
  end

  defp build_turn(instance_id, session_id, request, context) do
    timestamp = timestamp()
    turn_id = get_string(request, :turn_id) || unique_id("turn")
    history_index = State.next_turn_index(instance_id, session_id)
    operation = get_string(request, :operation)
    objective = get_string(request, :objective)
    requested_capabilities = get_list(request, :requested_capabilities)
    artifacts = normalize_artifacts(get_list(request, :artifacts))
    assistant_message = assistant_message(operation, objective, request)

    compact_nil_values(%{
      instance_id: instance_id,
      session_id: session_id,
      turn_id: turn_id,
      history_identity: "session",
      history_index: history_index,
      state: "completed",
      phase: "completed",
      operation: operation,
      objective: objective,
      origin: get_map(request, :origin),
      collaboration: get_map(request, :collaboration),
      project_id: get_string(context, :project_id),
      workspace_id: get_string(context, :workspace_id),
      request_id: get_string(context, :request_id),
      correlation_id: get_string(context, :correlation_id),
      started_at: timestamp,
      terminal_at: timestamp,
      metadata:
        compact_nil_values(%{
          operation: operation,
          objective: objective,
          origin: get_map(request, :origin),
          collaboration: get_map(request, :collaboration),
          prompt_ref: get_map(request, :prompt_ref),
          prompt_variables: get_map(request, :prompt_variables),
          operation_profile: get_map(request, :operation_profile),
          tool_intent: get_map(request, :tool_intent)
        }),
      outputs:
        compact_nil_values(%{
          assistant_message: assistant_message,
          preview: truncate_preview(assistant_message),
          requested_capabilities: requested_capabilities,
          tool_results: [],
          artifacts: artifacts,
          compatibility_payload: assist_payload(request)
        })
    })
  end

  defp build_turn_events(turn) do
    started_at = Map.fetch!(turn, :started_at)
    terminal_at = Map.fetch!(turn, :terminal_at)

    [
      build_turn_event(turn, "runtime.turn.admitted.v1", started_at, "admitted", "progress", %{
        "state" => "queued",
        "content" => "Accepted coding turn #{turn.turn_id}."
      }),
      build_turn_event(turn, "runtime.turn.progress.v1", started_at, "progress", "progress", %{
        "state" => "running",
        "content" => streaming_message(turn)
      }),
      build_turn_event(turn, "runtime.turn.completed.v1", terminal_at, "completed", "final_output", %{
        "state" => "completed",
        "content" => turn.outputs.assistant_message
      })
    ]
  end

  defp build_turn_review(turn) do
    %{
      turn_id: turn.turn_id,
      session_id: turn.session_id,
      conversation_id: turn.session_id,
      operation: turn.operation,
      objective: turn.objective,
      state: turn.state,
      summary_status: project_summary_status(turn),
      assistant_output: project_assistant_output(turn),
      artifact_count: length(project_turn_artifacts(turn)),
      review_context:
        compact_nil_values(%{
          project_id: Map.get(turn, :project_id),
          workspace_id: Map.get(turn, :workspace_id),
          request_id: Map.get(turn, :request_id),
          correlation_id: Map.get(turn, :correlation_id)
        })
    }
  end

  defp build_turn_event(turn, event_name, event_timestamp, family, bridge_kind, payload) do
    compact_nil_values(%{
      event_id: "#{turn.turn_id}:#{event_name}:#{event_timestamp}",
      session_id: turn.session_id,
      conversation_id: turn.session_id,
      turn_id: turn.turn_id,
      timestamp: event_timestamp,
      outcome: "ok",
      family: family,
      bridge_kind: bridge_kind,
      event_name: event_name,
      request_id: Map.get(turn, :request_id),
      correlation_id: Map.get(turn, :correlation_id),
      content: Map.get(payload, "content"),
      summary_status:
        compact_nil_values(%{
          state: Map.get(payload, "state"),
          artifact_count: length(project_turn_artifacts(turn)),
          tool_result_count: 0
        })
    })
  end

  defp ensure_cancelled_event_and_review(instance_id, session_id, turn, _context) do
    events = State.list_turn_events(instance_id, session_id, turn.turn_id)

    has_cancel_event? =
      Enum.any?(events, fn event ->
        Map.get(event, :event_name) == "runtime.turn.cancelled.v1" or
          Map.get(event, "event_name") == "runtime.turn.cancelled.v1"
      end)

    if has_cancel_event? do
      turn
    else
      cancelled_event =
        build_turn_event(
          turn,
          "runtime.turn.cancelled.v1",
          Map.get(turn, :terminal_at) || timestamp(),
          "cancelled",
          "failure",
          %{"state" => "cancelled", "content" => "Cancelled coding turn #{turn.turn_id}."}
        )

      State.append_turn_event(instance_id, session_id, turn.turn_id, cancelled_event)
      review = build_turn_review(turn)
      State.put_turn_review(instance_id, session_id, turn.turn_id, review)
      turn
    end
  end

  defp deliver_live_turn_events(instance_id, session_id, turn_id, subscription_id, subscriber, events, turn) do
    Task.start(fn ->
      Enum.each(events, fn event ->
        if subscription_active?(instance_id, session_id, turn_id, subscription_id) do
          send(
            subscriber,
            {:jido_os_turn_delivery,
             %{
               kind: "turn_event",
               subscription_id: subscription_id,
               session_id: session_id,
               conversation_id: session_id,
               turn_id: turn_id,
               event: event
             }}
          )
        end
      end)

      if subscription_active?(instance_id, session_id, turn_id, subscription_id) do
        latest_event_id = latest_event_id(State.list_turn_events(instance_id, session_id, turn_id))

        send(
          subscriber,
          {:jido_os_turn_delivery,
           %{
             kind: "terminal_handoff",
             subscription_id: subscription_id,
             session_id: session_id,
             conversation_id: session_id,
             turn_id: turn_id,
             terminal_state: Map.get(turn, :state),
             terminal_event_id: latest_event_id,
             latest_event_id: latest_event_id
           }}
        )
      end

      _ = State.delete_turn_subscription(instance_id, session_id, turn_id, subscription_id)
    end)
  end

  defp subscription_active?(instance_id, session_id, turn_id, subscription_id) do
    match?(%{}, State.get_turn_subscription(instance_id, session_id, turn_id, subscription_id))
  end

  defp project_turn(turn) when is_map(turn) do
    artifacts = project_turn_artifacts(turn)

    compact_nil_values(%{
      turn_id: Map.get(turn, :turn_id),
      session_id: Map.get(turn, :session_id),
      conversation_id: Map.get(turn, :session_id),
      history_identity: Map.get(turn, :history_identity) || "session",
      history_index: Map.get(turn, :history_index),
      state: Map.get(turn, :state),
      phase: Map.get(turn, :phase),
      operation: Map.get(turn, :operation),
      objective: Map.get(turn, :objective),
      origin: Map.get(turn, :origin),
      collaboration: Map.get(turn, :collaboration),
      effective_scope:
        compact_nil_values(%{
          project_id: Map.get(turn, :project_id),
          workspace_id: Map.get(turn, :workspace_id)
        }),
      terminal_at: Map.get(turn, :terminal_at),
      assistant_output: project_assistant_output(turn),
      tool_activity:
        compact_nil_values(%{
          tool_result_count:
            turn
            |> Map.get(:outputs, %{})
            |> Map.get(:tool_results, [])
            |> length(),
          requested_capabilities:
            turn
            |> Map.get(:outputs, %{})
            |> Map.get(:requested_capabilities, [])
        }),
      artifact_count: length(artifacts),
      context_summary:
        compact_nil_values(%{
          conversation_id: Map.get(turn, :session_id),
          turn_id: Map.get(turn, :turn_id),
          state: Map.get(turn, :state),
          assistant_preview:
            turn
            |> Map.get(:outputs, %{})
            |> Map.get(:preview)
        }),
      summary_status: project_summary_status(turn)
    })
  end

  defp project_turn_artifacts(turn) when is_map(turn) do
    turn
    |> Map.get(:outputs, %{})
    |> Map.get(:artifacts, [])
    |> Enum.with_index(1)
    |> Enum.map(fn {artifact, index} ->
      compact_nil_values(%{
        artifact_id: get_string(artifact, :artifact_id) || "#{Map.get(turn, :turn_id)}:artifact:#{index}",
        session_id: Map.get(turn, :session_id),
        conversation_id: Map.get(turn, :session_id),
        turn_id: Map.get(turn, :turn_id),
        kind: get_string(artifact, :kind) || "artifact",
        title: get_string(artifact, :title) || "Artifact #{index}",
        format: get_string(get_map(artifact, :content), :format),
        summary: artifact_summary(artifact)
      })
    end)
  end

  defp project_assistant_output(turn) do
    outputs = Map.get(turn, :outputs, %{})

    compact_nil_values(%{
      message: Map.get(outputs, :assistant_message),
      preview: Map.get(outputs, :preview)
    })
  end

  defp project_summary_status(turn) do
    compact_nil_values(%{
      state: Map.get(turn, :state),
      phase: Map.get(turn, :phase),
      artifact_count: length(project_turn_artifacts(turn)),
      tool_result_count:
        turn
        |> Map.get(:outputs, %{})
        |> Map.get(:tool_results, [])
        |> length(),
      output_kind: "assistant_message"
    })
  end

  defp filter_events_after(events, nil), do: events

  defp filter_events_after(events, after_event_id) when is_list(events) do
    case Enum.split_while(events, fn event ->
           event_id = Map.get(event, :event_id) || Map.get(event, "event_id")
           event_id != after_event_id
         end) do
      {_leading, []} -> []
      {_leading, [_matched | remaining]} -> remaining
    end
  end

  defp validate_resume_cursor(_events, nil), do: {:ok, nil}

  defp validate_resume_cursor(events, after_event_id) when is_binary(after_event_id) do
    if Enum.any?(events, fn event ->
         (Map.get(event, :event_id) || Map.get(event, "event_id")) == after_event_id
       end) do
      {:ok, after_event_id}
    else
      {:error, :invalid_after_event_id}
    end
  end

  defp validate_resume_cursor(_events, _after_event_id), do: {:error, :invalid_after_event_id}

  defp project_live_ack(ack) when is_map(ack) do
    compact_nil_values(%{
      status: Map.get(ack, :status) || Map.get(ack, "status"),
      subscription_id: Map.get(ack, :subscription_id) || Map.get(ack, "subscription_id"),
      session_id: Map.get(ack, :session_id) || Map.get(ack, "session_id"),
      conversation_id: Map.get(ack, :conversation_id) || Map.get(ack, "conversation_id"),
      turn_id: Map.get(ack, :turn_id) || Map.get(ack, "turn_id"),
      resume_after_event_id: Map.get(ack, :resume_after_event_id) || Map.get(ack, "resume_after_event_id"),
      replay_after_event_id: Map.get(ack, :replay_after_event_id) || Map.get(ack, "replay_after_event_id"),
      latest_event_id: Map.get(ack, :latest_event_id) || Map.get(ack, "latest_event_id"),
      terminal_state: Map.get(ack, :terminal_state) || Map.get(ack, "terminal_state"),
      terminal_event_id: Map.get(ack, :terminal_event_id) || Map.get(ack, "terminal_event_id"),
      detached_at: Map.get(ack, :detached_at) || Map.get(ack, "detached_at"),
      reason_code: Map.get(ack, :reason_code) || Map.get(ack, "reason_code")
    })
  end

  defp latest_event_id([]), do: nil

  defp latest_event_id(events) when is_list(events) do
    events
    |> List.last()
    |> case do
      nil -> nil
      event -> Map.get(event, :event_id) || Map.get(event, "event_id")
    end
  end

  defp normalize_artifacts(artifacts) when is_list(artifacts) do
    Enum.filter(artifacts, &is_map/1)
  end

  defp assistant_message(operation, objective, request) do
    explicit_message =
      request
      |> get_map(:context)
      |> get_string(:assistant_message)

    explicit_message || generated_assistant_message(operation, objective)
  end

  defp generated_assistant_message(nil, nil), do: "Captured coding turn."

  defp generated_assistant_message(operation, nil) do
    "#{humanize_operation(operation)} ready."
  end

  defp generated_assistant_message(nil, objective) do
    "Captured coding turn: #{objective}"
  end

  defp generated_assistant_message(operation, objective) do
    "#{humanize_operation(operation)} ready: #{objective}"
  end

  defp streaming_message(turn) do
    case Map.get(turn, :objective) do
      nil -> "Preparing coding turn..."
      objective -> "Preparing coding turn for #{objective}"
    end
  end

  defp artifact_summary(artifact) do
    get_string(artifact, :summary) || get_string(artifact, :title)
  end

  defp humanize_operation(nil), do: "Coding assistance"

  defp humanize_operation(operation) do
    operation
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp service_context(context, session_id) do
    context
    |> Map.put(:session_id, session_id)
    |> compact_nil_values()
  end

  defp session_id_from(request, context) do
    get_string(request, :session_id) || get_string(context, :session_id)
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp truncate_preview(nil), do: nil

  defp truncate_preview(value) when is_binary(value) do
    if String.length(value) > 140 do
      String.slice(value, 0, 137) <> "..."
    else
      value
    end
  end

  defp compact_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        compacted = compact_nil_values(value)
        if compacted == %{}, do: acc, else: Map.put(acc, key, compacted)

      {key, value}, acc when is_list(value) ->
        Map.put(acc, key, value)

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp get_string(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_binary(value) and value != "", do: value, else: nil
  end

  defp get_string(_map, _key), do: nil

  defp get_map(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: %{}
  end

  defp get_map(_map, _key), do: %{}

  defp get_list(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_list(value), do: value, else: []
  end

  defp get_list(_map, _key), do: []

  defp get_pid(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_pid(value), do: value, else: nil
  end

  defp get_pid(_map, _key), do: nil
end
