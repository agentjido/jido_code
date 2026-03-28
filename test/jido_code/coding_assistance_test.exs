defmodule JidoCode.CodingAssistanceTest do
  # covers: coding_assistance.boundary.session_prepared_before_assist
  # covers: coding_assistance.boundary.session_authority_delegation
  # covers: jido_os.runtime.compatibility.local_override_present
  # covers: jido_os.runtime.compatibility.public_runtime_surface
  # covers: jido_os.runtime.compatibility.session_and_envelope_behaviour
  use ExUnit.Case, async: false

  alias JidoCode.CodingAssistance

  setup do
    instance_id = "jido-code-test-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)
    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
    end)

    %{instance_id: instance_id}
  end

  test "assist ensures a jido_os session and returns a typed envelope" do
    actor_id = "user-1"
    session_id = "thread-1"

    assert {:ok, envelope} =
             CodingAssistance.assist(actor_id, %{
               session_id: session_id,
               objective: "Plan a safe refactor of the authentication flow",
               operation: "plan",
               operation_profile: %{
                 ai_mediation_required: false,
                 default_strategy_key: "adaptive",
                 allowed_strategy_keys: ["adaptive"]
               }
             })

    assert envelope.outcome == "ok"
    assert envelope.context.instance_id == Application.get_env(:jido_code, :jido_os_instance_id)
    assert envelope.context.session_id == session_id
    assert envelope.payload.operation == "plan"
    assert is_list(envelope.payload.artifacts)

    assert {:ok, session} = CodingAssistance.lookup_session(session_id, actor_id)
    assert session.session_id == session_id
  end

  test "session AI selection helpers delegate through jido_os session authority" do
    actor_id = "user-2"
    session_id = "thread-2"

    assert {:ok, _session} = CodingAssistance.ensure_session(session_id, actor_id)

    assert {:ok, updated} =
             CodingAssistance.update_ai_selection(session_id, actor_id, %{
               preferred_model_profile: "balanced"
             })

    assert updated.preferred_model_profile == "balanced"

    assert {:ok, selection} = CodingAssistance.get_ai_selection(session_id, actor_id)
    assert selection.preferred_model_profile == "balanced"
  end

  test "project binding helpers update session project assignment through the directory boundary" do
    actor_id = "user-3"
    session_id = "thread-3"

    assert {:ok, _session} = CodingAssistance.ensure_session(session_id, actor_id)

    assert {:ok, bound} =
             CodingAssistance.bind_project(session_id, actor_id, "project-a")

    assert bound.project_id == "project-a"

    assert {:ok, rebound} =
             CodingAssistance.rebind_project(session_id, actor_id, "project-b")

    assert rebound.project_id == "project-b"

    assert {:ok, unbound} = CodingAssistance.unbind_project(session_id, actor_id)
    refute Map.has_key?(unbound, :project_id)

    assert {:ok, reloaded} = CodingAssistance.lookup_session(session_id, actor_id)
    refute Map.has_key?(reloaded, :project_id)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
