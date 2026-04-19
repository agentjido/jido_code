# Phase 54 - Drift Closure And Current-Truth Convergence

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects -->
<!-- covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records -->
<!-- covers: architecture.run_governance.greenfield_tests_and_fixtures_create_canonical_run_graph -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/run_governance.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/source_provider_adapter.spec.md`
- `lib/jido_code/control/repo_bridge.ex`
- `lib/jido_code/orchestration/run.ex`
- `lib/jido_code/orchestration/run_bridge.ex`
- `lib/jido_code/orchestration/workflow_run.ex`
- `lib/jido_code/workflow_runtime/manual_run_kickoff.ex`
- `lib/jido_code/workbench/`
- `lib/jido_code_web/live/`
- `test/jido_code/`
- `test/jido_code_web/live/`
- `docs/developer/`
- `README.md`
- `.spec/planning/README.md`

## Relevant Assumptions / Defaults
- Phases 17 and 18 were intended to complete the canonical `ManagedRepo` and governed `Run` cutover, but a current audit shows residual `Project`- and `WorkflowRun`-era assumptions still survive in live product surfaces, helper paths, and greenfield tests.
- Several semantic and AgentOS subjects now have landed product code and integration coverage that substantially exceed `proposed`-only status, so current-truth spec metadata needs to catch up with the implementation.
- GitLab and Bitbucket service automation remain intentional placeholder capabilities and should stay explicit as deferred work rather than being misclassified as drift.
- The planning chronology also needs repair: the index stops at Phase 53 even though repo coverage has already advanced into Phase 55-style integration work.

[x] 54 Phase 54 - Drift Closure And Current-Truth Convergence
  Close the remaining gap between the current-truth specs and the implementation by finishing canonical repo and run cutovers, converging greenfield fixtures and helpers, reclassifying shipped subjects, and repairing planning plus contributor guidance where chronology or terminology has drifted.

  [x] 54.1 Section - Canonical Product Surface And Runtime Convergence
    Finish the remaining `Project` and `WorkflowRun` cutover in live product code so routed operator surfaces and product-owned runtime entrypoints depend on `ManagedRepo` and governed `Run` as the canonical records.

    [x] 54.1.1 Task - Remove legacy repo vocabulary and loaders from live product surfaces
      Replace user-facing `Project` language and direct project-row lookup behavior in routed LiveView surfaces with managed-repo-first labels, route helpers, and bounded product-owned loaders.

      [x] 54.1.1.1 Subtask - Update routed LiveView and LiveVue surfaces so operator-facing labels, headings, field names, and helper text speak in repository or managed-repository terms instead of `Project`.
      [x] 54.1.1.2 Subtask - Replace direct `Project` reads in live product modules with canonical repo-scope or managed-repo loaders wherever the surface already claims canonical control-plane ownership.
      [x] 54.1.1.3 Subtask - Keep residual legacy identifier handling inside bounded repo-bridge helpers rather than leaking compatibility vocabulary back into product-facing modules.

    [x] 54.1.2 Task - Keep workflow-history compatibility behind explicit internal adapters only
      Narrow remaining execution compatibility seams so product-owned launch, refresh, and route helpers read governed `Run` state first and treat `WorkflowRun` only as bounded audit or adapter support where a current path still requires it.

      [x] 54.1.2.1 Subtask - Remove direct `WorkflowRun` dependency from live product refresh, launch, and navigation helpers that can already resolve through governed `Run`.
      [x] 54.1.2.2 Subtask - Keep any still-needed `WorkflowRun` interaction inside internal bridge or webhook boundaries and document that scope as explicit compatibility or audit support.
      [x] 54.1.2.3 Subtask - Verify canonical run-detail and workflow-launch paths no longer depend on `Project` or `WorkflowRun` as their primary product records.

  [x] 54.2 Section - Greenfield Fixture And Helper Convergence
    Bring tests, setup helpers, and fixture conventions back into alignment with the canonical control-plane model so new work stops recreating the exact drift the audit found.

    [x] 54.2.1 Task - Convert greenfield product tests and helpers to canonical repo and run records
      Update general product tests, factories, and setup helpers to create `SourceRepo`, `ManagedRepo`, `WorkItem`, and governed `Run` graphs directly unless a migration-specific or adapter-specific case explicitly needs legacy audit data.

      [x] 54.2.1.1 Subtask - Replace `Project.create` and `WorkflowRun.create` in greenfield LiveView and orchestration tests with canonical repo and governed-run helper paths.
      [x] 54.2.1.2 Subtask - Update shared test helpers and fixtures so fresh product coverage defaults to canonical repo and run graph creation.
      [x] 54.2.1.3 Subtask - Keep migration-specific or compatibility-specific tests explicit about why legacy records are still required for that coverage.

    [x] 54.2.2 Task - Isolate intentional compatibility coverage instead of letting it masquerade as normal setup
      Preserve the few compatibility-era cases that still matter, but fence them into bounded adapter, audit, or migration coverage so the rest of the repo stops treating old record graphs as normal product prerequisites.

      [x] 54.2.2.1 Subtask - Mark legacy `Project` and `WorkflowRun` coverage as migration, adapter, or audit-oriented where it cannot yet be deleted.
      [x] 54.2.2.2 Subtask - Remove helper defaults that silently fall back to `get_by_legacy_project_id` or compatibility record creation in otherwise greenfield tests.
      [x] 54.2.2.3 Subtask - Verify new helper and fixture conventions make canonical repo and run graphs the default path for future feature work.

  [x] 54.3 Section - Current-Truth Spec Status And Subject Convergence
    Reconcile the spec workspace with the actual repo state by promoting shipped subjects, retaining truly partial subjects as proposed where appropriate, and keeping intentional placeholders explicit.

    [x] 54.3.1 Task - Reclassify implemented semantic and AgentOS subjects out of proposal-only status
      Promote specs that already have landed product surfaces and integration coverage from `proposed` to the correct current-truth status after a deliberate pass over their scope and verification coverage.

      [x] 54.3.1.1 Subtask - Review semantic and AgentOS subjects whose implementation and tests already exceed `proposed` status, including source-code-graph, memory-graph, memory-capture, ontology, and AgentOS integration subjects.
      [x] 54.3.1.2 Subtask - Update spec metadata and summaries so current-truth language describes shipped behavior instead of future-tense rollout claims where the work has landed.
      [x] 54.3.1.3 Subtask - Keep verification blocks and referenced surfaces aligned with the code and tests that now back those promoted subjects.

    [x] 54.3.2 Task - Keep intentionally deferred capabilities explicit instead of treating them as drift
      Preserve placeholder or partial capabilities as deliberate current truth so the spec workspace distinguishes real drift from work that is intentionally deferred.

      [x] 54.3.2.1 Subtask - Keep GitLab and Bitbucket service automation in explicit placeholder status until actual provider automation support lands.
      [x] 54.3.2.2 Subtask - Record any still-intentional compatibility or audit seams as bounded internal exceptions instead of silently leaving them ambiguous.
      [x] 54.3.2.3 Subtask - Verify only truly incomplete subjects remain `proposed` after the drift-closure pass.

  [x] 54.4 Section - Planning, Docs, And Contributor Convergence
    Repair the planning and guidance layers so contributors see one coherent story about what is canonical, what is deferred, and which phase work has already landed.

    [x] 54.4.1 Task - Repair planning chronology and rollout narrative
      Update the planning index and adjacent planning assets so Phase 54 closes the spec-to-implementation drift audit and explains any higher-numbered coverage that appeared before its planning doc existed.

      [x] 54.4.1.1 Subtask - Add Phase 54 to the planning index with a clear drift-closure description and current shared context.
      [x] 54.4.1.2 Subtask - Reconcile the planning README with any existing Phase 55-style coverage so phase numbering and rollout narrative stop drifting apart.
      [x] 54.4.1.3 Subtask - Remove stale planning or roadmap text that still implies canonical cutover work already finished everywhere when the audit shows otherwise.

    [x] 54.4.2 Task - Align contributor-facing docs and guidance with canonical terminology
      Remove lingering `Project` and `WorkflowRun` language from contributor and operator guides except where a bounded compatibility or migration note is still intentional and explicitly labeled.

      [x] 54.4.2.1 Subtask - Update repo guides, developer docs, and contributor instructions to prefer canonical repository and governed-run vocabulary.
      [x] 54.4.2.2 Subtask - Keep compatibility or migration notes explicit when a guide still needs to mention legacy identifiers, bridges, or audit support.
      [x] 54.4.2.3 Subtask - Verify contributor guidance now directs future work toward canonical repo and run helpers, spec statuses, and planning references.

  [x] 54.5 Section - Phase 54 Integration Tests
    Prove the drift is actually closed by checking live product behavior, greenfield fixture defaults, current-truth spec status, and contributor-facing planning or documentation together.

    [x] 54.5.1 Task - Add drift-closure coverage for canonical product surfaces and helpers
      Verify live product paths, setup helpers, and new tests no longer depend on `Project` and `WorkflowRun` as the primary product truths for greenfield behavior.

      [x] 54.5.1.1 Subtask - Add coverage proving live operator surfaces load canonical repository and governed-run state without direct legacy record reads.
      [x] 54.5.1.2 Subtask - Add coverage proving greenfield helpers and tests create canonical repo and run graphs by default.
      [x] 54.5.1.3 Subtask - Add coverage proving remaining compatibility seams are bounded to explicit adapter, audit, or migration paths.

    [x] 54.5.2 Task - Verify current-truth convergence across specs, planning, and docs
      Ensure the spec workspace, planning index, and contributor-facing guidance tell the same story after the drift-closure work lands.

      [x] 54.5.2.1 Subtask - Add verification proving promoted specs, current implementation surfaces, and their tests stay in sync after the status cleanup.
      [x] 54.5.2.2 Subtask - Add verification proving planning chronology and phase references remain coherent once Phase 54 is introduced.
      [x] 54.5.2.3 Subtask - Verify contributor and operator docs reflect canonical terminology and explicit placeholder exceptions instead of mixed current and legacy language.
