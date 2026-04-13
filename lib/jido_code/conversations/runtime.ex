defmodule JidoCode.Conversations.Runtime do
  # covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  @moduledoc """
  Product-owned real execution boundary for conversation child work.

  The LiveView never assembles prompts or calls the specialist runtime
  directly. This boundary resolves readiness, shapes the conversation request,
  and routes it through the existing `AgentWorkspace` surface.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Conversations.RuntimeReadiness

  @type runtime_spec :: %{
          conversation_id: String.t(),
          managed_repo_id: String.t(),
          work_item_id: String.t(),
          child_work_id: String.t(),
          turn_id: String.t(),
          instruction: String.t(),
          command_type: String.t() | nil,
          actor: map() | nil
        }

  @type runtime_event :: map()

  @spec run(runtime_spec(), (runtime_event() -> term())) ::
          {:completed, runtime_event()} | {:failed, runtime_event()}
  def run(runtime_spec, emit) when is_map(runtime_spec) and is_function(emit, 1) do
    instruction = runtime_spec[:instruction] || runtime_spec["instruction"] || ""
    emit.(%{"kind" => "progress", "summary" => "Routing repository conversation through the real runtime."})

    with {:ok, readiness} <- RuntimeReadiness.resolve(runtime_spec[:managed_repo_id] || runtime_spec["managed_repo_id"]),
         {:ok, result} <-
           AgentWorkspace.explain_work(
             runtime_spec[:managed_repo_id] || runtime_spec["managed_repo_id"],
             runtime_spec[:work_item_id] || runtime_spec["work_item_id"],
             instruction,
             workspace_path: readiness.workspace_path
           ) do
      explanation =
        result
        |> Map.get(:explanation, Map.get(result, "explanation"))
        |> normalize_summary()

      emit.(%{"kind" => "delta", "text" => explanation})

      {:completed,
       %{
         "kind" => "completed",
         "result" => %{
           "summary" => explanation,
           "workflow" => "explain",
           "instruction" => instruction
         }
       }}
    else
      {:error, %{} = typed_error} ->
        {:failed, %{"kind" => "failed", "error" => normalize_error(typed_error)}}

      {:error, reason} ->
        {:failed, %{"kind" => "failed", "error" => runtime_error(reason)}}
    end
  end

  defp normalize_summary(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "The repository conversation completed without a textual summary."
      trimmed -> trimmed
    end
  end

  defp normalize_summary(value), do: inspect(value)

  defp normalize_error(error) when is_map(error) do
    %{}
    |> maybe_put("error_type", string_value(Map.get(error, "error_type") || Map.get(error, :error_type)))
    |> maybe_put("detail", string_value(Map.get(error, "detail") || Map.get(error, :detail)))
    |> maybe_put(
      "remediation",
      string_value(Map.get(error, "remediation") || Map.get(error, :remediation))
    )
  end

  defp runtime_error(reason) do
    %{
      "error_type" => "conversation_runtime_execution_failed",
      "detail" => "Real conversation execution failed (#{inspect(reason)}).",
      "remediation" => "Retry the turn after runtime services recover."
    }
  end

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_value(value) when is_atom(value), do: value |> Atom.to_string() |> string_value()
  defp string_value(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
