defmodule Jido.Os.SystemInstanceSupervisor do
  # covers: jido_os.runtime.compatibility.public_runtime_surface
  # covers: jido_os.runtime.compatibility.session_and_envelope_behaviour
  @moduledoc false

  alias Jido.Os.State

  def lookup_instance(instance_id) when is_binary(instance_id) do
    State.lookup_instance(instance_id)
  end

  def start_instance(instance_id, context) when is_binary(instance_id) and is_map(context) do
    case State.lookup_instance(instance_id) do
      {:ok, pid} ->
        {:error, {:already_started, pid}}

      :error ->
        {:ok, pid} = Agent.start(fn -> %{instance_id: instance_id, context: context} end)
        State.put_instance(instance_id, pid, context)
        {:ok, pid}
    end
  end
end
