defmodule JidoCode.AgentWorkspace.RuntimeSpecialistRunner do
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  @moduledoc false

  @behaviour JidoCode.AgentWorkspace.SpecialistRunner

  alias JidoCode.LLMSelection

  @impl true
  def run(agent_module, pid, instruction, opts)
      when is_atom(agent_module) and is_pid(pid) and is_binary(instruction) and is_list(opts) do
    llm_selection = Keyword.get(opts, :llm_selection)

    with :ok <- LLMSelection.apply_to_agent(agent_module, pid, llm_selection) do
      agent_module.ask_sync(
        pid,
        instruction,
        opts
        |> Keyword.drop([:llm_selection])
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
