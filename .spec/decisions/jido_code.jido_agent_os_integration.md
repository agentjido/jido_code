---
id: jido_code.jido_agent_os_integration
status: proposed
date: 2025-04-06
affects:
  - package.jido_code
  - architecture.agent_os_integration
related:
  - jido_code.jido_os_deprecation
---

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# JidoCode + Jido.AgentOS Integration Design

## Context

Following the deprecation of `jido_os`, we've adopted `jido_agent_os` as our durable runtime layer. This document outlines how `jido_agent_os` integrates with JidoCode's domain model (ManagedRepo, WorkItem) to support multi-repository coding operations.

## Current Domain Model

```
SourceRepo (external Git identity)
    ↓
ManagedRepo (durable product wrapper, belongs_to SourceRepo)
    ↓
WorkItem (work to be done, belongs_to ManagedRepo)
```

**Key relationships:**
- One SourceRepo can have multiple ManagedRepos (e.g., different branches or forks)
- Each ManagedRepo can have multiple WorkItems
- WorkItems represent discrete units of work (plan, implement, review)

## Jido.AgentOS Architecture

```
Kernel (long-lived runtime boundary)
    ↓
Pod (durable, stateful agent team)
    ↓
Agent (behavioral unit)
```

**Key concepts from jido_agent_os:**
- **Kernel**: The `MyApp.AgentOS` wrapper supervised in the host app
- **Pod**: Durable Jido pod managed by a kernel, represents one agent team
- **Node**: Named agent instance within a pod's topology
- **Signal**: Message passing between agents

**Pattern:** `Kernel -> Pod -> Agent`

## Integration Design

### 1. One Kernel per ManagedRepo

**Primary design decision:** One kernel per ManagedRepo, hosting multiple specialized pods.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                         JidoCode (Phoenix)                          │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ManagedRepo A          │  ManagedRepo B          │  ManagedRepo C  │
│  ┌────────────────────┐ │  ┌────────────────────┐ │  ┌────────────┐ │
│  │  Kernel A          │ │  │  Kernel B          │ │  │  Kernel C  │ │
│  │  ├─ PlanningPod    │ │  │  ├─ PlanningPod    │ │  │  (idle)    │ │
│  │  ├─ CodingPod      │ │  │  ├─ CodingPod      │ │  │            │ │
│  │  ├─ ReviewPod      │ │  │  ├─ ReviewPod      │ │  │            │ │
│  │  └─ RepoStatePod   │ │  │  └─ RepoStatePod   │ │  │            │ │
│  └────────────────────┘ │  └────────────────────┘ │  └────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**Rationale:**
- **Kernel isolation**: Each repository has its own runtime boundary
- **Parallel pods**: Multiple pods within a kernel can work simultaneously
- **State persistence**: Kernel and pod state survive restarts
- **Clear mapping**: `kernel_name = managed_repo.id`
- **Scalability**: Only active repos have running kernels

### 2. Dynamic Kernel Wrapper

Since we need one kernel per ManagedRepo, we use a dynamic kernel manager:

```elixir
defmodule JidoCode.AgentOS.Manager do
  @moduledoc """
  Dynamic kernel manager for repository-scoped runtimes.

  Creates and manages one kernel per ManagedRepo.
  """

  def ensure_kernel(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    case Jido.AgentOS.kernel_status(kernel_name) do
      %{supervisor: nil} ->
        # Start new kernel for this repository
        start_kernel(managed_repo_id)

      %{supervisor: _pid} ->
        # Kernel already running
        {:ok, kernel_name}
    end
  end

  defp start_kernel(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    children = [
      {Jido.AgentOS.Supervisor,
       [
         kernel_name: kernel_name,
         pod: JidoCode.AgentOS.Pods.RepoState,
         persistence: [
           adapter: Jido.Ecto.Storage,
           repo: JidoCode.Repo
         ]
       ]}
    ]

    # Start under a dynamic supervisor
    JidoCode.AgentOS.KernelSupervisor.start_child(children)
  end

  defp kernel_name(managed_repo_id),
    do: :"repo_#{managed_repo_id}"
end
```

### 3. Pod Types per Kernel

Each kernel hosts pod instances for different work items. Following the `jido_agent_os` pattern, **each pod contains multiple collaborating agents**.

#### 3.1 RepoPod - Per Kernel (Singleton)

One `RepoPod` per kernel that tracks repository state:

```elixir
defmodule JidoCode.AgentOS.Pods.RepoPod do
  @moduledoc """
  Repository monitoring pod - one per kernel (per ManagedRepo).

  Tracks git state, file changes, and repository-level coordination.
  """

  use Jido.AgentOS.Pod,
    name: "repo_pod",
    topology: %{
      # Eager: always running to monitor repository
      repo_monitor: %{
        agent: JidoCode.AgentOS.Agents.RepoMonitor,
        manager: :repo_monitor,
        activation: :eager
      },

      # Eager: tracks all active work items in this repository
      work_registry: %{
        agent: JidoCode.AgentOS.Agents.WorkRegistry,
        manager: :work_registry,
        activation: :eager
      }
    }
end
```

#### 3.2 CodingPod - Per WorkItem

Multiple `CodingPod` instances per kernel (one per WorkItem). Each pod contains a full team of specialist agents:

