defmodule JidoCode.AgentWorkspace do
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.pod_cleanup_on_completion
  # covers: architecture.agent_os_integration.pod_naming_convention
  # covers: architecture.agent_os_integration.multiple_pods_parallel_execution
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
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

  alias JidoCode.Actions.{
    AnalyzeSourceCodeGraph,
    GetSourceCodeGraphStatus,
    LoadSourceCodeGraph,
    QuerySourceCodeGraph,
    RefreshSourceCodeGraph
  }

  alias JidoCode.Pods.SourceCodeGraphPod
  alias JidoCode.SourceCodeGraph

  @type managed_repo_id :: String.t()
  @type work_item_id :: String.t()
  @type kernel_name :: atom()
  @type pod_name :: atom()
  @type source_code_graph_summary :: map()

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
  def complete_work(_managed_repo_id, _work_item_id) do
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
  def active_work_items(_managed_repo_id) do
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
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, ""),
         _pod_name = pod_name(work_item_id) do
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
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, ""),
         _pod_name = pod_name(work_item_id) do
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
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, ""),
         _pod_name = pod_name(work_item_id) do
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
      {:ok,
       %{
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
  def parallel_plan(_managed_repo_id, work_item_ids) when is_list(work_item_ids) do
    # TODO: Implement parallel planning
    # For now, return placeholder response
    results =
      Map.new(work_item_ids, fn id ->
        {id, %{plan: "placeholder", work_item_id: id}}
      end)

    {:ok, results}
  end

  ## Source Code Graph

  @doc """
  Ensures the repository-scoped SourceCodeGraphPod is configured for a ManagedRepo.

  Returns a product-owned summary of the capability rather than pod internals.
  """
  @spec ensure_source_code_graph_pod(managed_repo_id(), String.t(), keyword()) ::
          {:ok, source_code_graph_summary()} | {:error, term()}
  def ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts \\ []) do
    with :ok <- ensure_source_code_graph_enabled(opts),
         {:ok, pod_metadata} <- SourceCodeGraph.pod_metadata(managed_repo_id, workspace_path, opts),
         {:ok, pod_entry} <-
           Manager.ensure_pod(
             managed_repo_id,
             SourceCodeGraph.pod_id(),
             SourceCodeGraphPod,
             pod_metadata
           ) do
      {:ok, source_code_graph_summary(managed_repo_id, pod_entry)}
    end
  end

  @doc """
  Returns the current repository-scoped source-code graph status.
  """
  @spec source_code_graph_status(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def source_code_graph_status(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <- GetSourceCodeGraphStatus.run(source_code_graph_params(opts), action_context) do
      {:ok, result}
    end
  end

  @doc """
  Runs full-profile ontology analysis for the repository-scoped source graph capability.
  """
  @spec analyze_source_code_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def analyze_source_code_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <- AnalyzeSourceCodeGraph.run(source_code_graph_params(opts), action_context) do
      {:ok, result}
    end
  end

  @doc """
  Loads ontology/schema and project individuals into the repository-scoped source graph.
  """
  @spec load_source_code_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def load_source_code_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <- LoadSourceCodeGraph.run(source_code_graph_params(opts), action_context),
         {:ok, _pod_entry} <-
           persist_source_code_graph_status(managed_repo_id, result.latest_import_status) do
      {:ok, result}
    end
  end

  @doc """
  Refreshes the repository-scoped source graph by replacing the named graph coherently.
  """
  @spec refresh_source_code_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def refresh_source_code_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <- RefreshSourceCodeGraph.run(source_code_graph_params(opts), action_context),
         {:ok, _pod_entry} <-
           persist_source_code_graph_status(managed_repo_id, result.latest_import_status) do
      {:ok, result}
    end
  end

  @doc """
  Executes a structured semantic query over the repository-scoped source graph.
  """
  @spec query_source_code_graph(managed_repo_id(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def query_source_code_graph(managed_repo_id, workspace_path, sparql, opts \\ [])
      when is_binary(sparql) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <-
           QuerySourceCodeGraph.run(
             Map.put(source_code_graph_params(opts), :sparql, sparql),
             action_context
           ) do
      {:ok, result}
    end
  end

  ## Private Functions

  defp pod_name(work_item_id) do
    # Convert work_item_id to a valid atom for pod name
    "work_#{work_item_id}"
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp ensure_pods_workspace_path(_kernel_name, _pod_name, _workspace_path) do
    # TODO: Set workspace path in the pod's ProjectContext agent
    # For now, this is a no-op since we don't have dynamic pod management
    {:ok, nil}
  end

  defp ensure_source_code_graph_enabled(opts) do
    if SourceCodeGraph.capability_enabled?(opts) do
      :ok
    else
      {:error, :source_code_graph_disabled}
    end
  end

  defp source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
    latest_import_status =
      managed_repo_id
      |> Manager.pod_status(SourceCodeGraph.pod_id())
      |> case do
        nil -> nil
        pod_entry -> get_in(pod_entry, [:metadata, :latest_import_status])
      end

    context = %{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      latest_import_status: latest_import_status,
      graph: %{revision: Keyword.get(opts, :revision)}
    }

    with {:ok, _graph_context} <- SourceCodeGraph.graph_context(managed_repo_id, workspace_path, opts) do
      {:ok, context}
    end
  end

  defp persist_source_code_graph_status(managed_repo_id, latest_import_status) when is_map(latest_import_status) do
    Manager.update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), %{
      latest_import_status: latest_import_status
    })
  end

  defp source_code_graph_summary(managed_repo_id, pod_entry) do
    %{
      managed_repo_id: managed_repo_id,
      pod_id: pod_entry.pod_id,
      graph_name: get_in(pod_entry, [:metadata, :graph_name]),
      ontology_profile: get_in(pod_entry, [:metadata, :ontology_profile]),
      workspace_path: get_in(pod_entry, [:metadata, :workspace_path]),
      graph_store_path: get_in(pod_entry, [:metadata, :graph_store_path]),
      ready?: get_in(pod_entry, [:metadata, :latest_import_status, :ready?]) || false
    }
  end

  defp source_code_graph_params(opts) do
    %{revision: Keyword.get(opts, :revision)}
  end
end
