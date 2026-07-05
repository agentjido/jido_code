# 14. Repository Mental Map

This guide is a practical "where things live" map for `jido_code`.

It is intentionally explanatory rather than normative. Trust implementation
code over this guide when they diverge, then update the guide.

## If You Only Open A Few Files First

These are the fastest orientation points in the repo:

1. [`../../lib/jido_code_web/router.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code_web/router.ex)
   The real browser surface and route vocabulary.
2. [`../../lib/jido_code/application.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/application.ex)
   The main supervision tree and long-running process boundaries.
3. [`../../lib/jido_code/agent_workspace.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/agent_workspace.ex)
   The product-owned boundary into AgentOS runtime, conversations, and graph
   behavior.
4. [`../../lib/jido_code/control/repo_bridge.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/control/repo_bridge.ex)
   The repo-scope bridge that turns route or setup input into canonical
   `ManagedRepo` and `SourceRepo` context.
5. [`../../lib/jido_code/control_plane/record_store.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/control_plane/record_store.ex)
   The map-level helper used by product services to create, update, list, and
   decode embedded control-plane records.
6. [`../../docs/developer/README.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/README.md)
   The rest of the explanatory guide set.

## Top-Level Layout

| Path | What it is for |
| --- | --- |
| `planning/` | Phased implementation and migration plans. |
| `docs/developer/` | Explanatory contributor guides that translate the current architecture into a faster mental model. |
| `lib/jido_code/` | Product plane, runtime boundary, semantic services, setup, security, and supporting modules. |
| `lib/jido_code_web/` | Phoenix router, LiveViews, components, controllers, and browser-facing boundaries. |
| `assets/` | Vite, LiveVue, CSS, and browser build inputs. |
| `priv/ontologies/` | The semantic ontology assets, especially `jido-control-plane.ttl`, `jido-memory.ttl`, and workflow provenance terms. |
| `config/` | Environment and runtime configuration. |
| `compat/` | Version-controlled compatibility packages such as local `jido_workflow`. |
| `test/` | Subsystem and phase-oriented coverage that mirrors the repo architecture. |

## The Main `lib/jido_code/` Zones

### 1. Product Entry Points

These modules and directories give the repo its top-level product vocabulary:

- [`../../lib/jido_code/accounts.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/accounts.ex)
- [`../../lib/jido_code/auth_providers.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/auth_providers.ex)
- [`../../lib/jido_code/control.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/control.ex)
- [`../../lib/jido_code/operations.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/operations.ex)
- [`../../lib/jido_code/governance.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/governance.ex)
- [`../../lib/jido_code/conversations.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/conversations.ex)

Read these first when you need to understand the main product records:

- `Accounts`: users, tokens, API keys, identities
- `AuthProviders`: provider-login configuration
- `Control`: `SourceRepo` and `ManagedRepo`
- `Operations`: external demand, observations, assessments, work items
- `Governance`: evidence, posture, change requests, decisions
- `Conversations`: durable productive conversation state

The durable record writes behind these areas flow through product-specific
stores or `JidoCode.ControlPlane.RecordStore`, not through Ash resources or a
Postgres repo.

### 2. Embedded Control-Plane Store

The product data plane is the embedded control-plane store under:

- `lib/jido_code/control_plane/`
- `lib/jido_code/control_plane/codecs/`
- `lib/jido_code/control_plane/store/`

Use this area when you are touching:

- graph topology and named graph assignment
- canonical subject IRIs and identity contracts
- codec projection between maps and RDF triples
- typed command and query boundaries
- integrity, recovery, diagnostics, and telemetry
- the product store contract used by product services

Normal callers should prefer product helpers such as
`JidoCode.ControlPlane.RecordStore`, `JidoCode.Control.ManagedRepoStore`,
`JidoCode.Operations.RecordStore`, `JidoCode.Governance.RecordStore`,
`JidoCode.Conversations.RecordStore`, and `JidoCode.ExecutionRuntime.RecordStore`.
Reach for raw SPARQL only through the explicit diagnostic boundary.

### 3. Product Plane And Record Bridges

These directories turn the control-plane model into usable product behavior:

- `lib/jido_code/control/`
  - repo identity, repo scope resolution, managed-repo provisioning
