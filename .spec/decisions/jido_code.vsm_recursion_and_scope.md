---
id: jido_code.vsm_recursion_and_scope
status: accepted
date: 2026-03-23
affects:
  - package.jido_code
  - architecture.vsm_recursion
  - docs.product_foundation
---

<!-- covers: architecture.vsm_recursion.factory_is_viable_system -->
<!-- covers: architecture.vsm_recursion.managed_repo_is_viable_system -->
<!-- covers: architecture.vsm_recursion.repo_system1_scope -->
<!-- covers: architecture.vsm_recursion.work_items_not_default_vsm -->
<!-- covers: architecture.vsm_recursion.promotion_rule_defined -->
<!-- covers: architecture.vsm_recursion.algedonic_escalation -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# VSM Recursion And Scope

## Context

`Jido.Code` is being shaped as a cloud software factory rather than a collection of
agent features. The current data ontology defines durable control-plane records such as
`ManagedRepo`, `WorkItem`, `Run`, `ChangeRequest`, and `Decision`, but the next
architectural question is where viable-system recursion should begin and end.

Stafford Beer's Viable System Model is recursive, but recursion should not be applied
indiscriminately. If every short-lived work packet is treated as a full viable system,
the architecture becomes noisy and ungovernable. If recursion is not applied where it is
needed, autonomous units will lack coordination, policy, intelligence, and feedback.

## Decision

`Jido.Code` shall model viability at two default recursive levels:

- the factory instance as a viable system
- each `ManagedRepo` as a viable subsystem within that factory

At the factory level:

- System 1 is the portfolio of `ManagedRepo` units
- System 2 coordinates capacity, queues, sandbox allocation, and cross-repo contention
- System 3 controls portfolio priorities, admission, and resource allocation
- System 3* audits drift, failures, and control-plane health
- System 4 scans external change, operator demand, and future risks across the factory
- System 5 defines factory identity, policy posture, and autonomy boundaries

At the `ManagedRepo` level:

- System 1 is the repository's operational work loops, expressed through `WorkItem`
  categories and executed through `Run`
- System 2 coordinates queueing, branch ownership, sandbox scheduling, and conflict
  prevention inside the repo
- System 3 is the repository orchestrator that governs dispatch and execution
- System 3* audits repo state, drift, and reconciliation against external systems
- System 4 scans for new demand, future risk, and environmental change affecting that repo
- System 5 defines repository policy, mission, autonomy mode, and escalation posture

`WorkItem` and `Run` shall not be treated as full viable systems by default. They are
operational records within `ManagedRepo` System 1 unless they are explicitly promoted.

Promotion to a lower recursive viable subsystem shall require all of the following:

- persistent identity across episodes
- bounded mission and operating boundary
- its own coordination needs
- its own control and feedback loop
- distinct policy or autonomy constraints

Viability-threatening conditions shall support algedonic escalation from lower levels to
higher policy levels without waiting for normal queue flow.

## Consequences

- The architecture gains a clear default recursion boundary instead of treating every
  agent action as a standalone system.
- `ManagedRepo` becomes the primary unit of recursive autonomy and governance.
- `WorkItem` remains the durable job-system unit without being over-modeled.
- Future promotion of long-lived specialized cells remains possible, but only when the
  subsystem truly needs its own VSM scope.
- Factory-wide operator views, budgets, and backpressure naturally live above the repo
  level rather than being recreated inside each run.
