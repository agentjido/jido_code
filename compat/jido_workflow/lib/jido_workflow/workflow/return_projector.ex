defmodule JidoWorkflow.Workflow.ReturnProjector do
  @moduledoc """
  Projects workflow return values from final execution state.
  """

  alias JidoWorkflow.Workflow.ArgumentResolver
  alias JidoWorkflow.Workflow.Definition.Return

  @spec project([term()], Return.t() | map() | nil) :: {:ok, term()} | {:error, term()}
  def project([], _config), do: {:error, :no_productions}

  def project(productions, config) when is_list(productions) do
    config = normalize_config(config)

    case resolve_base_value(productions, config.value) do
      {:ok, base_value} ->
        apply_transform(base_value, config.transform)

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize_config(nil), do: %{value: nil, transform: nil}

  defp normalize_config(%Return{} = config) do
    %{value: config.value, transform: config.transform}
  end

  defp normalize_config(config) when is_map(config) do
    %{
      value: fetch(config, :value),
      transform: fetch(config, :transform)
    }
  end

  defp resolve_base_value(productions, nil), do: {:ok, List.last(productions)}

  defp resolve_base_value(productions, value) when is_binary(value) do
    normalized = normalize_return_value(value)

    case resolve_return_reference_in_productions(productions, normalized) do
      {:ok, result} -> {:ok, result}
      :error -> {:error, {:return_value_not_found, value}}
    end
  end

  defp resolve_base_value(_productions, value), do: {:error, {:invalid_return_value, value}}

  defp resolve_return_reference_in_productions(productions, value) do
    productions
    |> Enum.reverse()
    |> Enum.reduce_while(:error, fn production, _acc ->
      case resolve_return_reference(production, value) do
        {:ok, _result} = ok -> {:halt, ok}
        :error -> {:cont, :error}
      end
    end)
  end

  defp resolve_return_reference(last_production, value) do
    state = ArgumentResolver.normalize_state(last_production)

    case String.split(value, ".", parts: 2) do
      [step_name] ->
        case ArgumentResolver.get_result(state, step_name, nil) do
          nil -> fallback_map_lookup(last_production, step_name)
          result -> {:ok, result}
        end

      [step_name, path] ->
        case ArgumentResolver.get_result(state, step_name, path) do
          nil -> :error
          result -> {:ok, result}
        end
    end
  end

  defp apply_transform(value, nil), do: {:ok, value}

  defp apply_transform(value, transform_source) when is_binary(transform_source) do
    with {:ok, transform_fn} <- compile_transform(transform_source) do
      try do
        {:ok, transform_fn.(value)}
      rescue
        exception ->
          {:error, {:transform_execution_failed, Exception.message(exception)}}
      end
    end
  end

  defp apply_transform(_value, transform), do: {:error, {:invalid_transform, transform}}

  defp compile_transform(source) do
    {value, _binding} = Code.eval_string(source)

    if is_function(value, 1) do
      {:ok, value}
    else
      {:error, :transform_must_be_function_arity_1}
    end
  rescue
    exception ->
      {:error, {:transform_compile_failed, Exception.message(exception)}}
  end

  defp normalize_return_value(value) do
    value
    |> String.trim()
    |> String.trim_leading("`")
    |> String.trim_trailing("`")
    |> String.trim_leading("result:")
  end

  defp fallback_map_lookup(last_production, step_name) when is_map(last_production) do
    case fetch(last_production, step_name) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  defp fallback_map_lookup(_last_production, _step_name), do: :error

  defp fetch(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || fetch_atom_key(map, key)
  end

  defp fetch(_map, _key), do: nil

  defp fetch_atom_key(map, key) do
    Enum.find_value(map, fn
      {atom_key, value} when is_atom(atom_key) ->
        if Atom.to_string(atom_key) == key, do: value

      _other ->
        nil
    end)
  end
end