- `lib/jido_code/operations/`
  - ingress normalization, repo-native state, event and assessment synthesis,
    work synthesis
- `lib/jido_code/governance/`
  - posture, policy, runtime evidence, run-governance projection
- `lib/jido_code/workbench/`
  - LiveView-facing loaders and kickoff helpers for dashboard, repo detail,
    conversations, semantic inspection, and memory inspection
- `lib/jido_code/orchestration/`
  - governed run records, execution profiles, run feeds, and run detail support

If you are following a managed repository from import to governed work, these
are usually the first directories to inspect.

### 4. Runtime Boundary

These files are the main runtime boundary:

- [`../../lib/jido_code/agent_workspace.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/agent_workspace.ex)
- `lib/jido_code/agent_workspace/`
- `lib/jido_code/agent_os/`
- `lib/jido_code/pods/`
- `lib/jido_code/agents/`
- `lib/jido_code/actions/`

Their roles are different:

- `agent_workspace.ex`
  - public product-facing API into kernels, pods, specialists, graph
    operations, memory operations, and conversations
- `agent_os/`
  - repository-scoped kernel lifecycle and tracked pod metadata
- `pods/`
  - pod topology for `RepoPod`, `CodingPod`, `SourceCodeGraphPod`, and
    `MemoryGraphPod`
- `agents/`
  - specialist or support agent implementations such as planner, coder,
    reviewer, task board, repo monitor, and graph specialists
- `actions/`
  - Jido actions used as the runtime tool boundary
- `agent_workspace/`
  - runner helpers that shape specialist execution and prompt flow

If you need to change runtime behavior, start at `AgentWorkspace` and work
downward. Do not start from a LiveView and reach directly into a pod.

### 5. Conversation Orchestration

The conversation-specific implementation lives in `lib/jido_code/conversations/`.

Important files:

- `coordinator.ex`
- `driver.ex`
- `workflow_router.ex`
- `persistence.ex`
- `pub_sub.ex`
- `runtime.ex`
- `work_resolution.ex`

This is where repo-scoped intake, work-item-scoped productive threads,
interruptible turns, event logs, snapshots, and workflow routing actually live.

### 6. Semantic Source Graph

The source graph lives under:

- [`../../lib/jido_code/source_code_graph.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/source_code_graph.ex)
- `lib/jido_code/source_code_graph/`

Use this area when you are touching:

- repository semantic analysis
- TripleStore-backed `source_code` graph behavior
- helper queries and bounded product shaping
- semantic workflow inputs
- governed semantic finding adoption

### 7. Memory Graph And Workflow Provenance

The memory stack lives under:

