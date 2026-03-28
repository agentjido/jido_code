defmodule Jido.Os.Session.DirectoryAgent do
  @moduledoc false

  alias Jido.Os.State

  def attach_session_to_project(instance_id, session_id, project_id, _context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(project_id) do
    State.update_session(instance_id, session_id, fn session ->
      Map.put(session, :project_id, project_id)
    end)
  end

  def rebind_session_project(instance_id, session_id, project_id, context) do
    attach_session_to_project(instance_id, session_id, project_id, context)
  end

  def detach_session_from_project(instance_id, session_id, _context)
      when is_binary(instance_id) and is_binary(session_id) do
    State.update_session(instance_id, session_id, fn session ->
      Map.delete(session, :project_id)
    end)
  end
end
