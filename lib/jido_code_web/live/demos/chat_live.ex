defmodule JidoCodeWeb.Demos.ChatLive do
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  @moduledoc """
  Event-driven conversation orchestration demo.

  This LiveView subscribes to the canonical conversation event stream instead of
  polling snapshots. Snapshots are only used for initial bootstrap, reconnect
  recovery, and continuity-gap fallback.
  """

  use JidoCodeWeb, :live_view

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.{Driver, PubSub}

  @progress_delay_ms 60
  @stdout_delay_ms 100
  @clarification_delay_ms 140
  @delta_delay_ms 180
  @completion_delay_ms 240
  @resume_delta_delay_ms 80
  @resume_completion_delay_ms 160
  @cancellation_settle_delay_ms 80
  @degraded_mode_message "Live conversation stream unavailable. Showing the latest conversation snapshot only."

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Conversation Orchestration Demo")
     |> assign(:preferred_managed_repo_id, normalize_optional_string(session["managed_repo_id"]))
     |> assign(:conversation_id, nil)
     |> assign(:snapshot, nil)
     |> assign(:events, [])
     |> assign(:last_event_sequence, 0)
     |> assign(:input, "")
     |> assign(:error, nil)
     |> assign(:stream_mode, :booting)
     |> assign(:stream_degraded_reason, nil)
     |> assign(:stream_discontinuity_count, 0)
     |> assign(:stream_notices, [])
     |> assign(:degraded_mode_message, @degraded_mode_message)
     |> assign(:client_ready?, false)}
  end

  @impl true
  def handle_event("client_ready", params, socket) do
    stored_conversation_id = normalize_optional_string(params["conversation_id"])
    after_sequence = normalize_sequence(params["after_sequence"])

    with {:ok, bootstrap} <- load_or_start_conversation(socket, stored_conversation_id) do
      socket =
        socket
        |> maybe_unsubscribe_conversation()
        |> assign(:client_ready?, true)
        |> assign(:conversation_id, bootstrap.conversation_id)
        |> assign(:error, nil)
        |> subscribe_to_conversation_stream(bootstrap.conversation_id)
        |> assign_from_snapshot(bootstrap.snapshot)
        |> maybe_note_fresh_start(stored_conversation_id, bootstrap.resumed?)
        |> maybe_restore_continuity(bootstrap.conversation_id, bootstrap.resumed?, after_sequence)

      {:noreply, socket}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :error, bootstrap_error_message(reason))}
    end
  end

  def handle_event("update_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("send", _params, socket) do
    input = String.trim(socket.assigns.input)
    submit_as_resume? = awaiting_input?(socket.assigns.snapshot)

    cond do
      input == "" ->
        {:noreply, socket}

      not is_binary(socket.assigns.conversation_id) ->
        {:noreply, assign(socket, :error, "Conversation stream is still booting.")}

      socket.assigns.snapshot && socket.assigns.snapshot.status == :paused ->
        {:noreply, assign(socket, :error, "Resume the conversation before submitting new work.")}

      true ->
        case Driver.handle_command(
               socket.assigns.conversation_id,
               input_command(socket, input),
               actor: current_actor(socket)
             ) do
          {:ok, snapshot} ->
            socket =
              socket
              |> assign(:input, "")
              |> assign(:error, nil)
              |> assign_from_snapshot(snapshot)
              |> maybe_schedule_runtime_flow(input, submit_as_resume?)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, :error, "Failed to submit work: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("pause", _params, socket) do
    dispatch_control_command(socket, "session.pause", %{
      reason: "Operator paused the conversation."
    })
  end

  def handle_event("resume", _params, socket) do
    dispatch_control_command(socket, "session.resume", %{})
  end

  def handle_event("stop_turn", _params, socket) do
    if is_binary(active_child_work_id(socket.assigns.snapshot)) do
      case Driver.handle_command(
             socket.assigns.conversation_id,
             %{type: "turn.stop", payload: %{reason: "Operator requested a stop."}},
             actor: current_actor(socket)
           ) do
        {:ok, snapshot} ->
          socket =
            socket
            |> assign(:error, nil)
            |> assign_from_snapshot(snapshot)
            |> maybe_schedule_cancellation()

          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Failed to stop the active turn: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("restart_conversation", _params, socket) do
    socket =
      socket
      |> maybe_unsubscribe_conversation()
      |> maybe_stop_conversation()

    case load_or_start_conversation(assign(socket, :conversation_id, nil), nil) do
      {:ok, bootstrap} ->
        socket =
          socket
          |> assign(:conversation_id, bootstrap.conversation_id)
          |> subscribe_to_conversation_stream(bootstrap.conversation_id)
          |> assign_from_snapshot(bootstrap.snapshot)
          |> assign(:error, nil)
          |> assign(:stream_notices, [
            %{id: gen_id(), kind: :info, text: "Started a fresh demo conversation."}
          ])

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :error, bootstrap_error_message(reason))}
    end
  end

  @impl true
  def handle_info({:conversation_event, event}, socket) do
    event_sequence = map_get(event, :sequence)

    cond do
      not is_integer(event_sequence) ->
        {:noreply, socket}

      event_sequence <= socket.assigns.last_event_sequence ->
        {:noreply, socket}

      event_sequence == socket.assigns.last_event_sequence + 1 ->
        {:noreply,
         socket
         |> update(:events, &(&1 ++ [event]))
         |> assign(:last_event_sequence, event_sequence)}

      true ->
        {:noreply, recover_from_gap(socket, event_sequence)}
    end
  end

  def handle_info({:simulate_tool_result, conversation_id, child_work_id, payload}, socket) do
    if socket.assigns.conversation_id == conversation_id do
      case Driver.snapshot(conversation_id) do
        {:ok, snapshot} ->
          if child_work_open?(snapshot, child_work_id) or
               child_work_cancelling?(snapshot, child_work_id) do
            case Driver.handle_command(
                   conversation_id,
                   %{
                     type: "tool_result.submit",
                     payload: Map.put(payload, :child_work_id, child_work_id)
                   },
                   actor: current_actor(socket)
                 ) do
              {:ok, updated_snapshot} ->
                {:noreply, assign_from_snapshot(socket, updated_snapshot)}

              {:error, _reason} ->
                {:noreply, socket}
            end
          else
            {:noreply, socket}
          end

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp dispatch_control_command(socket, command_type, payload) do
    case Driver.handle_command(
           socket.assigns.conversation_id,
           %{type: command_type, payload: payload},
           actor: current_actor(socket)
         ) do
      {:ok, snapshot} ->
        {:noreply, socket |> assign(:error, nil) |> assign_from_snapshot(snapshot)}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, "Failed to update the conversation: #{inspect(reason)}")}
    end
  end

  defp load_or_start_conversation(socket, stored_conversation_id) do
    case stored_conversation_id do
      conversation_id when is_binary(conversation_id) ->
        case Driver.snapshot(conversation_id) do
          {:ok, snapshot} ->
            {:ok, %{conversation_id: conversation_id, snapshot: snapshot, resumed?: true}}

          {:error, _reason} ->
            start_demo_conversation(socket)
        end

      _other ->
        start_demo_conversation(socket)
    end
  end

  defp start_demo_conversation(socket) do
    with {:ok, managed_repo_id} <- demo_managed_repo_id(socket),
         {:ok, %{conversation: conversation, snapshot: snapshot}} <-
           Driver.start_conversation(%{
             managed_repo_id: managed_repo_id,
             source: "conversation_demo",
             objective: "Demonstrate event-driven conversation orchestration.",
             actor: current_actor(socket),
             source_metadata: %{"surface" => "chat_live_demo"}
           }) do
      {:ok, %{conversation_id: conversation.id, snapshot: snapshot, resumed?: false}}
    end
  end

  defp demo_managed_repo_id(socket) do
    actor = current_actor(socket)

    case socket.assigns.preferred_managed_repo_id do
      managed_repo_id when is_binary(managed_repo_id) ->
        {:ok, managed_repo_id}

      _other ->
        case ManagedRepo.read(query: [sort: [display_name: :asc], limit: 1], actor: actor) do
          {:ok, [%ManagedRepo{id: managed_repo_id} | _rest]} -> {:ok, managed_repo_id}
          {:ok, []} -> {:error, :no_managed_repo_available}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp subscribe_to_conversation_stream(socket, conversation_id) do
    case PubSub.subscribe_conversation(conversation_id) do
      :ok ->
        socket
        |> assign(:stream_mode, :live)
        |> assign(:stream_degraded_reason, nil)

      {:error, reason} ->
        mark_stream_degraded(socket, reason)

      other ->
        mark_stream_degraded(socket, other)
    end
  end

  defp mark_stream_degraded(socket, reason) do
    socket
    |> assign(:stream_mode, :degraded)
    |> assign(:stream_degraded_reason, inspect(reason))
    |> append_stream_notice(@degraded_mode_message, :warning)
  end

  defp maybe_restore_continuity(socket, _conversation_id, _resumed?, after_sequence)
       when after_sequence <= 0,
       do: socket

  defp maybe_restore_continuity(socket, _conversation_id, false, _after_sequence) do
    append_stream_notice(
      socket,
      "The previous live conversation could not be resumed, so the demo started a fresh stream.",
      :warning
    )
  end

  defp maybe_restore_continuity(socket, conversation_id, true, after_sequence) do
    case Driver.events_since(conversation_id, after_sequence, actor: current_actor(socket)) do
      {:ok, []} ->
        if socket.assigns.last_event_sequence > after_sequence do
          missing_from = after_sequence + 1
          missing_to = socket.assigns.last_event_sequence

          socket
          |> assign(:stream_discontinuity_count, socket.assigns.stream_discontinuity_count + 1)
          |> append_stream_notice(
            continuity_gap_message(missing_from, missing_to, socket.assigns.last_event_sequence),
            :warning
          )
        else
          append_stream_notice(socket, "Conversation stream is current after reconnect.", :info)
        end

      {:ok, replayed_events} ->
        first_sequence = map_get(hd(replayed_events), :sequence)

        if first_sequence == after_sequence + 1 do
          append_stream_notice(
            socket,
            "Conversation stream resumed from event sequence #{first_sequence}.",
            :info
          )
        else
          socket
          |> assign(:stream_discontinuity_count, socket.assigns.stream_discontinuity_count + 1)
          |> append_stream_notice(
            continuity_gap_message(after_sequence + 1, first_sequence - 1, first_sequence),
            :warning
          )
        end

      {:error, reason} ->
        mark_stream_degraded(socket, reason)
    end
  end

  defp maybe_note_fresh_start(socket, nil, _resumed?), do: socket
  defp maybe_note_fresh_start(socket, _stored_conversation_id, true), do: socket

  defp maybe_note_fresh_start(socket, _stored_conversation_id, false) do
    append_stream_notice(
      socket,
      "Recovered with a fresh conversation snapshot because the prior live stream was unavailable.",
      :warning
    )
  end

  defp recover_from_gap(socket, resumed_at) do
    case Driver.snapshot(socket.assigns.conversation_id) do
      {:ok, snapshot} ->
        missing_from = socket.assigns.last_event_sequence + 1
        missing_to = resumed_at - 1

        socket
        |> assign_from_snapshot(snapshot)
        |> assign(:stream_discontinuity_count, socket.assigns.stream_discontinuity_count + 1)
        |> append_stream_notice(
          continuity_gap_message(missing_from, missing_to, resumed_at),
          :warning
        )

      {:error, reason} ->
        mark_stream_degraded(socket, reason)
    end
  end

  defp assign_from_snapshot(socket, snapshot) do
    socket
    |> assign(:snapshot, snapshot)
    |> assign(:events, snapshot.events || [])
    |> assign(:last_event_sequence, snapshot.last_event_sequence || 0)
  end

  defp input_command(socket, input) do
    case socket.assigns.snapshot do
      %{active_turn_id: turn_id} = snapshot
      when is_binary(turn_id) and awaiting_input?(snapshot) ->
        %{type: "turn.resume", payload: %{turn_id: turn_id, response: input}}

      _other ->
        %{type: "turn.submit", payload: %{instruction: input}}
    end
  end

  defp maybe_schedule_runtime_flow(socket, input, true) do
    case active_child_work_id(socket.assigns.snapshot) do
      child_work_id when is_binary(child_work_id) ->
        Process.send_after(
          self(),
          {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
           %{
             kind: "delta",
             text: "Continuing with the clarified instruction: #{input}"
           }},
          @resume_delta_delay_ms
        )

        Process.send_after(
          self(),
          {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
           %{
             kind: "completed",
             result: %{summary: "Completed the clarified demo work: #{input}"}
           }},
          @resume_completion_delay_ms
        )

        socket

      _other ->
        socket
    end
  end

  defp maybe_schedule_runtime_flow(socket, instruction, false) do
    case active_child_work_id(socket.assigns.snapshot) do
      child_work_id when is_binary(child_work_id) ->
        Process.send_after(
          self(),
          {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
           %{
             kind: "progress",
             summary: "Inspecting the requested conversation scope.",
             percent: 35
           }},
          @progress_delay_ms
        )

        Process.send_after(
          self(),
          {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
           %{kind: "stdout", text: simulated_stdout(instruction)}},
          @stdout_delay_ms
        )

        if requires_clarification?(instruction) do
          Process.send_after(
            self(),
            {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
             %{kind: "needs_input", prompt: "Which file should I inspect first?"}},
            @clarification_delay_ms
          )
        else
          Process.send_after(
            self(),
            {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
             %{kind: "delta", text: "Applying the requested scope: #{instruction}"}},
            @delta_delay_ms
          )

          Process.send_after(
            self(),
            {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
             %{
               kind: "completed",
               result: %{summary: "Completed the requested demo work: #{instruction}"}
             }},
            @completion_delay_ms
          )
        end

        socket

      _other ->
        socket
    end
  end

  defp maybe_schedule_cancellation(socket) do
    case active_child_work_id(socket.assigns.snapshot) do
      child_work_id when is_binary(child_work_id) ->
        Process.send_after(
          self(),
          {:simulate_tool_result, socket.assigns.conversation_id, child_work_id,
           %{
             kind: "cancelled",
             result: %{reason: "The active demo work was cancelled before completion."}
           }},
          @cancellation_settle_delay_ms
        )

        socket

      _other ->
        socket
    end
  end

  defp maybe_unsubscribe_conversation(%{assigns: %{conversation_id: conversation_id}} = socket)
       when is_binary(conversation_id) do
    _ = PubSub.unsubscribe_conversation(conversation_id)
    socket
  end

  defp maybe_unsubscribe_conversation(socket), do: socket

  defp maybe_stop_conversation(%{assigns: %{conversation_id: conversation_id}} = socket)
       when is_binary(conversation_id) do
    _ = Driver.stop(conversation_id)
    socket
  end

  defp maybe_stop_conversation(socket), do: socket

  defp active_child_work_id(nil), do: nil
  defp active_child_work_id(snapshot), do: snapshot.active_child_work_id

  defp awaiting_input?(%{active_turn: %{state: :awaiting_input}}), do: true

  defp awaiting_input?(%{
         shared_context: %{"pending_clarification" => %{} = _pending_clarification}
       }),
       do: true

  defp awaiting_input?(_snapshot), do: false

  defp child_work_open?(snapshot, child_work_id) do
    snapshot.child_works
    |> Enum.find(&(&1.id == child_work_id))
    |> case do
      %{state: state} when state in [:running, :cancel_requested, :cancel_acknowledged] -> true
      _other -> false
    end
  end

  defp child_work_cancelling?(snapshot, child_work_id) do
    snapshot.child_works
    |> Enum.find(&(&1.id == child_work_id))
    |> case do
      %{state: state} when state in [:cancel_requested, :cancel_acknowledged] -> true
      _other -> false
    end
  end

  defp pending_clarification(%{
         shared_context: %{"pending_clarification" => %{} = pending_clarification}
       }),
       do: pending_clarification

  defp pending_clarification(_snapshot), do: nil

  defp clarification_prompt(snapshot) do
    snapshot
    |> pending_clarification()
    |> case do
      %{"prompt" => %{"prompt" => prompt}} -> prompt
      %{"prompt" => %{"details" => %{"prompt" => prompt}}} -> prompt
      %{"prompt" => prompt} when is_binary(prompt) -> prompt
      _other -> nil
    end
  end

  defp latest_progress(%{active_child_work: %{result: %{} = result}}) do
    case result do
      %{"latest_progress" => %{} = latest_progress} -> latest_progress
      _other -> nil
    end
  end

  defp latest_progress(_snapshot), do: nil

  defp stdout_preview(%{active_child_work: %{result: %{"stdout" => stdout}}})
       when is_list(stdout),
       do: Enum.take(stdout, -4)

  defp stdout_preview(_snapshot), do: []

  defp requires_clarification?(instruction) when is_binary(instruction) do
    normalized = String.downcase(instruction)

    String.contains?(normalized, "clarify") or String.contains?(normalized, "input") or
      String.contains?(normalized, "question")
  end

  defp requires_clarification?(_instruction), do: false

  defp simulated_stdout(instruction) do
    "rg --context 2 #{String.slice(instruction, 0, 32)}"
  end

  defp append_stream_notice(socket, text, kind) do
    update(socket, :stream_notices, fn notices ->
      (notices ++ [%{id: gen_id(), kind: kind, text: text}]) |> Enum.take(-4)
    end)
  end

  defp continuity_gap_message(missing_from, missing_to, resumed_at) do
    "Missed conversation events #{missing_from}..#{missing_to}; recovered at sequence #{resumed_at}."
  end

  defp current_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        Actor.operator_actor(%{
          "id" => user |> Map.get(:id) |> normalize_optional_string() || "conversation-demo",
          "email" => user |> Map.get(:email) |> normalize_optional_string()
        })

      _other ->
        Actor.operator_actor(%{"id" => "conversation-demo", "email" => nil})
    end
  end

  defp bootstrap_error_message(:no_managed_repo_available) do
    "Create or import a managed repository before opening the conversation demo."
  end

  defp bootstrap_error_message(reason),
    do: "Failed to bootstrap the conversation demo: #{inspect(reason)}"

  defp map_get(map, key) when is_map(map) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_sequence(value) when is_integer(value) and value >= 0, do: value

  defp normalize_sequence(value) when is_binary(value) do
    case Integer.parse(value) do
      {sequence, ""} when sequence >= 0 -> sequence
      _other -> 0
    end
  end

  defp normalize_sequence(_value), do: 0

  defp gen_id, do: System.unique_integer([:positive]) |> Integer.to_string()

  defp format_time(nil), do: "n/a"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_value), do: "n/a"

  defp event_label(event_name) when is_binary(event_name) do
    case String.split(event_name, ".", parts: 2) do
      [prefix, _rest] -> prefix
      _other -> "event"
    end
  end

  defp event_badge_class("conversation." <> _rest), do: "bg-sky-100 text-sky-800"
  defp event_badge_class("turn." <> _rest), do: "bg-amber-100 text-amber-800"
  defp event_badge_class("tool." <> _rest), do: "bg-emerald-100 text-emerald-800"
  defp event_badge_class(_other), do: "bg-zinc-200 text-zinc-700"

  defp event_title(event) do
    case map_get(event, :name) do
      "conversation.message_added" ->
        command_payload = map_get(event_payload(event), :payload) || %{}

        instruction =
          map_get(command_payload, :instruction) || map_get(command_payload, :response) ||
            map_get(command_payload, :reason)

        command_type = map_get(event_payload(event), :command_type) || "conversation.update"
        instruction || "Recorded #{command_type}."

      "conversation.status_changed" ->
        "Conversation status is now #{map_get(event_payload(event), :status) || "active"}."

      "turn.intent_announced" ->
        map_get(event_payload(event), :text) || "Intent announced."

      "turn.queued" ->
        "Queued a new work turn."

      "turn.started" ->
        "Started the active turn."

      "turn.awaiting_input" ->
        map_get(event_payload(event), :prompt) || "Waiting for clarification before continuing."

      "turn.delta" ->
        map_get(event_payload(event), :text) || "Streaming turn update received."

      "turn.cancelling" ->
        "Stopping the active turn."

      "turn.superseding" ->
        "Superseding the active turn."

      "turn.completed" ->
        "The active turn completed."

      "turn.cancelled" ->
        "The active turn was cancelled."

      "turn.superseded" ->
        "The previous turn was superseded."

      "tool.started" ->
        "Started a child tool execution."

      "tool.progress" ->
        map_get(event_payload(event), :summary) ||
          "Progress update: #{map_get(event_payload(event), :percent) || "?"}%."

      "tool.stdout" ->
        map_get(event_payload(event), :text) || map_get(event_payload(event), :chunk) ||
          "Tool output received."

      "tool.needs_input" ->
        map_get(event_payload(event), :prompt) || "The active tool requested more input."

      "tool.cancel_requested" ->
        "Requested cancellation for the active tool."

      "tool.cancel_acknowledged" ->
        "The active tool acknowledged cancellation."

      "tool.completed" ->
        result_summary(event) || "The active tool completed."

      "tool.cancelled" ->
        result_summary(event) || "The active tool cancelled cleanly."

      "tool.cancel_failed" ->
        "The active tool reported a cancellation failure."

      "tool.failed" ->
        "The active tool failed."

      other when is_binary(other) ->
        other

      _other ->
        "Conversation event"
    end
  end

  defp event_excerpt(event) do
    actor_id = map_get(map_get(event, :actor) || %{}, :id)
    tool_call_id = map_get(event, :tool_call_id)
    payload = event_payload(event)
    kind = map_get(payload, :kind)

    %{}
    |> maybe_put("actor", actor_id)
    |> maybe_put("tool_call_id", tool_call_id)
    |> maybe_put("kind", kind)
    |> maybe_put("state", map_get(payload, :state))
    |> maybe_put("summary", map_get(payload, :summary))
    |> maybe_put("prompt", map_get(payload, :prompt))
    |> maybe_put("text", map_get(payload, :text) || map_get(payload, :chunk))
    |> case do
      empty when empty == %{} -> nil
      details -> inspect(details, pretty: false)
    end
  end

  defp event_payload(event), do: map_get(event, :payload) || %{}

  defp result_summary(event) do
    payload = event_payload(event)
    result = map_get(payload, :result) || %{}

    map_get(result, :summary) || map_get(result, :reason)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl true
  def render(assigns) do
    ready? = is_binary(assigns.conversation_id)
    paused? = assigns.snapshot && assigns.snapshot.status == :paused
    active_turn? = assigns.snapshot && is_binary(assigns.snapshot.active_turn_id)
    pending_clarification = pending_clarification(assigns.snapshot)
    clarification_prompt = clarification_prompt(assigns.snapshot)
    resume_mode? = awaiting_input?(assigns.snapshot)
    latest_progress = latest_progress(assigns.snapshot)
    stdout_preview = stdout_preview(assigns.snapshot)

    assigns =
      assign(assigns,
        ready?: ready?,
        paused?: paused?,
        active_turn?: active_turn?,
        pending_clarification: pending_clarification,
        clarification_prompt: clarification_prompt,
        resume_mode?: resume_mode?,
        latest_progress: latest_progress,
        stdout_preview: stdout_preview
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div
        id="conversation-demo"
        phx-hook=".ConversationStream"
        data-conversation-id={@conversation_id || ""}
        data-last-event-sequence={@last_event_sequence || 0}
        class="mx-auto max-w-7xl space-y-6"
      >
        <.header>
          Conversation Orchestration Demo
          <:subtitle>
            Event-driven turn and tool lifecycle updates with reconnect-aware recovery and degraded fallback.
          </:subtitle>
        </.header>

        <%= if @error do %>
          <div class="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
            {@error}
          </div>
        <% end %>

        <%= if @stream_mode == :degraded do %>
          <div id="conversation-stream-degraded-alert" class="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
            <p class="font-semibold">Stream degraded mode</p>
            <p class="mt-1">{@degraded_mode_message}</p>
          </div>
        <% end %>

        <%= for notice <- @stream_notices do %>
          <div class={[
            "rounded-2xl px-4 py-3 text-sm border",
            notice.kind == :warning && "border-amber-200 bg-amber-50 text-amber-900",
            notice.kind == :info && "border-sky-200 bg-sky-50 text-sky-900"
          ]}>
            {notice.text}
          </div>
        <% end %>

        <div class="grid gap-6 lg:grid-cols-[2fr,1fr]">
          <section class="rounded-3xl border border-zinc-200 bg-white shadow-sm">
            <div class="border-b border-zinc-200 px-6 py-4">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 class="text-lg font-semibold text-zinc-900">Event Transcript</h2>
                  <p class="text-sm text-zinc-500">
                    {if @ready?, do: "Conversation #{String.slice(@conversation_id, 0, 8)}", else: "Waiting for the browser to attach the conversation stream"}
                  </p>
                </div>
                <div class="flex items-center gap-2 text-xs">
                  <span class={[
                    "rounded-full px-3 py-1 font-medium",
                    @stream_mode == :live && "bg-emerald-100 text-emerald-800",
                    @stream_mode == :degraded && "bg-amber-100 text-amber-800",
                    @stream_mode == :booting && "bg-zinc-100 text-zinc-700"
                  ]}>
                    {@stream_mode}
                  </span>
                  <span class="rounded-full bg-zinc-100 px-3 py-1 font-medium text-zinc-700">
                    seq {@last_event_sequence}
                  </span>
                  <span id="conversation-stream-discontinuity-count" class="rounded-full bg-zinc-100 px-3 py-1 font-medium text-zinc-700">
                    discontinuities: {@stream_discontinuity_count}
                  </span>
                </div>
              </div>
            </div>

            <div id="conversation-events" class="h-[460px] space-y-3 overflow-y-auto px-6 py-5">
              <%= if @events == [] do %>
                <div class="rounded-2xl border border-dashed border-zinc-300 bg-zinc-50 px-5 py-10 text-center text-zinc-500">
                  <p class="text-base font-medium">
                    <%= if @client_ready? do %>
                      Submit a prompt to watch the event stream update without polling.
                    <% else %>
                      Connecting the browser-side conversation stream…
                    <% end %>
                  </p>
                </div>
              <% else %>
                <%= for event <- @events do %>
                  <article id={"event-#{map_get(event, :id)}"} class="rounded-2xl border border-zinc-200 bg-zinc-50 px-4 py-3">
                    <div class="flex flex-wrap items-center justify-between gap-2">
                      <div class="flex items-center gap-2">
                        <span class="font-mono text-xs text-zinc-500">#{map_get(event, :sequence)}</span>
                        <span class={["rounded-full px-2.5 py-1 text-xs font-semibold", event_badge_class(map_get(event, :name) || "")]}>
                          {event_label(map_get(event, :name) || "")}
                        </span>
                        <span class="text-xs text-zinc-400">{map_get(event, :name)}</span>
                      </div>
                      <time class="text-xs text-zinc-400">{format_time(map_get(event, :occurred_at))}</time>
                    </div>
                    <p class="mt-3 text-sm font-medium text-zinc-900">{event_title(event)}</p>
                    <p :if={event_excerpt(event)} class="mt-1 whitespace-pre-wrap text-xs text-zinc-500">{event_excerpt(event)}</p>
                  </article>
                <% end %>
              <% end %>
            </div>

            <div class="border-t border-zinc-200 px-6 py-4">
              <div
                :if={@pending_clarification}
                id="conversation-pending-clarification"
                class="mb-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950"
              >
                <p class="font-semibold">Input Required</p>
                <p class="mt-1">{@clarification_prompt || "The active turn is waiting on clarification."}</p>
              </div>

              <form id="chat-form" phx-submit="send" class="flex flex-col gap-3 sm:flex-row">
                <input
                  id="chat-input"
                  type="text"
                  name="input"
                  value={@input}
                  phx-change="update_input"
                  placeholder={
                    if @resume_mode? do
                      @clarification_prompt || "Provide the missing clarification…"
                    else
                      "Describe the work you want this conversation to coordinate…"
                    end
                  }
                  class="flex-1 rounded-2xl border border-zinc-300 px-4 py-3 text-sm text-zinc-900 placeholder:text-zinc-400 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                  disabled={not @ready?}
                  autocomplete="off"
                />
                <button
                  type="submit"
                  class={[
                    "rounded-2xl px-5 py-3 text-sm font-semibold text-white transition-colors",
                    (@ready? and String.trim(@input) != "" and not @paused?) && "bg-sky-600 hover:bg-sky-700",
                    (!@ready? or String.trim(@input) == "" or @paused?) && "bg-zinc-300 cursor-not-allowed"
                  ]}
                  disabled={not @ready? or String.trim(@input) == "" or @paused?}
                >
                  {if @resume_mode?, do: "Resume Turn", else: "Submit Turn"}
                </button>
              </form>
            </div>
          </section>

          <aside class="space-y-4">
            <div class="rounded-3xl border border-zinc-200 bg-white p-5 shadow-sm">
              <h3 class="text-sm font-semibold text-zinc-900">Conversation State</h3>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Status</dt>
                  <dd class="font-medium text-zinc-900">{@snapshot && @snapshot.status || "booting"}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Active Turn</dt>
                  <dd class="font-medium text-zinc-900">{@snapshot && @snapshot.active_turn && @snapshot.active_turn.state || "none"}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Queued Turns</dt>
                  <dd class="font-medium text-zinc-900">{@snapshot && length(@snapshot.queued_turn_ids) || 0}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Control History</dt>
                  <dd class="font-medium text-zinc-900">{@snapshot && length(@snapshot.control_history) || 0}</dd>
                </div>
              </dl>
            </div>

            <div class="rounded-3xl border border-zinc-200 bg-white p-5 shadow-sm">
              <h3 class="text-sm font-semibold text-zinc-900">Execution</h3>
              <dl class="mt-3 space-y-2 text-sm">
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Active Tool</dt>
                  <dd class="font-medium text-zinc-900">{@snapshot && @snapshot.active_child_work && @snapshot.active_child_work.state || "idle"}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Tool Call</dt>
                  <dd class="max-w-[10rem] truncate font-mono text-xs text-zinc-700">
                    {@snapshot && @snapshot.active_child_work && @snapshot.active_child_work.tool_call_id || "n/a"}
                  </dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Events</dt>
                  <dd class="font-medium text-zinc-900">{length(@events)}</dd>
                </div>
              </dl>

              <div
                :if={@latest_progress}
                id="conversation-latest-progress"
                class="mt-4 rounded-2xl border border-sky-200 bg-sky-50 px-4 py-3 text-sm text-sky-950"
              >
                <p class="font-semibold">Latest Progress</p>
                <p class="mt-1">
                  {@latest_progress["summary"] || "Runtime progress update received."}
                </p>
                <p :if={@latest_progress["percent"]} class="mt-1 text-xs text-sky-700">
                  {@latest_progress["percent"]}% complete
                </p>
              </div>

              <div
                :if={@stdout_preview != []}
                id="conversation-stdout-preview"
                class="mt-4 rounded-2xl border border-zinc-200 bg-zinc-50 px-4 py-3 text-sm text-zinc-800"
              >
                <p class="font-semibold">Recent Tool Output</p>
                <pre class="mt-2 whitespace-pre-wrap font-mono text-xs text-zinc-700">
    <%= for line <- @stdout_preview do %>{line}
    <% end %></pre>
              </div>

              <div class="mt-4 flex flex-wrap gap-2">
                <button
                  phx-click="pause"
                  class="rounded-full border border-zinc-300 px-3 py-1.5 text-xs font-medium text-zinc-700 transition hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={not @ready? or @paused?}
                >
                  Pause
                </button>
                <button
                  phx-click="resume"
                  class="rounded-full border border-zinc-300 px-3 py-1.5 text-xs font-medium text-zinc-700 transition hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={not @ready? or not @paused?}
                >
                  Resume
                </button>
                <button
                  phx-click="stop_turn"
                  class="rounded-full border border-zinc-300 px-3 py-1.5 text-xs font-medium text-zinc-700 transition hover:border-zinc-400 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={not @active_turn?}
                >
                  Stop Turn
                </button>
                <button
                  phx-click="restart_conversation"
                  class="rounded-full bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-zinc-800"
                >
                  Restart Demo
                </button>
              </div>
            </div>
          </aside>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".ConversationStream">
          export default {
            mounted() {
              const conversationId = sessionStorage.getItem("conversation-demo:conversation-id") || ""
              const lastSequence = sessionStorage.getItem("conversation-demo:last-sequence") || "0"
              this.pushEvent("client_ready", {
                conversation_id: conversationId,
                after_sequence: lastSequence
              })
              this.persist()
            },
            updated() {
              this.persist()
            },
            persist() {
              const { conversationId, lastEventSequence } = this.el.dataset

              if (conversationId && conversationId.length > 0) {
                sessionStorage.setItem("conversation-demo:conversation-id", conversationId)
              }

              if (lastEventSequence && lastEventSequence.length > 0) {
                sessionStorage.setItem("conversation-demo:last-sequence", lastEventSequence)
              }
            }
          }
        </script>
      </div>
    </Layouts.app>
    """
  end
end