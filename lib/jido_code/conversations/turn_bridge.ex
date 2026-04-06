defmodule JidoCode.Conversations.TurnBridge do
  # covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates
  # covers: architecture.factory_control_plane.runtime_turns_feed_governed_control_records
  # covers: architecture.execution_pipeline.public_turn_materialization_preserves_execution_authority
  @moduledoc """
  Bridge that translates coding assistance outcomes into the existing
  conversation subscriber event contract.
  """

  require Logger

  alias JidoCode.CodingAssistance
  alias JidoCode.Conversations.EventBridge

  @type bridge_state :: %{
          after_event_id: String.t() | nil,
          terminal_event_seen?: boolean(),
          delivery_mode: String.t() | nil
        }

  @spec start(map()) :: {:ok, pid()} | {:error, term()}
  def start(%{} = attrs) do
    Task.Supervisor.start_child(task_supervisor(), fn ->
      run(attrs, %{
        after_event_id: nil,
        terminal_event_seen?: false,
        delivery_mode: nil
      })
    end)
  end

  defp run(attrs, state) do
    case start_and_complete_turn(attrs, state) do
      {:ok, _next_state} ->
        :ok

      {:error, reason} ->
        emit_failure(attrs, reason)
    end
  end

  defp start_and_complete_turn(attrs, state) do
    coding_assistance_module().start_turn(attrs.actor_id, turn_params(attrs))
    |> case do
      {:ok, turn} ->
        # Emit success events
        translated_events = event_bridge_module().success_events(turn, attrs.ingress, attrs.context)
        :ok = dispatch_events(attrs, translated_events)

        # Materialize the turn
        materialize_turn(attrs, turn, translated_events)

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp turn_params(attrs) do
    %{
      session_id: get_in(attrs, [:context, :session_id]),
      project_id: get_in(attrs, [:context, :managed_repo_id]) || get_in(attrs, [:context, :project_id]),
      request_id: get_in(attrs, [:context, :request_id]),
      correlation_id: get_in(attrs, [:context, :correlation_id]),
      workspace_id: get_in(attrs, [:context, :workspace_id]),
      objective: get_in(attrs, [:params, :content]) || get_in(attrs, [:params, "content"]),
      operation: get_in(attrs, [:params, :operation]) || get_in(attrs, [:params, "operation"]) || "plan"
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

  defp materialize_turn(attrs, turn, events) do
    work_item_id = nested_get(attrs, [:ingress, :work_item, :id])

    if is_binary(work_item_id) do
      materialization_attrs = %{
        project_id: get_in(attrs, [:context, :project_id]),
        managed_repo_id: get_in(attrs, [:context, :managed_repo_id]),
        work_item_id: work_item_id,
        actor_id: attrs.actor_id,
        actor_email: get_in(attrs, [:context, :actor_email]),
        conversation_id: attrs.conversation_id,
        turn: turn,
        events: events,
        runtime_delivery: %{
          "delivery_mode" => "synchronous",
          "summary" => "Coding turn completed synchronously."
        }
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
end