- [`../../lib/jido_code/memory_graph.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph.ex)
- `lib/jido_code/memory_graph/`

This area covers:

- capture envelopes and writers
- durable memory insertion and update flow
- governed references
- workflow provenance
- memory query and product shaping
- cross-graph navigation
- operator-facing memory actions

### 8. Setup, Auth, And Provider Integration

These directories matter when orientation starts from bootstrap or identity
flows rather than repo work:

- `lib/jido_code/setup/`
- `lib/jido_code/accounts/`
- `lib/jido_code/auth_providers/`
- `lib/jido_code/source_providers/`
- `lib/jido_code/security/`
- `lib/jido_code/llm_selection.ex`

That is the cluster to read for:

- `/welcome` and `/setup`
- local auth and provider auth
- GitHub automation credential readiness
- provider-neutral repository access
- secret and token handling
- repo or conversation LLM selection

Auth and security metadata are embedded control-plane records. Secret material,
credential hashes, bearer tokens, webhook secrets, and private keys stay out of
RDF projections and out of default exports.

### 9. Transitional Or Narrower Areas

A few directories still exist but are not the center of the current model:

- `lib/jido_code/projects/`
  - older `Project` vocabulary still exists, but the preferred product language
    is `ManagedRepo`
- `lib/jido_code/orchestration/workflow_run.ex`
  - older `WorkflowRun` vocabulary still exists alongside governed `Run`
- `lib/jido_code/forge/`
  - legacy namespace for lower-level execution and sprite-session support;
    prefer `execution_runtime` naming for new product-facing work
- `lib/jido_code/github_issue_bot/`
  - narrower GitHub bot flows and supporting tests
- `lib/jido_code/workflow_runtime/`
  - local workflow compatibility helpers

Treat these as context to understand, not the default place to extend the
architecture unless the current code path truly lands there.

## The Main `lib/jido_code_web/` Zones

| Path | What it is for |
| --- | --- |
| `lib/jido_code_web/router.ex` | Canonical browser route map. |
| `lib/jido_code_web/live/` | LiveView page shells and bounded LiveVue-hosted surfaces. |
| `lib/jido_code_web/components/` | shared HEEx components, layouts, operator-state helpers, memory surface helpers, and LiveVue boundaries |
| `lib/jido_code_web/controllers/` | webhook, auth, and page controllers |
| `lib/jido_code_web/plugs/` | request-time browser and bootstrap guards |
| `lib/jido_code_web/security/` | UI redaction and browser-facing security helpers |

Practical reading pattern:

1. start at `router.ex`
2. find the relevant LiveView under `live/`
3. follow its loader or service module under `lib/jido_code/workbench/`,
   `setup/`, `conversations/`, `source_code_graph/`, or `memory_graph/`
4. only then step into runtime internals if the product boundary is too high

## Tests Mirror The Architecture

The `test/` tree is a good second mental map:

- `test/jido_code/control/`
- `test/jido_code/operations/`
- `test/jido_code/governance/`
- `test/jido_code/conversations*`
- `test/jido_code/agent_os/`
- `test/jido_code/source_code_graph*`
- `test/jido_code/memory_graph*`
- `test/jido_code/setup/`
- `test/jido_code/workbench/`
- `test/jido_code_web/live/`

There are also phase-oriented integration tests such as `phase_forty_*` or
`phase_fifty_*`. Those usually reflect architectural rollout slices recorded in
`planning/`, and they are often the fastest way to see the intended
behavior of a cross-cutting feature.

## Follow One Request Through The Repo

For a typical operator request on a managed repository:

1. `lib/jido_code_web/router.ex` chooses the LiveView route.
2. `lib/jido_code_web/live/*.ex` owns the page shell and event handling.
3. `lib/jido_code/workbench/` or another product service loads product-shaped
   state.
4. `lib/jido_code/control/`, `operations/`, and `governance/` resolve durable
   repo, work, posture, and run records.
5. `lib/jido_code/conversations/` and `agent_workspace.ex` decide whether the
   request is conversational, governed work, or runtime execution.
6. `lib/jido_code/agent_os/`, `pods/`, `agents/`, and `actions/` handle the
   runtime side if specialist execution is needed.
7. `lib/jido_code/source_code_graph/` and `memory_graph/` add bounded semantic
   context when explicitly requested.
8. Results come back into governed records, conversation state, and LiveView
   projections instead of remaining pod-local truth.

## Fast Navigation Shortcuts

If you need to answer one specific question, start here:

- "Where does repo detail come from?"
  - `router.ex` -> `project_detail_live.ex` -> `workbench/project_detail.ex` ->
    `control/repo_bridge.ex`
- "Where does a productive conversation live?"
  - `conversations/` plus `workbench/project_conversation.ex`
- "Where do specialists actually run?"
  - `agent_workspace.ex` -> `pods/coding_pod.ex` -> `agents/` ->
    `actions/`
- "Where is workflow routing decided?"
  - `conversations/workflow_router.ex`
- "Where is semantic code lookup implemented?"
  - `source_code_graph/`
- "Where is durable memory or provenance implemented?"
  - `memory_graph/`
- "Where does setup and provider auth live?"
  - `setup/`, `accounts/`, `auth_providers/`, `source_providers/`

## How To Use This Map

- Use it to decide where to read next.
- Use the numbered guide set when you need explanation.
- If code and this guide diverge, trust the code, then update the guide.

## Read Next

If you want a deeper conceptual explanation after this map, go back to:

- [`01-system-overview.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/01-system-overview.md)
- [`03-agent-workspace-and-runtime-topology.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/03-agent-workspace-and-runtime-topology.md)
- [`06-conversation-orchestration.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/06-conversation-orchestration.md)
- [`08-memory-graph-and-workflow-provenance.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08-memory-graph-and-workflow-provenance.md)
