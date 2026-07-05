defmodule JidoCode.AgentOS.Manager.Persistence do
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  @moduledoc false

  require Logger

  alias JidoCode.AgentOS.Manager.KernelState
  alias JidoCode.ExecutionRuntime.RecordStore

  @spec load(atom()) :: {:ok, KernelState.t()} | :error
  def load(kernel_name) when is_atom(kernel_name) do
    case RecordStore.list_checkpoints(%{id: checkpoint_id(kernel_name)}) do
      {:ok, [checkpoint | _rest]} ->
        with false <- deleted_checkpoint?(checkpoint),
             {:ok, snapshot_data} <- checkpoint_snapshot_data(checkpoint),
             {:ok, state} <- decode_snapshot(snapshot_data) do
          {:ok, state}
        else
          true ->
            :error

          {:error, reason} ->
            Logger.warning("AgentOS kernel snapshot restore failed for #{inspect(kernel_name)}: #{inspect(reason)}")
            :error

          _other ->
            :error
        end

      {:ok, []} ->
        :error

      {:error, reason} ->
        Logger.warning("AgentOS kernel snapshot restore failed for #{inspect(kernel_name)}: #{inspect(reason)}")
        :error
    end
  end

  @spec save(atom(), KernelState.t()) :: :ok | {:error, term()}
  def save(kernel_name, %KernelState{} = state) when is_atom(kernel_name) do
    attrs = %{
      checkpoint_id: checkpoint_id(kernel_name),
      managed_repo_id: state.managed_repo_id,
      sandbox_session_id: nil,
      sprites_checkpoint_id: "agent-os:#{Atom.to_string(kernel_name)}",
      name: "AgentOS kernel snapshot #{Atom.to_string(kernel_name)}",
      exec_session_sequence: 0,
      runner_state_snapshot: snapshot_payload(encode_snapshot(state)),
      metadata: %{
        "kind" => "agent_os_kernel_snapshot",
        "kernel_name" => Atom.to_string(kernel_name),
        "deleted" => false
      }
    }

    case RecordStore.create_checkpoint(attrs) do
      {:ok, _checkpoint} ->
        {:ok, state}

      {:error, reason} = error ->
        Logger.warning("AgentOS kernel snapshot persist failed for #{inspect(kernel_name)}: #{inspect(reason)}")
        error
    end
    |> case do
      {:ok, %KernelState{}} -> :ok
      other -> other
    end
  rescue
    error ->
      Logger.warning("AgentOS kernel snapshot persist failed for #{inspect(kernel_name)}: #{Exception.message(error)}")
      :ok
  end

  @spec delete(atom()) :: :ok
  def delete(kernel_name) when is_atom(kernel_name) do
    checkpoint_id = checkpoint_id(kernel_name)

    case RecordStore.create_checkpoint(%{
           checkpoint_id: checkpoint_id,
           managed_repo_id: existing_checkpoint_managed_repo_id(checkpoint_id),
           sandbox_session_id: nil,
           sprites_checkpoint_id: "agent-os:#{Atom.to_string(kernel_name)}",
           name: "AgentOS kernel snapshot #{Atom.to_string(kernel_name)}",
           exec_session_sequence: 0,
           runner_state_snapshot: %{},
           metadata: %{
             "kind" => "agent_os_kernel_snapshot",
             "kernel_name" => Atom.to_string(kernel_name),
             "deleted" => true
           }
         }) do
      {:ok, _checkpoint} ->
        :ok

      {:error, reason} ->
        Logger.warning("AgentOS kernel snapshot delete failed for #{inspect(kernel_name)}: #{inspect(reason)}")
        :ok
    end
  rescue
    _error ->
      :ok
  end

  defp checkpoint_id(kernel_name) when is_atom(kernel_name),
    do: "agent-os-kernel:#{Atom.to_string(kernel_name)}"

  defp existing_checkpoint_managed_repo_id(checkpoint_id) do
    case RecordStore.list_checkpoints(%{id: checkpoint_id}) do
      {:ok, [%{managed_repo_id: managed_repo_id} | _rest]} when is_binary(managed_repo_id) ->
        managed_repo_id

      _other ->
        nil
    end
  end

  defp encode_snapshot(%KernelState{} = state) do
    state
    |> sanitize_kernel_state()
    |> :erlang.term_to_binary()
  end

  defp snapshot_payload(snapshot_data) when is_binary(snapshot_data) do
    %{
      "encoding" => "erlang-term-binary-base64",
      "snapshot_data" => Base.encode64(snapshot_data)
    }
  end

  defp checkpoint_snapshot_data(%{runner_state_snapshot: snapshot}) when is_map(snapshot) do
    case Map.get(snapshot, "snapshot_data") || Map.get(snapshot, :snapshot_data) do
      snapshot_data when is_binary(snapshot_data) ->
        Base.decode64(snapshot_data)

      _other ->
        {:error, :missing_snapshot_data}
    end
  end

  defp checkpoint_snapshot_data(_checkpoint), do: {:error, :missing_snapshot_data}

  defp deleted_checkpoint?(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "deleted") == true or Map.get(metadata, :deleted) == true
  end

  defp deleted_checkpoint?(_checkpoint), do: false

  defp decode_snapshot(snapshot_data) when is_binary(snapshot_data) do
    snapshot_data
    |> :erlang.binary_to_term()
    |> case do
      %KernelState{} = state -> {:ok, state}
      %{} = state_map -> {:ok, restore_kernel_state(state_map)}
      other -> {:error, {:invalid_snapshot, other}}
    end
  rescue
    error ->
      {:error, error}
  end

  defp sanitize_kernel_state(%KernelState{} = state) do
    %KernelState{
      managed_repo_id: state.managed_repo_id,
      pid: nil,
      created_at: state.created_at,
      pods:
        state
        |> Map.get(:pods, %{})
        |> Enum.into(%{}, fn {pod_id, pod_entry} ->
          {pod_id, sanitize_pod_entry(pod_entry)}
        end)
    }
  end

  defp sanitize_pod_entry(%{metadata: metadata} = pod_entry) when is_map(metadata) do
    put_in(pod_entry.metadata, sanitize_metadata(metadata))
  end

  defp sanitize_pod_entry(pod_entry), do: pod_entry

  defp sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.delete(:runtime_pid)
    |> Map.put(:runtime_status, Map.get(metadata, :runtime_status, :persisted))
  end

  defp restore_kernel_state(state_map) do
    %KernelState{
      managed_repo_id: Map.get(state_map, :managed_repo_id) || Map.get(state_map, "managed_repo_id"),
      pid: nil,
      created_at: Map.get(state_map, :created_at) || Map.get(state_map, "created_at"),
      pods: Map.get(state_map, :pods) || Map.get(state_map, "pods") || %{}
    }
  end
end
