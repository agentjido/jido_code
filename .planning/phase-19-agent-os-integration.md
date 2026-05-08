# Phase 19 - AgentOS Integration

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/agent_os_integration.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../decisions/jido_code.jido_agent_os_integration.md`
- `../decisions/jido_code.jido_os_deprecation.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_os/`
- `lib/jido_code/agent_os/pods/`
- `lib/jido_code/agent_os/agents/`
- `lib/jido_code/agent_os/actions/`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- Phases 1 through 18 are complete, establishing the canonical managed-repo and governed-run product vocabulary.
- The `jido_os` integration has been deprecated and removed (Phase 17).
- `jido_agent_os` is available as a dependency for building durable, multi-repository coding operations.
- This phase introduces the AgentOS runtime layer as a product-local kernel-per-repository boundary rather than an external service dependency.

## Status Reconciliation
- Core AgentOS kernel, pod, action, and workspace routing foundations are now implemented and verified through focused AgentOS integration tests.
- Durable restart restoration, kernel crash recovery, and repository-scoped work queue limits are now implemented and covered.
- Specialist collaboration is now proven through eager-node state checks covering project-context seeding plus task-board task, event, and artifact updates during planner, coder, and reviewer workflows.
- The old `jido_os` work-entry integration wording from the original phase has been reconciled to the current architecture, where `AgentWorkspace` is the canonical product-owned AgentOS boundary.

[x] 19 Phase 19 - AgentOS Integration
  Integrate jido_agent_os to provide durable, multi-repository coding operations with one kernel per ManagedRepo, one RepoPod singleton for repository monitoring, and one CodingPod per WorkItem containing multiple collaborating AI agents.

  [x] 19.1 Section - Kernel Infrastructure
    Build the dynamic kernel manager and supervisor that create and manage one kernel per ManagedRepo with Ecto persistence.

    [x] 19.1.1 Task - Create AgentOS Manager module
      Implement the dynamic kernel lifecycle manager that creates, tracks, and shuts down kernels per ManagedRepo.

      [x] 19.1.1.1 Subtask - Create `JidoCode.AgentOS.Manager` module
        Implement `ensure_kernel/1`, `kernel_status/1`, and `shutdown_kernel/1` functions for managing repository-scoped kernels.

      [x] 19.1.1.2 Subtask - Create `JidoCode.AgentOS.KernelSupervisor`
        Implement a dynamic supervisor that manages multiple kernel processes keyed by ManagedRepo ID.

      [x] 19.1.1.3 Subtask - Implement kernel naming convention
        Use the naming pattern `:"repo_{managed_repo_id}"` for clear mapping between kernels and ManagedRepos.

    [x] 19.1.2 Task - Configure Ecto persistence per kernel
      Enable kernel and pod state to survive application restarts through Ecto storage.

      [x] 19.1.2.1 Subtask - Add persistence configuration to kernel startup
        Configure each kernel with `Jido.Ecto.Storage` adapter pointing to `JidoCode.Repo`, while failing closed to an explicit non-persistent path when the adapter is unavailable in the host repo.

      [x] 19.1.2.2 Subtask - Verify state restoration across restarts
        Ensure kernel, pod, and agent state restore properly after application restart.

    [x] 19.1.3 Task - Implement kernel health monitoring and recovery
      Add monitoring and recovery logic for kernel failures without losing work state.

      [x] 19.1.3.1 Subtask - Add kernel crash detection
        Detect when a kernel terminates unexpectedly and log the failure.

      [x] 19.1.3.2 Subtask - Implement kernel recovery strategies
        Provide recovery mechanisms such as restarting from persisted state or flagging affected WorkItems.

  [x] 19.2 Section - Core Pod Definitions
    Define and implement RepoPod (singleton per kernel) and CodingPod (per WorkItem) with their agent topologies.

    [x] 19.2.1 Task - Create RepoPod definition
      Implement the singleton RepoPod with eager agents for repository monitoring and work registry.

      [x] 19.2.1.1 Subtask - Create `JidoCode.AgentOS.Pods.RepoPod` module
        Define the pod with `use Jido.AgentOS.Pod` and the appropriate topology.

      [x] 19.2.1.2 Subtask - Implement RepoMonitor agent (eager)
        Create an agent that tracks git status, file changes, and repository state.

      [x] 19.2.1.3 Subtask - Implement WorkRegistry agent (eager)
        Create an agent that tracks all active WorkItems and their associated CodingPods within the repository.

    [x] 19.2.2 Task - Create CodingPod definition
      Implement the multi-agent CodingPod based on `Jido.AgentOS.Pods.CodingAssistant` pattern.

      [x] 19.2.2.1 Subtask - Create `JidoCode.AgentOS.Pods.CodingPod` module
        Define the pod with eager agents (task_board, project_context) and lazy AI specialists.

      [x] 19.2.2.2 Subtask - Implement TaskBoard agent (eager)
        Create an agent for task coordination with signal routes for task management.

      [x] 19.2.2.3 Subtask - Implement ProjectContext agent (eager)
        Create an agent that maintains workspace path, file index, and project-level context.

  [x] 19.3 Section - AI Agent Definitions
    Implement the AI-powered specialist agents (Planner, Coder, Reviewer, Refactorer, Explainer) as lazy agents within CodingPod.

    [x] 19.3.1 Task - Implement Planner agent
      Create the planning specialist that generates implementation plans.

      [x] 19.3.1.1 Subtask - Create `JidoCode.AgentOS.Agents.Planner` module
        Use `Jido.AI.Agent` with reasoning model, tools for reading and searching code.

      [x] 19.3.1.2 Subtask - Define planner system prompt
        Create a prompt that focuses the agent on breaking down requests into concrete steps.

    [x] 19.3.2 Task - Implement Coder agent
      Create the coding specialist that implements code changes.

      [x] 19.3.2.1 Subtask - Create `JidoCode.AgentOS.Agents.Coder` module
        Use `Jido.AI.Agent` with fast model, tools for reading, writing, and testing code.

      [x] 19.3.2.2 Subtask - Define coder system prompt
        Create a prompt that focuses on producing correct code with proper conventions and error handling.

    [x] 19.3.3 Task - Implement Reviewer agent
      Create the review specialist that reviews proposed changes.

      [x] 19.3.3.1 Subtask - Create `JidoCode.AgentOS.Agents.Reviewer` module
        Use `Jido.AI.Agent` with reasoning model, tools for reading and testing.

      [x] 19.3.3.2 Subtask - Define reviewer system prompt
        Create a prompt that focuses on correctness, security, performance, and code style.

    [x] 19.3.4 Task - Implement Refactorer agent
      Create the refactoring specialist for code optimization.

      [x] 19.3.4.1 Subtask - Create `JidoCode.AgentOS.Agents.Refactorer` module
        Use `Jido.AI.Agent` with tools for reading, writing, and analyzing code.

    [x] 19.3.5 Task - Implement Explainer agent
      Create the explanation specialist for code documentation and understanding.

      [x] 19.3.5.1 Subtask - Create `JidoCode.AgentOS.Agents.Explainer` module
        Use `Jido.AI.Agent` with tools for reading code and generating explanations.

  [x] 19.4 Section - Actions and Tools
    Implement Jido.Action modules for file operations, task board management, and JidoCode server integration.

    [x] 19.4.1 Task - Implement coding tool actions
      Create file operation actions that agents use to read, write, and analyze code.

      [x] 19.4.1.1 Subtask - Create ReadFile action
        Implement `JidoCode.AgentOS.Actions.ReadFile` with workspace path resolution.

      [x] 19.4.1.2 Subtask - Create WriteFile action
        Implement `JidoCode.AgentOS.Actions.WriteFile` with directory creation support.

      [x] 19.4.1.3 Subtask - Create ListFiles action
        Implement `JidoCode.AgentOS.Actions.ListFiles` for directory traversal.

      [x] 19.4.1.4 Subtask - Create SearchCode action
        Implement `JidoCode.AgentOS.Actions.SearchCode` for text search in files.

      [x] 19.4.1.5 Subtask - Create RunTests action
        Implement `JidoCode.AgentOS.Actions.RunTests` for test execution.

      [x] 19.4.1.6 Subtask - Create GitStatus and GitDiff actions
        Implement git-aware actions for repository state inspection.

    [x] 19.4.2 Task - Implement task board actions
      Create actions that modify TaskBoard agent state using StateOp.

      [x] 19.4.2.1 Subtask - Create AddTask action
        Implement `JidoCode.AgentOS.Actions.AddTask` with StateOp for adding tasks.

      [x] 19.4.2.2 Subtask - Create SelectTask action
        Implement `JidoCode.AgentOS.Actions.SelectTask` for changing the active task.

      [x] 19.4.2.3 Subtask - Create StoreArtifact action
        Implement `JidoCode.AgentOS.Actions.StoreArtifact` for storing work artifacts.

      [x] 19.4.2.4 Subtask - Create AppendEvent action
        Implement `JidoCode.AgentOS.Actions.AppendEvent` for activity logging.

    [x] 19.4.3 Task - Implement JidoCode server actions
      Create actions that integrate with the product API for WorkItem operations.

      [x] 19.4.3.1 Subtask - Create GetWorkItem action
        Implement `JidoCode.AgentOS.Actions.GetWorkItem` for fetching WorkItem details.

      [x] 19.4.3.2 Subtask - Create UpdateWorkItemStatus action
        Implement `JidoCode.AgentOS.Actions.UpdateWorkItemStatus` for status updates.

  [x] 19.5 Section - Workspace Context Integration
    Create the AgentWorkspace context that hides kernel and pod topology from Phoenix controllers and LiveViews.

    [x] 19.5.1 Task - Create AgentWorkspace context module
      Implement the public API for kernel and pod management.

      [x] 19.5.1.1 Subtask - Create `JidoCode.AgentWorkspace` module
        Define context functions for kernel lifecycle, pod operations, and work execution.

      [x] 19.5.1.2 Subtask - Implement kernel lifecycle functions
        Create `ensure_kernel/2`, `kernel_status/1`, `shutdown_kernel/1`.

      [x] 19.5.1.3 Subtask - Implement pod lifecycle functions
        Create `ensure_coding_pod/3`, `complete_work/2`, `active_work_items/1`.

    [x] 19.5.2 Task - Implement work execution functions
      Create functions that route operations to appropriate agents within pods.

      [x] 19.5.2.1 Subtask - Implement `plan_work/3`
        Route planning requests to the planner agent within the WorkItem's CodingPod.

      [x] 19.5.2.2 Subtask - Implement `execute_work/3`
        Route implementation requests to the coder agent within the WorkItem's CodingPod.

      [x] 19.5.2.3 Subtask - Implement `review_work/3`
        Route review requests to the reviewer agent within the WorkItem's CodingPod.

      [x] 19.5.2.4 Subtask - Implement `full_workflow/3`
        Coordinate the complete plan → code → review pipeline within one CodingPod.

    [x] 19.5.3 Task - Implement parallel execution support
      Enable multiple WorkItems to be processed concurrently using separate CodingPod instances.

      [x] 19.5.3.1 Subtask - Implement `parallel_plan/2`
        Plan multiple WorkItems in parallel using separate CodingPod instances.

      [x] 19.5.3.2 Subtask - Implement work queue management
        Add logic to track and limit concurrent work per repository.

  [x] 19.6 Section - Product Work Entrypoint Convergence
    Reconcile product-owned work routing so AgentWorkspace is the canonical AgentOS entry boundary after the deprecated `jido_os` path removal.

    [x] 19.6.1 Task - Converge product work entrypoints on AgentWorkspace
      Use `AgentWorkspace` as the product-owned boundary for kernel lifecycle, pod lifecycle, and specialist routing.

      [x] 19.6.1.1 Subtask - Remove deprecated pre-AgentOS work routing code
        Delete the remaining deprecated work-routing seams so AgentWorkspace is the only supported runtime boundary.

      [x] 19.6.1.2 Subtask - Add kernel and pod ensuring logic
        Call `AgentWorkspace.ensure_kernel/2` and `ensure_coding_pod/3` before routing work.

      [x] 19.6.1.3 Subtask - Update signal routing to agents
        Route operations to specific agents (planner, coder, reviewer) within pods.

    [x] 19.6.2 Task - Update work-entry tests for AgentOS
      Ensure the product-owned workspace and AgentOS integration tests pass with the canonical AgentWorkspace routing path.

      [x] 19.6.2.1 Subtask - Update work-entrypoint tests for AgentOS
        Verify kernel and pod lifecycle through AgentWorkspace-focused tests.

      [x] 19.6.2.2 Subtask - Update integration tests for AgentOS
        Ensure phase integration tests work with AgentOS backend.

  [x] 19.7 Section - AgentOS Integration Tests
    Verify that kernels, pods, and agents work correctly for multi-repository, multi-work-item scenarios.

    [x] 19.7.1 Task - Kernel lifecycle scenarios
      Prove kernels are created, managed, and shut down correctly per ManagedRepo.

      [x] 19.7.1.1 Subtask - Test kernel creation on first work
        Verify a new kernel is created when work begins on a ManagedRepo.

      [x] 19.7.1.2 Subtask - Test kernel reuse across WorkItems
        Verify the same kernel is reused for multiple WorkItems in the same repository.

      [x] 19.7.1.3 Subtask - Test kernel shutdown and cleanup
        Verify kernels shut down properly when work completes or explicitly closed.

    [x] 19.7.2 Task - Pod isolation and parallel execution scenarios
      Prove CodingPod instances are isolated and can execute in parallel.

      [x] 19.7.2.1 Subtask - Test pod-per-work-item isolation
        Verify each WorkItem gets its own CodingPod with isolated agent state.

      [x] 19.7.2.2 Subtask - Test parallel pod execution
        Verify multiple CodingPods run concurrently without interfering with each other.

      [x] 19.7.2.3 Subtask - Test pod state persistence
        Verify pod state survives across application restarts via Ecto.

    [x] 19.7.3 Task - Agent collaboration scenarios
      Prove agents within a pod collaborate correctly via signals.

      [x] 19.7.3.1 Subtask - Test planner agent workflow
        Verify the planner agent uses tools (ReadFile, SearchCode) and stores plans in task_board.

      [x] 19.7.3.2 Subtask - Test coder agent workflow
        Verify the coder agent reads, writes, and tests code based on plans.

      [x] 19.7.3.3 Subtask - Test reviewer agent workflow
        Verify the reviewer agent analyzes changes and provides feedback.

    [x] 19.7.4 Task - End-to-end work-entry scenarios
      Prove product work entrypoints flow through AgentOS to produce correct results.

      [x] 19.7.4.1 Subtask - Test plan operation through product entrypoints
        Verify sending a "plan" operation creates a CodingPod and routes to the planner agent.

      [x] 19.7.4.2 Subtask - Test implement operation through product entrypoints
        Verify sending an "implement" operation routes to the coder agent.

      [x] 19.7.4.3 Subtask - Test review operation through product entrypoints
        Verify sending a "review" operation routes to the reviewer agent.

      [x] 19.7.4.4 Subtask - Test full workflow entrypoint
        Verify a complete plan → code → review workflow works through product-owned work routing.