```elixir
defmodule JidoCode.AgentOS.Pods.CodingPod do
  @moduledoc """
  Coding assistance pod - one instance per WorkItem.

  A self-contained coding team with agents for planning, coding,
  review, and task coordination. Agents collaborate through signals.

  Based on: https://github.com/pcharbon70/jido_agent_os/tree/main/lib/jido/agent_os/pods/coding_assistant
  """

  use Jido.AgentOS.Pod,
    name: "coding_pod",
    topology: %{
      # Eager: Task coordination and state
      task_board: %{
        agent: JidoCode.AgentOS.Agents.TaskBoard,
        manager: :task_board,
        activation: :eager
      },

      # Eager: Project/workspace context for this work item
      project_context: %{
        agent: JidoCode.AgentOS.Agents.ProjectContext,
        manager: :project_context,
        activation: :eager
      },

      # Lazy: AI-powered specialists (started on demand)
      planner: %{
        agent: JidoCode.AgentOS.Agents.Planner,
        manager: :planning,
        activation: :lazy
      },

      coder: %{
        agent: JidoCode.AgentOS.Agents.Coder,
        manager: :coding,
        activation: :lazy
      },

      reviewer: %{
        agent: JidoCode.AgentOS.Agents.Reviewer,
        manager: :review,
        activation: :lazy
      },

      refactorer: %{
        agent: JidoCode.AgentOS.Agents.Refactorer,
        manager: :refactoring,
        activation: :lazy
      },

      explainer: %{
        agent: JidoCode.AgentOS.Agents.Explainer,
        manager: :explanation,
        activation: :lazy
      }
    }
end
```

**Agent collaboration within a CodingPod:**

```
┌─────────────────────────────────────────────────────────────────┐
│  CodingPod: "coding-pod-{work_item_id}"                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌──────────────────┐                    │
│  │ TaskBoard       │  │ ProjectContext   │                    │
│  │ (eager)         │  │ (eager)          │                    │
│  ├─────────────────┤  ├──────────────────┤                    │
│  │ - tasks[]       │  │ - workspace_id   │                    │
│  │ - active_task   │  │ - managed_repo_id│                    │
│  │ - artifacts[]   │  │ - file_index     │                    │
│  └─────────────────┘  └──────────────────┘                    │
│           │                                                      │
│           │ coordinates                                         │
│           ▼                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Lazy AI Specialists                         │   │
│  ├─────────────┬─────────────┬─────────────┬───────────────┤   │
│  │ Planner     │ Coder       │ Reviewer    │ Refactorer    │   │
│  │ (reasoning) │ (fast)      │ (reasoning) │ (fast)        │   │
│  ├─────────────┼─────────────┼─────────────┼───────────────┤   │
│  │ - Plan      │ - Write     │ - Review    │ - Refactor    │   │
│  │ - Breakdown │ - Edit      │ - Lint      │ - Optimize    │   │
│  │ - Research  │ - Test      │ - Approve   │ - Simplify    │   │
│  └─────────────┴─────────────┴─────────────┴───────────────┘   │
│                                                                 │
│  Agents communicate via signals within the pod                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.3 Agent Specifications

**TaskBoard Agent:**
```elixir
defmodule JidoCode.AgentOS.Agents.TaskBoard do
  @moduledoc """
  Task board agent - coordinates work within a CodingPod.

  Signal routes:
  - "task.add" - Add a new task to the board
  - "task.select" - Select the active task
  - "task.store" - Store an artifact
  - "task.event" - Append an event to the activity log
  """

  use Jido.Agent,
    name: "coding_task_board",
    signal_routes: [
      {"task.add", JidoCode.AgentOS.Actions.AddTask},
      {"task.select", JidoCode.AgentOS.Actions.SelectTask},
      {"task.store", JidoCode.AgentOS.Actions.StoreArtifact},
      {"task.event", JidoCode.AgentOS.Actions.AppendEvent}
    ],
    schema: [
      tasks: [type: {:list, :any}, default: []],
      active_task_id: [type: :string, default: ""],
      activity_log: [type: {:list, :any}, default: []],
      artifacts: [type: {:list, :any}, default: []],
      created_at: [type: :string, default: ""],
      last_updated_at: [type: :string, default: ""]
    ]
end
```

**Planner Agent (AI-powered):**
```elixir
defmodule JidoCode.AgentOS.Agents.Planner do
  @moduledoc """
  Planning specialist - creates implementation plans.
  """

  use Jido.AI.Agent,
    name: "coding_planner",
    description: "Planning specialist for coding assistance.",
    model: :reasoning,
    streaming: false,
    max_iterations: 10,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode
    ],
    system_prompt: """
    You are the planning specialist for a coding assistance pod.
    Create detailed, actionable implementation plans.

    Focus on:
    - Breaking down the request into concrete steps
    - Identifying files that need inspection or modification
    - Noting potential risks or edge cases
    - Suggesting tests to verify the implementation
    """
end
```

**Coder Agent (AI-powered):**
```elixir
defmodule JidoCode.AgentOS.Agents.Coder do
  @moduledoc """
  Coding specialist - implements code changes.
  """

  use Jido.AI.Agent,
    name: "coding_coder",
    description: "Code implementation specialist.",
    model: :fast,
    streaming: false,
    max_iterations: 15,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.WriteFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode,
      JidoCode.AgentOS.Actions.RunTests
    ],
    system_prompt: """
    You are the coding specialist for a coding assistance pod.
    Implement code changes following the provided plan.

    Focus on:
    - Producing concrete, correct code changes
    - Following the language and framework conventions
    - Including appropriate error handling
    - Adding or updating tests when relevant
    """
