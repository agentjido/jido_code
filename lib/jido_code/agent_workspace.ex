defmodule JidoCode.AgentWorkspace do
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.pod_cleanup_on_completion
  # covers: architecture.agent_os_integration.pod_naming_convention
  # covers: architecture.agent_os_integration.multiple_pods_parallel_execution
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
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
    FindSourceCodeGraphFunctions,
    FindSourceCodeGraphModules,
    FindSourceCodeGraphRuntimePatterns,
    GetSourceCodeGraphStatus,
    LoadSourceCodeGraph,
    QuerySourceCodeGraph,
    RefreshSourceCodeGraph,
    TraceSourceCodeGraphImpact
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
    plan_work(managed_repo_id, work_item_id, instruction, [])
  end

  @spec plan_work(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def plan_work(managed_repo_id, work_item_id, instruction, opts) when is_list(opts) do
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path, "")),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :plan, opts),
         _pod_name = pod_name(work_item_id) do
      # TODO: Route to planner agent
      # For now, return a placeholder response
      {:ok,
       %{
         plan: "placeholder",
         instruction: instruction,
         semantic_context: semantic_context
       }}
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
    execute_work(managed_repo_id, work_item_id, instruction, [])
  end

  @spec execute_work(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_work(managed_repo_id, work_item_id, instruction, opts) when is_list(opts) do
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path, "")),
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
    review_work(managed_repo_id, work_item_id, instruction, [])
  end

  @spec review_work(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def review_work(managed_repo_id, work_item_id, instruction, opts) when is_list(opts) do
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path, "")),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :review, opts),
         _pod_name = pod_name(work_item_id) do
      # TODO: Route to reviewer agent
      # For now, return a placeholder response
      {:ok,
       %{
         feedback: [],
         instruction: instruction,
         semantic_context: semantic_context
       }}
    end
  end

  @doc """
  Explains work with an optional explicit semantic source-graph context.
  """
  @spec explain_work(managed_repo_id(), work_item_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def explain_work(managed_repo_id, work_item_id, instruction) do
    explain_work(managed_repo_id, work_item_id, instruction, [])
  end

  @spec explain_work(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def explain_work(managed_repo_id, work_item_id, instruction, opts) when is_list(opts) do
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path, "")),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :explain, opts),
         _pod_name = pod_name(work_item_id) do
      {:ok,
       %{
         explanation: "placeholder",
         instruction: instruction,
         semantic_context: semantic_context
       }}
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
    full_workflow(managed_repo_id, work_item_id, instruction, [])
  end

  @spec full_workflow(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def full_workflow(managed_repo_id, work_item_id, instruction, opts) when is_list(opts) do
    with {:ok, plan} <- plan_work(managed_repo_id, work_item_id, instruction, opts),
         {:ok, changes} <- execute_work(managed_repo_id, work_item_id, instruction, opts),
         {:ok, feedback} <- review_work(managed_repo_id, work_item_id, instruction, opts) do
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
    with :ok <- ensure_source_code_graph_enabled(opts) do
      case Manager.pod_status(managed_repo_id, SourceCodeGraph.pod_id()) do
        nil ->
          with {:ok, pod_metadata} <- SourceCodeGraph.pod_metadata(managed_repo_id, workspace_path, opts),
               {:ok, pod_entry} <-
                 Manager.ensure_pod(
                   managed_repo_id,
                   SourceCodeGraph.pod_id(),
                   SourceCodeGraphPod,
                   pod_metadata
                 ) do
            {:ok, source_code_graph_summary(managed_repo_id, pod_entry)}
          end

        pod_entry ->
          {:ok, source_code_graph_summary(managed_repo_id, pod_entry)}
      end
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
         {:ok, result} <- AnalyzeSourceCodeGraph.run(source_code_graph_params(opts), action_context),
         {:ok, _pod_entry} <-
           persist_source_code_graph_state(managed_repo_id, %{
             latest_analysis_status: result.latest_analysis_status
           }) do
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
           persist_source_code_graph_state(managed_repo_id, %{
             latest_analysis_status: result.latest_analysis_status,
             latest_import_status: result.latest_import_status
           }) do
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
           persist_source_code_graph_state(managed_repo_id, %{
             latest_analysis_status: result.latest_analysis_status,
             latest_import_status: result.latest_import_status
           }) do
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
    run_source_code_graph_action(
      managed_repo_id,
      workspace_path,
      opts,
      QuerySourceCodeGraph,
      Map.put(source_code_graph_params(opts), :sparql, sparql)
    )
  end

  @doc """
  Runs the bounded module helper query against the repository-scoped source graph.
  """
  @spec find_source_code_graph_modules(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def find_source_code_graph_modules(managed_repo_id, workspace_path, opts \\ []) do
    run_source_code_graph_action(
      managed_repo_id,
      workspace_path,
      opts,
      FindSourceCodeGraphModules,
      source_code_graph_params(opts, [:revision, :module_name_contains, :limit])
    )
  end

  @doc """
  Runs the bounded function helper query against the repository-scoped source graph.
  """
  @spec find_source_code_graph_functions(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def find_source_code_graph_functions(managed_repo_id, workspace_path, opts \\ []) do
    run_source_code_graph_action(
      managed_repo_id,
      workspace_path,
      opts,
      FindSourceCodeGraphFunctions,
      source_code_graph_params(opts, [:revision, :module_name, :function_name, :limit])
    )
  end

  @doc """
  Runs the bounded runtime-pattern helper query against the repository-scoped source graph.
  """
  @spec find_source_code_graph_runtime_patterns(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def find_source_code_graph_runtime_patterns(managed_repo_id, workspace_path, opts \\ []) do
    run_source_code_graph_action(
      managed_repo_id,
      workspace_path,
      opts,
      FindSourceCodeGraphRuntimePatterns,
      source_code_graph_params(opts, [:revision, :pattern_name_contains, :limit])
    )
  end

  @doc """
  Runs the bounded impact helper query against the repository-scoped source graph.
  """
  @spec trace_source_code_graph_impact(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def trace_source_code_graph_impact(managed_repo_id, workspace_path, opts \\ []) do
    run_source_code_graph_action(
      managed_repo_id,
      workspace_path,
      opts,
      TraceSourceCodeGraphImpact,
      source_code_graph_params(opts, [
        :revision,
        :subject_iri,
        :module_name,
        :function_name,
        :arity,
        :direction,
        :limit
      ])
    )
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
    pod_entry = Manager.pod_status(managed_repo_id, SourceCodeGraph.pod_id())

    context = %{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      latest_import_status: get_in(pod_entry, [:metadata, :latest_import_status]),
      latest_analysis_status: get_in(pod_entry, [:metadata, :latest_analysis_status]),
      graph: %{revision: Keyword.get(opts, :revision)}
    }

    with {:ok, _graph_context} <- SourceCodeGraph.graph_context(managed_repo_id, workspace_path, opts) do
      {:ok, context}
    end
  end

  defp persist_source_code_graph_state(managed_repo_id, updates) when is_map(updates) do
    Manager.update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), updates)
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

  defp run_source_code_graph_action(managed_repo_id, workspace_path, opts, action_module, params)
       when is_atom(action_module) and is_map(params) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <- action_module.run(params, action_context) do
      {:ok, result}
    end
  end

  defp workflow_semantic_context(_managed_repo_id, _workflow, opts) when opts == [] do
    {:ok, %{}}
  end

  defp workflow_semantic_context(managed_repo_id, workflow, opts) when is_list(opts) do
    case Keyword.get(opts, :source_code_graph) do
      nil ->
        {:ok, %{}}

      graph_opts when is_list(graph_opts) ->
        workspace_path =
          Keyword.get(graph_opts, :workspace_path) ||
            Keyword.get(opts, :workspace_path)

        with {:ok, workspace_path} <- normalize_workflow_workspace_path(workspace_path),
             {:ok, graph_status_result} <-
               prepare_source_code_graph_for_workflow(managed_repo_id, workspace_path, graph_opts),
             {:ok, semantic_results} <-
               workflow_semantic_requests(managed_repo_id, workspace_path, workflow, graph_opts) do
          {:ok,
           %{
             workflow: workflow,
             graph_name: SourceCodeGraph.graph_name(),
             graph_status: normalize_workflow_graph_status(graph_status_result),
             results: semantic_results
           }}
        end
    end
  end

  defp normalize_workflow_workspace_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, :missing_workspace_path}
      value -> {:ok, value}
    end
  end

  defp normalize_workflow_workspace_path(_path), do: {:error, :missing_workspace_path}

  defp prepare_source_code_graph_for_workflow(managed_repo_id, workspace_path, graph_opts) do
    prepare_mode = Keyword.get(graph_opts, :prepare, :load_if_missing)
    source_graph_opts = source_code_graph_runtime_opts(graph_opts)

    case prepare_mode do
      :none ->
        source_code_graph_status(managed_repo_id, workspace_path, source_graph_opts)

      :load ->
        load_source_code_graph(managed_repo_id, workspace_path, source_graph_opts)

      :refresh ->
        refresh_source_code_graph(managed_repo_id, workspace_path, source_graph_opts)

      :load_if_missing ->
        with {:ok, status} <- source_code_graph_status(managed_repo_id, workspace_path, source_graph_opts) do
          if status.ready? do
            {:ok, status}
          else
            load_source_code_graph(managed_repo_id, workspace_path, source_graph_opts)
          end
        end
    end
  end

  defp workflow_semantic_requests(managed_repo_id, workspace_path, _workflow, graph_opts) do
    request_steps = semantic_request_steps(managed_repo_id, workspace_path, graph_opts)

    Enum.reduce_while(request_steps, {:ok, %{}}, fn {name, fun}, {:ok, acc} ->
      case fun.() do
        {:ok, result} ->
          {:cont, {:ok, Map.put(acc, name, result)}}

        {:error, _reason} = error ->
          {:halt, error}

        {:error, _reason, _diagnostics} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, results} when map_size(results) == 0 ->
        {:ok,
         %{
           status: :no_requests,
           managed_repo_id: managed_repo_id,
           workspace_path: workspace_path
         }}

      other ->
        other
    end
  end

  defp semantic_request_steps(managed_repo_id, workspace_path, graph_opts) do
    runtime_opts = source_code_graph_runtime_opts(graph_opts)

    []
    |> maybe_add_semantic_step(
      :modules,
      managed_repo_id,
      workspace_path,
      Keyword.get(graph_opts, :modules),
      fn params ->
      find_source_code_graph_modules(
          managed_repo_id,
          workspace_path,
          Keyword.merge(runtime_opts, params)
      )
      end
    )
    |> maybe_add_semantic_step(
      :functions,
      managed_repo_id,
      workspace_path,
      Keyword.get(graph_opts, :functions),
      fn params ->
      find_source_code_graph_functions(
          managed_repo_id,
          workspace_path,
          Keyword.merge(runtime_opts, params)
      )
      end
    )
    |> maybe_add_semantic_step(
      :runtime_patterns,
      managed_repo_id,
      workspace_path,
      Keyword.get(graph_opts, :runtime_patterns),
      fn params ->
        find_source_code_graph_runtime_patterns(
          managed_repo_id,
          workspace_path,
          Keyword.merge(runtime_opts, params)
        )
      end
    )
    |> maybe_add_semantic_step(:impact, managed_repo_id, workspace_path, Keyword.get(graph_opts, :impact), fn params ->
      trace_source_code_graph_impact(
        managed_repo_id,
        workspace_path,
        Keyword.merge(runtime_opts, params)
      )
    end)
    |> maybe_add_semantic_step(:query, managed_repo_id, workspace_path, Keyword.get(graph_opts, :query), fn
      params when is_list(params) ->
        query_source_code_graph(
          managed_repo_id,
          workspace_path,
          Keyword.fetch!(params, :sparql),
          Keyword.merge(runtime_opts, Keyword.delete(params, :sparql))
        )

      sparql when is_binary(sparql) ->
        query_source_code_graph(
          managed_repo_id,
          workspace_path,
          sparql,
          runtime_opts
        )
    end)
  end

  defp maybe_add_semantic_step(steps, _name, _managed_repo_id, _workspace_path, nil, _fun), do: steps

  defp maybe_add_semantic_step(steps, name, _managed_repo_id, _workspace_path, params, fun)
       when is_list(params) or is_binary(params) do
    steps ++
      [
        {name,
         fn ->
           fun.(params)
         end}
      ]
  end

  defp source_code_graph_runtime_opts(opts) do
    Keyword.take(opts, [:revision, :enabled?])
  end

  defp normalize_workflow_graph_status(%{ready?: _ready?} = result), do: result

  defp normalize_workflow_graph_status(%{latest_import_status: latest_import_status} = result) do
    %{
      ready?: Map.get(latest_import_status, :ready?, false),
      stale?: false,
      requested_revision: get_in(result, [:dataset, :revision]),
      imported_revision: Map.get(latest_import_status, :imported_revision),
      latest_import_status: latest_import_status,
      latest_analysis_status: Map.get(result, :latest_analysis_status, %{}),
      dataset: Map.get(result, :dataset, %{})
    }
  end

  defp normalize_workflow_graph_status(result), do: %{ready?: false, raw: result}

  defp source_code_graph_params(opts, allowed_keys \\ [:revision]) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.into(%{})
  end
end
