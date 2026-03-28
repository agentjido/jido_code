defmodule Jido.Os.Session.RuntimeAgent do
  # covers: jido_os.runtime.compatibility.public_runtime_surface
  # covers: jido_os.runtime.compatibility.session_and_envelope_behaviour
  @moduledoc false

  alias Jido.Os.State

  def load_session(instance_id, session_id, _context)
      when is_binary(instance_id) and is_binary(session_id) do
    case State.get_session(instance_id, session_id) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  def create_session(instance_id, session_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_map(context) do
    session =
      %{
        instance_id: instance_id,
        session_id: session_id,
        actor_id: Map.get(context, :actor_id),
        request_id: Map.get(context, :request_id),
        correlation_id: Map.get(context, :correlation_id),
        project_id: Map.get(context, :project_id),
        workspace_id: Map.get(context, :workspace_id)
      }
      |> compact_nil_values()

    State.put_session(instance_id, session_id, session)
    {:ok, session}
  end

  def update_session_ai_preferences(instance_id, session_id, selection, _context)
      when is_binary(instance_id) and is_binary(session_id) and is_map(selection) do
    State.update_session(instance_id, session_id, fn session ->
      Map.merge(session, selection)
    end)
  end

  def get_session_ai_preferences(instance_id, session_id, context)
      when is_binary(instance_id) and is_binary(session_id) do
    with {:ok, session} <- load_session(instance_id, session_id, context) do
      {:ok,
       session
       |> Map.take([:preferred_model_profile, :preferred_provider, :preferred_model])
       |> compact_nil_values()}
    end
  end

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
