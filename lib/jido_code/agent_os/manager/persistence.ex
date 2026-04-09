defmodule JidoCode.AgentOS.Manager.Persistence do
  # covers: architecture.agent_os_integration.ecto_persistence_per_kernel
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  @moduledoc false

  require Logger

  import Ecto.Query, only: [from: 2]

  alias JidoCode.AgentOS.Manager.KernelState
  alias JidoCode.AgentOS.Manager.PersistedKernel
  alias JidoCode.Repo

  @spec load(atom()) :: {:ok, KernelState.t()} | :error
  def load(kernel_name) when is_atom(kernel_name) do
    try do
      with true <- repo_available?(),
           %PersistedKernel{} = record <- Repo.get_by(PersistedKernel, kernel_name: Atom.to_string(kernel_name)),
           {:ok, state} <- decode_snapshot(record.snapshot_data) do
        {:ok, state}
      else
        false ->
          :error

        nil ->
          :error

        {:error, reason} ->
          Logger.warning("AgentOS kernel snapshot restore failed for #{inspect(kernel_name)}: #{inspect(reason)}")
          :error
      end
    rescue
      error in [Postgrex.Error, DBConnection.ConnectionError] ->
        Logger.warning(
          "AgentOS kernel snapshot restore unavailable for #{inspect(kernel_name)}: #{Exception.message(error)}"
        )

        :error
    end
  end

  @spec save(atom(), KernelState.t()) :: :ok | {:error, term()}
  def save(kernel_name, %KernelState{} = state) when is_atom(kernel_name) do
    try do
      with true <- repo_available?() do
        attrs = %{
          kernel_name: Atom.to_string(kernel_name),
          managed_repo_id: state.managed_repo_id,
          snapshot_data: encode_snapshot(state)
        }

        changeset = PersistedKernel.changeset(%PersistedKernel{}, attrs)
        updated_at = DateTime.utc_now()

        case Repo.insert(changeset,
               on_conflict: [
                 set: [
                   managed_repo_id: attrs.managed_repo_id,
                   snapshot_data: attrs.snapshot_data,
                   updated_at: updated_at
                 ]
               ],
               conflict_target: :kernel_name
             ) do
          {:ok, _record} ->
            :ok

          {:error, reason} = error ->
            Logger.warning("AgentOS kernel snapshot persist failed for #{inspect(kernel_name)}: #{inspect(reason)}")
            error
        end
      else
        false ->
          :ok
      end
    rescue
      error in [Postgrex.Error, DBConnection.ConnectionError] ->
        Logger.warning(
          "AgentOS kernel snapshot persist unavailable for #{inspect(kernel_name)}: #{Exception.message(error)}"
        )

        :ok
    end
  end

  @spec delete(atom()) :: :ok
  def delete(kernel_name) when is_atom(kernel_name) do
    if repo_available?() do
      from(record in PersistedKernel, where: record.kernel_name == ^Atom.to_string(kernel_name))
      |> Repo.delete_all()
    end

    :ok
  rescue
    _error ->
      :ok
  end

  defp repo_available? do
    Code.ensure_loaded?(Repo) and function_exported?(Repo, :get_by, 2)
  end

  defp encode_snapshot(%KernelState{} = state) do
    state
    |> sanitize_kernel_state()
    |> :erlang.term_to_binary()
  end

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