end
```

**Reviewer Agent (AI-powered):**
```elixir
defmodule JidoCode.AgentOS.Agents.Reviewer do
  @moduledoc """
  Review specialist - reviews proposed changes.
  """

  use Jido.AI.Agent,
    name: "coding_reviewer",
    description: "Code review specialist.",
    model: :reasoning,
    streaming: false,
    max_iterations: 10,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode,
      JidoCode.AgentOS.Actions.RunTests
    ],
    system_prompt: """
    You are the review specialist for a coding assistance pod.
    Review proposed code changes thoroughly.

    Focus on:
    - Correctness and logic errors
    - Security vulnerabilities
    - Performance considerations
    - Code style and conventions
    - Test coverage
    """
end
```

**Pod topology:**
```elixir
defmodule JidoCode.AgentOS.Pods.RepoPod do
  use Jido.AgentOS.Pod,
    name: "repo_pod",
    topology: %{
      # Eager: always running when pod is active
      repo_state: %{
        agent: JidoCode.AgentOS.Agents.RepoState,
        manager: :repo_state,
        activation: :eager
      },
      work_board: %{
        agent: JidoCode.AgentOS.Agents.WorkBoard,
        manager: :work_board,
        activation: :eager
      },

      # Lazy: started on demand
      planner: %{
        agent: JidoCode.AgentOS.Agents.Planner,
        manager: :planning,
        activation: :lazy
      },
      coder: %{
        agent: JidoCode.AgentOS.Agents.Coder,
        manager: :coding,
        activation: :lazy
      },
      reviewer: %{
        agent: JidoCode.AgentOS.Agents.Reviewer,
        manager: :review,
        activation: :lazy
      }
    }
end
```

### 4. Phoenix Context Layer

Following the jido_agent_os pattern, we create a domain-shaped context that manages kernels and their pods:

```elixir
defmodule JidoCode.AgentWorkspace do
  @moduledoc """
  Phoenix context for repository workspace operations.

  Public API that translates domain operations into kernel/pod interactions.
  Controllers and LiveViews call this context, not kernels/pods directly.
  """

  alias __MODULE__.Runtime

  # Kernel lifecycle (one per ManagedRepo)
  def ensure_kernel(managed_repo_id, workspace_path)
  def kernel_status(managed_repo_id)
  def shutdown_kernel(managed_repo_id)

  # Pod operations (within a repository's kernel)
  def ensure_pod(managed_repo_id, pod_type)
  def pod_status(managed_repo_id, pod_type)
  def list_pods(managed_repo_id)

  # Repo operations (via RepoState pod)
  def sync_repo(managed_repo_id, workspace_path)
  def repo_status(managed_repo_id)
  def repo_changed?(managed_repo_id)

  # WorkItem operations (route to appropriate pod)
  def plan_work(managed_repo_id, work_item_id, objective)
  def execute_work(managed_repo_id, work_item_id, plan)
  def review_work(managed_repo_id, work_item_id, changes)
  def cancel_work(managed_repo_id, work_item_id)
  def work_status(managed_repo_id, work_item_id)

  # Parallel operations
  def plan_and_review_parallel(managed_repo_id, work_items)
end
```

**Runtime implementation:**
```elixir
defmodule JidoCode.AgentWorkspace.Runtime do
  @moduledoc false

  # Ensure kernel exists, then route to appropriate pod
  def plan_work(managed_repo_id, work_item_id, objective) do
    with {:ok, kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, pod_pid} <- Jido.AgentOS.ensure_pod(kernel_name, "planning"),
         {:ok, agent} <- signal_pod(pod_pid, "work.plan", %{
           work_item_id: work_item_id,
           objective: objective
         }) do
      {:ok, extract_plan(agent.state)}
    end
  end

  # Multiple pods can work in parallel
  def plan_and_review_parallel(managed_repo_id, work_items) do
    {:ok, kernel_name} = ensure_kernel(managed_repo_id)

    work_items
    |> Enum.map(fn {work_item_id, type, content} ->
      Task.async(fn ->
        pod_type = case type do
          :plan -> "planning"
          :review -> "review"
          :execute -> "coding"
        end

        with {:ok, pod_pid} <- Jido.AgentOS.ensure_pod(kernel_name, pod_type),
             {:ok, _agent} <- signal_pod(pod_pid, "work.start", %{
               work_item_id: work_item_id,
               content: content
             }) do
          {work_item_id, :started}
        end
      end)
    end)
    |> Task.await_many(:infinity)
  end

  defp ensure_kernel(managed_repo_id) do
    JidoCode.AgentOS.Manager.ensure_kernel(managed_repo_id)
  end

  defp signal_pod(pod_pid, signal_type, params) do
    node_name = case signal_type do
      "work.plan" -> :planner
      "work.execute" -> :coder
      "work.review" -> :reviewer
      _ -> :repo_monitor
    end

    with {:ok, node_pid} <- Jido.Pod.ensure_node(pod_pid, node_name),
         {:ok, agent} <- Jido.AgentServer.call(
           node_pid,
           Jido.Signal.new!(signal_type, params, source: "/jido_code/workspace")
         ) do
      {:ok, agent}
    end
  end

  defp extract_plan(state), do: state.plan
