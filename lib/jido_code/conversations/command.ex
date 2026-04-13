defmodule JidoCode.Conversations.Command do
  # covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct
  @moduledoc """
  Normalizes conversation commands into explicit work and control classes.
  """

  @work_types %{
    "turn.submit" => :turn_submit,
    "tool_result.submit" => :tool_result_submit,
    "turn.resume" => :turn_resume
  }

  @control_types %{
    "turn.stop" => :turn_stop,
    "turn.steer" => :turn_steer,
    "tool.cancel" => :tool_cancel,
    "session.pause" => :session_pause,
    "session.resume" => :session_resume
  }

  @type normalized_command :: %{
          id: String.t(),
          class: :work | :control,
          type: atom(),
          raw_type: String.t(),
          payload: map(),
          actor: map(),
          admitted_at: DateTime.t()
        }

  @spec normalize(map(), map()) :: {:ok, normalized_command()} | {:error, term()}
  def normalize(command, actor) when is_map(command) and is_map(actor) do
    raw_type =
      command
      |> map_get(:type)
      |> normalize_optional_string()

    payload =
      command
      |> Map.get(:payload, Map.get(command, "payload", %{}))
      |> normalize_map()

    admitted_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    cond do
      type = @work_types[raw_type] ->
        {:ok,
         %{
           id: Ecto.UUID.generate(),
           class: :work,
           type: type,
           raw_type: raw_type,
           payload: payload,
           actor: actor,
           admitted_at: admitted_at
         }}

      type = @control_types[raw_type] ->
        {:ok,
         %{
           id: Ecto.UUID.generate(),
           class: :control,
           type: type,
           raw_type: raw_type,
           payload: payload,
           actor: actor,
           admitted_at: admitted_at
         }}

      true ->
        {:error, :unknown_command_type}
    end
  end

  def normalize(_command, _actor), do: {:error, :invalid_command}

  defp map_get(map, atom_key) when is_map(map) do
    string_key = Atom.to_string(atom_key)

    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
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

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value
end
