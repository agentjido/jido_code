defmodule JidoCode.AgentWorkspace do
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.pod_cleanup_on_completion
  # covers: architecture.agent_os_integration.pod_naming_convention
  # covers: architecture.agent_os_integration.multiple_pods_parallel_execution
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  # covers: architecture.agent_os_integration.repository_work_queue_is_bounded
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_capacity_limits_fail_closed
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.agent_os_integration.source_code_graph_stale_and_recovery_state_stays_workspace_bound
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
  alias JidoCode.Agents.{Coder, Explainer, Planner, Reviewer}
  alias JidoCode.Pods.{CodingPod, RepoPod}

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

  alias JidoCode.AgentWorkspace.RuntimeSpecialistRunner
  alias JidoCode.Pods.SourceCodeGraphPod
  alias JidoCode.SourceCodeGraph
  alias Jido.AgentOS.ManagerSupervisor
  alias Jido.AgentOS.Naming
  alias Jido.AgentOS.Persistence
  alias Jido.AgentOS.Pod, as: AgentOSPod
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Pod.Runtime, as: PodRuntime

  @type managed_repo_id :: String.t()
  @type work_item_id :: String.t()
  @type kernel_name :: atom()
  @type pod_name :: atom()
  @type source_code_graph_summary :: map()
  @repo_pod_id "repo-pod"

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
    with {:ok, kernel_name} <- Manager.ensure_kernel(managed_repo_id),
         {:ok, _repo_pod_entry, _repo_pod_pid} <- ensure_repo_pod_runtime(managed_repo_id),
         :ok <- restore_persisted_runtime_pods(managed_repo_id) do
      {:ok, kernel_name}
    end
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
    with {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         :ok <- admit_work_item(managed_repo_id, work_item_id),
         {:ok, resolved_workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, workspace_path),
         {:ok, _pod_entry, _pod_pid} <-
           ensure_runtime_coding_pod(managed_repo_id, work_item_id, resolved_workspace_path) do
      {:ok, pod_name(work_item_id)}
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
    pod_id = coding_pod_id(work_item_id)

    case Manager.pod_status(managed_repo_id, pod_id) do
      nil ->
        :ok

      pod_entry ->
        maybe_stop_runtime_pod(pod_entry)

        _ =
          Manager.update_pod_metadata(managed_repo_id, pod_id, %{
            runtime_pid: nil,
            runtime_status: :completed,
            completed_at: DateTime.utc_now(),
            latest_failure: nil
          })

        :ok
    end
  end

  @doc """
  Lists active WorkItems (CodingPods) for a ManagedRepo.

  ## Examples

      iex> AgentWorkspace.active_work_items("repo-123")
      ["work-item-1", "work-item-2"]

  """
  @spec active_work_items(managed_repo_id()) :: [work_item_id()]
  def active_work_items(managed_repo_id) do
    managed_repo_id
    |> Manager.list_pods()
    |> Enum.filter(&active_coding_pod?/1)
    |> Enum.map(&get_in(&1, [:metadata, :work_item_id]))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
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
    with {:ok, workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path)),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :plan, opts),
         {:ok, planner_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :planner),
         {:ok, response} <-
           run_specialist(
             Planner,
             planner_pid,
             agent_instruction(:plan, instruction, semantic_context),
             managed_repo_id,
             workspace_path,
             semantic_context,
             opts
           ) do
      result = %{
        plan: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context
      }

      persist_coding_pod_result(managed_repo_id, work_item_id, :planning, %{last_plan: result})
      {:ok, result}
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
    with {:ok, workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path)),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :execute, opts),
         {:ok, coder_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :coder),
         {:ok, response} <-
           run_specialist(
             Coder,
             coder_pid,
             agent_instruction(:execute, instruction, semantic_context),
             managed_repo_id,
             workspace_path,
             semantic_context,
             opts
           ) do
      result = %{
        changes: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context
      }

      persist_coding_pod_result(managed_repo_id, work_item_id, :coding, %{last_changes: result})
      {:ok, result}
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
    with {:ok, workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path)),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :review, opts),
         {:ok, reviewer_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :reviewer),
         {:ok, response} <-
           run_specialist(
             Reviewer,
             reviewer_pid,
             agent_instruction(:review, instruction, semantic_context),
             managed_repo_id,
             workspace_path,
             semantic_context,
             opts
           ) do
      result = %{
        feedback: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context
      }

      persist_coding_pod_result(managed_repo_id, work_item_id, :reviewing, %{last_review: result})
      {:ok, result}
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
    with {:ok, workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path)),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :explain, opts),
         {:ok, explainer_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :explainer),
         {:ok, response} <-
           run_specialist(
             Explainer,
             explainer_pid,
             agent_instruction(:explain, instruction, semantic_context),
             managed_repo_id,
             workspace_path,
             semantic_context,
             opts
           ) do
      result = %{
        explanation: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context
      }

      persist_coding_pod_result(managed_repo_id, work_item_id, :explaining, %{last_explanation: result})
      {:ok, result}
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
  def parallel_plan(managed_repo_id, work_item_ids) when is_list(work_item_ids) do
    existing_work_items = MapSet.new(active_work_items(managed_repo_id))

    if Enum.all?(work_item_ids, &MapSet.member?(existing_work_items, &1)) do
      results =
        work_item_ids
        |> Task.async_stream(
          fn work_item_id ->
            {work_item_id, plan_work(managed_repo_id, work_item_id, "Plan work item #{work_item_id}")}
          end,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.reduce_while(%{}, fn
          {:ok, {work_item_id, {:ok, result}}}, acc ->
            {:cont, Map.put(acc, work_item_id, result)}

          {:ok, {work_item_id, {:error, reason}}}, _acc ->
            {:halt, {:error, {:parallel_plan_failed, work_item_id, reason}}}

          {:exit, reason}, _acc ->
            {:halt, {:error, reason}}
        end)

      case results do
        {:error, _reason} = error -> error
        result_map -> {:ok, result_map}
      end
    else
      {:error, :missing_workspace_path}
    end
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
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
      case AnalyzeSourceCodeGraph.run(source_code_graph_params(opts), action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_source_code_graph_state(managed_repo_id, %{
                   latest_analysis_status: result.latest_analysis_status,
                   latest_failure: nil
                 }) do
            {:ok, result}
          end

        {:error, reason, diagnostics} ->
          persist_source_code_graph_failure(
            managed_repo_id,
            :analyze,
            reason,
            diagnostics,
            %{latest_analysis_status: diagnostics}
          )

          {:error, reason, diagnostics}
      end
    end
  end

  @doc """
  Loads ontology/schema and project individuals into the repository-scoped source graph.
  """
  @spec load_source_code_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def load_source_code_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
      case LoadSourceCodeGraph.run(source_code_graph_params(opts), action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_source_code_graph_state(managed_repo_id, %{
                   latest_analysis_status: result.latest_analysis_status,
                   latest_import_status: result.latest_import_status,
                   latest_failure: nil
                 }) do
            {:ok, result}
          end

        {:error, reason, diagnostics} ->
          persist_source_code_graph_failure(
            managed_repo_id,
            :load,
            reason,
            diagnostics,
            maybe_analysis_update(diagnostics)
          )

          {:error, reason, diagnostics}
      end
    end
  end

  @doc """
  Refreshes the repository-scoped source graph by replacing the named graph coherently.
  """
  @spec refresh_source_code_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def refresh_source_code_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
      case RefreshSourceCodeGraph.run(source_code_graph_params(opts), action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_source_code_graph_state(managed_repo_id, %{
                   latest_analysis_status: result.latest_analysis_status,
                   latest_import_status: result.latest_import_status,
                   latest_failure: nil
                 }) do
            {:ok, result}
          end

        {:error, reason, diagnostics} ->
          persist_source_code_graph_failure(
            managed_repo_id,
            :refresh,
            reason,
            diagnostics,
            maybe_analysis_update(diagnostics)
          )

          {:error, reason, diagnostics}
      end
    end
  end

  @doc """
  Recovers repository-scoped source graph state after analysis, load, refresh, or query failures.
  """
  @spec recover_source_code_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def recover_source_code_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, status} <- source_code_graph_status(managed_repo_id, workspace_path, opts) do
      recovery_action = source_code_graph_recovery_action(status, opts)

      case recovery_action do
        :none ->
          {:ok,
           %{
             status: :source_code_graph_recovery_not_needed,
             recovery_action: :none,
             graph_status: status
           }}

        action ->
          case run_source_code_graph_recovery(managed_repo_id, workspace_path, action, opts) do
            {:ok, result} ->
              {:ok,
               %{
                 status: :source_code_graph_recovered,
                 recovery_action: action,
                 graph_status: normalize_workflow_graph_status(result),
                 result: result
               }}

            {:error, _reason} = error ->
              error

            {:error, _reason, _diagnostics} = error ->
              error
          end
      end
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
      Map.put(source_code_graph_params(opts, [:revision, :allow_stale?]), :sparql, sparql)
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
      source_code_graph_params(opts, [:revision, :allow_stale?, :module_name_contains, :limit])
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
      source_code_graph_params(opts, [:revision, :allow_stale?, :module_name, :function_name, :limit])
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
      source_code_graph_params(opts, [:revision, :allow_stale?, :pattern_name_contains, :limit])
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
        :allow_stale?,
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

  defp coding_pod_id(work_item_id), do: "coding-pod-#{work_item_id}"

  defp ensure_repo_pod_runtime(managed_repo_id) do
    ensure_runtime_pod(
      managed_repo_id,
      @repo_pod_id,
      RepoPod,
      %{
        scope: :repository,
        managed_repo_id: managed_repo_id,
        runtime_status: :running
      },
      %{managed_repo_id: managed_repo_id}
    )
  end

  defp ensure_runtime_coding_pod(managed_repo_id, work_item_id, workspace_path) do
    ensure_runtime_pod(
      managed_repo_id,
      coding_pod_id(work_item_id),
      CodingPod,
      %{
        scope: :work_item,
        managed_repo_id: managed_repo_id,
        work_item_id: work_item_id,
        workspace_path: workspace_path,
        runtime_status: :running
      },
      %{
        managed_repo_id: managed_repo_id,
        work_item_id: work_item_id,
        workspace_path: workspace_path
      }
    )
  end

  defp restore_persisted_runtime_pods(managed_repo_id) do
    managed_repo_id
    |> Manager.list_pods()
    |> Enum.reject(&(&1.pod_id == @repo_pod_id))
    |> Enum.reduce_while(:ok, fn pod_entry, :ok ->
      case pod_entry do
        %{module: CodingPod, metadata: %{work_item_id: work_item_id, workspace_path: workspace_path} = metadata}
        when is_binary(work_item_id) and is_binary(workspace_path) ->
          if restorable_coding_pod?(metadata) do
            case ensure_runtime_coding_pod(managed_repo_id, work_item_id, workspace_path) do
              {:ok, _pod_entry, _pod_pid} -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          else
            {:cont, :ok}
          end

        _other ->
          {:cont, :ok}
      end
    end)
  end

  defp restorable_coding_pod?(metadata) when is_map(metadata) do
    case Map.get(metadata, :runtime_status) do
      :completed -> false
      nil -> true
      _other -> true
    end
  end

  defp admit_work_item(managed_repo_id, work_item_id) do
    if resumable_work_item?(managed_repo_id, work_item_id) do
      :ok
    else
      case work_queue_limit() do
        :infinity ->
          :ok

        limit when is_integer(limit) and limit > 0 ->
          active_items = active_work_items(managed_repo_id)

          if length(active_items) < limit do
            :ok
          else
            {:error,
             {:work_queue_full, %{managed_repo_id: managed_repo_id, limit: limit, active_work_items: active_items}}}
          end
      end
    end
  end

  defp resumable_work_item?(managed_repo_id, work_item_id) do
    case Manager.pod_status(managed_repo_id, coding_pod_id(work_item_id)) do
      %{module: CodingPod, metadata: metadata} -> restorable_coding_pod?(metadata)
      _other -> false
    end
  end

  defp work_queue_limit do
    case Application.get_env(:jido_code, :agent_workspace_max_concurrent_work_items, :infinity) do
      limit when is_integer(limit) and limit > 0 -> limit
      _other -> :infinity
    end
  end

  defp ensure_runtime_pod(managed_repo_id, pod_id, pod_module, metadata, initial_state) do
    case Manager.pod_status(managed_repo_id, pod_id) do
      %{metadata: %{runtime_pid: pid}} = pod_entry when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pod_entry, pid}
        else
          start_and_track_runtime_pod(managed_repo_id, pod_id, pod_module, metadata, initial_state)
        end

      _pod_entry ->
        start_and_track_runtime_pod(managed_repo_id, pod_id, pod_module, metadata, initial_state)
    end
  end

  defp start_and_track_runtime_pod(managed_repo_id, pod_id, pod_module, metadata, initial_state) do
    with {:ok, pod_pid} <- start_runtime_pod(managed_repo_id, pod_id, pod_module, initial_state),
         {:ok, pod_entry} <-
           Manager.ensure_pod(
             managed_repo_id,
             pod_id,
             pod_module,
             Map.merge(metadata, %{
               runtime_pid: pod_pid,
               started_at: DateTime.utc_now()
             })
           ) do
      {:ok, pod_entry, pod_pid}
    end
  end

  defp start_runtime_pod(managed_repo_id, pod_id, pod_module, initial_state) do
    naming = Naming.new(Manager.kernel_name(managed_repo_id))
    jido_instance = Naming.kernel_jido_instance(naming)
    pod_runtime_id = "#{managed_repo_id}:#{pod_id}"

    with :ok <-
           ManagerSupervisor.ensure_managers(
             pod_module,
             agent_os_persistence(),
             jido_instance,
             naming
           ),
         pod_agent <-
           pod_module.new(
             id: pod_runtime_id,
             state: initial_state
           ),
         {:ok, scoped_pod_agent} <-
           Pod.put_topology(pod_agent, AgentOSPod.scoped_topology(pod_module, naming)),
         {:ok, pod_pid} <-
           AgentServer.start(
             agent: scoped_pod_agent,
             agent_module: pod_module,
             jido: jido_instance,
             id: pod_runtime_id
           ),
         {:ok, _report} <- Pod.reconcile(pod_pid) do
      {:ok, pod_pid}
    else
      {:error, %{stage: :reconcile} = reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_coding_specialist(managed_repo_id, work_item_id, node_name) do
    with {:ok, pod_pid} <- coding_pod_pid(managed_repo_id, work_item_id) do
      Pod.ensure_node(pod_pid, node_name)
    end
  end

  defp coding_pod_pid(managed_repo_id, work_item_id) do
    case Manager.pod_status(managed_repo_id, coding_pod_id(work_item_id)) do
      %{metadata: %{runtime_pid: pid}} when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, :coding_pod_not_started}
        end

      _other ->
        {:error, :coding_pod_not_started}
    end
  end

  defp maybe_stop_runtime_pod(%{metadata: %{runtime_pid: pid}}) when is_pid(pid) do
    if Process.alive?(pid) do
      _ = PodRuntime.teardown_runtime(pid)

      try do
        GenServer.stop(pid, :shutdown, 5_000)
      catch
        :exit, _reason -> :ok
      end
    else
      :ok
    end
  end

  defp maybe_stop_runtime_pod(_pod_entry), do: :ok

  defp active_coding_pod?(%{module: CodingPod, metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, :runtime_status) != :completed and
      match?(pid when is_pid(pid), Map.get(metadata, :runtime_pid)) and
      Process.alive?(Map.get(metadata, :runtime_pid))
  end

  defp active_coding_pod?(_pod_entry), do: false

  defp resolve_workspace_path(managed_repo_id, work_item_id, workspace_path) when is_binary(workspace_path) do
    case String.trim(workspace_path) do
      "" -> resolve_workspace_path(managed_repo_id, work_item_id, nil)
      path -> {:ok, Path.expand(path)}
    end
  end

  defp resolve_workspace_path(managed_repo_id, work_item_id, _workspace_path) do
    case Manager.pod_status(managed_repo_id, coding_pod_id(work_item_id)) do
      %{metadata: %{workspace_path: path}} when is_binary(path) and path != "" ->
        {:ok, path}

      _other ->
        {:error, :missing_workspace_path}
    end
  end

  defp run_specialist(agent_module, pid, instruction, managed_repo_id, workspace_path, semantic_context, opts) do
    specialist_runner().run(
      agent_module,
      pid,
      instruction,
      tool_context: specialist_tool_context(managed_repo_id, workspace_path, semantic_context, opts),
      timeout: Keyword.get(opts, :timeout, 30_000)
    )
  end

  defp specialist_tool_context(managed_repo_id, workspace_path, semantic_context, opts) do
    base = %{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path
    }

    case Keyword.get(opts, :source_code_graph) do
      nil ->
        base

      _graph_opts ->
        case source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
          {:ok, graph_context} ->
            base
            |> Map.put(:latest_import_status, graph_context.latest_import_status)
            |> Map.put(:latest_analysis_status, graph_context.latest_analysis_status)
            |> Map.put(:latest_failure, graph_context.latest_failure)
            |> Map.put(:graph, %{revision: get_in(semantic_context, [:graph_status, :current_revision])})

          {:error, _reason} ->
            base
        end
    end
  end

  defp agent_instruction(_workflow, instruction, semantic_context) when semantic_context == %{}, do: instruction

  defp agent_instruction(workflow, instruction, semantic_context) do
    """
    Workflow: #{workflow}
    Instruction: #{instruction}

    Semantic context:
    #{inspect(semantic_context, pretty: true, limit: :infinity)}
    """
  end

  defp normalize_specialist_result(%{summary: summary}) when is_binary(summary), do: summary
  defp normalize_specialist_result(%{result: result}), do: result
  defp normalize_specialist_result(result), do: result

  defp persist_coding_pod_result(managed_repo_id, work_item_id, runtime_status, updates) do
    _ =
      Manager.update_pod_metadata(
        managed_repo_id,
        coding_pod_id(work_item_id),
        Map.merge(updates, %{
          runtime_status: runtime_status,
          last_activity_at: DateTime.utc_now()
        })
      )

    :ok
  end

  defp specialist_runner do
    Application.get_env(
      :jido_code,
      :agent_workspace_specialist_runner,
      RuntimeSpecialistRunner
    )
  end

  defp agent_os_persistence do
    :jido_code
    |> Application.get_env(:agent_os_persistence)
    |> Persistence.resolve()
    |> case do
      {:ok, %Persistence{adapter: adapter} = persistence} ->
        if Code.ensure_loaded?(adapter) do
          Persistence.storage(persistence)
        else
          nil
        end

      {:ok, nil} ->
        nil

      {:error, _reason} ->
        nil
    end
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
      latest_failure: get_in(pod_entry, [:metadata, :latest_failure]),
      graph: %{revision: Keyword.get(opts, :revision)}
    }

    with {:ok, _graph_context} <- SourceCodeGraph.graph_context(managed_repo_id, workspace_path, opts) do
      {:ok, context}
    end
  end

  defp persist_source_code_graph_state(managed_repo_id, updates) when is_map(updates) do
    Manager.update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), updates)
  end

  defp persist_source_code_graph_failure(managed_repo_id, operation, reason, diagnostics, updates \\ %{})
       when is_atom(operation) and is_map(updates) do
    failure =
      case diagnostics do
        diagnostics when is_map(diagnostics) ->
          %{
            kind: reason,
            operation: operation,
            stage: Map.get(diagnostics, :stage),
            message: failure_message(reason, diagnostics),
            recorded_at: DateTime.utc_now()
          }

        _ ->
          nil
      end

    merged_updates =
      updates
      |> Map.put(:latest_failure, failure)

    persist_source_code_graph_state(managed_repo_id, merged_updates)
  end

  defp source_code_graph_summary(managed_repo_id, pod_entry) do
    %{
      managed_repo_id: managed_repo_id,
      pod_id: pod_entry.pod_id,
      graph_name: get_in(pod_entry, [:metadata, :graph_name]),
      ontology_profile: get_in(pod_entry, [:metadata, :ontology_profile]),
      workspace_path: get_in(pod_entry, [:metadata, :workspace_path]),
      graph_store_path: get_in(pod_entry, [:metadata, :graph_store_path]),
      ready?: get_in(pod_entry, [:metadata, :latest_import_status, :ready?]) || false,
      latest_failure: get_in(pod_entry, [:metadata, :latest_failure])
    }
  end

  defp run_source_code_graph_action(managed_repo_id, workspace_path, opts, action_module, params)
       when is_atom(action_module) and is_map(params) do
    with {:ok, _pod} <- ensure_source_code_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
      case action_module.run(params, action_context) do
        {:ok, result} ->
          persist_source_code_graph_state(managed_repo_id, %{latest_failure: nil})
          {:ok, result}

        {:error, reason, diagnostics} = error ->
          if reason == :source_code_graph_query_failed and is_map(diagnostics) do
            persist_source_code_graph_failure(managed_repo_id, :query, reason, diagnostics)
          end

          error

        other ->
          other
      end
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

      :recover ->
        with {:ok, recovery_result} <-
               recover_source_code_graph(managed_repo_id, workspace_path, source_graph_opts) do
          {:ok, recovery_result.graph_status}
        end

      :load_if_missing ->
        with {:ok, status} <- source_code_graph_status(managed_repo_id, workspace_path, source_graph_opts) do
          cond do
            status.ready? and status.stale? ->
              refresh_source_code_graph(managed_repo_id, workspace_path, source_graph_opts)

            status.ready? ->
              {:ok, status}

            true ->
              load_source_code_graph(managed_repo_id, workspace_path, source_graph_opts)
          end
        end
    end
  end

  defp source_code_graph_recovery_action(status, opts) do
    case Keyword.get(opts, :mode, :auto) do
      :auto ->
        cond do
          status.stale? ->
            :refresh

          query_failure_requires_refresh?(status) ->
            :refresh

          not status.ready? and Map.get(status.latest_analysis_status, :ready?, false) ->
            :load

          not status.ready? ->
            :analyze

          true ->
            :none
        end

      mode ->
        mode
    end
  end

  defp run_source_code_graph_recovery(managed_repo_id, workspace_path, :analyze, opts) do
    analyze_source_code_graph(managed_repo_id, workspace_path, Keyword.delete(opts, :mode))
  end

  defp run_source_code_graph_recovery(managed_repo_id, workspace_path, :load, opts) do
    load_source_code_graph(managed_repo_id, workspace_path, Keyword.delete(opts, :mode))
  end

  defp run_source_code_graph_recovery(managed_repo_id, workspace_path, :refresh, opts) do
    refresh_source_code_graph(managed_repo_id, workspace_path, Keyword.delete(opts, :mode))
  end

  defp run_source_code_graph_recovery(managed_repo_id, workspace_path, :status, opts) do
    source_code_graph_status(managed_repo_id, workspace_path, Keyword.delete(opts, :mode))
  end

  defp query_failure_requires_refresh?(status) do
    case status.latest_failure do
      %{kind: :source_code_graph_query_failed} -> true
      _ -> false
    end
  end

  defp failure_message(reason, diagnostics) when is_map(diagnostics) do
    Map.get(diagnostics, :failure) ||
      Map.get(diagnostics, :reason) ||
      "Source code graph #{reason}"
  end

  defp failure_message(reason, _diagnostics), do: "Source code graph #{reason}"

  defp maybe_analysis_update(%{latest_analysis_status: latest_analysis_status})
       when is_map(latest_analysis_status) do
    %{latest_analysis_status: latest_analysis_status}
  end

  defp maybe_analysis_update(_diagnostics), do: %{}

  defp source_code_graph_runtime_opts(opts) do
    Keyword.take(opts, [:revision, :enabled?, :allow_stale?])
  end

  defp normalize_workflow_graph_status(%{ready?: _ready?} = result), do: result

  defp normalize_workflow_graph_status(%{latest_import_status: latest_import_status} = result) do
    stale? = Map.get(result, :stale?, false)
    latest_failure = Map.get(result, :latest_failure)

    %{
      ready?: Map.get(latest_import_status, :ready?, false),
      stale?: stale?,
      stale_reason: Map.get(result, :stale_reason),
      requested_revision: get_in(result, [:dataset, :revision]),
      current_revision: Map.get(result, :current_revision),
      imported_revision: Map.get(latest_import_status, :imported_revision),
      latest_import_status: latest_import_status,
      latest_analysis_status: Map.get(result, :latest_analysis_status, %{}),
      latest_failure: latest_failure,
      dataset: Map.get(result, :dataset, %{})
    }
  end

  defp normalize_workflow_graph_status(result), do: %{ready?: false, raw: result}

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

  defp source_code_graph_params(opts, allowed_keys \\ [:revision]) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.into(%{})
  end
end
