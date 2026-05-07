# Developer Guides

<!-- covers: docs.product_foundation.source_code_ontology_guide_present -->
<!-- covers: docs.product_foundation.memory_ontology_guide_present -->
<!-- covers: docs.product_foundation.workflow_provenance_ontology_guide_present -->

These guides explain `jido_code` in contributor terms.

## Reading Order

1. [`01-system-overview.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/01-system-overview.md)
   Continue with the big picture: product plane, runtime plane, and semantic
   layers.
2. [`02-product-plane-and-governed-records.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/02-product-plane-and-governed-records.md)
   Learn the canonical product records and why the repo is a governed software
   factory instead of a chat-first app.
3. [`03-agent-workspace-and-runtime-topology.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/03-agent-workspace-and-runtime-topology.md)
   See how repository-scoped runtime orchestration works.
4. [`04-coding-pod-and-specialist-workflows.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/04-coding-pod-and-specialist-workflows.md)
   Understand the per-work-item pod and the specialist workflow lifecycle.
5. [`05-specialist-prompts-context-and-tool-execution.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/05-specialist-prompts-context-and-tool-execution.md)
   Follow the exact prompt, context, and tool flow from `AgentWorkspace` to the
   LLM request.
6. [`06-conversation-orchestration.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/06-conversation-orchestration.md)
   See how productive conversations are coordinated, persisted, and streamed.
7. [`07-source-code-graph-and-semantic-services.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/07-source-code-graph-and-semantic-services.md)
   Understand the repository-scoped semantic source-code graph and its
   product-facing boundaries.
8. [`07b-source-code-ontology-and-query-examples.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/07b-source-code-ontology-and-query-examples.md)
   Go one level deeper on the semantic graph contents: ontology layers, loaded
   repository facts, and example queries.
9. [`08-memory-graph-and-workflow-provenance.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08-memory-graph-and-workflow-provenance.md)
   Learn how workflow provenance and durable coding memory are captured and
   surfaced.
10. [`08b-memory-ontology-and-query-examples.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08b-memory-ontology-and-query-examples.md)
   Go one level deeper on durable memory: ontology layers, stored memory
   content, freshness and evidence links, and example queries.
11. [`08c-workflow-provenance-ontology-and-query-examples.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08c-workflow-provenance-ontology-and-query-examples.md)
   Go one level deeper on operational history: work-session structure,
   execution lineage, governed links, and example provenance queries.
12. [`09-frontend-and-product-surfaces.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/09-frontend-and-product-surfaces.md)
   See how LiveView, `live_vue`, and product surfaces fit together.
13. [`10-development-workflow-and-quality-gates.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/10-development-workflow-and-quality-gates.md)
    Finish with the day-to-day contributor workflow and the verification
    surfaces that protect the repo.
14. [`11-ingress-synthesis-and-work-item-flow.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/11-ingress-synthesis-and-work-item-flow.md)
    Follow the concrete path from inbound demand to `WorkItem`, including the
    repo-conversation-to-governed-work handoff and a real `fix failing tests`
    example.
15. [`12-user-request-to-llm-message-path.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/12-user-request-to-llm-message-path.md)
    See exactly how a user request is preserved, wrapped, and transformed before
    becoming the final specialist LLM message list.
16. [`13-source-code-graph-operations.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/13-source-code-graph-operations.md)
    Learn operational aspects of the source code graph capability, including
    configuration, monitoring, troubleshooting, and production deployment.
17. [`14-repository-mental-map.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/14-repository-mental-map.md)
    Use this as a fast "where things live" index when you want to browse the
    codebase without reconstructing the repo layout from scratch.

## How To Use These Guides

- Use these guides to get oriented quickly before diving into implementation.
- When behavior in code and a guide seem to disagree, treat the code as the
  stronger signal and update the guide.

## Suggested Companion Reads

- [`../../README.md`](https://github.com/mikehostetler/jido_code/blob/main/README.md)
- [`../../CONTRIBUTING.md`](https://github.com/mikehostetler/jido_code/blob/main/CONTRIBUTING.md)
- [`../../AGENTS.md`](https://github.com/mikehostetler/jido_code/blob/main/AGENTS.md)
- [`../../memory_ontology_guide.md`](https://github.com/mikehostetler/jido_code/blob/main/memory_ontology_guide.md)
