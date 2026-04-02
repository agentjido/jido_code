defmodule JidoCode.Conversations.TurnBridge do
  # covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
  # covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates
  # covers: architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
  # covers: architecture.factory_control_plane.runtime_turns_feed_governed_control_records
  # covers: architecture.execution_pipeline.public_turn_materialization_preserves_execution_authority
  # covers: architecture.execution_pipeline.public_turn_projection_is_non_blocking_for_conversation_delivery
  # covers: architecture.run_governance.turn_projection_failures_degrade_without_blocking_runtime_progress
  @moduledoc """
  Live-delivery-first bridge that translates public coding-turn delivery into
  the existing conversation subscriber event contract while keeping replay as
  the canonical recovery and terminal-verification path.
  """

  require Logger

  alias JidoCode.CodingAssistance
  alias JidoCode.Conversations.EventBridge

  @default_poll_interval_ms 25
  @default_max_idle_polls 20
  @default_live_receive_timeout_ms 100
  @terminal_families ["completed", "failed", "interrupted", "cancelled"]
  @fallback_delivery_statuses ["withheld", "denied", "unavailable", "invalid_cursor", "detached", "already_detached"]

  @type bridge_state :: %{
          after_event_id: String.t() | nil,
          live_subscription_id: String.t() | nil,
          terminal_event_seen?: boolean(),
          delivery_mode: String.t() | nil,
          live_delivery_status: String.t() | nil,
          reason_code: String.t() | nil
        }

  @spec start(map()) :: {:ok, pid()} | {:error, term()}
  def start(%{} = attrs) do
    Task.Supervisor.start_child(task_supervisor(), fn ->
      run(attrs, %{
        after_event_id: nil,
        live_subscription_id: nil,
        terminal_event_seen?: false,
        delivery_mode: nil,
        live_delivery_status: nil,
        reason_code: nil
      })
    end)
  end

  defp run(attrs, state) do
    case subscribe_turn_events(attrs, state.after_event_id) do
      {:ok, ack} ->
        next_state = apply_live_ack(state, ack)

        case Map.get(ack, :delivery_status) || Map.get(ack, "delivery_status") do
          "subscribed" ->
            receive_live_delivery(attrs, next_state)

          status when status in @fallback_delivery_statuses ->
            replay_until_terminal(attrs, fallback_state(next_state, ack), 0)

          _other ->
            replay_until_terminal(attrs, next_state, 0)
        end

      {:error, reason} ->
        emit_failure(attrs, reason)
    end
  end

  defp receive_live_delivery(attrs, state) do
    receive do
      {:jido_os_turn_delivery, envelope} ->
        case handle_live_envelope(attrs, state, envelope) do
          {:continue, next_state} -> receive_live_delivery(attrs, next_state)
          {:fallback, next_state} -> replay_until_terminal(attrs, next_state, 0)
          {:stop, _next_state} -> :ok
        end
    after
      live_receive_timeout_ms() ->
        replay_until_terminal(attrs, replay_recovery_state(state, "live_delivery_timeout"), 0)
    end
  end

  defp handle_live_envelope(attrs, state, %{} = envelope) do
    if live_subscription_match?(state, envelope) do
      case normalize_optional_string(Map.get(envelope, :kind) || Map.get(envelope, "kind")) do
        "turn_event" ->
          event = Map.get(envelope, :event) || Map.get(envelope, "event") || %{}
          translated_events = event_bridge_module().turn_events([event], attrs.ingress, attrs.context)
          :ok = dispatch_events(attrs, translated_events)

          {:continue,
           %{
             state
             | after_event_id: event_id(event) || state.after_event_id,
               terminal_event_seen?: state.terminal_event_seen? or terminal_event?(event)
           }}

        "terminal_handoff" ->
          finalize_terminal_handoff(attrs, state, envelope)

        "detached" ->
          {:fallback, replay_recovery_state(state, "live_delivery_detached")}

        _other ->
          {:continue, state}
      end
    else
      {:continue, state}
    end
  end

  defp finalize_terminal_handoff(attrs, state, terminal_handoff) do
    case list_turn_events(attrs, state.after_event_id) do
      {:ok, replay_events} ->
        translated_events = event_bridge_module().turn_events(replay_events, attrs.ingress, attrs.context)
        :ok = dispatch_events(attrs, translated_events)

        next_state =
          %{
            state
            | after_event_id: last_event_id(replay_events) || state.after_event_id,
              terminal_event_seen?: state.terminal_event_seen? or Enum.any?(replay_events, &terminal_event?/1)
          }

        case get_turn(attrs) do
          {:ok, turn} ->
            dispatch_terminal_handoff_event(attrs, next_state, turn, terminal_handoff)

            materialize_terminal_turn(
              attrs,
              turn,
              full_turn_events(attrs),
              runtime_delivery(attrs, next_state, terminal_handoff)
            )

            best_effort_unsubscribe(attrs, next_state)
            {:stop, next_state}

          {:error, _reason} ->
            {:fallback, next_state}
        end

      {:error, _reason} ->
        {:fallback, state}
    end
  end

  defp replay_until_terminal(attrs, state, idle_polls) do
    case list_turn_events(attrs, state.after_event_id) do
      {:ok, events} ->
        translated_events = event_bridge_module().turn_events(events, attrs.ingress, attrs.context)
        :ok = dispatch_events(attrs, translated_events)

        next_state =
          %{
            state
            | after_event_id: last_event_id(events) || state.after_event_id,
              terminal_event_seen?: state.terminal_event_seen? or Enum.any?(events, &terminal_event?/1)
          }

        case get_turn(attrs) do
          {:ok, turn} ->
            cond do
              terminal_turn?(turn) ->
                dispatch_terminal_handoff_event(
                  attrs,
                  next_state,
                  turn,
                  %{
                    kind: "replay_terminal_lookup",
                    terminal_state: turn_state(turn),
                    terminal_event_id: next_state.after_event_id
                  }
                )

                materialize_terminal_turn(
                  attrs,
                  turn,
                  full_turn_events(attrs),
                  runtime_delivery(
                    attrs,
                    next_state,
                    %{
                      kind: "replay_terminal_lookup",
                      terminal_state: turn_state(turn),
                      terminal_event_id: next_state.after_event_id
                    }
                  )
                )

                best_effort_unsubscribe(attrs, next_state)
                :ok

              true ->
                next_idle_polls = if events == [], do: idle_polls + 1, else: 0

                if next_idle_polls >= max_idle_polls() do
                  best_effort_unsubscribe(attrs, next_state)
                  :ok
                else
                  Process.sleep(poll_interval_ms())
                  replay_until_terminal(attrs, next_state, next_idle_polls)
                end
            end

          {:error, reason} ->
            emit_failure(attrs, reason)
        end

      {:error, reason} ->
        emit_failure(attrs, reason)
    end
  end

  defp subscribe_turn_events(attrs, after_event_id) do
    coding_assistance_module().subscribe_turn_events(
      attrs.actor_id,
      turn_request(attrs, after_event_id)
      |> Map.put(:subscriber, self())
      |> Map.put(:resume_after_event_id, after_event_id)
    )
  end

  defp best_effort_unsubscribe(attrs, %{live_subscription_id: subscription_id}) when is_binary(subscription_id) do
    _ =
      coding_assistance_module().unsubscribe_turn_events(attrs.actor_id, %{
        session_id: get_in(attrs, [:context, :session_id]),
        turn_id: get_in(attrs, [:turn, :turn_id]),
        project_id: get_in(attrs, [:context, :managed_repo_id]) || get_in(attrs, [:context, :project_id]),
        request_id: get_in(attrs, [:context, :request_id]),
        correlation_id: get_in(attrs, [:context, :correlation_id]),
        workspace_id: get_in(attrs, [:context, :workspace_id]),
        subscription_id: subscription_id
      })

    :ok
  end

  defp best_effort_unsubscribe(_attrs, _state), do: :ok

  defp list_turn_events(attrs, after_event_id) do
    coding_assistance_module().list_turn_events(attrs.actor_id, turn_request(attrs, after_event_id))
  end

  defp get_turn(attrs) do
    coding_assistance_module().get_turn(attrs.actor_id, turn_request(attrs, nil))
  end

  defp review_turn(attrs) do
    coding_assistance_module().review_turn(attrs.actor_id, turn_request(attrs, nil))
  end

  defp list_turn_artifacts(attrs) do
    coding_assistance_module().list_turn_artifacts(attrs.actor_id, turn_request(attrs, nil))
  end

  defp full_turn_events(attrs) do
    case list_turn_events(attrs, nil) do
      {:ok, events} -> events
      {:error, _reason} -> []
    end
  end

  defp turn_request(attrs, after_event_id) do
    %{
      session_id: get_in(attrs, [:context, :session_id]),
      turn_id: get_in(attrs, [:turn, :turn_id]),
      project_id: get_in(attrs, [:context, :managed_repo_id]) || get_in(attrs, [:context, :project_id]),
      request_id: get_in(attrs, [:context, :request_id]),
      correlation_id: get_in(attrs, [:context, :correlation_id]),
      workspace_id: get_in(attrs, [:context, :workspace_id]),
      after_event_id: after_event_id
    }
    |> compact_nil_values()
  end

  defp dispatch_events(_attrs, []), do: :ok

  defp dispatch_events(attrs, events) when is_list(events) do
    Enum.each(events, fn event ->
      case runtime_module().send_event(attrs.project_id, attrs.conversation_id, event) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "conversation turn bridge failed to dispatch event: #{inspect(reason)} " <>
              "project_id=#{inspect(attrs.project_id)} conversation_id=#{inspect(attrs.conversation_id)}"
          )
      end
    end)

    :ok
  end

  defp emit_failure(attrs, reason) do
    failure_event =
      event_bridge_module().failure_event(
        reason,
        attrs.context,
        %{actor_id: attrs.actor_id}
      )

    _ = dispatch_events(attrs, [failure_event])
    :ok
  end

  defp dispatch_terminal_handoff_event(attrs, state, turn, terminal_handoff) do
    if state.terminal_event_seen? do
      :ok
    else
      case event_bridge_module().terminal_handoff_event(turn, terminal_handoff, attrs.ingress, attrs.context) do
        nil -> :ok
        event -> dispatch_events(attrs, [event])
      end
    end
  end

  defp materialize_terminal_turn(attrs, turn, events, runtime_delivery) do
    work_item_id = nested_get(attrs, [:ingress, :work_item, :id])

    if is_binary(work_item_id) do
      review =
        case review_turn(attrs) do
          {:ok, review_projection} -> review_projection
          {:error, _reason} -> %{}
        end

      artifacts =
        case list_turn_artifacts(attrs) do
          {:ok, artifact_projections} -> artifact_projections
          {:error, _reason} -> []
        end

      materialization_attrs = %{
        project_id: get_in(attrs, [:context, :project_id]),
        managed_repo_id: get_in(attrs, [:context, :managed_repo_id]),
        work_item_id: work_item_id,
        actor_id: attrs.actor_id,
        actor_email: get_in(attrs, [:context, :actor_email]),
        conversation_id: attrs.conversation_id,
        turn: turn,
        review: review,
        artifacts: artifacts,
        events: events,
        runtime_delivery: runtime_delivery
      }

      case run_bridge_module().materialize_turn(materialization_attrs) do
        {:ok, _materialization} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "conversation turn bridge failed to materialize governed turn projection: #{inspect(reason)} " <>
              "project_id=#{inspect(attrs.project_id)} conversation_id=#{inspect(attrs.conversation_id)}"
          )

          :ok
      end
    else
      :ok
    end
  end

  defp apply_live_ack(state, ack) when is_map(ack) do
    %{
      state
      | live_subscription_id: map_get(ack, :subscription_id, "subscription_id"),
        after_event_id: map_get(ack, :resume_after_event_id, "resume_after_event_id") || state.after_event_id,
        live_delivery_status: map_get(ack, :delivery_status, "delivery_status"),
        reason_code: map_get(ack, :reason_code, "reason_code"),
        delivery_mode:
          delivery_mode_for_ack(
            map_get(ack, :delivery_status, "delivery_status"),
            state.delivery_mode
          )
    }
  end

  defp fallback_state(state, ack) when is_map(ack) do
    %{
      state
      | after_event_id: map_get(ack, :replay_after_event_id, "replay_after_event_id") || state.after_event_id,
        delivery_mode: "replay_fallback",
        reason_code: map_get(ack, :reason_code, "reason_code") || state.reason_code
    }
  end

  defp replay_recovery_state(state, reason_code) do
    %{
      state
      | delivery_mode:
          if(state.delivery_mode in [nil, "live_subscription"], do: "replay_recovery", else: state.delivery_mode),
        reason_code: state.reason_code || reason_code
    }
  end

  defp live_subscription_match?(%{live_subscription_id: nil}, _envelope), do: true

  defp live_subscription_match?(%{live_subscription_id: subscription_id}, envelope) do
    envelope_subscription_id = map_get(envelope, :subscription_id, "subscription_id")
    envelope_subscription_id == subscription_id
  end

  defp terminal_turn?(%{} = turn), do: turn_state(turn) in @terminal_families

  defp terminal_event?(%{} = event) do
    family = Map.get(event, :family) || Map.get(event, "family")
    family in @terminal_families
  end

  defp runtime_delivery(attrs, state, terminal_handoff) do
    terminal_handoff_kind =
      normalize_optional_string(Map.get(terminal_handoff, :kind) || Map.get(terminal_handoff, "kind"))

    terminal_state =
      normalize_optional_string(
        Map.get(terminal_handoff, :terminal_state) || Map.get(terminal_handoff, "terminal_state")
      )

    delivery_mode =
      cond do
        is_binary(state.delivery_mode) ->
          state.delivery_mode

        terminal_handoff_kind == "replay_terminal_lookup" ->
          "replay_recovery"

        true ->
          "live_subscription"
      end

    %{
      "delivery_mode" => delivery_mode,
      "live_delivery_status" => state.live_delivery_status || "subscribed",
      "reason_code" => state.reason_code,
      "terminal_handoff_kind" => terminal_handoff_kind,
      "terminal_state" => terminal_state,
      "turn_id" => nested_get(attrs, [:turn, :turn_id]),
      "session_id" => get_in(attrs, [:context, :session_id]),
      "conversation_id" => attrs.conversation_id,
      "work_item_id" => nested_get(attrs, [:ingress, :work_item, :id]),
      "request_id" => get_in(attrs, [:context, :request_id]),
      "correlation_id" => get_in(attrs, [:context, :correlation_id]),
      "summary" => runtime_delivery_summary(delivery_mode, state.reason_code, terminal_handoff_kind)
    }
    |> compact_nil_values()
  end

  defp runtime_delivery_summary("replay_fallback", "rollout_withheld", _terminal_handoff_kind) do
    "Coding turn delivery fell back to replay because live rollout was withheld."
  end

  defp runtime_delivery_summary("replay_fallback", reason_code, _terminal_handoff_kind)
       when is_binary(reason_code) do
    "Coding turn delivery fell back to replay because #{reason_code}."
  end

  defp runtime_delivery_summary("replay_recovery", _reason_code, "replay_terminal_lookup") do
    "Coding turn delivery repaired completion through replay recovery."
  end

  defp runtime_delivery_summary("replay_recovery", _reason_code, _terminal_handoff_kind) do
    "Coding turn delivery repaired from live stream loss through replay recovery."
  end

  defp runtime_delivery_summary("live_subscription", _reason_code, _terminal_handoff_kind) do
    "Coding turn delivery completed through live runtime delivery."
  end

  defp runtime_delivery_summary(_delivery_mode, _reason_code, _terminal_handoff_kind) do
    "Coding turn runtime delivery was recorded."
  end

  defp delivery_mode_for_ack("subscribed", _current_mode), do: "live_subscription"
  defp delivery_mode_for_ack(status, _current_mode) when status in @fallback_delivery_statuses, do: "replay_fallback"
  defp delivery_mode_for_ack(_status, current_mode), do: current_mode

  defp turn_state(turn) do
    Map.get(turn, :state) || Map.get(turn, "state")
  end

  defp event_id(%{} = event), do: Map.get(event, :event_id) || Map.get(event, "event_id")
  defp event_id(_event), do: nil

  defp last_event_id([]), do: nil

  defp last_event_id(events) when is_list(events) do
    events
    |> List.last()
    |> event_id()
  end

  defp task_supervisor do
    Application.get_env(
      :jido_code,
      :conversation_turn_bridge_supervisor,
      JidoCode.Conversations.TurnBridgeSupervisor
    )
  end

  defp coding_assistance_module do
    Application.get_env(:jido_code, :conversation_turn_bridge_coding_assistance_module, CodingAssistance)
  end

  defp event_bridge_module do
    Application.get_env(:jido_code, :conversation_driver_event_bridge_module, EventBridge)
  end

  defp runtime_module do
    Application.get_env(:jido_code, :code_server_runtime_module, Jido.Code.Server)
  end

  defp run_bridge_module do
    Application.get_env(:jido_code, :conversation_turn_bridge_run_bridge_module, JidoCode.Orchestration.RunBridge)
  end

  defp poll_interval_ms do
    Application.get_env(:jido_code, :conversation_turn_bridge_poll_interval_ms, @default_poll_interval_ms)
  end

  defp max_idle_polls do
    Application.get_env(:jido_code, :conversation_turn_bridge_max_idle_polls, @default_max_idle_polls)
  end

  defp live_receive_timeout_ms do
    Application.get_env(
      :jido_code,
      :conversation_turn_bridge_live_receive_timeout_ms,
      @default_live_receive_timeout_ms
    )
  end

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp nested_get(value, keys) when is_list(keys) do
    Enum.reduce_while(keys, value, fn key, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) and is_atom(key) and Map.has_key?(acc, Atom.to_string(key)) ->
          {:cont, Map.get(acc, Atom.to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp map_get(map, atom_key, string_key) when is_map(map) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key)
    end
  end

  defp map_get(_map, _atom_key, _string_key), do: nil

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
