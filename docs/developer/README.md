# Developer Guides

These guides explain `jido_code` in contributor terms.

They are intentionally explanatory rather than normative. Current truth still
lives in:

- [`../../.spec/README.md`](../../.spec/README.md)
- [`../../.spec/topology.md`](../../.spec/topology.md)
- [`../../.spec/specs/`](../../.spec/specs/)
- [`../../.spec/decisions/`](../../.spec/decisions/)

## Reading Order

1. [`01-system-overview.md`](01-system-overview.md)  
   Start here for the big picture: product plane, runtime plane, and semantic
   layers.
2. [`02-product-plane-and-governed-records.md`](02-product-plane-and-governed-records.md)  
   Learn the canonical product records and why the repo is a governed software
   factory instead of a chat-first app.
3. [`03-agent-workspace-and-runtime-topology.md`](03-agent-workspace-and-runtime-topology.md)  
   See how repository-scoped runtime orchestration works.
4. [`04-coding-pod-and-specialist-workflows.md`](04-coding-pod-and-specialist-workflows.md)  
   Understand the per-work-item pod and the specialist workflow lifecycle.
5. [`05-specialist-prompts-context-and-tool-execution.md`](05-specialist-prompts-context-and-tool-execution.md)  
   Follow the exact prompt, context, and tool flow from `AgentWorkspace` to the
   LLM request.
6. [`06-conversation-orchestration.md`](06-conversation-orchestration.md)  
   See how productive conversations are coordinated, persisted, and streamed.
7. [`07-source-code-graph-and-semantic-services.md`](07-source-code-graph-and-semantic-services.md)  
   Understand the repository-scoped semantic source-code graph and its
   product-facing boundaries.
8. [`08-memory-graph-and-workflow-provenance.md`](08-memory-graph-and-workflow-provenance.md)  
   Learn how workflow provenance and durable coding memory are captured and
   surfaced.
9. [`09-frontend-and-product-surfaces.md`](09-frontend-and-product-surfaces.md)  
   See how LiveView, `live_vue`, and product surfaces fit together.
10. [`10-development-workflow-and-quality-gates.md`](10-development-workflow-and-quality-gates.md)  
    Finish with the day-to-day contributor workflow and the verification
    surfaces that protect the repo.
11. [`11-ingress-synthesis-and-work-item-flow.md`](11-ingress-synthesis-and-work-item-flow.md)
    Follow the concrete path from inbound demand to `WorkItem`, including the
    repo-conversation-to-governed-work handoff and a real `fix failing tests`
    example.
12. [`12-user-request-to-llm-message-path.md`](12-user-request-to-llm-message-path.md)
    See exactly how a user request is preserved, wrapped, and transformed before
    becoming the final specialist LLM message list.
13. [`13-source-code-graph-operations.md`](13-source-code-graph-operations.md)
    Learn operational aspects of the source code graph capability, including
    configuration, monitoring, troubleshooting, and production deployment.

## How To Use These Guides

- Use these guides to get oriented quickly before diving into implementation.
- Use the `.spec` workspace when you need the exact current contract.
- When behavior in code and a guide seem to disagree, treat the code and `.spec`
  files as the stronger signal and update the guide.

## Suggested Companion Reads

- [`../../README.md`](../../README.md)
- [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)
- [`../../AGENTS.md`](../../AGENTS.md)
- [`../../memory_ontology_guide.md`](../../memory_ontology_guide.md)
