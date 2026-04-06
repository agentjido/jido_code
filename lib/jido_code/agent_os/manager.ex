defmodule JidoCode.AgentOS.Manager do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
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
      kernel_name: kernel_name,
      otp_app: :jido_code,
      pod: JidoCode.AgentOS.Pods.Empty,
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
        if Code.ensure_loaded?(JidoCode.Repo) do
          [
            adapter: Jido.Ecto.Storage,
            repo: JidoCode.Repo
          ]
        else
          nil
        end

      config when is_list(config) ->
        config
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
      pods: Map.get(state, :pods, [])
    }
  end

  defp kernel_supervisor do
    Application.get_env(:jido_code, :agent_os_kernel_supervisor, __MODULE__.Supervisor)
  end
end
