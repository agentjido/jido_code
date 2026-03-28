defmodule Jido.Os.CodingAssist.Service do
  # covers: jido_os.runtime.compatibility.public_runtime_surface
  # covers: jido_os.runtime.compatibility.session_and_envelope_behaviour
  @moduledoc false

  alias Jido.Os.Session.RuntimeAgent

  def assist(instance_id, request, context)
      when is_binary(instance_id) and is_map(request) and is_map(context) do
    with session_id when is_binary(session_id) <- Map.get(context, :session_id),
         {:ok, _session} <- RuntimeAgent.load_session(instance_id, session_id, context) do
      {:ok,
       %{
         outcome: "ok",
         context:
           compact_nil_values(%{
             instance_id: instance_id,
             session_id: session_id,
             actor_id: Map.get(context, :actor_id),
             project_id: Map.get(context, :project_id),
             workspace_id: Map.get(context, :workspace_id)
           }),
         payload:
           compact_nil_values(%{
             operation: Map.get(request, :operation),
             objective: Map.get(request, :objective),
             requested_capabilities: Map.get(request, :requested_capabilities, []),
             operation_profile: Map.get(request, :operation_profile),
             prompt_ref: Map.get(request, :prompt_ref),
             prompt_variables: Map.get(request, :prompt_variables),
             tool_intent: Map.get(request, :tool_intent),
             artifacts: []
           })
       }}
    else
      nil ->
        {:error, :missing_session_id}

      {:error, _reason} = error ->
        error
    end
  end

  defp compact_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        Map.put(acc, key, compact_nil_values(value))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end
end
