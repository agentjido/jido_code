defmodule JidoCode.Conversations.TurnBridge do
  @moduledoc """
  Polling bridge that replays public coding-turn events into the existing
  conversation subscriber event contract.
  """

  require Logger

  alias JidoCode.CodingAssistance
  alias JidoCode.Conversations.EventBridge

  @default_poll_interval_ms 25
  @default_max_idle_polls 20
  @terminal_families ["completed", "failed", "interrupted", "cancelled"]

  @spec start(map()) :: {:ok, pid()} | {:error, term()}
  def start(%{} = attrs) do
    Task.Supervisor.start_child(task_supervisor(), fn ->
      run(attrs, nil, 0)
    end)
  end

  defp run(attrs, after_event_id, idle_polls) do
    case list_turn_events(attrs, after_event_id) do
      {:ok, events} ->
        translated_events = event_bridge_module().turn_events(events, attrs.ingress, attrs.context)
        :ok = dispatch_events(attrs, translated_events)

        next_after_event_id = last_event_id(events) || after_event_id
        terminal_event_seen? = Enum.any?(events, &terminal_event?/1)

        case get_turn(attrs) do
          {:ok, turn} ->
            cond do
              terminal_event_seen? ->
                :ok

              terminal_turn?(turn) and events == [] ->
                :ok

              true ->
                next_idle_polls = if events == [], do: idle_polls + 1, else: 0

                if next_idle_polls >= max_idle_polls() do
                  :ok
                else
                  Process.sleep(poll_interval_ms())
                  run(attrs, next_after_event_id, next_idle_polls)
                end
            end

          {:error, reason} ->
            emit_failure(attrs, reason)
        end

      {:error, reason} ->
        emit_failure(attrs, reason)
    end
  end

  defp list_turn_events(attrs, after_event_id) do
    coding_assistance_module().list_turn_events(attrs.actor_id, turn_request(attrs, after_event_id))
  end

  defp get_turn(attrs) do
    coding_assistance_module().get_turn(attrs.actor_id, turn_request(attrs, nil))
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

  defp terminal_turn?(%{} = turn) do
    state =
      Map.get(turn, :state) || Map.get(turn, "state")

    state in @terminal_families
  end

  defp terminal_event?(%{} = event) do
    family =
      Map.get(event, :family) || Map.get(event, "family")

    family in @terminal_families
  end

  defp last_event_id([]), do: nil

  defp last_event_id(events) when is_list(events) do
    events
    |> List.last()
    |> case do
      nil -> nil
      event -> Map.get(event, :event_id) || Map.get(event, "event_id")
    end
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

  defp poll_interval_ms do
    Application.get_env(:jido_code, :conversation_turn_bridge_poll_interval_ms, @default_poll_interval_ms)
  end

  defp max_idle_polls do
    Application.get_env(:jido_code, :conversation_turn_bridge_max_idle_polls, @default_max_idle_polls)
  end

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
