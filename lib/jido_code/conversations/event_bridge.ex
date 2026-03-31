defmodule JidoCode.Conversations.EventBridge do
  # covers: architecture.conversation_driver.subscriber_event_contract_preserved
  # covers: architecture.conversation_driver.public_jido_os_turn_event_bridge
  @moduledoc """
  Translates product-local coding assistance outcomes into the existing
  conversation event model consumed by subscriber-facing UI surfaces.
  """

  @spec success_events(map(), map(), map()) :: [map()]
  def success_events(result, ingress_result, context)
      when is_map(result) and is_map(ingress_result) and is_map(context) do
    meta = event_meta(context, ingress_result, result)

    [
      %{
        "type" => "assistant.delta",
        "data" => %{"content" => streaming_preamble(ingress_result)},
        "meta" => meta
      },
      %{
        "type" => "assistant.message",
        "data" => %{"content" => final_message(result, ingress_result)},
        "meta" => meta
      }
    ]
  end

  def success_events(_result, _ingress_result, _context), do: []

  @spec failure_event(term(), map(), map()) :: map()
  def failure_event(reason, context, attrs) when is_map(context) and is_map(attrs) do
    %{
      "type" => "llm.failed",
      "data" => %{
        "detail" => failure_detail(reason)
      },
      "meta" => failure_meta(context, attrs)
    }
  end

  defp streaming_preamble(%{turn_mode: :steer_existing_work, work_item: %{id: work_item_id}}) do
    "Steering work item #{work_item_id}..."
  end

  defp streaming_preamble(_ingress_result), do: "Capturing coding request..."

  defp final_message(result, ingress_result) do
    assistant_message =
      result
      |> nested_get([:assistant_output, :message])
      |> normalize_optional_string()

    objective =
      result
      |> payload_value(:objective)
      |> normalize_optional_string()

    operation =
      result
      |> payload_value(:operation)
      |> normalize_optional_string()

    base =
      case ingress_result do
        %{turn_mode: :steer_existing_work, work_item: %{id: work_item_id}} ->
          "Steering work item #{work_item_id}"

        %{work_item: %{id: work_item_id}} ->
          "Captured request for work item #{work_item_id}"

        _other ->
          "Captured coding request"
      end

    cond do
      is_binary(assistant_message) ->
        assistant_message

      true ->
        case {operation, objective} do
          {nil, nil} ->
            base <> "."

          {operation_value, nil} ->
            "#{base}. #{humanize_operation(operation_value)}."

          {nil, objective_value} ->
            "#{base}. #{objective_value}"

          {operation_value, objective_value} ->
            "#{base}. #{humanize_operation(operation_value)}: #{objective_value}"
        end
    end
  end

  defp failure_detail(reason) do
    case reason do
      {:missing_required_field, field} ->
        "Conversation driver is missing required field #{field}."

      :missing_actor_id ->
        "Conversation driver requires actor context before coding assistance can run."

      {:conversation_policy_halt, reason_code} ->
        "Conversation policy halted the turn (#{reason_code})."

      other ->
        format_reason(other)
    end
  end

  defp event_meta(context, ingress_result, result) do
    %{
      "session_id" => normalize_optional_string(Map.get(context, :session_id)),
      "conversation_id" => normalize_optional_string(Map.get(context, :session_id)),
      "project_id" => normalize_optional_string(Map.get(context, :project_id)),
      "managed_repo_id" => normalize_optional_string(Map.get(context, :managed_repo_id)),
      "request_id" => normalize_optional_string(Map.get(context, :request_id)),
      "correlation_id" => normalize_optional_string(Map.get(context, :correlation_id)),
      "turn_id" => result |> nested_get([:turn_id]) |> normalize_optional_string(),
      "work_item_id" => ingress_result |> nested_get([:work_item, :id]) |> normalize_optional_string(),
      "intake_id" => ingress_result |> nested_get([:intake, :id]) |> normalize_optional_string(),
      "turn_mode" => ingress_result |> Map.get(:turn_mode) |> normalize_optional_string()
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp failure_meta(context, attrs) do
    %{
      "session_id" => normalize_optional_string(Map.get(context, :session_id)),
      "conversation_id" => normalize_optional_string(Map.get(context, :session_id)),
      "project_id" => normalize_optional_string(Map.get(context, :project_id)),
      "managed_repo_id" => normalize_optional_string(Map.get(context, :managed_repo_id)),
      "request_id" => normalize_optional_string(Map.get(context, :request_id)),
      "correlation_id" => normalize_optional_string(Map.get(context, :correlation_id)),
      "actor_id" => normalize_optional_string(Map.get(attrs, :actor_id) || Map.get(attrs, "actor_id"))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp humanize_operation(nil), do: "Coding assistance prepared the turn"

  defp humanize_operation(operation) do
    operation
    |> normalize_optional_string()
    |> case do
      nil -> "Coding assistance prepared the turn"
      normalized -> normalized |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp payload_value(result, key) do
    nested_get(result, [:payload, key]) ||
      nested_get(result, [Atom.to_string(key)]) ||
      nested_get(result, [key])
  end

  defp nested_get(value, keys) when is_list(keys) do
    Enum.reduce_while(keys, value, fn key, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) and is_atom(key) ->
          string_key = Atom.to_string(key)

          if Map.has_key?(acc, string_key) do
            {:cont, Map.get(acc, string_key)}
          else
            {:halt, nil}
          end

        is_map(acc) and is_binary(key) ->
          atom_key = safe_existing_atom(key)

          if is_atom(atom_key) and Map.has_key?(acc, atom_key) do
            {:cont, Map.get(acc, atom_key)}
          else
            {:halt, nil}
          end

        true ->
          {:halt, nil}
      end
    end)
  end

  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

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

  defp format_reason(reason) do
    Exception.message(reason)
  rescue
    _exception -> inspect(reason)
  end
end
