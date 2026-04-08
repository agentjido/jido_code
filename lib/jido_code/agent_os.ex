defmodule JidoCode.AgentOS do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
  # covers: architecture.agent_os_integration.ecto_persistence_per_kernel
  # covers: architecture.agent_os_integration.kernel_naming_convention
  @moduledoc """
  Public API for JidoCode's AgentOS integration.

  This module provides the product-local interface for managing repository-scoped
  AgentOS kernels. Each ManagedRepo gets its own kernel for isolated runtime
  operations.

  ## Architecture

  - One kernel per ManagedRepo (`:"repo_{managed_repo_id}"`)
  - Kernels are created on-demand and managed by a dynamic supervisor
  - Kernel state persists via Ecto across application restarts

  ## Usage

      # Ensure a kernel exists for a repository
      {:ok, kernel_name} = AgentOS.ensure_kernel("repo-123")

      # Check kernel status
      status = AgentOS.kernel_status("repo-123")

      # List all active kernels
      kernels = AgentOS.list_kernels()

      # Shut down a kernel when no longer needed
      :ok = AgentOS.shutdown_kernel("repo-123")

  """

  alias JidoCode.AgentOS.Manager

  @type kernel_ref :: String.t()
  @type kernel_name :: atom()

  @doc """
  Ensures a kernel exists for the given ManagedRepo ID.

  Creates a new kernel if one doesn't exist, otherwise returns the
  existing kernel reference.

  ## Examples

      iex> AgentOS.ensure_kernel("repo-123")
      {:ok, :repo_repo_123}

  """
  @spec ensure_kernel(String.t()) :: {:ok, kernel_name()} | {:error, term()}
  defdelegate ensure_kernel(managed_repo_id), to: Manager

  @doc """
  Returns the status of a kernel for the given ManagedRepo ID.

  Returns `nil` if the kernel doesn't exist.

  ## Examples

      iex> AgentOS.kernel_status("repo-123")
      %{kernel_name: :repo_repo_123, supervisor_pid: #PID<...>, pods: [...]}

      iex> AgentOS.kernel_status("nonexistent")
      nil

  """
  @spec kernel_status(String.t()) :: map() | nil
  defdelegate kernel_status(managed_repo_id), to: Manager

  @doc """
  Shuts down a kernel for the given ManagedRepo ID.

  ## Examples

      iex> AgentOS.shutdown_kernel("repo-123")
      :ok

  """
  @spec shutdown_kernel(String.t()) :: :ok
  defdelegate shutdown_kernel(managed_repo_id), to: Manager

  @doc """
  Lists all active kernels.

  ## Examples

      iex> AgentOS.list_kernels()
      [:repo_repo_123, :repo_repo_456]

  """
  @spec list_kernels() :: [kernel_name()]
  defdelegate list_kernels, to: Manager

  @doc """
  Returns the number of active kernels.

  ## Examples

      iex> AgentOS.kernel_count()
      2

  """
  @spec kernel_count :: non_neg_integer()
  def kernel_count do
    list_kernels() |> length()
  end

  @doc """
  Checks if a kernel exists for the given ManagedRepo ID.

  ## Examples

      iex> AgentOS.kernel_exists?("repo-123")
      true

      iex> AgentOS.kernel_exists?("nonexistent")
      false

  """
  @spec kernel_exists?(String.t()) :: boolean()
  def kernel_exists?(managed_repo_id) do
    !!kernel_status(managed_repo_id)
  end
end