end
```

### 4. WorkItem to Pod/Signal Mapping

Each WorkItem gets its own `CodingPod` instance. Signals are routed to specific agents within the pod:

| Operation | Target Pod | Target Agent | Signal Type |
|-----------|------------|--------------|-------------|
| Add task | `coding-{work_item_id}` | `task_board` | `task.add` |
| Start planning | `coding-{work_item_id}` | `planner` | `work.plan` |
| Start coding | `coding-{work_item_id}` | `coder` | `work.execute` |
| Start review | `coding-{work_item_id}` | `reviewer` | `work.review` |
| Store artifact | `coding-{work_item_id}` | `task_board` | `task.store` |
| Log event | `coding-{work_item_id}` | `task_board` | `task.event` |

### 5. Pod Naming and Instance Management

**Pod instances per WorkItem:**

```elixir
# Create a CodingPod instance for a specific WorkItem
pod_id = "coding-pod-#{work_item_id}"
{:ok, _pid} = Jido.AgentOS.ensure_pod(kernel_name, pod_id, pod: CodingPod)
```

**Kernel structure:**
```
Kernel: repo-{managed_repo_id}
├── RepoPod (singleton, eager)
│   ├── repo_monitor (eager)
│   └── work_registry (eager)
│
├── CodingPod: "coding-pod-work-item-123"
│   ├── task_board (eager)
│   ├── project_context (eager)
│   ├── planner (lazy)
│   ├── coder (lazy)
│   ├── reviewer (lazy)
│   ├── refactorer (lazy)
│   └── explainer (lazy)
│
└── CodingPod: "coding-pod-work-item-456"
    ├── task_board (eager)
    ├── project_context (eager)
    ├── planner (lazy)
    └── ... (same topology)
```

### 6. Persistence Configuration

| WorkItem operation | Target Pod | Target Node | Signal type |
|-------------------|------------|-------------|-------------|
| Plan | `PlanningPod` | `planner` | `work.plan` |
| Implement | `CodingPod` | `coder` | `work.execute` |
| Review | `ReviewPod` | `reviewer` | `work.review` |
| Cancel | Any active pod | active node | `work.cancel` |
| Status | `RepoStatePod` | `repo_monitor` | `work.status` |

### 6. Persistence Configuration

Each kernel can be configured with Ecto persistence:

```elixir
# Kernel startup configuration
{Jido.AgentOS.Supervisor,
 [
   kernel_name: :"repo_#{managed_repo_id}",
   pod: JidoCode.AgentOS.Pods.RepoState,
   persistence: [
     adapter: Jido.Ecto.Storage,
     repo: JidoCode.Repo
   ]
 ]}
```

This enables kernel and pod state to persist across application restarts.

### 7. Multi-Repository Workflow

**Scenario:** User works on multiple repositories and work items simultaneously

```
1. User activates Repo A (managed_repo_id: "repo-a")
   → JidoCode.AgentOS.Manager.ensure_kernel("repo-a")
   → Kernel A starts with RepoPod (repo_monitor + work_registry)

2. User creates WorkItem #123 for Repo A
   → CodingPod "coding-pod-123" starts
   → Pod contains: task_board, project_context (eager)
   → Lazy agents (planner, coder, reviewer) start on demand

3. User requests planning for WorkItem #123
   → Signal sent to planner agent within "coding-pod-123"
   → Planner uses tools (ReadFile, SearchCode) to analyze codebase
   → Plan stored in task_board

4. User creates WorkItem #456 for Repo A
   → CodingPod "coding-pod-456" starts
   → Independent from "coding-pod-123"
   → Both can work in parallel

5. User activates Repo B (managed_repo_id: "repo-b")
   → Kernel B starts (independent from Kernel A)
   → Work in Repo A continues uninterrupted

6. User switches context back to WorkItem #123
   → "coding-pod-123" still exists with all state preserved
   → task_board contains the plan
   → Can continue where left off
```

### 8. Agent Collaboration Within a Pod

**Example: Planning workflow within a CodingPod**

```elixir
defmodule JidoCode.AgentWorkspace do
  @doc """
  Plan a work item using the planner agent within the pod.
  """
  def plan_work(managed_repo_id, work_item_id, objective) do
    pod_id = "coding-pod-#{work_item_id}"

    with {:ok, kernel_name} <- ensure_kernel(managed_repo_id),
         {:ok, pod_pid} <- ensure_coding_pod(kernel_name, pod_id, work_item_id),
         {:ok, task_board} <- add_task_to_board(pod_pid, work_item_id, objective),
         {:ok, plan} <- signal_planner(pod_pid, work_item_id, objective) do
      {:ok, %{task_board: task_board, plan: plan}}
    end
  end

  # Signal the planner agent - it will use its tools (ReadFile, SearchCode, etc.)
  defp signal_planner(pod_pid, work_item_id, objective) do
    with {:ok, planner_pid} <- Jido.Pod.ensure_node(pod_pid, :planner),
         {:ok, agent} <- Jido.AgentServer.call(
           planner_pid,
           Jido.Signal.new!(
             "work.plan",
             %{work_item_id: work_item_id, objective: objective},
             source: "/jido_code/workspace"
           )
         ) do
      {:ok, extract_plan(agent.state)}
    end
  end

  # Add task to the task_board (eager agent, always running)
  defp add_task_to_board(pod_pid, work_item_id, objective) do
    with {:ok, task_board_pid} <- Jido.Pod.ensure_node(pod_pid, :task_board),
         {:ok, agent} <- Jido.AgentServer.call(
           task_board_pid,
           Jido.Signal.new!(
             "task.add",
             %{id: work_item_id, title: objective, status: "planning"},
             source: "/jido_code/workspace"
           )
         ) do
      {:ok, summarize_task_board(agent.state)}
    end
  end
