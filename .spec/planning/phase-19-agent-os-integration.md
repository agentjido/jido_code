# Phase 19 - AgentOS Integration

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/agent_os_integration.spec.md`
- `../specs/conversation_driver.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/execution_pipeline.spec.md`
- `../decisions/jido_code.jido_agent_os_integration.md`
- `../decisions/jido_code.jido_os_deprecation.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_os/`
- `lib/jido_code/agent_os/pods/`
- `lib/jido_code/agent_os/agents/`
- `lib/jido_code/agent_os/actions/`
- `lib/jido_code/conversations/driver.ex`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults
- Phases 1 through 18 are complete, establishing the canonical managed-repo and governed-run product vocabulary.
- The `jido_os` integration has been deprecated and removed (Phase 17).
- `jido_agent_os` is available as a dependency for building durable, multi-repository coding operations.
- This phase introduces the AgentOS runtime layer as a product-local kernel-per-repository boundary rather than an external service dependency.

[ ] 19 Phase 19 - AgentOS Integration
  Integrate jido_agent_os to provide durable, multi-repository coding operations with one kernel per ManagedRepo, one RepoPod singleton for repository monitoring, and one CodingPod per WorkItem containing multiple collaborating AI agents.

  [ ] 19.1 Section - Kernel Infrastructure
    Build the dynamic kernel manager and supervisor that create and manage one kernel per ManagedRepo with Ecto persistence.

    [ ] 19.1.1 Task - Create AgentOS Manager module
      Implement the dynamic kernel lifecycle manager that creates, tracks, and shuts down kernels per ManagedRepo.

      [ ] 19.1.1.1 Subtask - Create `JidoCode.AgentOS.Manager` module
        Implement `ensure_kernel/1`, `kernel_status/1`, and `shutdown_kernel/1` functions for managing repository-scoped kernels.

      [ ] 19.1.1.2 Subtask - Create `JidoCode.AgentOS.KernelSupervisor` 
        Implement a dynamic supervisor that manages multiple kernel processes keyed by ManagedRepo ID.

      [ ] 19.1.1.3 Subtask - Implement kernel naming convention
        Use the naming pattern `:"repo_{managed_repo_id}"` for clear mapping between kernels and ManagedRepos.

    [ ] 19.1.2 Task - Configure Ecto persistence per kernel
      Enable kernel and pod state to survive application restarts through Ecto storage.

      [ ] 19.1.2.1 Subtask - Add persistence configuration to kernel startup
        Configure each kernel with `Jido.Ecto.Storage` adapter pointing to `JidoCode.Repo`.

      [ ] 19.1.2.2 Subtask - Verify state restoration across restarts
        Ensure kernel, pod, and agent state restore properly after application restart.

    [ ] 19.1.3 Task - Implement kernel health monitoring and recovery
      Add monitoring and recovery logic for kernel failures without losing work state.

      [ ] 19.1.3.1 Subtask - Add kernel crash detection
        Detect when a kernel terminates unexpectedly and log the failure.

      [ ] 19.1.3.2 Subtask - Implement kernel recovery strategies
        Provide recovery mechanisms such as restarting from persisted state or flagging affected WorkItems.

  [ ] 19.2 Section - Core Pod Definitions
    Define and implement RepoPod (singleton per kernel) and CodingPod (per WorkItem) with their agent topologies.

    [ ] 19.2.1 Task - Create RepoPod definition
      Implement the singleton RepoPod with eager agents for repository monitoring and work registry.

      [ ] 19.2.1.1 Subtask - Create `JidoCode.AgentOS.Pods.RepoPod` module
        Define the pod with `use Jido.AgentOS.Pod` and the appropriate topology.

      [ ] 19.2.1.2 Subtask - Implement RepoMonitor agent (eager)
        Create an agent that tracks git status, file changes, and repository state.

      [ ] 19.2.1.3 Subtask - Implement WorkRegistry agent (eager)
        Create an agent that tracks all active WorkItems and their associated CodingPods within the repository.

    [ ] 19.2.2 Task - Create CodingPod definition
      Implement the multi-agent CodingPod based on `Jido.AgentOS.Pods.CodingAssistant` pattern.

      [ ] 19.2.2.1 Subtask - Create `JidoCode.AgentOS.Pods.CodingPod` module
        Define the pod with eager agents (task_board, project_context) and lazy AI specialists.

      [ ] 19.2.2.2 Subtask - Implement TaskBoard agent (eager)
        Create an agent for task coordination with signal routes for task management.

      [ ] 19.2.2.3 Subtask - Implement ProjectContext agent (eager)
        Create an agent that maintains workspace path, file index, and project-level context.

  [ ] 19.3 Section - AI Agent Definitions
    Implement the AI-powered specialist agents (Planner, Coder, Reviewer, Refactorer, Explainer) as lazy agents within CodingPod.

    [ ] 19.3.1 Task - Implement Planner agent
      Create the planning specialist that generates implementation plans.

      [ ] 19.3.1.1 Subtask - Create `JidoCode.AgentOS.Agents.Planner` module
        Use `Jido.AI.Agent` with reasoning model, tools for reading and searching code.

      [ ] 19.3.1.2 Subtask - Define planner system prompt
        Create a prompt that focuses the agent on breaking down requests into concrete steps.

    [ ] 19.3.2 Task - Implement Coder agent
      Create the coding specialist that implements code changes.

      [ ] 19.3.2.1 Subtask - Create `JidoCode.AgentOS.Agents.Coder` module
        Use `Jido.AI.Agent` with fast model, tools for reading, writing, and testing code.

      [ ] 19.3.2.2 Subtask - Define coder system prompt
        Create a prompt that focuses on producing correct code with proper conventions and error handling.

    [ ] 19.3.3 Task - Implement Reviewer agent
      Create the review specialist that reviews proposed changes.

      [ ] 19.3.3.1 Subtask - Create `JidoCode.AgentOS.Agents.Reviewer` module
        Use `Jido.AI.Agent` with reasoning model, tools for reading and testing.

      [ ] 19.3.3.2 Subtask - Define reviewer system prompt
        Create a prompt that focuses on correctness, security, performance, and code style.

    [ ] 19.3.4 Task - Implement Refactorer agent
      Create the refactoring specialist for code optimization.

      [ ] 19.3.4.1 Subtask - Create `JidoCode.AgentOS.Agents.Refactorer` module
        Use `Jido.AI.Agent` with tools for reading, writing, and analyzing code.

    [ ] 19.3.5 Task - Implement Explainer agent
      Create the explanation specialist for code documentation and understanding.

      [ ] 19.3.5.1 Subtask - Create `JidoCode.AgentOS.Agents.Explainer` module
        Use `Jido.AI.Agent` with tools for reading code and generating explanations.

  [ ] 19.4 Section - Actions and Tools
    Implement Jido.Action modules for file operations, task board management, and JidoCode server integration.

    [ ] 19.4.1 Task - Implement coding tool actions
      Create file operation actions that agents use to read, write, and analyze code.

      [ ] 19.4.1.1 Subtask - Create ReadFile action
        Implement `JidoCode.AgentOS.Actions.ReadFile` with workspace path resolution.

      [ ] 19.4.1.2 Subtask - Create WriteFile action
        Implement `JidoCode.AgentOS.Actions.WriteFile` with directory creation support.

      [ ] 19.4.1.3 Subtask - Create ListFiles action
        Implement `JidoCode.AgentOS.Actions.ListFiles` for directory traversal.

      [ ] 19.4.1.4 Subtask - Create SearchCode action
        Implement `JidoCode.AgentOS.Actions.SearchCode` for text search in files.

      [ ] 19.4.1.5 Subtask - Create RunTests action
        Implement `JidoCode.AgentOS.Actions.RunTests` for test execution.

      [ ] 19.4.1.6 Subtask - Create GitStatus and GitDiff actions
        Implement git-aware actions for repository state inspection.

    [ ] 19.4.2 Task - Implement task board actions
      Create actions that modify TaskBoard agent state using StateOp.

      [ ] 19.4.2.1 Subtask - Create AddTask action
        Implement `JidoCode.AgentOS.Actions.AddTask` with StateOp for adding tasks.

      [ ] 19.4.2.2 Subtask - Create SelectTask action
        Implement `JidoCode.AgentOS.Actions.SelectTask` for changing the active task.

      [ ] 19.4.2.3 Subtask - Create StoreArtifact action
        Implement `JidoCode.AgentOS.Actions.StoreArtifact` for storing work artifacts.

      [ ] 19.4.2.4 Subtask - Create AppendEvent action
        Implement `JidoCode.AgentOS.Actions.AppendEvent` for activity logging.

    [ ] 19.4.3 Task - Implement JidoCode server actions
      Create actions that integrate with the product API for WorkItem operations.

      [ ] 19.4.3.1 Subtask - Create GetWorkItem action
        Implement `JidoCode.AgentOS.Actions.GetWorkItem` for fetching WorkItem details.

      [ ] 19.4.3.2 Subtask - Create UpdateWorkItemStatus action
        Implement `JidoCode.AgentOS.Actions.UpdateWorkItemStatus` for status updates.

  [ ] 19.5 Section - Workspace Context Integration
    Create the AgentWorkspace context that hides kernel and pod topology from Phoenix controllers and LiveViews.

    [ ] 19.5.1 Task - Create AgentWorkspace context module
      Implement the public API for kernel and pod management.

      [ ] 19.5.1.1 Subtask - Create `JidoCode.AgentWorkspace` module
        Define context functions for kernel lifecycle, pod operations, and work execution.

      [ ] 19.5.1.2 Subtask - Implement kernel lifecycle functions
        Create `ensure_kernel/2`, `kernel_status/1`, `shutdown_kernel/1`.

      [ ] 19.5.1.3 Subtask - Implement pod lifecycle functions
        Create `ensure_coding_pod/3`, `complete_work/2`, `active_work_items/1`.

    [ ] 19.5.2 Task - Implement work execution functions
      Create functions that route operations to appropriate agents within pods.

      [ ] 19.5.2.1 Subtask - Implement `plan_work/3`
        Route planning requests to the planner agent within the WorkItem's CodingPod.

      [ ] 19.5.2.2 Subtask - Implement `execute_work/3`
        Route implementation requests to the coder agent within the WorkItem's CodingPod.

      [ ] 19.5.2.3 Subtask - Implement `review_work/3`
        Route review requests to the reviewer agent within the WorkItem's CodingPod.

      [ ] 19.5.2.4 Subtask - Implement `full_workflow/3`
        Coordinate the complete plan → code → review pipeline within one CodingPod.

    [ ] 19.5.3 Task - Implement parallel execution support
      Enable multiple WorkItems to be processed concurrently using separate CodingPod instances.

      [ ] 19.5.3.1 Subtask - Implement `parallel_plan/2`
        Plan multiple WorkItems in parallel using separate CodingPod instances.

      [ ] 19.5.3.2 Subtask - Implement work queue management
      Add logic to track and limit concurrent work per repository.

  [ ] 19.6 Section - Conversation Driver Integration
    Update the conversation driver to integrate with AgentOS instead of the deprecated jido_os boundary.

    [ ] 19.6.1 Task - Update conversation driver for AgentOS
    Modify `JidoCode.Conversations.Driver` to use AgentWorkspace for kernel and pod management.

      [ ] 19.6.1.1 Subtask - Remove deprecated jido_os integration code
        Delete calls to `JidoCode.CodingAssistance` (old jido_os boundary).

      [ ] 19.6.1.2 Subtask - Add kernel and pod ensuring logic
        Call `AgentWorkspace.ensure_kernel/2` and `ensure_coding_pod/3` before routing work.

      [ ] 19.6.1.3 Subtask - Update signal routing to agents
        Route operations to specific agents (planner, coder, reviewer) within pods.

    [ ] 19.6.2 Task - Update conversation tests for AgentOS
      Ensure existing conversation tests pass with the new AgentOS integration.

      [ ] 19.6.2.1 Subtask - Update `DriverTest` for AgentOS
        Modify tests to mock AgentWorkspace and verify kernel/pod lifecycle.

      [ ] 19.6.2.2 Subtask - Update integration tests for AgentOS
        Ensure phase integration tests work with AgentOS backend.

  [ ] 19.7 Section - AgentOS Integration Tests
    Verify that kernels, pods, and agents work correctly for multi-repository, multi-work-item scenarios.

    [ ] 19.7.1 Task - Kernel lifecycle scenarios
      Prove kernels are created, managed, and shut down correctly per ManagedRepo.

      [ ] 19.7.1.1 Subtask - Test kernel creation on first work
        Verify a new kernel is created when work begins on a ManagedRepo.

      [ ] 19.7.1.2 Subtask - Test kernel reuse across WorkItems
        Verify the same kernel is reused for multiple WorkItems in the same repository.

      [ ] 19.7.1.3 Subtask - Test kernel shutdown and cleanup
        Verify kernels shut down properly when work completes or explicitly closed.

    [ ] 19.7.2 Task - Pod isolation and parallel execution scenarios
      Prove CodingPod instances are isolated and can execute in parallel.

      [ ] 19.7.2.1 Subtask - Test pod-per-work-item isolation
        Verify each WorkItem gets its own CodingPod with isolated agent state.

      [ ] 19.7.2.2 Subtask - Test parallel pod execution
        Verify multiple CodingPods run concurrently without interfering with each other.

      [ ] 19.7.2.3 Subtask - Test pod state persistence
        Verify pod state survives across application restarts via Ecto.

    [ ] 19.7.3 Task - Agent collaboration scenarios
      Prove agents within a pod collaborate correctly via signals.

      [ ] 19.7.3.1 Subtask - Test planner agent workflow
        Verify the planner agent uses tools (ReadFile, SearchCode) and stores plans in task_board.

      [ ] 19.7.3.2 Subtask - Test coder agent workflow
        Verify the coder agent reads, writes, and tests code based on plans.

      [ ] 19.7.3.3 Subtask - Test reviewer agent workflow
        Verify the reviewer agent analyzes changes and provides feedback.

    [ ] 19.7.4 Task - End-to-end conversation scenarios
      Prove conversations flow through AgentOS to produce correct results.

      [ ] 19.7.4.1 Subtask - Test plan operation through conversation
        Verify sending a "plan" operation creates a CodingPod and routes to the planner agent.

      [ ] 19.7.4.2 Subtask - Test implement operation through conversation
        Verify sending an "implement" operation routes to the coder agent.

      [ ] 19.7.4.3 Subtask - Test review operation through conversation
        Verify sending a "review" operation routes to the reviewer agent.

      [ ] 19.7.4.4 Subtask - Test full workflow conversation
        Verify a complete plan → code → review workflow works through conversation turns.
