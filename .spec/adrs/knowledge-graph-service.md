# Knowledge Graph Service ADR

## Status
**Accepted**

## Context

In the previous `jido_os` architecture, a Knowledge Graph (KG) service provided:
- SPARQL query capabilities over code structure and relationships
- Named graphs for isolating different knowledge contexts
- Ontology management for code understanding
- Service contract with operations like `query_sparql`, `update_sparql`, etc.

As we migrate to the AgentOS pod-based architecture, we need to re-create this capability.

## Decision

**We will implement the Knowledge Graph as a set of Jido.Action modules that agents can explicitly invoke.**

### Rationale

1. **Explicit invocation** - Agents decide when to query the KG based on their current task, rather than having ambient KG access
2. **Tool-based composition** - Consistent with how we handle files, git operations, and other resources
3. **Fine-grained control** - Each agent can have a subset of KG tools relevant to its role
4. **Clear responsibility** - KG operations are exposed as explicit actions rather than opaque service calls
5. **Pod independence** - No shared singleton state between pods; each pod can maintain its own context if needed

### Implementation Plan

The KG will be implemented as:

1. **JidoCode.Knowledge adapter** - Low-level interface to the KG backend
2. **JidoCode.Actions.KGQuery** - Action for SPARQL queries
3. **JidoCode.Actions.KGUpdate** - Action for updating the KG
4. **JidoCode.Actions.KGExplore** - Action for exploring code relationships
5. **JidoCode.Agents.Knowledge** (optional) - Eager agent in RepoPod that maintains the KG proactively

### Tool Distribution

| Agent | KG Tools |
|-------|-----------|
| Planner | KGQuery, KGExplore |
| Coder | KGQuery, KGUpdate |
| Reviewer | KGQuery |
| Explainer | KGQuery, KGExplore |
| RepoMonitor | KGUpdate (proactively updates KG on changes) |

## Alternatives Considered

### Option 1: Knowledge Agent in RepoPod
- **Pros:** Single source of truth, always available
- **Cons:** Implicit coupling, harder to control when KG is accessed, potential performance overhead

### Option 2: Singleton KG Service (jido_os style)
- **Pros:** Familiar pattern, centralized management
- **Cons:** Requires service discovery, harder to test, violates explicit tool-based approach

## Consequences

- Agents must explicitly include KG tools in their `tools:` list
- KG operations become traceable in agent activity logs (via AppendEvent)
- KG backend can be swapped out by changing the adapter
- Tests can mock KG actions easily without spinning up full service
- Migration path: Add KG tools to agents incrementally

## References

- Original KG service: `jido_os/lib/jido_os/kg/service.ex`
- Contract: `jido_os/specs/contracts/knowledge_graph_contract.md` (if exists)
- Phase plan: `.spec/planning/phase-XX-knowledge-graph.md` (to be created)
