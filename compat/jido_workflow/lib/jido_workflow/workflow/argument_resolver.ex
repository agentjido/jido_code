defmodule JidoWorkflow.Workflow.ArgumentResolver do
  @moduledoc """
  Resolves workflow step input references against runtime workflow state.
  """

  @type state :: %{
          required(String.t()) => map()
        }

  @spec normalize_state(term()) :: state()
  def normalize_state(value) when is_list(value) do
    Enum.reduce(value, empty_state(), fn item, acc ->
      merge_state(acc, normalize_state(item))
    end)
  end

  def normalize_state(value) when is_map(value) do
    if has_state_shape?(value) do
      %{
        "inputs" => stringify_keys(fetch_map(value, "inputs")),
        "results" => stringify_keys(fetch_map(value, "results"))
      }
    else
      %{"inputs" => stringify_keys(value), "results" => %{}}
    end
  end

  def normalize_state(other), do: %{"inputs" => %{"input" => other}, "results" => %{}}

  @spec resolve_inputs(map() | list() | nil, state()) :: {:ok, map()} | {:error, term()}
  def resolve_inputs(nil, _state), do: {:ok, %{}}

  def resolve_inputs(inputs, state) when is_map(inputs) do
    resolved =
      Enum.reduce(inputs, %{}, fn {key, value}, acc ->
        Map.put(acc, to_string(key), resolve_value(value, state))
      end)

    {:ok, resolved}
  end

  def resolve_inputs(inputs, state) when is_list(inputs) do
    inputs
    |> list_inputs_to_map()
    |> resolve_inputs(state)
  end

  def resolve_inputs(inputs, _state), do: {:error, {:invalid_inputs_shape, inputs}}

  @spec put_result(state(), String.t() | atom(), term()) :: state()
  def put_result(state, step_name, result) do
    key = to_string(step_name)
    results = Map.get(state, "results", %{})
    Map.put(state, "results", Map.put(results, key, result))
  end

  @spec get_result(state(), String.t(), String.t() | nil) :: term()
  def get_result(state, step_name, nil) do
    state
    |> Map.get("results", %{})
    |> fetch_any(step_name)
  end

  def get_result(state, step_name, path) do
    state
    |> get_result(step_name, nil)
    |> get_nested(path)
  end

  defp resolve_value(value, state) when is_binary(value) do
    case parse_reference(value) do
      {:input, input_name} ->
        state
        |> Map.get("inputs", %{})
        |> fetch_any(input_name)

      {:result, step_name, path} ->
        get_result(state, step_name, path)

      :static ->
        value
    end
  end

  defp resolve_value(value, _state), do: value

  defp parse_reference(raw_value) do
    value =
      raw_value
      |> String.trim()
      |> String.trim_leading("`")
      |> String.trim_trailing("`")

    cond do
      String.starts_with?(value, "input:") ->
        {:input, String.trim_leading(value, "input:")}

      String.starts_with?(value, "result:") ->
        reference = String.trim_leading(value, "result:")

        case String.split(reference, ".", parts: 2) do
          [step_name] -> {:result, step_name, nil}
          [step_name, path] -> {:result, step_name, path}
        end

      true ->
        :static
    end
  end

  defp get_nested(nil, _path), do: nil

  defp get_nested(value, path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce(value, fn key, acc ->
      fetch_any(acc, key)
    end)
  end

  defp fetch_any(value, _key) when not is_map(value), do: nil

  defp fetch_any(value, key) do
    string_key = to_string(key)
    Map.get(value, key) || Map.get(value, string_key) || fetch_atom_key(value, string_key)
  end

  defp fetch_atom_key(value, string_key) do
    Enum.find_value(value, fn
      {map_key, map_value} when is_atom(map_key) ->
        if Atom.to_string(map_key) == string_key, do: map_value

      _other ->
        nil
    end)
  end

  defp has_state_shape?(value) do
    is_map(fetch_any(value, "inputs")) and is_map(fetch_any(value, "results"))
  end

  defp fetch_map(value, key) do
    case fetch_any(value, key) do
      candidate when is_map(candidate) -> candidate
      _other -> %{}
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, item} ->
      {to_string(key), stringify_keys(item)}
    end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp list_inputs_to_map(inputs) do
    Enum.reduce(inputs, %{}, fn
      {key, value}, acc ->
        Map.put(acc, key, value)

      %{} = map, acc ->
        Map.merge(acc, map)

      _other, acc ->
        acc
    end)
  end

  defp merge_state(left, right) do
    %{
      "inputs" => Map.merge(left["inputs"] || %{}, right["inputs"] || %{}),
      "results" => Map.merge(left["results"] || %{}, right["results"] || %{})
    }
  end

  defp empty_state, do: %{"inputs" => %{}, "results" => %{}}
end