end
```

### 9. Parallel Pod Execution

Multiple CodingPod instances can run in parallel, each with its own team of agents:

```elixir
defmodule JidoCode.AgentWorkspace do
  @doc """
  Plan multiple work items in parallel using separate CodingPod instances.
  Each pod has its own planner agent working independently.
  """
  def parallel_plan(managed_repo_id, work_items) do
    {:ok, kernel_name} = ensure_kernel(managed_repo_id)

    work_items
    |> Enum.map(fn {work_item_id, objective} ->
      Task.async(fn ->
        pod_id = "coding-pod-#{work_item_id}"

        with {:ok, pod_pid} <- ensure_coding_pod(kernel_name, pod_id, work_item_id),
             {:ok, _task_board} <- add_task_to_board(pod_pid, work_item_id, objective),
             {:ok, plan} <- signal_planner(pod_pid, work_item_id, objective) do
          {work_item_id, {:ok, plan}}
        else
          error -> {work_item_id, error}
        end
      end)
    end)
    |> Task.await_many(60_000)
    |> Map.new()
  end

  @doc """
  Full workflow for a single WorkItem within one CodingPod.
  All agents (planner, coder, reviewer) work within the same pod.
  """
  def full_workflow(managed_repo_id, work_item_id, objective) do
    pod_id = "coding-pod-#{work_item_id}"
    {:ok, kernel_name} = ensure_kernel(managed_repo_id)
    {:ok, pod_pid} <- ensure_coding_pod(kernel_name, pod_id, work_item_id)

    # All operations happen within the same pod
    with {:ok, plan} <- signal_planner(pod_pid, work_item_id, objective),
         {:ok, changes} <- signal_coder(pod_pid, work_item_id, plan),
         {:ok, review} <- signal_reviewer(pod_pid, work_item_id, changes) do
      {:ok, %{plan: plan, changes: changes, review: review}}
    end
  end
end
```

### 10. Pod Lifecycle and Cleanup

Since we create one pod instance per WorkItem, we need cleanup strategies:

```elixir
defmodule JidoCode.AgentWorkspace do
  @doc """
  Shut down a specific CodingPod instance after work is complete.
  State is persisted before shutdown.
  """
  def complete_work(managed_repo_id, work_item_id) do
    pod_id = "coding-pod-#{work_item_id}"
    {:ok, kernel_name} = ensure_kernel(managed_repo_id)

    case Jido.AgentOS.pod_pid(kernel_name, pod_id) do
      {:ok, pod_pid} ->
        # Pod state will be persisted via Ecto before shutdown
        Jido.Pod.stop(pod_pid)
        :ok

      {:error, :pod_not_found} ->
        :ok
    end
  end

  @doc """
  List all active CodingPod instances for a repository.
  """
  def active_work_items(managed_repo_id) do
    kernel_name = kernel_name(managed_repo_id)

    kernel_name
    |> Jido.AgentOS.list_pods()
    |> Enum.filter(&String.starts_with?(&1, "coding-pod-"))
    |> Enum.map(fn pod_id ->
      {work_item_id, _} = String.split_at(pod_id, "coding-pod-" |> String.length())
      work_item_id
    end)
  end

  @doc """
  Archive pod state before shutdown - preserves work for later resumption.
  """
  def archive_work(managed_repo_id, work_item_id) do
    pod_id = "coding-pod-#{work_item_id}"
    {:ok, kernel_name} = ensure_kernel(managed_repo_id)

    with {:ok, pod_snapshot} <- Jido.AgentOS.pod_snapshot(kernel_name, pod_id),
         {:ok, _stored} <- store_pod_snapshot(work_item_id, pod_snapshot) do
      # Store snapshot in database for later resumption
      Jido.Pod.stop(pod_snapshot.pid)
      :ok
    end
  end
end
```

**Cleanup strategies:**
1. **Explicit shutdown** - Call `complete_work/2` after work finishes
2. **Archive and resume** - Store pod state, can resume later with restored state
3. **Idle timeout** - Pods auto-shutdown after N minutes of inactivity
4. **Kernel shutdown** - All pods shut down when kernel is shut down

### 11. Conversation Driver Integration

The `JidoCode.Conversations.Driver` integrates with AgentOS by:
1. Ensuring the repository kernel exists
2. Creating or finding the CodingPod for this WorkItem
3. Routing to the appropriate agent within the pod

```elixir
defmodule JidoCode.Conversations.Driver do
  @moduledoc """
  Integrates conversations with AgentOS by routing to CodingPod agents.

  Each WorkItem has its own CodingPod instance containing multiple agents.
  The driver ensures the kernel and pod exist, then signals the appropriate agent.
  """

  alias JidoCode.AgentWorkspace

  def handle_turn(attrs) do
    with {:ok, context} <- prepare_conversation(attrs),
         {:ok, _kernel} <- ensure_repo_kernel(context),
         {:ok, pod_pid} <- ensure_coding_pod(context),
         {:ok, result} <- route_to_pod_agent(pod_pid, context, attrs) do
      {:ok, result}
    end
  end

  defp ensure_repo_kernel(context) do
    AgentWorkspace.ensure_kernel(
      context.managed_repo_id,
      context.workspace_id
    )
  end

  defp ensure_coding_pod(context) do
    pod_id = "coding-pod-#{context.work_item_id}"
    AgentWorkspace.ensure_coding_pod(context.managed_repo_id, pod_id, context.work_item_id)
  end

  defp route_to_pod_agent(pod_pid, context, attrs) do
    operation = Map.get(attrs, :operation, "plan")

    case operation do
      "plan" ->
        # Route to planner agent within the pod
        signal_pod_agent(pod_pid, :planner, "work.plan", %{
          work_item_id: context.work_item_id,
          objective: Map.get(attrs, :content)
        })

      "implement" ->
        # Route to coder agent within the pod
        signal_pod_agent(pod_pid, :coder, "work.execute", %{
          work_item_id: context.work_item_id,
          plan: Map.get(attrs, :plan),
          content: Map.get(attrs, :content)
        })

      "review" ->
        # Route to reviewer agent within the pod
        signal_pod_agent(pod_pid, :reviewer, "work.review", %{
          work_item_id: context.work_item_id,
          changes: Map.get(attrs, :changes)
        })

      _ ->
        {:error, :unknown_operation}
    end
  end

  defp signal_pod_agent(pod_pid, agent_name, signal_type, params) do
    with {:ok, agent_pid} <- Jido.Pod.ensure_node(pod_pid, agent_name),
         {:ok, agent} <- Jido.AgentServer.call(
           agent_pid,
           Jido.Signal.new!(signal_type, params, source: "/jido_code/driver")
         ) do
      {:ok, extract_agent_result(agent)}
    end
  end
