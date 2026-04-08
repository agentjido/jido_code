defmodule JidoCode.AgentOS.Manager do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
  # covers: architecture.agent_os_integration.kernel_naming_convention
  @moduledoc """
  Dynamic kernel manager for repository-scoped AgentOS kernels.

  This module creates and manages one kernel per ManagedRepo, providing
  isolated runtime boundaries for multi-repository coding operations.

  ## Kernel Naming

  Kernels are named by converting the ManagedRepo ID to an atom,
  replacing hyphens with underscores for valid atom syntax.

  Examples:
  - "repo-123" → :repo_123
  - "my-repo" → :my_repo

  ## Lifecycle

  Kernels are created on-demand when work begins on a ManagedRepo and
  can be shut down explicitly or via idle timeout.

  ## Note on kernel_status

  Due to Jido.AgentOS's internal registry complexity, we track kernels
  using our own ETS table. `kernel_status/1` returns our tracked status rather
  than calling `Jido.AgentOS.kernel_status/1` directly.
  """

  require Logger

  alias JidoCode.AgentOS.Manager.KernelState

  @type kernel_ref :: atom() | String.t()
  @type kernel_name :: atom()
  @type pod_id :: String.t()
  @table_name __MODULE__

  ## Client API

  @doc """
  Ensures a kernel exists for the given ManagedRepo ID.

  Creates a new kernel if one doesn't exist, otherwise returns the
  existing kernel reference.

  ## Examples

      iex> AgentOS.Manager.ensure_kernel("repo-123")
      {:ok, :repo_123}

  """
  @spec ensure_kernel(String.t()) :: {:ok, kernel_name()} | {:error, term()}
  def ensure_kernel(managed_repo_id) when is_binary(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    case get_kernel_state(kernel_name) do
      {:ok, _state} ->
        {:ok, kernel_name}

      :error ->
        start_kernel(managed_repo_id, kernel_name)
    end
  end

  @doc """
  Returns the status of a kernel for the given ManagedRepo ID.

  Returns `nil` if the kernel doesn't exist.

  ## Examples

      iex> AgentOS.Manager.kernel_status("repo-123")
      %{kernel_name: :repo_123, supervisor_pid: #PID<...>, pods: [...]}

      iex> AgentOS.Manager.kernel_status("nonexistent")
      nil

  """
  @spec kernel_status(String.t()) :: map() | nil
  def kernel_status(managed_repo_id) when is_binary(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    case get_kernel_state(kernel_name) do
      {:ok, state} ->
        build_status_from_state(kernel_name, state)

      :error ->
        nil
    end
  end

  @doc """
  Shuts down a kernel for the given ManagedRepo ID.

  ## Examples

      iex> AgentOS.Manager.shutdown_kernel("repo-123")
      :ok

  """
  @spec shutdown_kernel(String.t()) :: :ok
  def shutdown_kernel(managed_repo_id) when is_binary(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    case get_kernel_state(kernel_name) do
      {:ok, state} ->
        shutdown_kernel_impl(kernel_name, state)

      :error ->
        :ok
    end
  end

  @doc """
  Lists all active kernels.

  ## Examples

      iex> AgentOS.Manager.list_kernels()
      [:repo_repo_123, :repo_repo_456]

  """
  @spec list_kernels() :: [kernel_name()]
  def list_kernels do
    list_tracked_kernels()
  end

  @doc """
  Returns the number of active kernels.

  ## Examples

      iex> AgentOS.Manager.kernel_count()
      2

  """
  @spec kernel_count :: non_neg_integer()
  def kernel_count do
    list_kernels() |> length()
  end

  @doc """
  Checks if a kernel exists for the given ManagedRepo ID.

  ## Examples

      iex> AgentOS.Manager.kernel_exists?("repo-123")
      true

      iex> AgentOS.Manager.kernel_exists?("nonexistent")
      false

  """
  @spec kernel_exists?(String.t()) :: boolean()
  def kernel_exists?(managed_repo_id) when is_binary(managed_repo_id) do
    !!kernel_status(managed_repo_id)
  end

  @doc """
  Ensures a logical pod entry exists for the given ManagedRepo.

  This product-owned registry keeps repository-scoped pod identity and metadata
  explicit even while the underlying AgentOS integration continues to evolve.
  """
  @spec ensure_pod(String.t(), pod_id(), module(), map()) :: {:ok, map()} | {:error, term()}
  def ensure_pod(managed_repo_id, pod_id, pod_module, metadata \\ %{})
      when is_binary(managed_repo_id) and is_binary(pod_id) and is_atom(pod_module) and is_map(metadata) do
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id) do
      kernel_name = kernel_name(managed_repo_id)

      case get_kernel_state(kernel_name) do
        {:ok, state} ->
          pod_entry = build_pod_entry(state, pod_id, pod_module, metadata)
          next_state = put_in(state.pods[pod_id], pod_entry)
          :ets.insert(@table_name, {kernel_name, next_state})
          {:ok, pod_entry}

        :error ->
          {:error, :kernel_not_found}
      end
    end
  end

  @doc """
  Returns the tracked pod entry for a ManagedRepo and pod ID.
  """
  @spec pod_status(String.t(), pod_id()) :: map() | nil
  def pod_status(managed_repo_id, pod_id) when is_binary(managed_repo_id) and is_binary(pod_id) do
    kernel_name = kernel_name(managed_repo_id)

    case get_kernel_state(kernel_name) do
      {:ok, state} ->
        state
        |> pod_entries()
        |> Map.get(pod_id)

      :error ->
        nil
    end
  end

  @doc """
  Lists tracked logical pod entries for a ManagedRepo.
  """
  @spec list_pods(String.t()) :: [map()]
  def list_pods(managed_repo_id) when is_binary(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    case get_kernel_state(kernel_name) do
      {:ok, state} ->
        state
        |> pod_entries()
        |> Map.values()
        |> Enum.sort_by(& &1.pod_id)

      :error ->
        []
    end
  end

  @doc """
  Merges metadata into an existing logical pod entry for a ManagedRepo.
  """
  @spec update_pod_metadata(String.t(), pod_id(), map()) :: {:ok, map()} | {:error, term()}
  def update_pod_metadata(managed_repo_id, pod_id, updates)
      when is_binary(managed_repo_id) and is_binary(pod_id) and is_map(updates) do
    kernel_name = kernel_name(managed_repo_id)

    case get_kernel_state(kernel_name) do
      {:ok, state} ->
        case pod_entries(state)[pod_id] do
          nil ->
            {:error, :pod_not_found}

          pod_entry ->
            next_pod_entry = put_in(pod_entry.metadata, Map.merge(pod_entry.metadata, updates))
            next_state = put_in(state.pods[pod_id], next_pod_entry)
            :ets.insert(@table_name, {kernel_name, next_state})
            {:ok, next_pod_entry}
        end

      :error ->
        {:error, :kernel_not_found}
    end
  end

  @doc """
  Converts a ManagedRepo ID to a kernel name.

  ## Examples

      iex> AgentOS.Manager.kernel_name("repo-123")
      :repo_123

      iex> AgentOS.Manager.kernel_name("my-repo")
      :my_repo

  """
  @spec kernel_name(String.t()) :: kernel_name()
  def kernel_name(managed_repo_id) when is_binary(managed_repo_id) do
    # Replace hyphens with underscores to make a valid atom
    managed_repo_id |> String.replace("-", "_") |> String.to_atom()
  end

  ## Private Functions

  defp start_kernel(managed_repo_id, kernel_name) do
    Logger.info("Starting kernel #{inspect(kernel_name)} for repo #{managed_repo_id}")

    child_spec = kernel_child_spec(kernel_name)

    case DynamicSupervisor.start_child(kernel_supervisor(), child_spec) do
      {:ok, pid} ->
        track_kernel(kernel_name, managed_repo_id, pid: pid)
        {:ok, kernel_name}

      {:error, {:already_started, pid}} ->
        # Kernel already exists, track it if not already tracked
        track_kernel(kernel_name, managed_repo_id, pid: pid)
        {:ok, kernel_name}

      {:error, reason} ->
        Logger.error("Failed to start kernel #{inspect(kernel_name)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp shutdown_kernel_impl(kernel_name, state) do
    Logger.info("Shutting down kernel #{inspect(kernel_name)}")
    DynamicSupervisor.terminate_child(kernel_supervisor(), state.pid)
    untrack_kernel(kernel_name)
    :ok
  end

  defp kernel_child_spec(kernel_name) do
    # Build kernel configuration
    config = [
      name: kernel_name,
      otp_app: :jido_code,
      pod: JidoCode.Pods.Empty,
      persistence: persistence_config()
    ]

    %{
      id: kernel_name,
      start: {Jido.AgentOS.Supervisor, :start_link, [config]},
      restart: :transient,
      type: :supervisor
    }
  end

  defp persistence_config do
    case Application.get_env(:jido_code, :agent_os_persistence) do
      nil ->
        # Default to Ecto if configured
        if Code.ensure_loaded?(JidoCode.Repo) and Code.ensure_loaded?(Jido.Ecto.Storage) do
          [
            adapter: Jido.Ecto.Storage,
            repo: JidoCode.Repo
          ]
        else
          nil
        end

      config when is_list(config) ->
        case Keyword.get(config, :adapter) || Keyword.get(config, :module) do
          adapter when is_atom(adapter) ->
            if Code.ensure_loaded?(adapter), do: config, else: nil

          _other ->
            nil
        end
    end
  end

  # ETS-based tracking functions

  defp get_kernel_state(kernel_name) do
    case :ets.lookup(@table_name, kernel_name) do
      [{^kernel_name, state}] -> {:ok, state}
      [] -> :error
    end
  end

  defp track_kernel(kernel_name, managed_repo_id, extra) when is_list(extra) do
    state = %KernelState{
      managed_repo_id: managed_repo_id,
      created_at: DateTime.utc_now()
    }

    state = Enum.reduce(extra, state, fn {k, v}, acc -> Map.put(acc, k, v) end)

    :ets.insert(@table_name, {kernel_name, state})
    :ok
  end

  defp untrack_kernel(kernel_name) do
    :ets.delete(@table_name, kernel_name)
  end

  defp list_tracked_kernels do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {kernel_name, _state} -> kernel_name end)
    |> Enum.sort()
  end

  defp build_status_from_state(kernel_name, state) do
    %{
      kernel_name: kernel_name,
      managed_repo_id: state.managed_repo_id,
      supervisor_pid: Map.get(state, :pid),
      created_at: state.created_at,
      pods:
        state
        |> pod_entries()
        |> Map.values()
        |> Enum.sort_by(& &1.pod_id)
    }
  end

  defp build_pod_entry(state, pod_id, pod_module, metadata) do
    existing = pod_entries(state)[pod_id]
    incoming_metadata = Map.delete(metadata, :scope)

    merged_metadata =
      existing
      |> then(fn
        nil -> incoming_metadata
        existing_entry -> merge_pod_metadata(existing_entry.metadata, incoming_metadata)
      end)

    %{
      pod_id: pod_id,
      module: pod_module,
      scope: Map.get(metadata, :scope, :repository),
      metadata: merged_metadata,
      registered_at: (existing && existing.registered_at) || DateTime.utc_now()
    }
  end

  defp pod_entries(%KernelState{pods: pods}) when is_map(pods), do: pods

  defp pod_entries(%KernelState{pods: pods}) when is_list(pods) do
    Enum.reduce(pods, %{}, fn
      pod_id, acc when is_binary(pod_id) ->
        Map.put(acc, pod_id, %{
          pod_id: pod_id,
          module: nil,
          scope: :unknown,
          metadata: %{},
          registered_at: nil
        })

      %{pod_id: pod_id} = pod_entry, acc when is_binary(pod_id) ->
        Map.put(acc, pod_id, pod_entry)

      _other, acc ->
        acc
    end)
  end

  defp merge_pod_metadata(existing_metadata, incoming_metadata) do
    merged_metadata = Map.merge(existing_metadata, incoming_metadata)

    case {Map.get(existing_metadata, :latest_import_status), Map.get(incoming_metadata, :latest_import_status)} do
      {%{ready?: true} = existing_status, %{ready?: false}} ->
        Map.put(merged_metadata, :latest_import_status, existing_status)

      {%{ready?: true} = existing_status, nil} ->
        Map.put(merged_metadata, :latest_import_status, existing_status)

      _other ->
        merged_metadata
    end
  end

  defp kernel_supervisor do
    Application.get_env(:jido_code, :agent_os_kernel_supervisor, __MODULE__.Supervisor)
  end
end
