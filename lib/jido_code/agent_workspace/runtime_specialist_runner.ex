defmodule JidoCode.AgentWorkspace.RuntimeSpecialistRunner do
  # covers: architecture.repository_runtime_integration.signal_routing_within_pod
  @moduledoc false

  @behaviour JidoCode.AgentWorkspace.SpecialistRunner

  alias JidoCode.ContextBudget
  alias JidoCode.ContextBudget.ReActRequestTransformer
  alias JidoCode.LLMSelection

  @impl true
  def run(agent_module, pid, instruction, opts)
      when is_atom(agent_module) and is_pid(pid) and is_binary(instruction) and is_list(opts) do
    llm_selection = Keyword.get(opts, :llm_selection)

    with :ok <- LLMSelection.apply_to_agent(agent_module, pid, llm_selection) do
      tool_context =
        opts
        |> Keyword.get(:tool_context, %{})
        |> Map.put_new(:context_budget_policy, ContextBudget.policy(llm_selection: llm_selection))

      agent_module.ask_sync(
        pid,
        instruction,
        opts
        |> Keyword.drop([:llm_selection])
        |> Keyword.put(:tool_context, tool_context)
        |> Keyword.put_new(:request_transformer, ReActRequestTransformer)
        |> maybe_put(:llm_opts, llm_selection && Map.get(llm_selection, :llm_opts, []))
        |> maybe_put(
          :req_http_options,
          llm_selection && Map.get(llm_selection, :req_http_options, [])
        )
      )
    end
  end

  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