end
```

**Key points:**
- **One CodingPod per WorkItem** - Each conversation/WorkItem gets its own pod
- **Agent routing** - Operations route to specific agents within the pod
- **State persistence** - Pod state persists between related work requests
- **Parallel conversations** - Different WorkItems have independent pods

### 12. Summary Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           JidoCode (Phoenix)                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        AgentWorkspace (Context)                          │
│  - Manages kernels and pods                                             │
│  - Routes operations to agents                                          │
│  - Handles pod lifecycle                                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Kernel per ManagedRepo: :"repo_{managed_repo_id}"                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  RepoPod (singleton, eager)                                         │ │
│  │  ├─ repo_monitor  - Tracks git status, file changes                │ │
│  │  └─ work_registry - Tracks all active WorkItems in this repo       │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  CodingPod: "coding-pod-{work_item_id}" (one per WorkItem)        │ │
│  │                                                                    │ │
│  │  Eager agents (always running):                                    │ │
│  │  ├─ task_board       - Task coordination, artifacts                │ │
│  │  └─ project_context  - Workspace/file context for this work        │ │
│  │                                                                    │ │
│  │  Lazy agents (started on demand):                                  │ │
│  │  ├─ planner   (AI)  - Creates implementation plans                 │ │
│  │  ├─ coder     (AI)  - Implements code changes                      │ │
│  │  ├─ reviewer  (AI)  - Reviews proposed changes                     │ │
│  │  ├─ refactorer (AI) - Refactors code                               │ │
│  │  └─ explainer (AI)  - Explains code                                │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  CodingPod: "coding-pod-{work_item_id_2}"                          │ │
│  │  (same topology, independent state)                                 │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key relationships:**
- **1 Kernel per ManagedRepo** - Isolated runtime boundary per repository
- **1 RepoPod per Kernel** - Singleton for repo-level coordination
- **1 CodingPod per WorkItem** - Each work item gets its own pod with full agent team
- **Multiple agents per CodingPod** - Planner, coder, reviewer collaborate within the pod
- **Lazy agent activation** - AI agents start only when needed
- **Persistent state** - All state survives restarts via Ecto

**Reference:**
- Based on `Jido.AgentOS.Pods.CodingAssistant`: https://github.com/pcharbon70/jido_agent_os/tree/main/lib/jido/agent_os/pods/coding_assistant

## Actions and Tools

In Jido, **Actions** are the fundamental unit of work. AI agents are configured with a list of tools (which are Action modules). When an agent needs to perform work, it calls these actions.

### Action Categories

#### 1. Coding Tools (File Operations)

Actions for reading, writing, and analyzing code:

```elixir
defmodule JidoCode.AgentOS.Actions.ReadFile do
  @moduledoc """
  Read a file from the project workspace.
  """

  use Jido.Action,
    name: "coding_read_file",
    description: "Read a file from the active project.",
    schema: [
      path: [type: :string, required: true],
      max_chars: [type: :integer, default: 10_000]
    ]

  @impl true
  def run(%{path: path, max_chars: max_chars}, context) do
    with {:ok, project_path} <- project_path(context),
         full_path = Path.join(project_path, path),
         {:ok, content} <- File.read(full_path) do

      truncated = if String.length(content) > max_chars do
        {content, _} = String.split_at(content, max_chars)
        content <> "\n\n... (truncated)"
      else
        content
      end

      {:ok, %{
        path: path,
        full_path: full_path,
        content: truncated,
        size: String.length(content),
        truncated?: String.length(content) > max_chars
      }}
    end
  end

  defp project_path(context) do
    context[:project_path] ||
      get_in(context, [:tool_context, :project_path]) ||
      get_in(context, [:agent, :state, :workspace_path])
  end
