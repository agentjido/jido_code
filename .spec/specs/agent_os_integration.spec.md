# AgentOS Integration

This subject defines how `JidoCode` integrates with `jido_agent_os` for durable, multi-repository coding operations using kernels, pods, and agents.

```spec-meta
id: architecture.agent_os_integration
kind: policy
status: proposed
summary: JidoCode integrates with jido_agent_os using one kernel per ManagedRepo, one RepoPod singleton per kernel for repository monitoring, optional repository-scoped specialist pods such as SourceCodeGraphPod with repository-local semantic readiness state preserved through AgentWorkspace, explicit source-graph helper actions for semantic lookup, explicit semantic-tool composition into selected coding specialists, and one CodingPod per WorkItem containing multiple collaborating AI agents.
decisions:
  - jido_code.jido_os_deprecation
  - jido_code.jido_agent_os_integration
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
surface:
  - .spec/decisions/jido_code.jido_agent_os_integration.md
  - .spec/decisions/jido_code.jido_os_deprecation.md
  - .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
  - lib/jido_code/agent_os.ex
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/pods/
  - lib/jido_code/agents/
  - lib/jido_code/actions/
```

## Requirements

```spec-requirements
- id: architecture.agent_os_integration.kernel_per_managed_repo
  statement: JidoCode shall create and manage one AgentOS kernel per ManagedRepo for isolated runtime boundaries.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.dynamic_kernel_lifecycle
  statement: Kernels shall be created on-demand when work begins on a ManagedRepo and shut down based on idle timeout or explicit close.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.repo_pod_singleton_per_kernel
  statement: Each kernel shall host exactly one RepoPod instance with eager agents for repository monitoring and work registry.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
  statement: When semantic source-code graph capability is enabled for a managed repository, its kernel shall host one repository-scoped SourceCodeGraphPod singleton for ontology extraction, named-graph loading, and semantic query.
  priority: should
  stability: proposed

- id: architecture.agent_os_integration.coding_pod_per_work_item
  statement: Each WorkItem shall have its own CodingPod instance within the repository's kernel, containing multiple collaborating agents.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.multiple_pods_parallel_execution
  statement: Multiple CodingPod instances shall execute in parallel within a single kernel, enabling concurrent work on different WorkItems.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.pod_contains_multiple_agents
  statement: Each CodingPod shall contain multiple agents (task_board, project_context, planner, coder, reviewer, refactorer, explainer) that collaborate via signals.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.eager_and_lazy_agent_activation
  statement: Task board and project context agents shall be eager (always running), while AI specialist agents (planner, coder, reviewer) shall be lazy (started on demand).
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.ecto_persistence_per_kernel
  statement: Each kernel shall be configured with Ecto persistence so kernel and pod state survive application restarts.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  statement: The AgentWorkspace context shall hide kernel and pod topology details from Phoenix controllers and LiveViews.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  statement: Product-owned work entrypoints shall integrate with AgentOS through `AgentWorkspace` by ensuring kernels and pods exist, then routing to appropriate agents within pods.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.actions_use_jido_action
  statement: All agent tools shall be implemented as Jido.Action modules with proper schema definitions and context handling.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.state_operations_modify_agent_state
  statement: Actions that modify agent state shall return StateOp operations alongside their results.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.pod_naming_convention
  statement: Pod instances shall follow the naming convention "coding-pod-{work_item_id}" for CodingPods and "repo-pod" for the singleton RepoPod.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.kernel_naming_convention
  statement: Kernels shall be named following the pattern :"repo_{managed_repo_id}" for clear mapping to ManagedRepos.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.signal_routing_within_pod
  statement: Signals shall be routed to specific agents within a pod using Jido.Pod.ensure_node/3 and Jido.AgentServer.call/3.
  priority: must
  stability: proposed

- id: architecture.agent_os_integration.pod_cleanup_on_completion
  statement: CodingPod instances shall be shut down and archived when work completes, with state persisted for potential resumption.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.agent_os_integration.scenario_kernel_creation_on_first_work
  covers:
    - architecture.agent_os_integration.kernel_per_managed_repo
    - architecture.agent_os_integration.dynamic_kernel_lifecycle
  given:
    - A ManagedRepo exists but no kernel has been created.
  when:
    - Work begins on a WorkItem for that ManagedRepo.
  then:
    - A new kernel is created with the ManagedRepo ID.
    - The RepoPod singleton starts within the kernel.
    - A CodingPod instance is created for the WorkItem.

- id: architecture.agent_os_integration.scenario_parallel_work_items_separate_pods
  covers:
    - architecture.agent_os_integration.coding_pod_per_work_item
    - architecture.agent_os_integration.multiple_pods_parallel_execution
  given:
    - A kernel exists for a ManagedRepo.
  when:
    - Multiple WorkItems are worked on simultaneously.
  then:
    - Each WorkItem gets its own CodingPod instance.
    - All CodingPods execute in parallel within the same kernel.
    - Each pod has isolated agent state.

- id: architecture.agent_os_integration.scenario_source_code_graph_pod_is_repo_scoped
  covers:
    - architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
    - architecture.agent_os_integration.kernel_per_managed_repo
  given:
    - Semantic source-code graph capability is enabled for a managed repository.
  when:
    - The repository kernel is prepared for semantic analysis work.
  then:
    - The kernel hosts one repository-scoped SourceCodeGraphPod singleton.
    - The pod remains associated with that managed repository rather than one WorkItem.

- id: architecture.agent_os_integration.scenario_agent_collaboration_within_pod
  covers:
    - architecture.agent_os_integration.pod_contains_multiple_agents
    - architecture.agent_os_integration.eager_and_lazy_agent_activation
    - architecture.agent_os_integration.signal_routing_within_pod
  given:
    - A CodingPod exists for a WorkItem.
  when:
    - Planning work is requested.
  then:
    - The task_board and project_context agents are already running (eager).
    - The planner agent starts on demand (lazy).
    - The planner uses tools (ReadFile, SearchCode) to analyze the codebase.
    - The plan is stored in the task_board agent state.

- id: architecture.agent_os_integration.scenario_selected_coding_agents_receive_semantic_tools_explicitly
  covers:
    - architecture.agent_os_integration.pod_contains_multiple_agents
    - architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  given:
    - A managed repository has a loaded source-code graph.
  when:
    - Planning, review, or explanation specialists need semantic repository context.
  then:
    - Only selected coding specialists receive semantic graph tools through explicit composition.
    - The same bounded source-graph action surface is reused rather than hidden helper pathways.
    - Repository readiness and stale-revision gating remain enforced by the product boundary and action layer.

- id: architecture.agent_os_integration.scenario_workspace_context_hides_topology
  covers:
    - architecture.agent_os_integration.workspace_context_hides_kernel_topology
  given:
    - A Phoenix controller needs to start planning work.
  when:
    - The controller calls AgentWorkspace.plan_work.
  then:
    - The context ensures the kernel exists.
    - The context ensures the CodingPod exists.
    - The context routes the signal to the planner agent.
    - The controller is unaware of kernel/pod topology details.

- id: architecture.agent_os_integration.scenario_persistence_survives_restart
  covers:
    - architecture.agent_os_integration.ecto_persistence_per_kernel
  given:
    - A kernel and pods are running with active work.
  when:
    - The application restarts.
  then:
    - Kernels and pods restore their previous state from Ecto storage.
    - Work can continue without losing context.

- id: architecture.agent_os_integration.scenario_product_work_entrypoint_routes_to_workspace
  covers:
    - architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  given:
    - A product work request is received for a WorkItem.
  when:
    - The product entrypoint processes the request through `AgentWorkspace`.
  then:
    - The entrypoint ensures the repository kernel exists.
    - The entrypoint ensures or finds the CodingPod for the WorkItem.
    - The entrypoint routes the operation to the appropriate agent (planner, coder, reviewer).

- id: architecture.agent_os_integration.scenario_repository_scoped_source_graph_capability_routes_through_workspace
  covers:
    - architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
    - architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
    - architecture.agent_os_integration.workspace_context_hides_kernel_topology
    - architecture.agent_os_integration.actions_use_jido_action
  given:
    - A managed repository enables the source-code graph capability.
  when:
    - Product code ensures, loads, and queries the repository-scoped source graph through `AgentWorkspace`.
  then:
    - `AgentWorkspace` ensures one repository-scoped SourceCodeGraphPod.
    - The workspace boundary returns product-owned graph summaries rather than pod internals.
    - Analyze, load, refresh, status, and query operations route through explicit `Jido.Action` tools.
    - Repository-local readiness and stale-revision state are preserved per repository kernel rather than as global state.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.jido_agent_os_integration.md
  covers:
    - architecture.agent_os_integration.kernel_per_managed_repo
    - architecture.agent_os_integration.coding_pod_per_work_item
    - architecture.agent_os_integration.pod_contains_multiple_agents
    - architecture.agent_os_integration.eager_and_lazy_agent_activation
    - architecture.agent_os_integration.multiple_pods_parallel_execution
    - architecture.agent_os_integration.kernel_naming_convention
    - architecture.agent_os_integration.pod_naming_convention
    - architecture.agent_os_integration.signal_routing_within_pod

- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
  covers:
    - architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled

- kind: source_file
  target: lib/jido_code/agent_workspace.ex
  covers:
    - architecture.agent_os_integration.workspace_context_hides_kernel_topology
    - architecture.agent_os_integration.pod_cleanup_on_completion
    - architecture.agent_os_integration.pod_naming_convention
    - architecture.agent_os_integration.multiple_pods_parallel_execution
    - architecture.agent_os_integration.signal_routing_within_pod
    - architecture.agent_os_integration.product_work_entrypoints_route_to_workspace

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_one_integration_test.exs
  covers:
    - architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
    - architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
    - architecture.agent_os_integration.workspace_context_hides_kernel_topology

- kind: source_file
  target: lib/jido_code/agent_os.ex
  covers:
    - architecture.agent_os_integration.kernel_per_managed_repo
    - architecture.agent_os_integration.ecto_persistence_per_kernel
    - architecture.agent_os_integration.kernel_naming_convention

- kind: source_file
  target: lib/jido_code/agent_os/manager.ex
  covers:
    - architecture.agent_os_integration.dynamic_kernel_lifecycle
    - architecture.agent_os_integration.kernel_naming_convention

- kind: source_file
  target: lib/jido_code/pods/repo_pod.ex
  covers:
    - architecture.agent_os_integration.repo_pod_singleton_per_kernel

- kind: source_file
  target: lib/jido_code/pods/coding_pod.ex
  covers:
    - architecture.agent_os_integration.coding_pod_per_work_item
    - architecture.agent_os_integration.pod_contains_multiple_agents
    - architecture.agent_os_integration.eager_and_lazy_agent_activation

- kind: source_file
  target: lib/jido_code/agents/
  covers:
    - architecture.agent_os_integration.pod_contains_multiple_agents

- kind: source_file
  target: lib/jido_code/actions/
  covers:
    - architecture.agent_os_integration.actions_use_jido_action
    - architecture.agent_os_integration.state_operations_modify_agent_state

- kind: source_file
  target: lib/jido_code/pods/source_code_graph_pod.ex
  covers:
    - architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled

- kind: source_file
  target: lib/jido_code/actions/analyze_source_code_graph.ex
  covers:
    - architecture.agent_os_integration.actions_use_jido_action

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_integration_test.exs
  covers:
    - architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
    - architecture.agent_os_integration.workspace_context_hides_kernel_topology
    - architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
    - architecture.agent_os_integration.actions_use_jido_action
```
