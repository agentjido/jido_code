defmodule JidoCode.ContextBudget.ReActRequestTransformer do
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  @moduledoc """
  ReAct request transformer that applies product context-budget history limits.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias JidoCode.ContextBudget

  @impl true
  def transform_request(%{messages: messages} = _request, _state, config, runtime_context)
      when is_list(messages) and is_map(runtime_context) do
    policy =
      runtime_context
      |> Map.get(:context_budget_policy, Map.get(runtime_context, "context_budget_policy"))
      |> case do
        %{input_token_budget: _input_token_budget} = policy ->
          policy

        _other ->
          ContextBudget.policy(llm_selection: llm_selection_from_config(config))
      end

    packed = ContextBudget.pack_messages(messages, policy: policy)

    {:ok, %{messages: packed.messages}}
  end

  def transform_request(_request, _state, _config, _runtime_context), do: {:ok, %{}}

  defp llm_selection_from_config(config) do
    model =
      config
      |> Map.get(:model)
      |> normalize_optional_string()

    case model do
      nil ->
        %{}

      model_spec ->
        case String.split(model_spec, ":", parts: 2) do
          [provider, model] ->
            %{provider: provider, model: model, model_spec: model_spec}

          _other ->
            %{model: model_spec, model_spec: model_spec}
        end
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value), do: inspect(value)
end
