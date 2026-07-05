# Phase 5 - Control, Operations, Governance, And Orchestration Data Plane

Back to plan: [README](./README.md)

**Description:** This phase replaces the primary product control-plane resource families with embedded TripleStore-backed services. It covers managed repositories, source repositories, external objects, observations, assessments, work items, runs, evidence, change requests, decisions, policies, posture, and execution profiles.

- [x] 5 Phase - Control, operations, governance, and orchestration data plane.

  Description: Move core product truth from Ash resources to semantic records and product services.

## 5.1 Section - Managed Repositories And Source Records

**Description:** This section makes managed repositories and source repository records canonical semantic entities.

- [x] 5.1 Section - Managed repositories and source records.

  Description: Managed repo services become the root lookup and scoping boundary for most other product records.

  - [x] 5.1.1 Task - Implement managed repo and source repo services.

    Description: Repo import, workspace binding, runtime readiness, and settings surfaces should operate through store-backed projections.

    - [x] 5.1.1.1 Subtask - Implement source repo and managed repo codecs.
    - [x] 5.1.1.2 Subtask - Rewire project import to create source and managed repo records through product services.
    - [x] 5.1.1.3 Subtask - Rewire workspace binding and runtime readiness reads away from Ash.

  - [x] 5.1.2 Task - Remove legacy project as a preferred data path.

    Description: Since the project is greenfield, `Project` should exist only if needed for naming compatibility during code removal.

    - [x] 5.1.2.1 Subtask - Replace product callers that create or query `Projects.Project`.
    - [x] 5.1.2.2 Subtask - Remove legacy project fixtures from tests that can seed managed repos directly.
    - [x] 5.1.2.3 Subtask - Document any remaining `Project` references as deletion targets for Phase 7.

    Phase 7 deletion target note: after the Section 5.1 cutover, `Project` remains only in legacy Ash resource definitions, WorkflowRun compatibility relations, browser/conn setup helpers that still create WorkflowRun-era fixtures, and older LiveView/integration tests. A scan during this section found 247 remaining `Project` references across runtime and test code. Phase 7.1 and 7.3 should remove those references after operations, governance, orchestration, conversation, and runtime records have equivalent store-backed services.

## 5.2 Section - Operations Records

**Description:** This section replaces demand ingress, observation, assessment, external object, and work item persistence.

- [x] 5.2 Section - Operations records.

  Description: Work synthesis remains product-shaped while record storage moves to semantic triples.

  - [x] 5.2.1 Task - Implement operations codecs and services.

    Description: Operations records must retain canonical relationships from external demand through governed work.

    - [x] 5.2.1.1 Subtask - Implement codecs for intake, external object, event, observation, assessment, and work item.
    - [x] 5.2.1.2 Subtask - Rewire ingress and synthesis modules to product store services.
    - [x] 5.2.1.3 Subtask - Preserve deduplication semantics for external objects and work items.

  - [x] 5.2.2 Task - Implement operations query projections.

    Description: Dashboard, workbench, and repo-detail surfaces need bounded projections without Ash relationship loading.

    - [x] 5.2.2.1 Subtask - Add list work by managed repo, external object, status, and priority queries.
    - [x] 5.2.2.2 Subtask - Add repository monitoring summary queries.
    - [x] 5.2.2.3 Subtask - Add product-shaped empty, degraded, and stale states.

## 5.3 Section - Governance And Orchestration Records

**Description:** This section replaces governed run, evidence, review, decision, policy, posture, and execution profile persistence.

- [x] 5.3 Section - Governance and orchestration records.

  Description: Governance remains explicit and auditable while no longer depending on Ash resources or Postgres migrations.

  - [x] 5.3.1 Task - Implement orchestration services.

    Description: Runs and execution profiles need store-backed lifecycle transitions and projections.

    - [x] 5.3.1.1 Subtask - Implement codecs for run, workflow run compatibility, and execution profile records.
    - [x] 5.3.1.2 Subtask - Rewire run bridge, run summary feed, and workflow launch paths to store services.
    - [x] 5.3.1.3 Subtask - Preserve retry lineage and stage-status projections.

  - [x] 5.3.2 Task - Implement governance services.

    Description: Evidence, change requests, decisions, policies, posture, and posture checks need explicit product-owned lifecycle rules.

    - [x] 5.3.2.1 Subtask - Implement codecs for evidence, change request, decision, policy set, repo posture, and posture check.
    - [x] 5.3.2.2 Subtask - Rewire governance bridges to store-backed reads and writes.
    - [x] 5.3.2.3 Subtask - Preserve algedonic escalation, decision supersession, and evidence linkage behavior.

    Section verification: `mix test test/jido_code/orchestration/run_bridge_test.exs test/jido_code/orchestration/phase_three_integration_test.exs test/jido_code/governance/run_governance_bridge_test.exs test/jido_code/governance/policy_bridge_test.exs test/jido_code/governance/posture_bridge_test.exs test/jido_code/governance/runtime_evidence_feed_test.exs` passes against isolated embedded product stores.

## 5.4 Section - Integration Tests

**Description:** This final section proves the core control plane can create, query, and govern work without Ash/Postgres.

- [x] 5.4 Section - Integration tests.

  Description: End-to-end tests should follow a demand item from source observation through governed run and decision records.

  - [x] 5.4.1 Task - Add operations-to-work integration coverage.

    Description: Operations tests should validate the replacement for current repo-native work synthesis flows.

    - [x] 5.4.1.1 Subtask - Create a managed repo, external object, observation, assessment, and work item in one scenario.
    - [x] 5.4.1.2 Subtask - Prove duplicate external demand reuses the expected semantic identity.
    - [x] 5.4.1.3 Subtask - Prove dashboard and workbench projections return the expected work roster.

  - [x] 5.4.2 Task - Add governance and orchestration integration coverage.

    Description: Governance tests should validate run lifecycle and review records over the embedded store.

    - [x] 5.4.2.1 Subtask - Launch a governed run for a work item and record evidence.
    - [x] 5.4.2.2 Subtask - Create a change request and governed decision linked to the run.
    - [x] 5.4.2.3 Subtask - Query repo posture and policy projections without Ash relationship loading.

    Section verification: `mix test test/jido_code/control_plane/embedded_store_phase_five_integration_test.exs --trace` proves operations, governance, orchestration, posture, and policy projections through isolated embedded product stores.