end
```

```elixir
defmodule JidoCode.AgentOS.Actions.WriteFile do
  @moduledoc """
  Write content to a file in the project workspace.
  """

  use Jido.Action,
    name: "coding_write_file",
    description: "Write content to a file in the active project.",
    schema: [
      path: [type: :string, required: true],
      content: [type: :string, required: true],
      create_dirs: [type: :boolean, default: true]
    ]

  @impl true
  def run(%{path: path, content: content, create_dirs: create_dirs}, context) do
    with {:ok, project_path} <- project_path(context),
         full_path = Path.join(project_path, path),
         :ok <- (if create_dirs, do: File.mkdir_p!(Path.dirname(full_path)), else: :ok),
         :ok <- File.write(full_path, content) do
      {:ok, %{
        path: path,
        full_path: full_path,
        size: String.length(content),
        written: true
      }}
    end
  end
end
```

```elixir
defmodule JidoCode.AgentOS.Actions.ListFiles do
  use Jido.Action,
    name: "coding_list_files",
    description: "List files in a directory.",
    schema: [
      path: [type: :string, required: false],
      pattern: [type: :string, required: false],
      recursive: [type: :boolean, default: false]
    ]
end

defmodule JidoCode.AgentOS.Actions.SearchCode do
  use Jido.Action,
    name: "coding_search_code",
    description: "Search for text in files.",
    schema: [
      query: [type: :string, required: true],
      file_pattern: [type: :string, required: false],
      max_results: [type: :integer, default: 50]
    ]
end

defmodule JidoCode.AgentOS.Actions.RunTests do
  use Jido.Action,
    name: "coding_run_tests",
    description: "Run the test suite.",
    schema: [
      path: [type: :string, required: false],
      args: [type: {:list, :string}, default: []]
    ]
end

defmodule JidoCode.AgentOS.Actions.GitStatus do
  use Jido.Action,
    name: "coding_git_status",
    description: "Get git status of the repository.",
    schema: []
end

defmodule JidoCode.AgentOS.Actions.GitDiff do
  use Jido.Action,
    name: "coding_git_diff",
    description: "Get git diff of changes.",
    schema: [
      path: [type: :string, required: false]
    ]
