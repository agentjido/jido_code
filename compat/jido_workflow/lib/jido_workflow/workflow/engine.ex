defmodule JidoWorkflow.Workflow.Engine do
  # covers: workflow.runtime.compatibility.legacy_loader_and_engine_surface
  # covers: workflow.runtime.compatibility.action_workflow_execution
  @moduledoc """
  Minimal action-oriented workflow runtime used to preserve the legacy
  workflow API surface in CI and local development.
  """

  alias JidoWorkflow.Workflow.ArgumentResolver
  alias JidoWorkflow.Workflow.Definition
  alias JidoWorkflow.Workflow.Definition.Input
  alias JidoWorkflow.Workflow.Definition.Step
  alias JidoWorkflow.Workflow.ReturnProjector

  @type execution_result :: %{
          run_id: String.t(),
          workflow_id: String.t(),
          status: :completed,
          result: term(),
          productions: [term()],
          workflow: map()
        }

  @spec execute_definition(Definition.t(), map(), keyword()) ::
          {:ok, execution_result()} | {:error, term()}
  def execute_definition(definition, inputs, opts \\ [])

  @spec execute_definition(Definition.t(), map(), keyword()) ::
          {:ok, execution_result()} | {:error, term()}
  def execute_definition(%Definition{} = definition, inputs, opts) when is_map(inputs) do
    with {:ok, normalized_inputs} <- normalize_inputs(inputs, definition.inputs),
         {:ok, final_state, productions} <- execute_steps(definition.steps, normalized_inputs) do
      workflow_id = Keyword.get(opts, :workflow_id, definition.name)
      run_id = Keyword.get_lazy(opts, :run_id, &default_run_id/0)

      case ReturnProjector.project(productions, definition.return) do
        {:ok, result} ->
          {:ok,
           %{
             run_id: run_id,
             workflow_id: workflow_id,
             status: :completed,
             result: result,
             productions: productions,
             workflow: %{
               name: definition.name,
               version: definition.version,
               state: final_state
             }
           }}

        {:error, reason} ->
          {:error, {:return_projection_failed, reason}}
      end
    end
  end

  def execute_definition(_definition, _inputs, _opts), do: {:error, :invalid_definition}

  defp execute_steps(steps, normalized_inputs) do
    initial_state = %{"inputs" => normalized_inputs, "results" => %{}}

    Enum.reduce_while(steps, {:ok, initial_state, [initial_state]}, fn step, {:ok, state, productions} ->
      case execute_step(step, state) do
        {:ok, next_state} ->
          {:cont, {:ok, next_state, productions ++ [next_state]}}

        {:error, reason} ->
          {:halt, {:error, {:execution_failed, step.name, reason}}}
      end
    end)
  end

  defp execute_step(%Step{type: type} = step, state) when type in ["action", :action] do
    with {:ok, target_module} <- resolve_module(step.module),
         {:ok, resolved_inputs} <- ArgumentResolver.resolve_inputs(step.inputs, state),
         {:ok, result} <- run_action(target_module, resolved_inputs, step) do
      {:ok, ArgumentResolver.put_result(state, step.name, result)}
    end
  end

  defp execute_step(%Step{type: type}, _state), do: {:error, {:unsupported_step_type, type}}

  defp run_action(target_module, resolved_inputs, step) do
    params = atomize_existing_top_level_keys(resolved_inputs)
    context = %{workflow_step: step.name}

    if function_exported?(target_module, :run, 2) do
      normalize_action_result(target_module.run(params, context))
    else
      {:error, {:action_runner_unavailable, target_module}}
    end
  end

  defp normalize_action_result({:ok, result}), do: {:ok, result}
  defp normalize_action_result({:ok, result, _extra}), do: {:ok, result}
  defp normalize_action_result({:error, reason}), do: {:error, reason}
  defp normalize_action_result(other), do: {:ok, other}

  defp resolve_module(module) when is_atom(module), do: {:ok, module}

  defp resolve_module(module) when is_binary(module) do
    qualified =
      if String.starts_with?(module, "Elixir.") do
        module
      else
        "Elixir." <> module
      end

    try do
      resolved = String.to_existing_atom(qualified)

      if Code.ensure_loaded?(resolved) do
        {:ok, resolved}
      else
        {:error, {:module_not_loaded, module}}
      end
    rescue
      ArgumentError ->
        {:error, {:module_not_loaded, module}}
    end
  end

  defp resolve_module(other), do: {:error, {:invalid_module, other}}

  defp normalize_inputs(inputs, input_definitions) when is_map(inputs) and is_list(input_definitions) do
    normalized_inputs = stringify_keys(inputs)

    Enum.reduce_while(input_definitions, {:ok, normalized_inputs}, fn %Input{} = input, {:ok, acc} ->
      case Map.fetch(acc, input.name) do
        {:ok, _value} ->
          {:cont, {:ok, acc}}

        :error when not is_nil(input.default) ->
          {:cont, {:ok, Map.put(acc, input.name, input.default)}}

        :error when input.required == true ->
          {:halt, {:error, {:invalid_inputs, {:missing_required_args, [input.name]}}}}

        :error ->
          {:cont, {:ok, acc}}
      end
    end)
  end

  defp atomize_existing_top_level_keys(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {maybe_existing_atom(key), value}
    end)
  end

  defp maybe_existing_atom(key) when is_atom(key), do: key

  defp maybe_existing_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, item} ->
      {to_string(key), item}
    end)
  end

  defp default_run_id do
    "wf-#{System.unique_integer([:positive, :monotonic])}"
  end
end
