defmodule JidoCode.Forge.Runners.Workflow do
  @moduledoc """
  Data-driven workflow runner.

  Executes a series of steps defined in data, supporting:
  - `:exec` - Run shell command with InfraClient.exec
  - `:prompt` - Return :needs_input status with question
  - `:condition` - Evaluate check and set jump_to in metadata
  - `:call` - Call a custom StepHandler module
  - `:noop` - Skip step

  ## Variable Interpolation

  Commands support `{{step_id.field}}` syntax to reference results from
  previous steps.

  ## Conditional Execution

  Steps can include:
  - `when` - Skip step if condition is false
  - `check` - Map of step_id => expected_value for condition evaluation
  """

  @behaviour JidoCode.Forge.Runner

  alias JidoCode.Forge.Runner
  alias JidoCode.Forge.InfraClient

  @impl true
  def init(client, %{workflow: workflow} = config) do
    if config[:write_to_infra] do
      path = config[:workflow_path] || "/tmp/workflow.json"
      content = Jason.encode!(workflow)
      InfraClient.write_file(client, path, content)
    end

    :ok
  end

  def init(_client, _config), do: :ok

  @impl true
  def run_iteration(client, state, opts) do
    workflow = state[:workflow] || opts[:workflow] || %{steps: []}
    steps = workflow[:steps] || workflow["steps"] || []
    current_step = state[:current_step] || 0
    step_results = state[:step_results] || %{}

    if current_step >= length(steps) do
      {:ok, Runner.done(metadata: %{step_results: step_results})}
    else
      step = Enum.at(steps, current_step)
      execute_step(client, step, state, opts, step_results, current_step)
    end
  end

  @impl true
  def apply_input(_client, input, state) do
    current_step = state[:current_step] || 0
    step_results = state[:step_results] || %{}
    workflow = state[:workflow] || %{steps: []}
    steps = workflow[:steps] || workflow["steps"] || []
    step = Enum.at(steps, current_step)
    step_id = step[:id] || step["id"] || "step_#{current_step}"

    new_results = Map.put(step_results, step_id, %{input: input})

    new_state =
      state
      |> Map.put(:current_step, current_step + 1)
      |> Map.put(:step_results, new_results)
      |> Map.put(:last_input, input)

    {:ok, new_state}
  end

  defp execute_step(client, step, state, opts, step_results, current_step) do
    step_type = step[:type] || step["type"] || :noop
    step_id = step[:id] || step["id"] || "step_#{current_step}"

    if should_skip_step?(step, step_results) do
      new_state =
        state
        |> Map.put(:current_step, current_step + 1)
        |> Map.put(:step_results, Map.put(step_results, step_id, %{skipped: true}))

      {:ok, Runner.continue(metadata: %{state: new_state, skipped: true})}
    else
      do_execute_step(step_type, client, step, state, opts, step_results, current_step, step_id)
    end
  end

  defp do_execute_step(:exec, client, step, state, opts, step_results, current_step, step_id) do
    command = step[:command] || step["command"]
    interpolated = interpolate_variables(command, step_results)

    case InfraClient.exec(client, interpolated, opts) do
      {output, 0} ->
        new_results = Map.put(step_results, step_id, %{output: output, exit_code: 0})

        new_state =
          state
          |> Map.put(:current_step, current_step + 1)
          |> Map.put(:step_results, new_results)

        {:ok, Runner.continue(output: output, metadata: %{state: new_state, exit_code: 0})}

      {output, code} ->
        new_results = Map.put(step_results, step_id, %{output: output, exit_code: code})

        new_state =
          state
          |> Map.put(:current_step, current_step + 1)
          |> Map.put(:step_results, new_results)

        {:ok, Runner.error("Exit code: #{code}", output: output, metadata: %{state: new_state})}
    end
  end

  defp do_execute_step(:prompt, _client, step, state, _opts, step_results, current_step, step_id) do
    question = step[:question] || step["question"] || "Please provide input:"

    new_state =
      state
      |> Map.put(:current_step, current_step)
      |> Map.put(:step_results, step_results)
      |> Map.put(:pending_step_id, step_id)

    {:ok, Runner.needs_input(question, metadata: %{state: new_state})}
  end

  defp do_execute_step(
         :condition,
         _client,
         step,
         state,
         _opts,
         step_results,
         current_step,
         step_id
       ) do
    check = step[:check] || step["check"] || %{}
    then_jump = step[:then] || step["then"]
    else_jump = step[:else] || step["else"]

    condition_met = evaluate_condition(check, step_results)
    jump_to = if condition_met, do: then_jump, else: else_jump

    new_results = Map.put(step_results, step_id, %{condition_met: condition_met, jump_to: jump_to})

    next_step =
      if jump_to do
        find_step_index(state[:workflow] || %{steps: []}, jump_to) || current_step + 1
      else
        current_step + 1
      end

    new_state =
      state
      |> Map.put(:current_step, next_step)
      |> Map.put(:step_results, new_results)

    {:ok, Runner.continue(metadata: %{state: new_state, jump_to: jump_to})}
  end

  defp do_execute_step(:call, client, step, state, opts, step_results, current_step, step_id) do
    handler = step[:handler] || step["handler"]
    args = step[:args] || step["args"] || %{}
    interpolated_args = interpolate_map(args, step_results)

    case handler.execute(client, interpolated_args, opts) do
      {:ok, result} ->
        new_results = Map.put(step_results, step_id, result)

        new_state =
          state
          |> Map.put(:current_step, current_step + 1)
          |> Map.put(:step_results, new_results)

        {:ok, Runner.continue(metadata: %{state: new_state, handler_result: result})}

      {:needs_input, question} ->
        new_state =
          state
          |> Map.put(:current_step, current_step)
          |> Map.put(:step_results, step_results)
          |> Map.put(:pending_step_id, step_id)

        {:ok, Runner.needs_input(question, metadata: %{state: new_state})}

      {:error, reason} ->
        new_results = Map.put(step_results, step_id, %{error: reason})

        new_state =
          state
          |> Map.put(:current_step, current_step + 1)
          |> Map.put(:step_results, new_results)

        {:ok, Runner.error("Handler error: #{inspect(reason)}", metadata: %{state: new_state})}
    end
  end

  defp do_execute_step(:noop, _client, _step, state, _opts, step_results, current_step, step_id) do
    new_results = Map.put(step_results, step_id, %{skipped: true})

    new_state =
      state
      |> Map.put(:current_step, current_step + 1)
      |> Map.put(:step_results, new_results)

    {:ok, Runner.continue(metadata: %{state: new_state})}
  end

  defp do_execute_step(
         unknown_type,
         _client,
         _step,
         state,
         _opts,
         step_results,
         current_step,
         step_id
       ) do
    new_results = Map.put(step_results, step_id, %{error: :unknown_type})

    new_state =
      state
      |> Map.put(:current_step, current_step + 1)
      |> Map.put(:step_results, new_results)

    {:ok, Runner.error("Unknown step type: #{inspect(unknown_type)}", metadata: %{state: new_state})}
  end

  defp should_skip_step?(step, step_results) do
    case step[:when] || step["when"] do
      nil -> false
      condition -> not evaluate_condition(condition, step_results)
    end
  end

  defp evaluate_condition(check, step_results) when is_map(check) do
    Enum.all?(check, fn {step_id, expected} ->
      result = Map.get(step_results, to_string(step_id)) || Map.get(step_results, step_id)

      case result do
        nil -> false
        %{output: output} -> output == expected or String.contains?(to_string(output), to_string(expected))
        value -> value == expected
      end
    end)
  end

  defp evaluate_condition(_, _), do: true

  defp find_step_index(workflow, step_id) do
    steps = workflow[:steps] || workflow["steps"] || []

    Enum.find_index(steps, fn step ->
      id = step[:id] || step["id"]
      id == step_id
    end)
  end

  defp interpolate_variables(nil, _), do: nil

  defp interpolate_variables(command, step_results) when is_binary(command) do
    Regex.replace(~r/\{\{(\w+)\.(\w+)\}\}/, command, fn _, step_id, field ->
      result = Map.get(step_results, step_id) || Map.get(step_results, String.to_atom(step_id))

      case result do
        nil ->
          "{{#{step_id}.#{field}}}"

        map when is_map(map) ->
          value = Map.get(map, field) || Map.get(map, String.to_atom(field))
          to_string(value || "{{#{step_id}.#{field}}}")

        _ ->
          "{{#{step_id}.#{field}}}"
      end
    end)
  end

  defp interpolate_variables(command, _), do: command

  defp interpolate_map(args, step_results) when is_map(args) do
    Map.new(args, fn {key, value} ->
      interpolated =
        case value do
          v when is_binary(v) -> interpolate_variables(v, step_results)
          v -> v
        end

      {key, interpolated}
    end)
  end

  defp interpolate_map(args, _), do: args
end