end
```

#### 2. Task Board Actions (State Operations)

Actions that modify the TaskBoard agent's state:

```elixir
defmodule JidoCode.AgentOS.Actions.AddTask do
  @moduledoc """
  Add a task to the task board.
  Uses StateOp to modify agent state.
  """

  use Jido.Action,
    name: "task_add",
    description: "Add a new task to the task board.",
    schema: [
      title: [type: :string, required: true],
      description: [type: :string, required: true],
      priority: [type: :string, default: "medium"],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{title: title, description: description, priority: priority, metadata: metadata}, context) do
    alias Jido.Agent.StateOp

    task = %{
      id: generate_task_id(),
      title: title,
      description: description,
      priority: priority,
      status: :pending,
      metadata: metadata,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    current_tasks = Map.get(context.state, :tasks, [])
    active_task_id = Map.get(context.state, :active_task_id, "")

    # Return state operation alongside result
    state_op = StateOp.set_state(%{
      tasks: current_tasks ++ [task],
      active_task_id: if(active_task_id == "", do: task.id, else: active_task_id),
      last_updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:ok, %{task: task, added: true}, state_op}
  end
end
```

```elixir
defmodule JidoCode.AgentOS.Actions.SelectTask do
  use Jido.Action,
    name: "task_select",
    description: "Select the active task.",
    schema: [
      task_id: [type: :string, required: true]
    ]
end

defmodule JidoCode.AgentOS.Actions.StoreArtifact do
  use Jido.Action,
    name: "task_store",
    description: "Store an artifact (plan, code, review) on the task board.",
    schema: [
      task_id: [type: :string, required: true],
      stage: [type: :string, required: true],  # "plan", "code", "review"
      content: [type: :string, required: true],
      status: [type: :string, required: true]
    ]
end

defmodule JidoCode.AgentOS.Actions.AppendEvent do
  use Jido.Action,
    name: "task_event",
    description: "Append an event to the activity log.",
    schema: [
      kind: [type: :string, required: true],
      message: [type: :string, required: true],
      task_id: [type: :string, required: false]
    ]
end
```

#### 3. JidoCode Server Actions

Actions that interact with the JidoCode server (our product API):

```elixir
defmodule JidoCode.AgentOS.Actions.GetWorkItem do
  @moduledoc """
  Fetch WorkItem details from JidoCode server.
  """

  use Jido.Action,
    name: "jido_get_work_item",
    description: "Get work item details from the server.",
    schema: [
      work_item_id: [type: :string, required: true]
    ]

  @impl true
  def run(%{work_item_id: work_item_id}, _context) do
    # Call JidoCode server API
    case JidoCode.Server.get_work_item(work_item_id) do
      {:ok, work_item} ->
        {:ok, %{
          id: work_item.id,
          title: work_item.title,
          description: work_item.description,
          status: work_item.status
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule JidoCode.AgentOS.Actions.UpdateWorkItemStatus do
  use Jido.Action,
    name: "jido_update_work_item_status",
    description: "Update work item status on the server.",
    schema: [
      work_item_id: [type: :string, required: true],
      status: [type: :string, required: true]
    ]
end
```

### Agent Tool Assignments

Each AI agent is configured with the tools it needs:

```elixir
# Planner agent - needs to read and understand code
defmodule JidoCode.AgentOS.Agents.Planner do
  use Jido.AI.Agent,
    name: "coding_planner",
    model: :reasoning,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode,
      JidoCode.AgentOS.Actions.GetWorkItem
    ]
end

# Coder agent - needs to read and write files
defmodule JidoCode.AgentOS.Agents.Coder do
  use Jido.AI.Agent,
    name: "coding_coder",
    model: :fast,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.WriteFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode,
      JidoCode.AgentOS.Actions.RunTests,
      JidoCode.AgentOS.Actions.GitStatus,
      JidoCode.AgentOS.Actions.GitDiff
    ]
end

# Reviewer agent - needs to read and analyze
defmodule JidoCode.AgentOS.Agents.Reviewer do
  use Jido.AI.Agent,
    name: "coding_reviewer",
    model: :reasoning,
    tools: [
      JidoCode.AgentOS.Actions.ReadFile,
      JidoCode.AgentOS.Actions.ListFiles,
      JidoCode.AgentOS.Actions.SearchCode,
      JidoCode.AgentOS.Actions.RunTests,
      JidoCode.AgentOS.Actions.GitDiff
    ]
end
```

### Action Context Flow

When an agent calls a tool/action:

```
┌─────────────────────────────────────────────────────────────────┐
│  Agent (e.g., Planner)                                          │
│  "I need to read the user auth file"                           │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  AI Model decides to use coding_read_file tool                 │
│  Parameters: %{path: "lib/auth.ex"}                            │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Jido.Action.ReadFile.run(params, context)                     │
│                                                                 │
│  context contains:                                              │
│  - project_path (from agent state or pod context)              │
│  - workspace_id                                                │
│  - managed_repo_id                                             │
│  - agent state                                                 │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Action returns:                                                │
│  {:ok, %{content: "...", path: "lib/auth.ex", ...}}            │
│  or                                                            │
│  {:ok, result, StateOp.set_state(...)}  (for state changes)    │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Agent receives result, continues work                         │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Kernel Infrastructure
- [ ] Create `JidoCode.AgentOS.Manager` for dynamic kernel lifecycle
- [ ] Create `JidoCode.AgentOS.KernelSupervisor` for managing multiple kernels
- [ ] Configure per-kernel persistence via Ecto
- [ ] Kernel health monitoring and recovery

### Phase 2: Core Pod Definitions

**RepoPod (per kernel, singleton):**
- [ ] `RepoPod` definition with eager agents
- [ ] `RepoMonitor` agent - git status, file watching
- [ ] `WorkRegistry` agent - tracks active WorkItems

**CodingPod (per WorkItem, multiple instances):**
- [ ] `CodingPod` definition based on `Jido.AgentOS.Pods.CodingAssistant`
- [ ] `TaskBoard` agent (eager) - task coordination, artifacts
- [ ] `ProjectContext` agent (eager) - workspace/file context

### Phase 3: AI Agent Definitions

All agents within CodingPod:
- [ ] `Planner` agent (lazy, AI) - creates plans
- [ ] `Coder` agent (lazy, AI) - implements changes
- [ ] `Reviewer` agent (lazy, AI) - reviews changes
- [ ] `Refactorer` agent (lazy, AI) - refactors code
- [ ] `Explainer` agent (lazy, AI) - explains code

### Phase 4: Actions/Tools

Agent tools (shared across agents):
- [ ] `ReadFile` - read file contents
- [ ] `WriteFile` - write file contents
- [ ] `ListFiles` - list directory contents
- [ ] `SearchCode` - search codebase
- [ ] `RunTests` - execute test suite

Task board actions:
- [ ] `AddTask` - add task to board
- [ ] `SelectTask` - select active task
- [ ] `StoreArtifact` - store work artifact
- [ ] `AppendEvent` - log event

### Phase 5: Context Integration
- [ ] Create `JidoCode.AgentWorkspace` context
- [ ] Implement pod-per-workitem lifecycle management
- [ ] Wire `Conversations.Driver` to `AgentWorkspace`
- [ ] LiveView kernel/pod monitoring UI

### Phase 6: Parallel Operations & Cleanup
- [ ] Concurrent pod execution for multiple WorkItems
- [ ] Pod cleanup and resource management
- [ ] Archive/resume functionality

## Open Questions

1. **Kernel Lifecycle Management**
   - When should kernels be shut down? (idle timeout, explicit close, etc.)
   - How do we handle kernel failures without losing work state?
   - Maximum number of concurrent kernels?

2. **Pod Per WorkItem Scalability**
   - With one pod instance per WorkItem, what's the maximum pods we should allow per kernel?
   - How do we handle 100+ active WorkItems in a single repository?
   - Should we pool pods or keep the 1:1 mapping?

3. **Pod Coordination**
   - How do pods within a kernel communicate? (shared state vs signals)
   - How do we handle conflicting operations across pods (e.g., two CodingPods editing the same file)?

4. **WorkItem to Signal Correlation**
   - How do we ensure signals are routed to the correct WorkItem context?
   - Should WorkItem ID be included in all signal metadata?

5. **Multi-User Collaboration**
   - If multiple users work on the same ManagedRepo, do they share the kernel?
   - How do we handle concurrent WorkItem operations across users?

6. **Resource Limits**
   - Memory/CPU per kernel?
   - Maximum pods per kernel?
   - Maximum agents per pod?

## References

- [jido_agent_os README](https://github.com/pcharbon70/jido_agent_os)
- [jido_agent_os CodingAssistant Pod](https://github.com/pcharbon70/jido_agent_os/tree/main/lib/jido/agent_os/pods/coding_assistant)
- [jido_os Deprecation ADR](./jido_code.jido_os_deprecation.md)
- [ManagedRepo domain](../../lib/jido_code/control/managed_repo.ex)
- [WorkItem domain](../../lib/jido_code/operations/work_item.ex)
