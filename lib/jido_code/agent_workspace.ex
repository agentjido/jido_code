defmodule JidoCode.AgentWorkspace do
  # covers: architecture.agent_os_integration.workspace_context
  @moduledoc """
  Context module for AgentOS workspace operations.

  Provides a clean API for Phoenix controllers and LiveViews to interact
  with AgentOS kernels and pods without exposing the internal topology.

  ## Kernel Lifecycle

  Kernels are created per ManagedRepo and managed through this context.

  ## Pod Operations

  CodingPods are created per WorkItem and provide isolated execution
  contexts for AI-powered coding work.

  ## Work Execution

  Functions for planning, executing, and reviewing work through agents.
  """

  alias JidoCode.AgentOS.Manager
  alias JidoCode.Pods.{RepoPod, CodingPod}

  @type managed_repo_id :: String.t()
  @type work_item_id :: String.t()
  @type kernel_name :: atom()
  @type pod_name :: atom()

  ## Kernel Lifecycle

  @doc """
  Ensures a kernel exists for the given ManagedRepo ID.

  Creates a new kernel if one doesn't exist, otherwise returns the
  existing kernel reference.

  ## Examples

      iex> AgentWorkspace.ensure_kernel("repo-123")
      {:ok, :repo_123}

  """
  @spec ensure_kernel(managed_repo_id()) :: {:ok, kernel_name()} | {:error, term()}
  def ensure_kernel(managed_repo_id) when is_binary(managed_repo_id) do
    Manager.ensure_kernel(managed_repo_id)
  end

  @doc """
  Returns the status of a kernel for the given ManagedRepo ID.

  ## Examples

      iex> AgentWorkspace.kernel_status("repo-123")
      %{kernel_name: :repo_123, supervisor_pid: #PID<...>, pods: [...]}

      iex> AgentWorkspace.kernel_status("nonexistent")
      nil

  """
  @spec kernel_status(managed_repo_id()) :: map() | nil
  def kernel_status(managed_repo_id) when is_binary(managed_repo_id) do
    Manager.kernel_status(managed_repo_id)
  end

  @doc """
  Shuts down a kernel for the given ManagedRepo ID.

  ## Examples

      iex> AgentWorkspace.shutdown_kernel("repo-123")
      :ok

  """
  @spec shutdown_kernel(managed_repo_id()) :: :ok
  def shutdown_kernel(managed_repo_id) when is_binary(managed_repo_id) do
    Manager.shutdown_kernel(managed_repo_id)
  end

  @doc """
  Lists all active kernels.

  ## Examples

      iex> AgentWorkspace.list_kernels()
      [:repo_123, :repo_456]

  """
  @spec list_kernels() :: [kernel_name()]
  def list_kernels do
    Manager.list_kernels()
  end

  ## Pod Lifecycle

  @doc """
  Ensures a CodingPod exists for the given WorkItem.

  Creates a new CodingPod if one doesn't exist for the WorkItem,
  configured with the workspace path and other context.

  ## Examples

      iex> AgentWorkspace.ensure_coding_pod("repo-123", "work-item-1", "/path/to/workspace")
      {:ok, :work_item_1}

  """
  @spec ensure_coding_pod(managed_repo_id(), work_item_id(), String.t()) :: {:ok, pod_name()} | {:error, term()}
  def ensure_coding_pod(managed_repo_id, work_item_id, workspace_path) do
    with {:ok, kernel_name} <- ensure_kernel(managed_repo_id),
         pod_name = pod_name(work_item_id),
         {:ok, _} <- ensure_pods_workspace_path(kernel_name, pod_name, workspace_path) do
      {:ok, pod_name}
    end
  end

  @doc """
  Completes work for a WorkItem by shutting down its CodingPod.

  ## Examples

      iex> AgentWorkspace.complete_work("repo-123", "work-item-1")
      :ok

  """
  @spec complete_work(managed_repo_id(), work_item_id()) :: :ok
  def complete_work(managed_repo_id, work_item_id) do
    # TODO: Implement pod shutdown
    # For now, this is a no-op since we don't have dynamic pod management yet
    :ok
  end

  @doc """
  Lists active WorkItems (CodingPods) for a ManagedRepo.

  ## Examples

      iex> AgentWorkspace.active_work_items("repo-123")
      ["work-item-1", "work-item-2"]

  """
  @spec active_work_items(managed_repo_id()) :: [work_item_id()]
  def active_work_items(managed_repo_id) do
    # TODO: Implement active work tracking
    # For now, return empty list
    []
  end

  ## Work Execution

  @doc """
  Plans work by routing to the planner agent.

  Sends a planning request to the planner agent within the WorkItem's
  CodingPod and returns the result.

  ## Examples

      iex> AgentWorkspace.plan_work("repo-123", "work-item-1", "Implement user authentication")
      {:ok, %Plan{steps: [...]}}

  """
  @spec plan_work(managed_repo_id(), work_item_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def plan_work(managed_repo_id, work_item_id, instruction) do
    with {:ok, kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, ""),
         pod_name = pod_name(work_item_id) do
      # TODO: Route to planner agent
      # For now, return a placeholder response
      {:ok, %{plan: "placeholder", instruction: instruction}}
    end
  end

  @doc """
  Executes work by routing to the coder agent.

  Sends an implementation request to the coder agent within the WorkItem's
  CodingPod and returns the result.

  ## Examples

      iex> AgentWorkspace.execute_work("repo-123", "work-item-1", "Implement the login function")
      {:ok, %{changes: [...]}}

  """
  @spec execute_work(managed_repo_id(), work_item_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def execute_work(managed_repo_id, work_item_id, instruction) do
    with {:ok, kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, ""),
         pod_name = pod_name(work_item_id) do
      # TODO: Route to coder agent
      # For now, return a placeholder response
      {:ok, %{changes: [], instruction: instruction}}
    end
  end

  @doc """
  Reviews work by routing to the reviewer agent.

  Sends a review request to the reviewer agent within the WorkItem's
  CodingPod and returns the result.

  ## Examples

      iex> AgentWorkspace.review_work("repo-123", "work-item-1", "Review the login implementation")
      {:ok, %{feedback: [...]}}

  """
  @spec review_work(managed_repo_id(), work_item_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def review_work(managed_repo_id, work_item_id, instruction) do
    with {:ok, kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, ""),
         pod_name = pod_name(work_item_id) do
      # TODO: Route to reviewer agent
      # For now, return a placeholder response
      {:ok, %{feedback: [], instruction: instruction}}
    end
  end

  @doc """
  Executes the full workflow: plan → code → review.

  Coordinates all three agents within the WorkItem's CodingPod
  and returns the combined result.

  ## Examples

      iex> AgentWorkspace.full_workflow("repo-123", "work-item-1", "Add user settings page")
      {:ok, %{plan: [...], changes: [...], feedback: [...]}}

  """
  @spec full_workflow(managed_repo_id(), work_item_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def full_workflow(managed_repo_id, work_item_id, instruction) do
    with {:ok, plan} <- plan_work(managed_repo_id, work_item_id, instruction),
         {:ok, changes} <- execute_work(managed_repo_id, work_item_id, instruction),
         {:ok, feedback} <- review_work(managed_repo_id, work_item_id, instruction) do
      {:ok, %{
        plan: plan,
        changes: changes,
        feedback: feedback
      }}
    end
  end

  ## Parallel Execution

  @doc """
  Plans multiple WorkItems in parallel using separate CodingPod instances.

  ## Examples

      iex> AgentWorkspace.parallel_plan("repo-123", ["work-1", "work-2"])
      {:ok, %{"work-1" => %{plan: [...]}, "work-2" => %{plan: [...]}}}

  """
  @spec parallel_plan(managed_repo_id(), [work_item_id()]) :: {:ok, map()} | {:error, term()}
  def parallel_plan(managed_repo_id, work_item_ids) when is_list(work_item_ids) do
    # TODO: Implement parallel planning
    # For now, return placeholder response
    results =
      Map.new(work_item_ids, fn id ->
        {id, %{plan: "placeholder", work_item_id: id}}
      end)

    {:ok, results}
  end

  ## Private Functions

  defp pod_name(work_item_id) do
    # Convert work_item_id to a valid atom for pod name
    "work_#{work_item_id}"
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp ensure_pods_workspace_path(kernel_name, pod_name, workspace_path) do
    # TODO: Set workspace path in the pod's ProjectContext agent
    # For now, this is a no-op since we don't have dynamic pod management
    {:ok, nil}
  end
end
