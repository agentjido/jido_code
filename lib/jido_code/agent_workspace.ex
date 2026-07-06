defmodule JidoCode.AgentWorkspace do
  # covers: architecture.repository_runtime_integration.workspace_context_hides_kernel_topology
  # covers: architecture.repository_runtime_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.repository_runtime_integration.pod_cleanup_on_completion
  # covers: architecture.repository_runtime_integration.pod_naming_convention
  # covers: architecture.repository_runtime_integration.multiple_pods_parallel_execution
  # covers: architecture.repository_runtime_integration.signal_routing_within_pod
  # covers: architecture.repository_runtime_integration.kernel_snapshots_restore_resumable_runtime_state
  # covers: architecture.repository_runtime_integration.repository_work_queue_is_bounded
  # covers: architecture.repository_runtime_integration.eager_collaboration_state_is_seeded_before_specialist_work
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_capacity_limits_fail_closed
  # covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context
  # covers: architecture.policy_layers.memory_operator_actions_remain_policy_bound
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.source_code_graph_pod.workspace_binding_is_explicit_and_product_owned
  # covers: architecture.repository_runtime_integration.source_code_graph_stale_and_recovery_state_stays_workspace_bound
  # covers: architecture.repository_runtime_integration.memory_graph_read_write_and_query_stay_workspace_bound
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.governed_surfaces_may_cohost_semantic_cross_links
  # covers: architecture.repository_runtime_integration.memory_graph_product_actions_stay_workspace_bound
  @moduledoc """
  Context module for repository workspace operations.

  Provides a clean API for Phoenix controllers and LiveViews to interact
  with repository runtimes and pods without exposing the internal topology.

  ## Repository Runtime Lifecycle

  Repository runtimes are created per ManagedRepo and managed through this context.

  ## Pod Operations

  CodingPods are created per WorkItem and provide isolated execution
  contexts for AI-powered coding work.

  ## Work Execution

  Functions for planning, executing, refactoring, reviewing, and explaining
  work through agents.
  """

  alias JidoCode.Agents.{Coder, Explainer, Planner, Refactorer, RepoMonitor, Reviewer}
  alias JidoCode.Control.Actor
  alias JidoCode.Conversations
  alias JidoCode.Conversations.Driver, as: ConversationDriver
  alias JidoCode.LLMSelection
  alias JidoCode.MemoryGraph.{CaptureEnvelope, GovernedReference}
  alias JidoCode.MemoryGraph.ProductFeedback, as: MemoryGraphProductFeedback

  alias JidoCode.Actions.{
    AnalyzeSourceCodeGraph,
    FindSourceCodeGraphFunctions,
    FindSourceCodeGraphModules,
    FindSourceCodeGraphRuntimePatterns,
    GetSourceCodeGraphStatus,
    GetMemoryGraphStatus,
    InvalidateMemoryGraph,
    LoadSourceCodeGraph,
    QuerySourceCodeGraph,
    QueryMemoryGraph,
    RecordMemoryGraph,
    RefreshSourceCodeGraph,
    RefreshMemoryGraph,
    TraceSourceCodeGraphImpact,
    ValidateMemoryGraph
  }

  alias JidoCode.AgentWorkspace.RuntimeSpecialistRunner
  alias JidoCode.AgentWorkspace.PromptProjection
  alias JidoCode.Conversations.ContextCompaction, as: ConversationContextCompaction
  alias JidoCode.{ContextBudget, ContextManagement, MemoryGraph, Runtime, SourceCodeGraph}
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Signal

  @type managed_repo_id :: String.t()
  @type work_item_id :: String.t()
  @type runtime_status :: map()
  @type kernel_name :: runtime_status()
  @type pod_name :: String.t()
  @type source_code_graph_summary :: map()
  @type memory_graph_summary :: map()
  @workflow_provenance_actor Actor.factory_system_actor(%{
                               "id" => "system:agent-workspace-provenance",
                               "email" => "agent-workspace-provenance@system.local"
                             })

  ## Repository Runtime Lifecycle

  @doc """
  Ensures a repository runtime exists for the given ManagedRepo ID.
  """
  @spec ensure_repository_runtime(managed_repo_id(), String.t() | nil) ::
          {:ok, runtime_status()} | {:error, term()}
  def ensure_repository_runtime(managed_repo_id, workspace_path \\ nil)

  def ensure_repository_runtime(managed_repo_id, workspace_path) when is_binary(managed_repo_id) do
    with {:ok, _status} <- Runtime.ensure_repository(managed_repo_id, workspace_path),
         {:ok, _repo_pod} <- Runtime.ensure_repo_pod(managed_repo_id),
         {:ok, status} <- Runtime.fetch_repository(managed_repo_id) do
      {:ok, status}
    end
  end

  @doc """
  Backward-compatible wrapper for older call sites.
  """
  @spec ensure_kernel(managed_repo_id()) :: {:ok, runtime_status()} | {:error, term()}
  def ensure_kernel(managed_repo_id) when is_binary(managed_repo_id) do
    ensure_repository_runtime(managed_repo_id)
  end

  @doc """
  Returns the status of a repository runtime for the given ManagedRepo ID.
  """
  @spec repository_status(managed_repo_id()) :: runtime_status() | nil
  def repository_status(managed_repo_id) when is_binary(managed_repo_id) do
    Runtime.repository_status(managed_repo_id)
  end

  @doc """
  Backward-compatible wrapper for older call sites.
  """
  @spec kernel_status(managed_repo_id()) :: runtime_status() | nil
  def kernel_status(managed_repo_id) when is_binary(managed_repo_id) do
    repository_status(managed_repo_id)
  end

  @doc """
  Shuts down a repository runtime for the given ManagedRepo ID.
  """
  @spec shutdown_repository_runtime(managed_repo_id()) :: :ok
  def shutdown_repository_runtime(managed_repo_id) when is_binary(managed_repo_id) do
    Runtime.shutdown_repository(managed_repo_id)
  end

  @doc """
  Backward-compatible wrapper for older call sites.
  """
  @spec shutdown_kernel(managed_repo_id()) :: :ok
  def shutdown_kernel(managed_repo_id) when is_binary(managed_repo_id) do
    shutdown_repository_runtime(managed_repo_id)
  end

  @doc """
  Lists all active repository runtimes.
  """
  @spec list_repository_runtimes() :: [runtime_status()]
  def list_repository_runtimes do
    Runtime.list_repositories()
  end

  @doc """
  Backward-compatible wrapper for older call sites.
  """
  @spec list_kernels() :: [runtime_status()]
  def list_kernels do
    list_repository_runtimes()
  end

  @doc """
  Returns the number of active repository runtimes.
  """
  @spec repository_runtime_count() :: non_neg_integer()
  def repository_runtime_count do
    Runtime.repository_count()
  end

  @doc """
  Backward-compatible wrapper for older call sites.
  """
  @spec kernel_count() :: non_neg_integer()
  def kernel_count do
    repository_runtime_count()
  end

  ## Pod Lifecycle

  @doc """
  Ensures a CodingPod exists for the given WorkItem.

  Creates a new CodingPod if one doesn't exist for the WorkItem,
  configured with the workspace path and other context.

  ## Examples

      iex> AgentWorkspace.ensure_coding_pod("repo-123", "work-item-1", "/path/to/workspace")
      {:ok, "coding-pod-work-item-1"}

  """
  @spec ensure_coding_pod(managed_repo_id(), work_item_id(), String.t()) :: {:ok, pod_name()} | {:error, term()}
  def ensure_coding_pod(managed_repo_id, work_item_id, workspace_path) do
    ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, [])
  end

  @spec ensure_coding_pod(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, pod_name()} | {:error, term()}
  def ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, opts) when is_list(opts) do
    with {:ok, resolved_workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, workspace_path),
         {:ok, _runtime} <- ensure_repository_runtime(managed_repo_id, resolved_workspace_path),
         {:ok, coding_pod} <- Runtime.ensure_coding_pod(managed_repo_id, work_item_id, resolved_workspace_path),
         :ok <- sync_project_context(managed_repo_id, work_item_id, resolved_workspace_path, coding_pod.runtime_pid),
         {:ok, _context_management} <-
           ensure_context_management_pod(managed_repo_id, work_item_id, resolved_workspace_path, opts) do
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
    Runtime.complete_work(managed_repo_id, work_item_id)
  end

  @doc """
  Returns the stable context-management pod id for a WorkItem.
  """
  @spec context_management_pod_id(work_item_id()) :: String.t()
  def context_management_pod_id(work_item_id), do: ContextManagement.pod_id(work_item_id)

  @doc """
  Ensures the work-item-scoped context-management pod is running when enabled.

  Disabled context management returns a metadata-only skipped status. The
  request-time `ContextBudget` path remains independent and still protects
  provider requests.
  """
  @spec ensure_context_management_pod(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_list(opts) do
    context_opts = context_management_opts(opts)

    with {:ok, resolved_workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, workspace_path) do
      if ContextManagement.enabled?(context_opts) do
        metadata =
          ContextManagement.initial_metadata(
            managed_repo_id,
            work_item_id,
            resolved_workspace_path,
            coding_pod_id(work_item_id),
            context_opts
          )

        with {:ok, _runtime} <- ensure_repository_runtime(managed_repo_id, resolved_workspace_path),
             {:ok, pod_entry} <-
               Runtime.ensure_context_management_pod(managed_repo_id, work_item_id, resolved_workspace_path, metadata) do
          {:ok, ContextManagement.status_summary(pod_entry.metadata)}
        end
      else
        {:ok, ContextManagement.status_summary(ContextManagement.disabled_metadata())}
      end
    end
  end

  @doc """
  Returns context-management state for a work item without exposing pod internals.
  """
  @spec context_management_status(managed_repo_id(), work_item_id()) :: map()
  def context_management_status(managed_repo_id, work_item_id)
      when is_binary(managed_repo_id) and is_binary(work_item_id) do
    managed_repo_id
    |> pod_status(ContextManagement.pod_id(work_item_id))
    |> case do
      %{metadata: metadata} -> ContextManagement.status_summary(metadata)
      _other -> ContextManagement.status_summary(nil)
    end
  end

  @doc """
  Stops a context-management pod for a work item, if present.
  """
  @spec shutdown_context_management_pod(managed_repo_id(), work_item_id()) :: :ok
  def shutdown_context_management_pod(managed_repo_id, work_item_id)
      when is_binary(managed_repo_id) and is_binary(work_item_id) do
    Runtime.shutdown_context_management_pod(managed_repo_id, work_item_id)
  end

  @doc """
  Stores a validated compaction summary for a work item.
  """
  @spec store_context_compaction_summary(managed_repo_id(), work_item_id(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def store_context_compaction_summary(managed_repo_id, work_item_id, summary_attrs, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(summary_attrs) and is_list(opts) do
    pod_id = ContextManagement.pod_id(work_item_id)

    with %{metadata: metadata} <- pod_status(managed_repo_id, pod_id),
         {:ok, updated_metadata} <-
           ContextManagement.add_summary(
             metadata,
             Map.merge(summary_attrs, %{
               managed_repo_id: managed_repo_id,
               work_item_id: work_item_id
             }),
             context_management_opts(opts)
           ),
         {:ok, pod_entry} <- update_pod_metadata(managed_repo_id, pod_id, updated_metadata) do
      {:ok, ContextManagement.status_summary(pod_entry.metadata)}
    else
      nil -> {:error, :context_management_pod_not_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs bounded compaction for an eligible candidate and stores the accepted summary.
  """
  @spec compact_context(managed_repo_id(), work_item_id(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def compact_context(managed_repo_id, work_item_id, candidate, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(candidate) and is_list(opts) do
    case ContextManagement.compact_candidate(candidate, context_management_opts(opts)) do
      {:ok, summary} ->
        store_context_compaction_summary(managed_repo_id, work_item_id, Map.from_struct(summary), opts)

      {:error, reason} = error ->
        _ = persist_context_compaction_failure(managed_repo_id, work_item_id, reason, candidate, opts)
        error
    end
  end

  @doc """
  Runs automatic compaction for the latest eligible monitor recommendation.

  This is the product-owned bridge from metadata-only monitoring to the
  compactor. It does not mutate conversation history; callers decide how to
  record any reset marker after an accepted summary is stored.
  """
  @spec auto_compact_context(managed_repo_id(), work_item_id(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def auto_compact_context(managed_repo_id, work_item_id, conversation_state_or_snapshot, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(conversation_state_or_snapshot) and
             is_list(opts) do
    pod_id = ContextManagement.pod_id(work_item_id)
    context_opts = context_management_opts(opts)

    with %{metadata: metadata} <- pod_status(managed_repo_id, pod_id),
         action <- ContextManagement.automatic_compaction_action(metadata, context_opts),
         {:action, "compact"} <- {:action, Map.get(action, "state")},
         {:ok, candidate} <-
           ConversationContextCompaction.compaction_candidate(conversation_state_or_snapshot, action, context_opts),
         :ok <- reject_already_compacted(managed_repo_id, work_item_id, candidate, opts),
         {:ok, status} <- compact_context(managed_repo_id, work_item_id, candidate, opts) do
      {:ok,
       Map.put(status, "auto_compaction", %{
         "state" => "compacted",
         "recommendation_id" => Map.get(action, "recommendation_id"),
         "debounce_key" => Map.get(action, "debounce_key"),
         "source_span_ids" => Map.get(candidate, :source_span_ids, Map.get(candidate, "source_span_ids", [])),
         "workflow" => Map.get(candidate, :workflow, Map.get(candidate, "workflow")),
         "specialist_role" => Map.get(candidate, :specialist_role, Map.get(candidate, "specialist_role")),
         "policy_id" => Map.get(action, "policy_id")
       })}
    else
      nil ->
        {:ok, ContextManagement.automatic_compaction_action(nil, context_opts)}

      {:action, _state} ->
        case pod_status(managed_repo_id, pod_id) do
          %{metadata: metadata} -> {:ok, ContextManagement.automatic_compaction_action(metadata, context_opts)}
          _other -> {:ok, ContextManagement.automatic_compaction_action(nil, context_opts)}
        end

      {:error, {:already_compacted, summary}} ->
        {:ok,
         %{
           "state" => "skip",
           "reason" => "source_span_already_compacted",
           "summary_id" => Map.get(summary, "id"),
           "source_span_ids" => Map.get(summary, "source_span_ids", []),
           "policy_id" => Map.get(summary, "policy_id")
         }}

      {:error, reason} = error ->
        _ = persist_context_compaction_failure(managed_repo_id, work_item_id, reason, nil, opts)
        error
    end
  end

  @doc """
  Retries automatic compaction for the latest monitor recommendation.

  This explicit operator/test path allows the latest debounced recommendation
  to run again while retaining the same idempotency guard for already-compacted
  source spans.
  """
  @spec retry_auto_compact_context(managed_repo_id(), work_item_id(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def retry_auto_compact_context(managed_repo_id, work_item_id, conversation_state_or_snapshot, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(conversation_state_or_snapshot) and
             is_list(opts) do
    pod_id = ContextManagement.pod_id(work_item_id)

    retry_opts =
      case pod_status(managed_repo_id, pod_id) do
        %{metadata: metadata} -> retry_context_management_opts(opts, latest_monitor_decision(metadata))
        _other -> retry_context_management_opts(opts, %{})
      end

    auto_compact_context(managed_repo_id, work_item_id, conversation_state_or_snapshot, retry_opts)
  end

  @doc """
  Disables automatic compaction for a work item while leaving monitoring active.
  """
  @spec disable_auto_compaction(managed_repo_id(), work_item_id(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def disable_auto_compaction(managed_repo_id, work_item_id, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_list(opts) do
    pod_id = ContextManagement.pod_id(work_item_id)
    reason = Keyword.get(opts, :reason)

    case pod_status(managed_repo_id, pod_id) do
      %{metadata: metadata} ->
        with {:ok, pod_entry} <-
               update_pod_metadata(
                 managed_repo_id,
                 pod_id,
                 ContextManagement.disable_auto_compaction_metadata(metadata, reason)
               ) do
          {:ok, ContextManagement.status_summary(pod_entry.metadata)}
        end

      _other ->
        {:ok, ContextManagement.status_summary(nil)}
    end
  end

  @doc """
  Returns bounded active compaction summaries for prompt assembly.
  """
  @spec context_compaction_summaries(managed_repo_id(), work_item_id(), keyword()) :: [map()]
  def context_compaction_summaries(managed_repo_id, work_item_id, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_list(opts) do
    case pod_status(managed_repo_id, ContextManagement.pod_id(work_item_id)) do
      %{metadata: metadata} ->
        ContextManagement.active_summaries(metadata, context_management_summary_opts(opts))

      _other ->
        []
    end
  end

  @doc """
  Records a metadata-only context-budget observation for a work item.

  Missing or disabled context management degrades to an unavailable summary and
  never blocks active specialist or conversation work.
  """
  @spec record_context_observation(managed_repo_id(), work_item_id(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def record_context_observation(managed_repo_id, work_item_id, observation_attrs, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(work_item_id) and is_map(observation_attrs) and is_list(opts) do
    pod_id = ContextManagement.pod_id(work_item_id)

    case pod_status(managed_repo_id, pod_id) do
      %{metadata: %{context_management_status: :disabled}} ->
        {:ok, ContextManagement.status_summary(ContextManagement.disabled_metadata())}

      %{metadata: metadata} ->
        observation_attrs =
          Map.merge(observation_attrs, %{
            managed_repo_id: managed_repo_id,
            work_item_id: work_item_id
          })

        with {:ok, updated_metadata} <-
               ContextManagement.add_observation(metadata, observation_attrs, context_management_opts(opts)),
             {:ok, pod_entry} <- update_pod_metadata(managed_repo_id, pod_id, updated_metadata) do
          {:ok, ContextManagement.status_summary(pod_entry.metadata)}
        end

      _other ->
        {:ok, ContextManagement.status_summary(nil)}
    end
  end

  defp persist_context_compaction_failure(managed_repo_id, work_item_id, reason, candidate, opts) do
    pod_id = ContextManagement.pod_id(work_item_id)

    case pod_status(managed_repo_id, pod_id) do
      %{metadata: metadata} ->
        update_pod_metadata(
          managed_repo_id,
          pod_id,
          Map.merge(
            metadata,
            ContextManagement.compaction_failure_metadata(reason, candidate, context_management_opts(opts))
          )
        )

      _other ->
        :ok
    end
  end

  defp reject_already_compacted(managed_repo_id, work_item_id, candidate, opts) do
    source_span_ids =
      candidate
      |> Map.get(:source_span_ids, Map.get(candidate, "source_span_ids", []))
      |> normalize_string_list()
      |> Enum.sort()

    context_compaction_summaries(managed_repo_id, work_item_id, opts)
    |> Enum.find(fn summary ->
      summary
      |> Map.get("source_span_ids", [])
      |> normalize_string_list()
      |> Enum.sort()
      |> Kernel.==(source_span_ids)
    end)
    |> case do
      nil -> :ok
      summary -> {:error, {:already_compacted, summary}}
    end
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_string_list(value) do
    value
    |> normalize_string_value()
    |> case do
      nil -> []
      string -> [string]
    end
  end

  defp normalize_string_value(nil), do: nil

  defp normalize_string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string_value(value), do: inspect(value)

  @doc """
  Lists active WorkItems (CodingPods) for a ManagedRepo.

  ## Examples

      iex> AgentWorkspace.active_work_items("repo-123")
      ["work-item-1", "work-item-2"]

  """
  @spec active_work_items(managed_repo_id()) :: [work_item_id()]
  def active_work_items(managed_repo_id) do
    Runtime.active_work_items(managed_repo_id)
  end

  ## Conversation Coordination

  @doc """
  Returns the latest repo-scoped conversation for the managed repository, if any.
  """
  @spec latest_repo_conversation(managed_repo_id(), keyword()) ::
          {:ok, Conversations.Conversation.t() | nil} | {:error, term()}
  def latest_repo_conversation(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    Conversations.latest_for_managed_repo(managed_repo_id, actor: conversation_actor(opts))
  end

  @doc """
  Returns the latest repo-scoped intake conversation for the managed repository, if any.
  """
  @spec latest_repo_intake_conversation(managed_repo_id(), keyword()) ::
          {:ok, Conversations.Conversation.t() | nil} | {:error, term()}
  def latest_repo_intake_conversation(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    Conversations.latest_repo_intake_for_managed_repo(
      managed_repo_id,
      actor: conversation_actor(opts)
    )
  end

  @doc """
  Returns the active repo-scoped intake conversation for the managed repository, if any.
  """
  @spec active_repo_intake_conversation(managed_repo_id(), keyword()) ::
          {:ok, Conversations.Conversation.t() | nil} | {:error, term()}
  def active_repo_intake_conversation(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    Conversations.active_repo_intake_for_managed_repo(
      managed_repo_id,
      actor: conversation_actor(opts)
    )
  end

  @doc """
  Opens a repo-scoped conversation and returns its initial snapshot.
  """
  @spec open_repo_conversation(managed_repo_id(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def open_repo_conversation(managed_repo_id, attrs \\ %{}, opts \\ [])
      when is_binary(managed_repo_id) and is_map(attrs) and is_list(opts) do
    ConversationDriver.start_conversation(
      attrs
      |> Map.put("managed_repo_id", managed_repo_id)
      |> Map.put_new("actor", conversation_actor(opts))
    )
  end

  @doc """
  Returns the active work-item-scoped conversation for the work item, if any.
  """
  @spec active_work_item_conversation(work_item_id(), keyword()) ::
          {:ok, Conversations.Conversation.t() | nil} | {:error, term()}
  def active_work_item_conversation(work_item_id, opts \\ [])
      when is_binary(work_item_id) and is_list(opts) do
    Conversations.active_for_work_item(work_item_id, actor: conversation_actor(opts))
  end

  @doc """
  Lists the active productive conversations for a managed repository by work item.
  """
  @spec active_work_item_conversations(managed_repo_id(), keyword()) ::
          {:ok, [Conversations.Conversation.t()]} | {:error, term()}
  def active_work_item_conversations(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    Conversations.active_work_item_conversations_for_managed_repo(
      managed_repo_id,
      actor: conversation_actor(opts)
    )
  end

  @doc """
  Opens or resumes the active productive conversation for a work item and returns its current snapshot.
  """
  @spec open_work_item_conversation(work_item_id(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def open_work_item_conversation(work_item_id, attrs \\ %{}, opts \\ [])
      when is_binary(work_item_id) and is_map(attrs) and is_list(opts) do
    ConversationDriver.start_or_resume_work_item_conversation(
      work_item_id,
      attrs,
      actor: conversation_actor(opts)
    )
  end

  @doc """
  Returns the current snapshot for a conversation.
  """
  @spec conversation_snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def conversation_snapshot(conversation_id) when is_binary(conversation_id) do
    ConversationDriver.snapshot(conversation_id)
  end

  @doc """
  Replays conversation events after the provided sequence.
  """
  @spec conversation_events_since(String.t(), non_neg_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def conversation_events_since(conversation_id, after_sequence, opts \\ [])
      when is_binary(conversation_id) and is_integer(after_sequence) and after_sequence >= 0 and
             is_list(opts) do
    ConversationDriver.events_since(conversation_id, after_sequence, actor: conversation_actor(opts))
  end

  @doc """
  Admits a conversation command through the product-owned driver.
  """
  @spec handle_conversation_command(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def handle_conversation_command(conversation_id, command, opts \\ [])
      when is_binary(conversation_id) and is_map(command) and is_list(opts) do
    ConversationDriver.handle_command(conversation_id, command, actor: conversation_actor(opts))
  end

  @doc """
  Stops a running conversation coordinator if one exists.
  """
  @spec stop_conversation(String.t()) :: :ok
  def stop_conversation(conversation_id) when is_binary(conversation_id) do
    ConversationDriver.stop(conversation_id)
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
         {:ok, opts} <- put_llm_selection(managed_repo_id, opts),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, opts),
         {:ok, provenance_context} <-
           workflow_provenance_context(
             managed_repo_id,
             work_item_id,
             workspace_path,
             :plan,
             instruction,
             opts
           ),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :plan, opts),
         {:ok, memory_context} <- workflow_memory_context(:plan, opts),
         opts <- put_compaction_summaries(managed_repo_id, work_item_id, :plan, opts),
         {:ok, specialist_prompt} <- specialist_prompt(:plan, instruction, semantic_context, memory_context, opts),
         {:ok, planner_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :planner),
         {:ok, response} <-
           run_specialist(
             Planner,
             planner_pid,
             specialist_prompt.text,
             managed_repo_id,
             work_item_id,
             workspace_path,
             semantic_context,
             memory_context,
             provenance_context,
             opts
             |> Keyword.put(:work_item_id, work_item_id)
             |> Keyword.put(:context_budget, specialist_prompt.context_budget)
           ) do
      result = %{
        plan: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context,
        memory_context: memory_context,
        context_budget: ContextBudget.summary(specialist_prompt.context_budget),
        context_management: context_management_status(managed_repo_id, work_item_id),
        workflow_provenance: provenance_summary(provenance_context),
        llm_selection: llm_selection_summary(opts)
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
         {:ok, opts} <- put_llm_selection(managed_repo_id, opts),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, opts),
         {:ok, provenance_context} <-
           workflow_provenance_context(
             managed_repo_id,
             work_item_id,
             workspace_path,
             :execute,
             instruction,
             opts
           ),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :execute, opts),
         {:ok, memory_context} <- workflow_memory_context(:execute, opts),
         opts <- put_compaction_summaries(managed_repo_id, work_item_id, :execute, opts),
         {:ok, specialist_prompt} <- specialist_prompt(:execute, instruction, semantic_context, memory_context, opts),
         {:ok, coder_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :coder),
         {:ok, response} <-
           run_specialist(
             Coder,
             coder_pid,
             specialist_prompt.text,
             managed_repo_id,
             work_item_id,
             workspace_path,
             semantic_context,
             memory_context,
             provenance_context,
             opts
             |> Keyword.put(:work_item_id, work_item_id)
             |> Keyword.put(:context_budget, specialist_prompt.context_budget)
           ) do
      result = %{
        changes: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context,
        memory_context: memory_context,
        context_budget: ContextBudget.summary(specialist_prompt.context_budget),
        context_management: context_management_status(managed_repo_id, work_item_id),
        workflow_provenance: provenance_summary(provenance_context),
        llm_selection: llm_selection_summary(opts)
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
         {:ok, opts} <- put_llm_selection(managed_repo_id, opts),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, opts),
         {:ok, provenance_context} <-
           workflow_provenance_context(
             managed_repo_id,
             work_item_id,
             workspace_path,
             :review,
             instruction,
             opts
           ),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :review, opts),
         {:ok, memory_context} <- workflow_memory_context(:review, opts),
         opts <- put_compaction_summaries(managed_repo_id, work_item_id, :review, opts),
         {:ok, specialist_prompt} <- specialist_prompt(:review, instruction, semantic_context, memory_context, opts),
         {:ok, reviewer_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :reviewer),
         {:ok, response} <-
           run_specialist(
             Reviewer,
             reviewer_pid,
             specialist_prompt.text,
             managed_repo_id,
             work_item_id,
             workspace_path,
             semantic_context,
             memory_context,
             provenance_context,
             opts
             |> Keyword.put(:work_item_id, work_item_id)
             |> Keyword.put(:context_budget, specialist_prompt.context_budget)
           ) do
      result = %{
        feedback: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context,
        memory_context: memory_context,
        context_budget: ContextBudget.summary(specialist_prompt.context_budget),
        context_management: context_management_status(managed_repo_id, work_item_id),
        workflow_provenance: provenance_summary(provenance_context),
        llm_selection: llm_selection_summary(opts)
      }

      persist_coding_pod_result(managed_repo_id, work_item_id, :reviewing, %{last_review: result})
      {:ok, result}
    end
  end

  @doc """
  Refactors work by routing to the refactorer agent.

  Sends a behavior-preserving refactor request to the refactorer agent within
  the WorkItem's CodingPod and returns the result.

  ## Examples

      iex> AgentWorkspace.refactor_work("repo-123", "work-item-1", "Extract shared login validation")
      {:ok, %{refactoring: "..."}}

  """
  @spec refactor_work(managed_repo_id(), work_item_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def refactor_work(managed_repo_id, work_item_id, instruction) do
    refactor_work(managed_repo_id, work_item_id, instruction, [])
  end

  @spec refactor_work(managed_repo_id(), work_item_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def refactor_work(managed_repo_id, work_item_id, instruction, opts) when is_list(opts) do
    with {:ok, workspace_path} <-
           resolve_workspace_path(managed_repo_id, work_item_id, Keyword.get(opts, :workspace_path)),
         {:ok, opts} <- put_llm_selection(managed_repo_id, opts),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, opts),
         {:ok, provenance_context} <-
           workflow_provenance_context(
             managed_repo_id,
             work_item_id,
             workspace_path,
             :refactor,
             instruction,
             opts
           ),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :refactor, opts),
         {:ok, memory_context} <- workflow_memory_context(:refactor, opts),
         opts <- put_compaction_summaries(managed_repo_id, work_item_id, :refactor, opts),
         {:ok, specialist_prompt} <- specialist_prompt(:refactor, instruction, semantic_context, memory_context, opts),
         {:ok, refactorer_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :refactorer),
         {:ok, response} <-
           run_specialist(
             Refactorer,
             refactorer_pid,
             specialist_prompt.text,
             managed_repo_id,
             work_item_id,
             workspace_path,
             semantic_context,
             memory_context,
             provenance_context,
             opts
             |> Keyword.put(:work_item_id, work_item_id)
             |> Keyword.put(:context_budget, specialist_prompt.context_budget)
           ) do
      result = %{
        refactoring: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context,
        memory_context: memory_context,
        context_budget: ContextBudget.summary(specialist_prompt.context_budget),
        context_management: context_management_status(managed_repo_id, work_item_id),
        workflow_provenance: provenance_summary(provenance_context),
        llm_selection: llm_selection_summary(opts)
      }

      persist_coding_pod_result(managed_repo_id, work_item_id, :refactoring, %{last_refactor: result})
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
         {:ok, opts} <- put_llm_selection(managed_repo_id, opts),
         {:ok, _kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, _} <- ensure_coding_pod(managed_repo_id, work_item_id, workspace_path, opts),
         {:ok, provenance_context} <-
           workflow_provenance_context(
             managed_repo_id,
             work_item_id,
             workspace_path,
             :explain,
             instruction,
             opts
           ),
         {:ok, semantic_context} <- workflow_semantic_context(managed_repo_id, :explain, opts),
         {:ok, memory_context} <- workflow_memory_context(:explain, opts),
         opts <- put_compaction_summaries(managed_repo_id, work_item_id, :explain, opts),
         {:ok, specialist_prompt} <- specialist_prompt(:explain, instruction, semantic_context, memory_context, opts),
         {:ok, explainer_pid} <- ensure_coding_specialist(managed_repo_id, work_item_id, :explainer),
         {:ok, response} <-
           run_specialist(
             Explainer,
             explainer_pid,
             specialist_prompt.text,
             managed_repo_id,
             work_item_id,
             workspace_path,
             semantic_context,
             memory_context,
             provenance_context,
             opts
             |> Keyword.put(:work_item_id, work_item_id)
             |> Keyword.put(:context_budget, specialist_prompt.context_budget)
           ) do
      result = %{
        explanation: normalize_specialist_result(response),
        instruction: instruction,
        semantic_context: semantic_context,
        memory_context: memory_context,
        context_budget: ContextBudget.summary(specialist_prompt.context_budget),
        context_management: context_management_status(managed_repo_id, work_item_id),
        workflow_provenance: provenance_summary(provenance_context),
        llm_selection: llm_selection_summary(opts)
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
    existing_pod = pod_status(managed_repo_id, SourceCodeGraph.pod_id())

    with :ok <- ensure_source_code_graph_enabled(opts),
         {:ok, _runtime} <- ensure_repository_runtime(managed_repo_id, workspace_path),
         {:ok, _pod_entry} <- Runtime.ensure_source_code_graph_pod(managed_repo_id),
         {:ok, pod_entry} <-
           initialize_source_code_graph_metadata(existing_pod, managed_repo_id, workspace_path, opts),
         :ok <- maybe_ensure_source_watcher(managed_repo_id, workspace_path, opts) do
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
  Notifies the repo-scoped source watcher that product-managed code writes have
  changed source graph inputs.

  This keeps LLM/tool writes on the same normalized source-change path as human
  editor saves observed by the filesystem watcher.
  """
  @spec notify_workspace_source_changed(managed_repo_id(), String.t(), String.t() | [String.t()], keyword()) ::
          :ok | {:error, term()}
  def notify_workspace_source_changed(managed_repo_id, workspace_path, changed_paths, opts \\ []) do
    with {:ok, _repo_pod} <- ensure_repo_pod_entry(managed_repo_id),
         {:ok, _watcher_pid} <-
           RepoMonitor.ensure_source_watcher(
             managed_repo_id,
             workspace_path,
             Keyword.take(opts, [:start_file_system?, :debounce_ms])
           ) do
      changed_paths
      |> List.wrap()
      |> Enum.reduce_while(:ok, fn changed_path, :ok ->
        case RepoMonitor.notify_source_changed(
               managed_repo_id,
               normalize_changed_source_path(workspace_path, changed_path),
               Keyword.get(opts, :file_events, [:modified]),
               Keyword.get(opts, :event_source, :runtime_write)
             ) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
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

  ## Memory Graph

  @doc """
  Ensures the repository-scoped MemoryGraphPod is configured for a ManagedRepo.

  Returns a product-owned summary of the capability rather than pod internals.
  """
  @spec ensure_memory_graph_pod(managed_repo_id(), String.t(), keyword()) ::
          {:ok, memory_graph_summary()} | {:error, term()}
  def ensure_memory_graph_pod(managed_repo_id, workspace_path, opts \\ []) do
    existing_pod = pod_status(managed_repo_id, MemoryGraph.pod_id())

    with :ok <- ensure_memory_graph_enabled(opts),
         {:ok, _runtime} <- ensure_repository_runtime(managed_repo_id, workspace_path),
         {:ok, _pod_entry} <- Runtime.ensure_memory_graph_pod(managed_repo_id),
         {:ok, pod_entry} <- initialize_memory_graph_metadata(existing_pod, managed_repo_id, workspace_path, opts) do
      {:ok, memory_graph_summary(managed_repo_id, pod_entry)}
    end
  end

  @doc """
  Returns the current repository-scoped memory graph status.
  """
  @spec memory_graph_status(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def memory_graph_status(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_memory_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- memory_graph_action_context(managed_repo_id, workspace_path, opts),
         {:ok, result} <- GetMemoryGraphStatus.run(memory_graph_params(opts), action_context) do
      {:ok, normalize_memory_graph_status(managed_repo_id, workspace_path, result, opts)}
    end
  end

  @doc """
  Refreshes the repository-scoped memory graph foundation in the shared semantic store.
  """
  @spec refresh_memory_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def refresh_memory_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_memory_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- memory_graph_action_context(managed_repo_id, workspace_path, opts) do
      case RefreshMemoryGraph.run(memory_graph_params(opts), action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_memory_graph_state(managed_repo_id, %{
                   latest_validation_status: result.latest_validation_status,
                   latest_failure: Map.get(result, :latest_failure)
                 }) do
            {:ok, result}
          end

        {:error, reason, diagnostics} ->
          persist_memory_graph_failure(
            managed_repo_id,
            :refresh,
            reason,
            diagnostics,
            %{latest_validation_status: failure_validation_status(action_context, diagnostics)}
          )

          {:error, reason, diagnostics}
      end
    end
  end

  @doc """
  Validates that the repository-scoped memory graph foundation is ready and revision-aware.
  """
  @spec validate_memory_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def validate_memory_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_memory_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- memory_graph_action_context(managed_repo_id, workspace_path, opts) do
      case ValidateMemoryGraph.run(memory_graph_params(opts), action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_memory_graph_state(managed_repo_id, %{
                   latest_validation_status: result.latest_validation_status,
                   latest_failure: Map.get(result, :latest_failure)
                 }) do
            {:ok, result}
          end

        {:error, reason, diagnostics} ->
          persist_memory_graph_failure(
            managed_repo_id,
            :validate,
            reason,
            diagnostics,
            %{latest_validation_status: failure_validation_status(action_context, diagnostics)}
          )

          {:error, reason, diagnostics}
      end
    end
  end

  @doc """
  Records an explicit memory capture request through the bounded memory graph surface.
  """
  @spec record_memory_graph(managed_repo_id(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()} | {:error, atom(), map()}
  def record_memory_graph(managed_repo_id, workspace_path, capture, opts \\ []) when is_map(capture) do
    with {:ok, _pod} <- ensure_memory_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- memory_graph_action_context(managed_repo_id, workspace_path, opts) do
      params =
        memory_graph_params(opts)
        |> Map.put(:capture, capture)

      case RecordMemoryGraph.run(params, action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_memory_graph_state(managed_repo_id, %{
                   latest_record_status: Map.get(result, :latest_record_status),
                   latest_failure: nil
                 }) do
            {:ok, result}
          end

        {:error, reason, diagnostics} ->
          persist_memory_graph_failure(
            managed_repo_id,
            :record,
            reason,
            diagnostics,
            %{latest_record_status: failure_record_status(action_context, reason, diagnostics)}
          )

          {:error, reason, diagnostics}

        other ->
          other
      end
    end
  end

  @doc """
  Executes a structured SPARQL query over the repository-scoped memory or workflow provenance graph.
  """
  @spec query_memory_graph(managed_repo_id(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def query_memory_graph(managed_repo_id, workspace_path, sparql, opts \\ [])
      when is_binary(sparql) do
    run_memory_graph_action(
      managed_repo_id,
      workspace_path,
      opts,
      QueryMemoryGraph,
      Map.put(memory_graph_params(opts, [:revision, :graph_name, :allow_stale?]), :sparql, sparql)
    )
  end

  @doc """
  Invalidates current memory-graph validation state with a bounded typed outcome.
  """
  @spec invalidate_memory_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def invalidate_memory_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, _pod} <- ensure_memory_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- memory_graph_action_context(managed_repo_id, workspace_path, opts) do
      case InvalidateMemoryGraph.run(memory_graph_params(opts, [:revision, :graph_name, :reason]), action_context) do
        {:ok, result} ->
          with {:ok, _pod_entry} <-
                 persist_memory_graph_state(managed_repo_id, %{
                   latest_validation_status: result.latest_validation_status,
                   latest_failure: nil
                 }) do
            {:ok, result}
          end

        other ->
          other
      end
    end
  end

  @doc """
  Recovers repository-scoped memory graph state after stale, invalidated, or failed memory behavior.
  """
  @spec recover_memory_graph(managed_repo_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def recover_memory_graph(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, status} <- memory_graph_status(managed_repo_id, workspace_path, opts) do
      recovery_action = memory_graph_recovery_action(status, opts)

      case recovery_action do
        :none ->
          {:ok,
           %{
             status: :memory_graph_recovery_not_needed,
             recovery_action: :none,
             graph_status: status
           }}

        action ->
          case run_memory_graph_recovery(
                 managed_repo_id,
                 workspace_path,
                 action,
                 Keyword.put(opts, :graph_status, status)
               ) do
            {:ok, result} ->
              {:ok,
               %{
                 status: :memory_graph_recovered,
                 recovery_action: action,
                 graph_status:
                   normalize_memory_graph_recovery_result(
                     managed_repo_id,
                     workspace_path,
                     result,
                     opts
                   ),
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

  ## Private Functions

  defp pod_name(work_item_id), do: coding_pod_id(work_item_id)

  defp coding_pod_id(work_item_id), do: "coding-pod-#{work_item_id}"

  defp ensure_repo_pod_entry(managed_repo_id) do
    with {:ok, _runtime} <- ensure_repository_runtime(managed_repo_id),
         {:ok, repo_pod} <- Runtime.ensure_repo_pod(managed_repo_id) do
      {:ok, repo_pod}
    end
  end

  defp pod_status(managed_repo_id, pod_id), do: Runtime.pod_status(managed_repo_id, pod_id)

  defp update_pod_metadata(managed_repo_id, pod_id, updates) do
    Runtime.update_pod_metadata(managed_repo_id, pod_id, updates)
  end

  defp retry_context_management_opts(opts, decision) do
    retry_context_opts =
      opts
      |> context_management_opts()
      |> Keyword.merge(
        allow_debounced_recommendation?: true,
        recommendation_id: Map.get(decision, "id"),
        debounce_key: Map.get(decision, "debounce_key")
      )

    Keyword.put(opts, :context_management, retry_context_opts)
  end

  defp latest_monitor_decision(metadata) when is_map(metadata) do
    metadata
    |> Map.get(:latest_monitor_decision, Map.get(metadata, "latest_monitor_decision", %{}))
    |> ContextManagement.public_payload()
    |> case do
      %{} = decision -> decision
      _other -> %{}
    end
  end

  defp latest_monitor_decision(_metadata), do: %{}

  defp context_management_opts(opts) when is_list(opts) do
    nested =
      opts
      |> Keyword.get(:context_management, [])
      |> case do
        context_opts when is_list(context_opts) -> context_opts
        %{} = context_opts -> Map.to_list(context_opts)
        _other -> []
      end

    direct =
      Keyword.take(opts, [
        :enabled?,
        :compaction_enabled?,
        :auto_compaction_enabled?,
        :high_water_mark,
        :repeated_trim_threshold,
        :debounce_window_ms,
        :max_summary_tokens,
        :max_candidate_tokens
      ])

    Keyword.merge(nested, direct)
  end

  defp context_management_summary_opts(opts) when is_list(opts) do
    opts
    |> context_management_opts()
    |> Keyword.merge(Keyword.take(opts, [:workflow, :specialist_role, :limit]))
  end

  defp ensure_coding_specialist(managed_repo_id, work_item_id, node_name) do
    Runtime.ensure_work_item_node(managed_repo_id, work_item_id, node_name)
  end

  defp resolve_workspace_path(managed_repo_id, work_item_id, workspace_path) when is_binary(workspace_path) do
    case String.trim(workspace_path) do
      "" -> resolve_workspace_path(managed_repo_id, work_item_id, nil)
      path -> {:ok, Path.expand(path)}
    end
  end

  defp resolve_workspace_path(managed_repo_id, work_item_id, _workspace_path) do
    case pod_status(managed_repo_id, coding_pod_id(work_item_id)) do
      %{metadata: %{workspace_path: path}} when is_binary(path) and path != "" ->
        {:ok, path}

      _other ->
        {:error, :missing_workspace_path}
    end
  end

  defp run_specialist(
         agent_module,
         pid,
         instruction,
         managed_repo_id,
         work_item_id,
         workspace_path,
         semantic_context,
         memory_context,
         provenance_context,
         opts
       ) do
    stage = specialist_stage(agent_module)
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    tool_context =
      specialist_tool_context(managed_repo_id, workspace_path, semantic_context, memory_context, opts)

    agent_run_id = specialist_agent_run_id(stage, work_item_id)
    llm_selection = Keyword.get(opts, :llm_selection)

    with {:ok, task_context} <- start_task_board_stage(managed_repo_id, work_item_id, stage, instruction),
         {:ok, response} <-
           specialist_runner().run(
             agent_module,
             pid,
             instruction,
             tool_context: tool_context,
             llm_selection: llm_selection,
             timeout: Keyword.get(opts, :timeout, 30_000)
           ),
         :ok <- complete_task_board_stage(managed_repo_id, work_item_id, stage, task_context, response) do
      ended_at = DateTime.utc_now() |> DateTime.truncate(:second)

      _ =
        capture_specialist_success(
          managed_repo_id,
          workspace_path,
          provenance_context,
          stage,
          agent_module,
          agent_run_id,
          instruction,
          response,
          tool_context,
          started_at,
          ended_at,
          opts
        )

      _ =
        record_specialist_context_observation(
          managed_repo_id,
          work_item_id,
          stage,
          agent_module,
          opts,
          tool_context,
          :success
        )

      {:ok, response}
    else
      {:error, reason} = error ->
        _ = fail_task_board_stage(managed_repo_id, work_item_id, stage, instruction, reason)
        ended_at = DateTime.utc_now() |> DateTime.truncate(:second)

        _ =
          capture_specialist_failure(
            managed_repo_id,
            workspace_path,
            provenance_context,
            stage,
            agent_module,
            agent_run_id,
            instruction,
            reason,
            started_at,
            ended_at,
            opts
          )

        _ =
          record_specialist_context_observation(
            managed_repo_id,
            work_item_id,
            stage,
            agent_module,
            opts,
            tool_context,
            :failed
          )

        error
    end
  end

  defp record_specialist_context_observation(
         managed_repo_id,
         work_item_id,
         stage,
         agent_module,
         opts,
         tool_context,
         outcome
       ) do
    context_budget =
      (Keyword.get(opts, :context_budget) ||
         Map.get(tool_context, :context_budget) ||
         Map.get(tool_context, "context_budget"))
      |> ContextBudget.summary()

    record_context_observation(
      managed_repo_id,
      work_item_id,
      %{
        workflow: stage,
        specialist_role: agent_module |> agent_name() |> Macro.underscore(),
        source: "agent_workspace.specialist",
        context_budget: context_budget,
        diagnostics: %{
          outcome: outcome,
          tool_context_keys: Map.keys(tool_context)
        }
      },
      opts
    )
  end

  defp specialist_stage(Planner), do: :planning
  defp specialist_stage(Coder), do: :coding
  defp specialist_stage(Reviewer), do: :reviewing
  defp specialist_stage(Refactorer), do: :refactoring
  defp specialist_stage(Explainer), do: :explaining
  defp specialist_stage(_other), do: :working

  defp put_llm_selection(managed_repo_id, opts) when is_binary(managed_repo_id) and is_list(opts) do
    case LLMSelection.resolve(managed_repo_id, opts) do
      {:ok, selection} -> {:ok, Keyword.put(opts, :llm_selection, selection)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp llm_selection_summary(opts) when is_list(opts) do
    opts
    |> Keyword.get(:llm_selection)
    |> LLMSelection.summary()
  end

  defp sync_project_context(_managed_repo_id, work_item_id, workspace_path, pod_pid) when is_pid(pod_pid) do
    with {:ok, project_context_pid} <- Pod.ensure_node(pod_pid, :project_context),
         {:ok, _agent} <-
           AgentServer.call(
             project_context_pid,
             Signal.new!(
               "project.context.set",
               %{workspace_path: workspace_path, work_item_id: work_item_id, project_metadata: %{}},
               source: "/jido_code/agent_workspace"
             )
           ) do
      :ok
    end
  end

  defp start_task_board_stage(managed_repo_id, work_item_id, stage, instruction) do
    with {:ok, task_board_pid} <- task_board_pid(managed_repo_id, work_item_id),
         {:ok, task_id} <- ensure_task_board_task(task_board_pid, work_item_id, instruction),
         {:ok, _agent} <-
           append_task_board_event(
             task_board_pid,
             Atom.to_string(stage) <> ".started",
             "#{humanize_stage(stage)} started for work item #{work_item_id}.",
             task_id
           ) do
      {:ok, %{task_board_pid: task_board_pid, task_id: task_id}}
    end
  end

  defp complete_task_board_stage(
         _managed_repo_id,
         work_item_id,
         stage,
         %{task_board_pid: task_board_pid, task_id: task_id},
         response
       ) do
    artifact_content = normalize_specialist_result(response)

    with :ok <- store_task_board_artifact(task_board_pid, stage, task_id, artifact_content),
         {:ok, _agent} <-
           append_task_board_event(
             task_board_pid,
             Atom.to_string(stage) <> ".completed",
             "#{humanize_stage(stage)} completed for work item #{work_item_id}.",
             task_id
           ),
         :ok <- select_task_board_task(task_board_pid, task_id) do
      :ok
    end
  end

  defp fail_task_board_stage(managed_repo_id, work_item_id, stage, instruction, reason) do
    with {:ok, task_board_pid} <- task_board_pid(managed_repo_id, work_item_id),
         {:ok, task_id} <- ensure_task_board_task(task_board_pid, work_item_id, instruction) do
      _ =
        append_task_board_event(
          task_board_pid,
          Atom.to_string(stage) <> ".failed",
          "#{humanize_stage(stage)} failed for work item #{work_item_id}: #{inspect(reason)}.",
          task_id
        )

      :ok
    else
      _other -> :ok
    end
  end

  defp task_board_pid(managed_repo_id, work_item_id) do
    Runtime.ensure_work_item_node(managed_repo_id, work_item_id, :task_board)
  end

  defp ensure_task_board_task(task_board_pid, work_item_id, instruction) when is_pid(task_board_pid) do
    with {:ok, server_state} <- AgentServer.state(task_board_pid) do
      state = server_state.agent.state

      case Map.get(state, :active_task_id) || existing_task_id(state, work_item_id) do
        active_task_id when is_binary(active_task_id) and active_task_id != "" ->
          _ = select_task_board_task(task_board_pid, active_task_id)
          {:ok, active_task_id}

        _other ->
          case AgentServer.call(
                 task_board_pid,
                 Signal.new!(
                   "task.add",
                   %{
                     title: "Work item #{work_item_id}",
                     description: instruction,
                     priority: "medium",
                     metadata: %{work_item_id: work_item_id}
                   },
                   source: "/jido_code/agent_workspace"
                 )
               ) do
            {:ok, agent} ->
              {:ok, agent.state.active_task_id}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  defp existing_task_id(state, work_item_id) when is_map(state) do
    state
    |> Map.get(:tasks, [])
    |> Enum.find_value(fn
      %{id: task_id, metadata: %{work_item_id: ^work_item_id}} when is_binary(task_id) -> task_id
      _other -> nil
    end)
  end

  defp select_task_board_task(task_board_pid, task_id) do
    case AgentServer.call(
           task_board_pid,
           Signal.new!("task.select", %{task_id: task_id}, source: "/jido_code/agent_workspace")
         ) do
      {:ok, _agent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_task_board_artifact(task_board_pid, stage, task_id, content) do
    case AgentServer.call(
           task_board_pid,
           Signal.new!(
             "task.store",
             %{
               type: task_board_artifact_type(stage),
               content: stringify_artifact_content(content),
               task_id: task_id,
               metadata: %{stage: stage}
             },
             source: "/jido_code/agent_workspace"
           )
         ) do
      {:ok, _agent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_task_board_event(task_board_pid, event_type, message, task_id) do
    AgentServer.call(
      task_board_pid,
      Signal.new!(
        "task.event",
        %{event_type: event_type, message: message, data: %{task_id: task_id}},
        source: "/jido_code/agent_workspace"
      )
    )
  end

  defp task_board_artifact_type(:planning), do: "plan"
  defp task_board_artifact_type(:coding), do: "draft"
  defp task_board_artifact_type(:reviewing), do: "review"
  defp task_board_artifact_type(:refactoring), do: "refactor"
  defp task_board_artifact_type(:explaining), do: "explanation"
  defp task_board_artifact_type(_other), do: "artifact"

  defp humanize_stage(stage) when is_atom(stage) do
    stage
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp stringify_artifact_content(content) when is_binary(content), do: content
  defp stringify_artifact_content(content), do: inspect(content, pretty: true, limit: :infinity)

  defp specialist_tool_context(managed_repo_id, workspace_path, semantic_context, memory_context, opts) do
    base =
      %{
        managed_repo_id: managed_repo_id,
        workspace_path: workspace_path
      }
      |> maybe_put_context_budget(opts)

    base =
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

    case normalize_workflow_memory_context(memory_context) do
      nil ->
        base

      workflow_memory ->
        Map.put(base, :memory_graph, workflow_memory)
    end
  end

  defp maybe_put_context_budget(base, opts) do
    case Keyword.get(opts, :context_budget) do
      nil -> base
      context_budget -> Map.put(base, :context_budget, ContextBudget.summary(context_budget))
    end
  end

  defp put_compaction_summaries(managed_repo_id, work_item_id, workflow, opts) do
    summaries =
      context_compaction_summaries(managed_repo_id, work_item_id,
        workflow: workflow,
        limit: 6
      )

    Keyword.put(opts, :compaction_summaries, summaries)
  end

  defp specialist_prompt(workflow, instruction, semantic_context, memory_context, opts) do
    semantic_projection = PromptProjection.semantic(semantic_context)
    memory_projection = PromptProjection.memory(normalize_workflow_memory_context(memory_context))
    compaction_summaries = Keyword.get(opts, :compaction_summaries, [])

    policy =
      opts
      |> Keyword.get(:context_budget, [])
      |> context_budget_opts()
      |> Keyword.put(:llm_selection, Keyword.get(opts, :llm_selection))
      |> ContextBudget.policy()

    sections = [
      ContextBudget.section(:workflow, "Workflow: #{workflow}", retention: :important),
      ContextBudget.section(:current_request, "Instruction: #{instruction}", retention: :required),
      ContextBudget.section(:semantic_context, semantic_projection.lines,
        retention: :useful,
        metadata: semantic_projection.diagnostics
      ),
      ContextBudget.section(:memory_context, memory_projection.lines,
        retention: :important,
        metadata: memory_projection.diagnostics
      ),
      ContextBudget.section(
        :compaction_summary,
        compaction_summary_lines(compaction_summaries),
        retention: :useful,
        metadata: %{
          kind: :compaction_summary,
          summary_count: length(compaction_summaries),
          summary_ids: Enum.map(compaction_summaries, &Map.get(&1, "id"))
        }
      ),
      ContextBudget.section(
        :guidance,
        [
          "- Treat semantic and memory context as bounded prompt projections, not product truth.",
          "- Use structured tool context and current source inspection before relying on graph-derived summaries."
        ],
        retention: :important
      )
    ]

    packed = ContextBudget.pack(sections, policy: policy)

    {:ok,
     %{
       text: packed.text,
       context_budget: packed,
       semantic_projection: semantic_projection,
       memory_projection: memory_projection,
       compaction_summaries: compaction_summaries
     }}
  end

  defp compaction_summary_lines([]), do: []

  defp compaction_summary_lines(summaries) when is_list(summaries) do
    summaries
    |> Enum.map(fn summary ->
      summary_text = Map.get(summary, "summary_text", "")
      summary_id = Map.get(summary, "id", "unknown-summary")
      workflow = Map.get(summary, "workflow", "unknown-workflow")
      specialist_role = Map.get(summary, "specialist_role", "unknown-specialist")
      span_count = summary |> Map.get("source_span_ids", []) |> length()

      "- #{summary_id} (#{workflow}/#{specialist_role}, #{span_count} span(s)): #{summary_text}"
    end)
  end

  defp context_budget_opts(%{} = budget) do
    case Map.get(budget, "policy", Map.get(budget, :policy)) do
      %{} = policy ->
        context_budget_opts(policy)

      policy when is_list(policy) ->
        policy

      _other ->
        budget
        |> Enum.flat_map(fn {key, value} ->
          case context_budget_key(key) do
            nil -> []
            atom -> [{atom, value}]
          end
        end)
    end
  end

  defp context_budget_opts(opts) when is_list(opts), do: opts
  defp context_budget_opts(_opts), do: []

  defp context_budget_key(key) when is_atom(key), do: key

  defp context_budget_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp context_budget_key(_key), do: nil

  defp workflow_memory_context(_workflow, opts) when opts == [] do
    {:ok, %{}}
  end

  defp workflow_memory_context(_workflow, opts) when is_list(opts) do
    {:ok, normalize_workflow_memory_context(Keyword.get(opts, :memory_graph)) || %{}}
  end

  defp normalize_workflow_memory_context(nil), do: nil

  defp normalize_workflow_memory_context(%{} = memory_context) do
    %{
      workflow: Map.get(memory_context, :workflow),
      graph: normalize_nested_memory_map(Map.get(memory_context, :graph, %{})),
      freshness: normalize_nested_memory_map(Map.get(memory_context, :freshness, %{})),
      policy: normalize_nested_memory_map(Map.get(memory_context, :policy, %{})),
      selection: normalize_nested_memory_map(Map.get(memory_context, :selection, %{}))
    }
    |> Enum.reject(fn
      {_key, %{} = value} -> map_size(value) == 0
      {_key, nil} -> true
      _other -> false
    end)
    |> Map.new()
  end

  defp normalize_workflow_memory_context(_memory_context), do: nil

  defp normalize_nested_memory_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_boolean(nested_value) or is_nil(nested_value) -> nested_value
          match?(%DateTime{}, nested_value) -> DateTime.to_iso8601(nested_value)
          is_map(nested_value) -> normalize_nested_memory_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_memory_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_nested_memory_map(_value), do: %{}

  defp normalize_nested_memory_value(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_nested_memory_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_nested_memory_value(value) when is_map(value), do: normalize_nested_memory_map(value)
  defp normalize_nested_memory_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_memory_value/1)
  defp normalize_nested_memory_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_memory_value(value), do: value

  defp provenance_related_resources(opts) do
    opts
    |> Keyword.get(:provenance, [])
    |> Keyword.get(:related_resources, [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp provenance_governed_references(work_item_id, opts) do
    explicit =
      [
        work_item_id && %{kind: :work_item, id: work_item_id}
      ]
      |> Enum.reject(&is_nil/1)

    inherited =
      opts
      |> Keyword.get(:provenance, [])
      |> Keyword.get(:governed_references)
      |> GovernedReference.explicit_many()

    legacy =
      opts
      |> Keyword.get(:provenance, [])
      |> Keyword.get(:governed_context)
      |> GovernedReference.explicit_many()

    (explicit ++ inherited ++ legacy)
    |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end)
  end

  defp provenance_memory_policy(opts) do
    opts
    |> Keyword.get(:provenance, [])
    |> Keyword.get(:memory_policy)
    |> normalize_nested_memory_map()
    |> case do
      %{} = policy when map_size(policy) > 0 -> policy
      _other -> nil
    end
  end

  defp provenance_follow_up_intent(opts) do
    opts
    |> Keyword.get(:provenance, [])
    |> Keyword.get(:follow_up_intent)
    |> case do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> String.trim(value)
      _other -> nil
    end
  end

  defp provenance_llm_selection(opts) do
    opts
    |> Keyword.get(:llm_selection)
    |> LLMSelection.summary()
  end

  defp provenance_metadata(provenance_context) do
    %{}
    |> maybe_put_map_value(:memory_policy, Map.get(provenance_context, :memory_policy))
    |> maybe_put_map_value(:follow_up_intent, Map.get(provenance_context, :follow_up_intent))
    |> maybe_put_map_value(:llm_provider, get_in(provenance_context, [:llm_selection, :provider]))
    |> maybe_put_map_value(:llm_selection_source, get_in(provenance_context, [:llm_selection, :source]))
  end

  defp maybe_put_context_budget_metadata(metadata, opts) do
    case Keyword.get(opts, :context_budget) do
      nil -> metadata
      context_budget -> Map.put(metadata, :context_budget, ContextBudget.summary(context_budget))
    end
  end

  defp maybe_put_context_management_metadata(metadata, managed_repo_id, work_item_id)
       when is_binary(managed_repo_id) and is_binary(work_item_id) do
    Map.put(metadata, :context_management, context_management_status(managed_repo_id, work_item_id))
  end

  defp maybe_put_context_management_metadata(metadata, _managed_repo_id, _work_item_id), do: metadata

  defp maybe_put_map_value(map, _key, nil), do: map
  defp maybe_put_map_value(map, key, value), do: Map.put(map, key, value)

  defp normalize_specialist_result(%{summary: summary}) when is_binary(summary), do: summary
  defp normalize_specialist_result(%{result: result}), do: result
  defp normalize_specialist_result(result), do: result

  defp workflow_provenance_context(
         managed_repo_id,
         work_item_id,
         workspace_path,
         workflow,
         instruction,
         opts
       ) do
    actor_id = provenance_actor_id(opts)
    revision = provenance_revision(workspace_path, opts)

    context = %{
      enabled?: MemoryGraph.capability_enabled?(opts),
      session_id: provenance_session_id(work_item_id, workflow, opts),
      actor_id: actor_id,
      revision: revision,
      workflow: workflow,
      work_item_id: work_item_id,
      instruction: instruction,
      workspace_path: workspace_path,
      related_resources: provenance_related_resources(opts),
      governed_references: provenance_governed_references(work_item_id, opts),
      memory_policy: provenance_memory_policy(opts),
      follow_up_intent: provenance_follow_up_intent(opts),
      llm_selection: provenance_llm_selection(opts)
    }

    _ = capture_session_start(managed_repo_id, context, opts)
    {:ok, context}
  end

  defp capture_session_start(_managed_repo_id, %{enabled?: false}, _opts), do: :ok

  defp capture_session_start(managed_repo_id, provenance_context, opts) do
    session_capture =
      CaptureEnvelope.work_session(
        session_id: provenance_context.session_id,
        actor_id: provenance_context.actor_id,
        workflow: provenance_context.workflow,
        work_item_id: provenance_context.work_item_id,
        goal: provenance_context.instruction,
        outcome: "started",
        model: provenance_model_name(provenance_context),
        revision: provenance_context.revision,
        related_resources: provenance_context.related_resources,
        governed_references: provenance_context.governed_references,
        metadata: provenance_metadata(provenance_context)
      )

    prompt_capture =
      CaptureEnvelope.prompt_turn(
        session_id: provenance_context.session_id,
        actor_id: provenance_context.actor_id,
        workflow: provenance_context.workflow,
        work_item_id: provenance_context.work_item_id,
        content: provenance_context.instruction,
        model: provenance_model_name(provenance_context),
        revision: provenance_context.revision,
        related_resources: provenance_context.related_resources,
        governed_references: provenance_context.governed_references,
        metadata: provenance_metadata(provenance_context)
      )

    capture_workflow_provenance_safe(managed_repo_id, provenance_context.workspace_path, session_capture, opts)
    capture_workflow_provenance_safe(managed_repo_id, provenance_context.workspace_path, prompt_capture, opts)
  end

  defp capture_specialist_success(
         _managed_repo_id,
         _workspace_path,
         %{enabled?: false},
         _stage,
         _agent_module,
         _agent_run_id,
         _instruction,
         _response,
         _tool_context,
         _started_at,
         _ended_at,
         _opts
       ),
       do: :ok

  defp capture_specialist_success(
         managed_repo_id,
         workspace_path,
         provenance_context,
         stage,
         agent_module,
         agent_run_id,
         instruction,
         response,
         tool_context,
         started_at,
         ended_at,
         opts
       ) do
    agent_run_capture =
      CaptureEnvelope.agent_run(
        session_id: provenance_context.session_id,
        id: agent_run_id,
        actor_id: provenance_context.actor_id,
        workflow: provenance_context.workflow,
        work_item_id: provenance_context.work_item_id,
        agent_name: agent_name(agent_module),
        content: "#{instruction}\n\nOutcome: success",
        started_at: started_at,
        ended_at: ended_at,
        model: provenance_model_name(provenance_context),
        revision: provenance_context.revision,
        governed_references: provenance_context.governed_references,
        related_resources: provenance_context.related_resources,
        metadata:
          provenance_metadata(provenance_context)
          |> Map.put(:stage, stage)
          |> maybe_put_context_budget_metadata(opts)
          |> maybe_put_context_management_metadata(managed_repo_id, provenance_context.work_item_id)
      )

    tool_capture =
      CaptureEnvelope.tool_invocation(
        session_id: provenance_context.session_id,
        actor_id: provenance_context.actor_id,
        workflow: provenance_context.workflow,
        work_item_id: provenance_context.work_item_id,
        agent_run_id: agent_run_id,
        tool_name: "specialist_tool_context",
        content: inspect(%{agent: agent_name(agent_module), keys: Map.keys(tool_context)}, pretty: true),
        started_at: started_at,
        ended_at: ended_at,
        model: provenance_model_name(provenance_context),
        revision: provenance_context.revision,
        governed_references: provenance_context.governed_references,
        related_resources: provenance_context.related_resources,
        metadata:
          provenance_metadata(provenance_context)
          |> Map.put(:stage, stage)
          |> maybe_put_context_budget_metadata(opts)
          |> maybe_put_context_management_metadata(managed_repo_id, provenance_context.work_item_id)
      )

    artifact_capture =
      specialist_artifact_capture(
        stage,
        provenance_context,
        agent_run_id,
        normalize_specialist_result(response),
        started_at,
        ended_at
      )

    capture_workflow_provenance_safe(managed_repo_id, workspace_path, agent_run_capture, opts)
    capture_workflow_provenance_safe(managed_repo_id, workspace_path, tool_capture, opts)

    if artifact_capture do
      capture_workflow_provenance_safe(managed_repo_id, workspace_path, artifact_capture, opts)
    end

    :ok
  end

  defp capture_specialist_failure(
         _managed_repo_id,
         _workspace_path,
         %{enabled?: false},
         _stage,
         _agent_module,
         _agent_run_id,
         _instruction,
         _reason,
         _started_at,
         _ended_at,
         _opts
       ),
       do: :ok

  defp capture_specialist_failure(
         managed_repo_id,
         workspace_path,
         provenance_context,
         stage,
         agent_module,
         agent_run_id,
         instruction,
         reason,
         started_at,
         ended_at,
         opts
       ) do
    agent_run_capture =
      CaptureEnvelope.agent_run(
        session_id: provenance_context.session_id,
        id: agent_run_id,
        actor_id: provenance_context.actor_id,
        workflow: provenance_context.workflow,
        work_item_id: provenance_context.work_item_id,
        agent_name: agent_name(agent_module),
        content: "#{instruction}\n\nOutcome: failed\n#{inspect(reason)}",
        started_at: started_at,
        ended_at: ended_at,
        model: provenance_model_name(provenance_context),
        revision: provenance_context.revision,
        governed_references: provenance_context.governed_references,
        related_resources: provenance_context.related_resources,
        metadata:
          provenance_metadata(provenance_context)
          |> Map.put(:stage, stage)
          |> Map.put(:failure, inspect(reason))
          |> maybe_put_context_budget_metadata(opts)
          |> maybe_put_context_management_metadata(managed_repo_id, provenance_context.work_item_id)
      )

    capture_workflow_provenance_safe(managed_repo_id, workspace_path, agent_run_capture, opts)
  end

  defp specialist_artifact_capture(:planning, provenance_context, agent_run_id, content, started_at, ended_at) do
    CaptureEnvelope.plan(
      session_id: provenance_context.session_id,
      actor_id: provenance_context.actor_id,
      workflow: provenance_context.workflow,
      work_item_id: provenance_context.work_item_id,
      agent_run_id: agent_run_id,
      content: stringify_artifact_content(content),
      started_at: started_at,
      ended_at: ended_at,
      model: provenance_model_name(provenance_context),
      revision: provenance_context.revision,
      governed_references: provenance_context.governed_references,
      related_resources: provenance_context.related_resources,
      metadata: provenance_metadata(provenance_context)
    )
  end

  defp specialist_artifact_capture(:coding, provenance_context, agent_run_id, content, started_at, ended_at) do
    CaptureEnvelope.patch(
      session_id: provenance_context.session_id,
      actor_id: provenance_context.actor_id,
      workflow: provenance_context.workflow,
      work_item_id: provenance_context.work_item_id,
      agent_run_id: agent_run_id,
      content: stringify_artifact_content(content),
      started_at: started_at,
      ended_at: ended_at,
      model: provenance_model_name(provenance_context),
      revision: provenance_context.revision,
      governed_references: provenance_context.governed_references,
      related_resources: provenance_context.related_resources,
      metadata: provenance_metadata(provenance_context)
    )
  end

  defp specialist_artifact_capture(:refactoring, provenance_context, agent_run_id, content, started_at, ended_at) do
    CaptureEnvelope.patch(
      session_id: provenance_context.session_id,
      actor_id: provenance_context.actor_id,
      workflow: provenance_context.workflow,
      work_item_id: provenance_context.work_item_id,
      agent_run_id: agent_run_id,
      content: stringify_artifact_content(content),
      started_at: started_at,
      ended_at: ended_at,
      model: provenance_model_name(provenance_context),
      revision: provenance_context.revision,
      governed_references: provenance_context.governed_references,
      related_resources: provenance_context.related_resources,
      metadata: provenance_metadata(provenance_context)
    )
  end

  defp specialist_artifact_capture(:reviewing, provenance_context, agent_run_id, content, started_at, ended_at) do
    CaptureEnvelope.review(
      session_id: provenance_context.session_id,
      actor_id: provenance_context.actor_id,
      workflow: provenance_context.workflow,
      work_item_id: provenance_context.work_item_id,
      agent_run_id: agent_run_id,
      content: stringify_artifact_content(content),
      started_at: started_at,
      ended_at: ended_at,
      model: provenance_model_name(provenance_context),
      revision: provenance_context.revision,
      governed_references: provenance_context.governed_references,
      related_resources: provenance_context.related_resources,
      metadata: provenance_metadata(provenance_context)
    )
  end

  defp specialist_artifact_capture(_stage, _provenance_context, _agent_run_id, _content, _started_at, _ended_at),
    do: nil

  defp capture_workflow_provenance_safe(managed_repo_id, workspace_path, capture, opts) do
    if MemoryGraph.capability_enabled?(opts) do
      capture_revision = Map.get(capture, :revision)

      with :ok <- ensure_workflow_provenance_ready(managed_repo_id, workspace_path, capture_revision, opts),
           {:ok, _result} <-
             record_memory_graph(
               managed_repo_id,
               workspace_path,
               capture,
               [graph_name: MemoryGraph.workflow_provenance_graph_name(), revision: capture_revision] ++ opts
             ) do
        :ok
      else
        _other -> :ok
      end
    else
      :ok
    end
  end

  defp ensure_workflow_provenance_ready(managed_repo_id, workspace_path, revision, _opts) do
    case memory_graph_status(
           managed_repo_id,
           workspace_path,
           graph_name: MemoryGraph.workflow_provenance_graph_name(),
           revision: revision
         ) do
      {:ok, %{ready?: true, stale?: false}} ->
        :ok

      {:ok, _status} ->
        case refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             ) do
          {:ok, _result} -> :ok
          _other -> {:error, :memory_graph_not_ready}
        end

      _other ->
        {:error, :memory_graph_not_ready}
    end
  end

  defp provenance_summary(%{enabled?: false}), do: nil

  defp provenance_summary(provenance_context) do
    %{
      session_id: provenance_context.session_id,
      actor_id: provenance_context.actor_id,
      revision: provenance_context.revision,
      workflow: provenance_context.workflow,
      related_resources: Map.get(provenance_context, :related_resources, []),
      memory_policy: Map.get(provenance_context, :memory_policy),
      follow_up_intent: Map.get(provenance_context, :follow_up_intent),
      llm_selection: Map.get(provenance_context, :llm_selection)
    }
  end

  defp provenance_model_name(provenance_context) do
    case Map.get(provenance_context, :llm_selection, %{}) do
      %{} = llm_selection -> Map.get(llm_selection, :model_spec) || Map.get(llm_selection, "model_spec")
      _other -> nil
    end
  end

  defp provenance_session_id(work_item_id, workflow, opts) do
    opts
    |> Keyword.get(:provenance, [])
    |> Keyword.get(:session_id, "#{workflow}-#{work_item_id}-#{System.unique_integer([:positive])}")
  end

  defp provenance_actor_id(opts) do
    provenance_opts = Keyword.get(opts, :provenance, [])

    provenance_opts
    |> Keyword.get(
      :actor_id,
      actor_id_from_option(Keyword.get(opts, :actor)) || actor_id_from_option(@workflow_provenance_actor)
    )
  end

  defp provenance_revision(workspace_path, opts) do
    revision =
      opts
      |> Keyword.get(:provenance, [])
      |> Keyword.get(:revision, Keyword.get(opts, :revision))

    case MemoryGraph.current_revision_metadata(workspace_path, revision: revision) do
      {:ok, revision_metadata} -> revision_metadata.current_revision
      {:error, _reason} -> revision
    end
  end

  defp specialist_agent_run_id(stage, work_item_id) do
    "#{stage}-#{work_item_id}-#{System.unique_integer([:positive])}"
  end

  defp agent_name(agent_module) do
    agent_module
    |> Module.split()
    |> List.last()
  end

  defp actor_id_from_option(nil), do: nil
  defp actor_id_from_option(%{} = actor), do: actor["id"] || actor[:id]
  defp actor_id_from_option(value) when is_binary(value), do: value
  defp actor_id_from_option(_value), do: nil

  defp persist_coding_pod_result(managed_repo_id, work_item_id, runtime_status, updates) do
    _ =
      update_pod_metadata(
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

  defp ensure_source_code_graph_enabled(opts) do
    if SourceCodeGraph.capability_enabled?(opts) do
      :ok
    else
      {:error, :source_code_graph_disabled}
    end
  end

  defp maybe_ensure_source_watcher(managed_repo_id, workspace_path, opts) do
    watcher_opts = Keyword.take(opts, [:start_file_system?, :debounce_ms])

    case RepoMonitor.ensure_source_watcher(managed_repo_id, workspace_path, watcher_opts) do
      {:ok, _pid} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp normalize_changed_source_path(workspace_path, changed_path) when is_binary(changed_path) do
    case Path.type(changed_path) do
      :absolute -> changed_path
      _relative -> Path.join(workspace_path, changed_path)
    end
  end

  defp ensure_memory_graph_enabled(opts) do
    if MemoryGraph.capability_enabled?(opts) do
      :ok
    else
      {:error, :memory_graph_disabled}
    end
  end

  defp initialize_source_code_graph_metadata(nil, managed_repo_id, workspace_path, opts) do
    with {:ok, pod_metadata} <- SourceCodeGraph.pod_metadata(managed_repo_id, workspace_path, opts) do
      update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), pod_metadata)
    end
  end

  defp initialize_source_code_graph_metadata(pod_entry, managed_repo_id, _workspace_path, _opts) do
    {:ok, pod_status(managed_repo_id, SourceCodeGraph.pod_id()) || pod_entry}
  end

  defp initialize_memory_graph_metadata(nil, managed_repo_id, workspace_path, opts) do
    with {:ok, pod_metadata} <- MemoryGraph.pod_metadata(managed_repo_id, workspace_path, opts) do
      update_pod_metadata(managed_repo_id, MemoryGraph.pod_id(), pod_metadata)
    end
  end

  defp initialize_memory_graph_metadata(pod_entry, managed_repo_id, _workspace_path, _opts) do
    {:ok, pod_status(managed_repo_id, MemoryGraph.pod_id()) || pod_entry}
  end

  defp source_code_graph_action_context(managed_repo_id, workspace_path, opts) do
    pod_entry = pod_status(managed_repo_id, SourceCodeGraph.pod_id())

    context = %{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      latest_import_status: get_in(pod_entry, [:metadata, :latest_import_status]),
      latest_analysis_status: get_in(pod_entry, [:metadata, :latest_analysis_status]),
      latest_failure: get_in(pod_entry, [:metadata, :latest_failure]),
      source_graph_refresh: get_in(pod_entry, [:metadata, :source_graph_refresh]),
      graph: %{revision: Keyword.get(opts, :revision)}
    }

    with {:ok, _graph_context} <- SourceCodeGraph.graph_context(managed_repo_id, workspace_path, opts) do
      {:ok, context}
    end
  end

  defp memory_graph_action_context(managed_repo_id, workspace_path, opts) do
    pod_entry = pod_status(managed_repo_id, MemoryGraph.pod_id())

    context = %{
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      graph_name: Keyword.get(opts, :graph_name, MemoryGraph.memory_graph_name()),
      latest_record_status: get_in(pod_entry, [:metadata, :latest_record_status]),
      latest_query_status: get_in(pod_entry, [:metadata, :latest_query_status]),
      latest_validation_status: get_in(pod_entry, [:metadata, :latest_validation_status]),
      latest_failure: get_in(pod_entry, [:metadata, :latest_failure]),
      graph: %{revision: Keyword.get(opts, :revision)}
    }

    with {:ok, _graph_context} <- MemoryGraph.graph_context(managed_repo_id, workspace_path, opts) do
      {:ok, context}
    end
  end

  defp persist_source_code_graph_state(managed_repo_id, updates) when is_map(updates) do
    update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), updates)
  end

  defp persist_memory_graph_state(managed_repo_id, updates) when is_map(updates) do
    update_pod_metadata(managed_repo_id, MemoryGraph.pod_id(), updates)
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

  defp persist_memory_graph_failure(managed_repo_id, operation, reason, diagnostics, updates)
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

    persist_memory_graph_state(managed_repo_id, merged_updates)
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

  defp memory_graph_summary(managed_repo_id, pod_entry) do
    %{
      managed_repo_id: managed_repo_id,
      pod_id: pod_entry.pod_id,
      graph_names: get_in(pod_entry, [:metadata, :graph_names]) || MemoryGraph.graph_names(),
      named_graph_iris: get_in(pod_entry, [:metadata, :named_graph_iris]) || MemoryGraph.named_graph_iris(),
      workspace_path: get_in(pod_entry, [:metadata, :workspace_path]),
      graph_store_path: get_in(pod_entry, [:metadata, :graph_store_path]),
      ready?: get_in(pod_entry, [:metadata, :latest_validation_status, :ready?]) || false,
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

        {:error, reason, diagnostics} ->
          if reason == :source_code_graph_query_failed and is_map(diagnostics) do
            persist_source_code_graph_failure(managed_repo_id, :query, reason, diagnostics)
          end

          {:error, reason, diagnostics}

        other ->
          other
      end
    end
  end

  defp run_memory_graph_action(managed_repo_id, workspace_path, opts, action_module, params)
       when is_atom(action_module) and is_map(params) do
    with {:ok, _pod} <- ensure_memory_graph_pod(managed_repo_id, workspace_path, opts),
         {:ok, action_context} <- memory_graph_action_context(managed_repo_id, workspace_path, opts) do
      case action_module.run(params, action_context) do
        {:ok, result} ->
          normalized_result =
            normalize_memory_graph_query_result(
              managed_repo_id,
              workspace_path,
              result,
              opts
            )

          with {:ok, _pod_entry} <-
                 persist_memory_graph_state(managed_repo_id, %{
                   latest_query_status: success_query_status(normalized_result),
                   latest_failure: nil
                 }) do
            {:ok, normalized_result}
          end

        {:error, reason, diagnostics} ->
          normalized_diagnostics =
            normalize_memory_graph_error_diagnostics(
              managed_repo_id,
              workspace_path,
              reason,
              diagnostics,
              opts
            )

          if reason == :memory_graph_query_failed and is_map(normalized_diagnostics) do
            persist_memory_graph_failure(
              managed_repo_id,
              :query,
              reason,
              extract_memory_graph_failure_diagnostics(normalized_diagnostics),
              %{latest_query_status: failure_query_status(action_context, normalized_diagnostics)}
            )
          end

          {:error, reason, normalized_diagnostics}

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

  defp memory_graph_recovery_action(status, opts) do
    case Keyword.get(opts, :mode, :auto) do
      :auto ->
        cond do
          status.latest_failure ->
            :recover

          Map.get(status, :state) == :invalidated or status.stale? ->
            :validate

          not status.ready? ->
            :refresh

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

  defp run_memory_graph_recovery(managed_repo_id, workspace_path, :recover, opts) do
    graph_status = Keyword.get(opts, :graph_status, %{})
    recovery_opts = opts |> Keyword.delete(:mode) |> Keyword.delete(:graph_status)

    if get_in(graph_status, [:latest_failure, :kind]) == :memory_graph_semantic_cutover_required do
      refresh_memory_graph(managed_repo_id, workspace_path, Keyword.put(recovery_opts, :reset_store?, true))
    else
      refresh_memory_graph(managed_repo_id, workspace_path, recovery_opts)
    end
  end

  defp run_memory_graph_recovery(managed_repo_id, workspace_path, :refresh, opts) do
    refresh_memory_graph(
      managed_repo_id,
      workspace_path,
      opts |> Keyword.delete(:mode) |> Keyword.delete(:graph_status)
    )
  end

  defp run_memory_graph_recovery(managed_repo_id, workspace_path, :validate, opts) do
    validate_memory_graph(
      managed_repo_id,
      workspace_path,
      opts |> Keyword.delete(:mode) |> Keyword.delete(:graph_status)
    )
  end

  defp run_memory_graph_recovery(managed_repo_id, workspace_path, :status, opts) do
    memory_graph_status(managed_repo_id, workspace_path, opts |> Keyword.delete(:mode) |> Keyword.delete(:graph_status))
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
      "Graph operation #{reason}"
  end

  defp failure_message(reason, _diagnostics), do: "Graph operation #{reason}"

  defp maybe_analysis_update(%{latest_analysis_status: latest_analysis_status})
       when is_map(latest_analysis_status) do
    %{latest_analysis_status: latest_analysis_status}
  end

  defp maybe_analysis_update(_diagnostics), do: %{}

  defp failure_validation_status(action_context, diagnostics) do
    %{
      state: :validation_failed,
      ready?: false,
      graph_name: action_context[:graph_name] || MemoryGraph.memory_graph_name(),
      current_revision: get_in(action_context, [:graph, :revision]),
      validated_revision: nil,
      validated_at: nil,
      stale?: false,
      failure: diagnostics
    }
  end

  defp failure_record_status(action_context, reason, diagnostics) do
    %{
      state: :record_rejected,
      ready?: false,
      graph_name: action_context[:graph_name] || MemoryGraph.memory_graph_name(),
      recorded_at: nil,
      failure: %{
        kind: reason,
        detail: diagnostics
      }
    }
  end

  defp success_query_status(result) when is_map(result) do
    %{
      state: :queried,
      ready?: true,
      graph_name: Map.get(result, :graph_name, MemoryGraph.memory_graph_name()),
      queried_at: DateTime.utc_now(),
      row_count: Map.get(result, :row_count, 0),
      failure: nil
    }
  end

  defp failure_query_status(action_context, diagnostics) do
    %{
      state: :query_failed,
      ready?: false,
      graph_name: action_context[:graph_name] || MemoryGraph.memory_graph_name(),
      queried_at: DateTime.utc_now(),
      failure: extract_memory_graph_failure_diagnostics(diagnostics)
    }
  end

  defp normalize_memory_graph_status(managed_repo_id, workspace_path, status, opts) when is_map(status) do
    cross_graph = memory_graph_cross_graph_summary(managed_repo_id, workspace_path, status, opts)

    status
    |> Map.put(:cross_graph, cross_graph)
    |> MemoryGraphProductFeedback.normalize_graph()
    |> then(fn normalized ->
      status
      |> Map.merge(%{
        state: normalized.state,
        recovery_action: normalized.recovery_action,
        cross_graph: normalized.cross_graph,
        semantic_model:
          Map.get(status, :semantic_model) || get_in(status, [:latest_validation_status, :semantic_model]),
        feedback: MemoryGraphProductFeedback.for_graph(normalized)
      })
    end)
  end

  defp normalize_memory_graph_query_result(managed_repo_id, workspace_path, result, opts)
       when is_map(result) do
    status =
      %{
        graph_name: Map.get(result, :graph_name, MemoryGraph.memory_graph_name()),
        ready?: true,
        stale?: Map.get(result, :stale_graph?, false),
        degraded?: Map.get(result, :degraded?, false),
        queryable_when_stale?: Map.get(result, :degraded?, false),
        current_revision: Map.get(result, :current_revision),
        validated_revision: Map.get(result, :validated_revision),
        latest_failure: nil
      }

    cross_graph = memory_graph_cross_graph_summary(managed_repo_id, workspace_path, status, opts)
    normalized = status |> Map.put(:cross_graph, cross_graph) |> MemoryGraphProductFeedback.normalize_graph()

    Map.merge(result, %{
      state: normalized.state,
      recovery_action: normalized.recovery_action,
      cross_graph: normalized.cross_graph,
      feedback: MemoryGraphProductFeedback.for_graph(normalized)
    })
  end

  defp normalize_memory_graph_error_diagnostics(managed_repo_id, workspace_path, reason, diagnostics, opts) do
    status =
      case memory_graph_status(managed_repo_id, workspace_path, opts) do
        {:ok, status} ->
          status

        _other ->
          MemoryGraphProductFeedback.fallback_graph(reason)
      end

    normalized_graph =
      status
      |> Map.put(:latest_failure, extract_memory_graph_failure_diagnostics(diagnostics))
      |> Map.put(:state, Map.get(status, :state, nil))
      |> MemoryGraphProductFeedback.normalize_graph(reason)

    detail =
      diagnostics_detail(diagnostics) ||
        MemoryGraphProductFeedback.for_graph(normalized_graph, %{type: reason}).detail

    %{
      stage: diagnostics_stage(diagnostics),
      reason: diagnostics_reason(diagnostics),
      graph: normalized_graph,
      feedback: MemoryGraphProductFeedback.for_graph(normalized_graph, %{type: reason}),
      error: %{type: reason, detail: detail},
      diagnostics: diagnostics
    }
  end

  defp memory_graph_cross_graph_summary(managed_repo_id, workspace_path, status, opts) do
    source_code =
      if SourceCodeGraph.capability_enabled?(opts) do
        case source_code_graph_status(
               managed_repo_id,
               workspace_path,
               Keyword.take(opts, [:revision, :enabled?, :allow_stale?])
             ) do
          {:ok, source_status} ->
            %{
              graph_name: SourceCodeGraph.graph_name(),
              ready?: source_status.ready?,
              stale?: source_status.stale?,
              state: source_code_dependency_state(source_status),
              imported_revision: Map.get(source_status, :imported_revision),
              recovery_action: Map.get(source_status, :recovery_action)
            }

          {:error, reason} ->
            %{
              graph_name: SourceCodeGraph.graph_name(),
              ready?: false,
              stale?: false,
              state: fallback_source_state(reason)
            }

          {:error, reason, _detail} ->
            %{
              graph_name: SourceCodeGraph.graph_name(),
              ready?: false,
              stale?: false,
              state: fallback_source_state(reason)
            }
        end
      else
        %{graph_name: SourceCodeGraph.graph_name(), ready?: false, stale?: false, state: :disabled}
      end

    workflow_provenance = %{
      graph_name: MemoryGraph.workflow_provenance_graph_name(),
      named_graph_iri: MemoryGraph.workflow_provenance_named_graph_iri(),
      ready?: Map.get(status, :ready?, false),
      stale?: Map.get(status, :stale?, false),
      current_revision: Map.get(status, :current_revision),
      validated_revision: Map.get(status, :validated_revision)
    }

    %{
      source_code: source_code,
      workflow_provenance: workflow_provenance,
      consistency: %{
        state: memory_graph_consistency_state(status, source_code),
        explainable?: true
      }
    }
  end

  defp memory_graph_consistency_state(_status, %{state: :disabled}), do: :source_code_disabled

  defp memory_graph_consistency_state(_status, %{state: state}) when state in [:not_ready, :unavailable],
    do: :source_code_unavailable

  defp memory_graph_consistency_state(_status, %{stale?: true}), do: :source_code_stale

  defp memory_graph_consistency_state(status, %{imported_revision: imported_revision})
       when is_binary(imported_revision) do
    case Map.get(status, :validated_revision) do
      ^imported_revision -> :aligned
      nil -> :source_code_unavailable
      _other -> :revision_mismatch
    end
  end

  defp memory_graph_consistency_state(_status, _source_code), do: :aligned

  defp fallback_source_state(:source_code_graph_disabled), do: :disabled
  defp fallback_source_state(:source_code_graph_not_ready), do: :not_ready
  defp fallback_source_state(_reason), do: :unavailable

  defp source_code_dependency_state(source_status) when is_map(source_status) do
    cond do
      latest_failure = Map.get(source_status, :latest_failure) ->
        if latest_failure, do: :failed, else: :unavailable

      Map.get(source_status, :stale?, false) ->
        :stale

      Map.get(source_status, :ready?, false) ->
        :ready

      true ->
        :not_ready
    end
  end

  defp normalize_memory_graph_recovery_result(managed_repo_id, workspace_path, result, opts)
       when is_map(result) do
    case result do
      %{graph_status: %{} = graph_status} ->
        normalize_memory_graph_status(managed_repo_id, workspace_path, graph_status, opts)

      %{graph_name: _graph_name} ->
        normalize_memory_graph_status(managed_repo_id, workspace_path, result, opts)

      _other ->
        case memory_graph_status(managed_repo_id, workspace_path, opts) do
          {:ok, status} -> status
          _other -> MemoryGraphProductFeedback.fallback_graph(:memory_graph_not_ready)
        end
    end
  end

  defp extract_memory_graph_failure_diagnostics(%{diagnostics: diagnostics}) when is_map(diagnostics),
    do: diagnostics

  defp extract_memory_graph_failure_diagnostics(%{error: %{detail: detail}} = diagnostics) when is_map(diagnostics) do
    Map.merge(Map.drop(diagnostics, [:graph, :feedback, :error, :diagnostics]), %{reason: detail})
  end

  defp extract_memory_graph_failure_diagnostics(diagnostics) when is_map(diagnostics), do: diagnostics
  defp extract_memory_graph_failure_diagnostics(_diagnostics), do: %{}

  defp diagnostics_detail(%{error: %{detail: detail}}) when is_binary(detail), do: detail
  defp diagnostics_detail(%{detail: detail}) when is_binary(detail), do: detail
  defp diagnostics_detail(%{reason: reason}) when is_binary(reason), do: reason
  defp diagnostics_detail(_diagnostics), do: nil

  defp diagnostics_stage(%{stage: stage}) when not is_nil(stage), do: stage
  defp diagnostics_stage(%{diagnostics: %{stage: stage}}) when not is_nil(stage), do: stage
  defp diagnostics_stage(_diagnostics), do: nil

  defp diagnostics_reason(%{reason: reason}) when is_binary(reason), do: reason
  defp diagnostics_reason(%{diagnostics: %{reason: reason}}) when is_binary(reason), do: reason
  defp diagnostics_reason(_diagnostics), do: nil

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

  defp conversation_actor(opts) when is_list(opts) do
    opts
    |> Keyword.get(:actor)
    |> case do
      %{} = actor -> Actor.operator_actor(actor)
      _other -> Actor.operator_actor()
    end
  end

  defp source_code_graph_params(opts, allowed_keys \\ [:revision]) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.into(%{})
  end

  defp memory_graph_params(opts, allowed_keys \\ [:revision, :graph_name, :reset_store?]) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.into(%{})
  end
end
