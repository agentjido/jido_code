# Phase 6 - Compatibility, UI Migration, and Rollout Hardening

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/policy_layers.spec.md`
- `JidoCode.Workbench`
- `JidoCodeWeb.ProjectDetailLive`
- `JidoCodeWeb.RunDetailLive`
- `JidoCodeWeb.DashboardLive`

## Relevant Assumptions / Defaults
- Earlier phases have introduced the preferred control-plane records and transitional compatibility bridges.
- Existing UI surfaces still speak mostly in `Project` and `WorkflowRun` terms and need a careful migration path.
- Rollout should be staged so operator trust is earned through evidence, not by suddenly swapping core product concepts everywhere at once.

[x] 6 Phase 6 - Compatibility, UI Migration, and Rollout Hardening
  Finish the migration by moving remaining product surfaces onto the new managed-repo control plane, hardening policy and audit behavior, and completing compatibility and backfill rollout with explicit safeguards.

  [x] 6.1 Section - UI and Product-Surface Migration
    Move operator-facing surfaces from transitional resource assumptions to the preferred control-plane model without destabilizing current workflows.

    [x] 6.1.1 Task - Migrate workbench and repo-detail surfaces to `ManagedRepo`
      Make the preferred repo ontology visible to operators once compatibility bridges are proven.

      [x] 6.1.1.1 Subtask - Rework workbench and repo-detail loaders to prefer `ManagedRepo` over `Project`.
      [x] 6.1.1.2 Subtask - Preserve existing routes, deep links, and import entrypoints during the transition.
      [x] 6.1.1.3 Subtask - Keep operator language and UI labels clear about the managed-repo control role rather than only “project” framing.

    [x] 6.1.2 Task - Migrate run-detail and dashboard surfaces to the governed run model
      Make `Run`, `Evidence`, `ChangeRequest`, and `Decision` visible as first-class product concepts in operator workflows.

      [x] 6.1.2.1 Subtask - Rework dashboard and run-detail views to prefer governed `Run` records over transitional `WorkflowRun` assumptions.
      [x] 6.1.2.2 Subtask - Surface evidence, review requests, and decisions through first-class UI sections rather than only run-local maps.
      [x] 6.1.2.3 Subtask - Preserve compatibility with existing run links and pending-review flows during the migration.

  [x] 6.2 Section - Policy Hardening and Machine-Actor Rollout
    Replace permissive placeholder behavior with production-ready control-plane authorization and machine-actor boundaries.

    [x] 6.2.1 Task - Harden Ash policies across control-plane resources
      Move from transitional permissive policies to actor-aware authorization that matches the factory architecture.

      [x] 6.2.1.1 Subtask - Remove `authorize_if always()` placeholders from control-plane resources as the new actor model becomes available.
      [x] 6.2.1.2 Subtask - Apply actor, relationship, and context-aware policies for read versus mutate behavior across repos, work, runs, evidence, and decisions.
      [x] 6.2.1.3 Subtask - Preserve field-level protection for sensitive payloads, secrets, and evidence as the control plane becomes richer.

    [x] 6.2.2 Task - Roll out explicit machine-actor usage in orchestration paths
      Make machine authority visible and bounded instead of relying on implicit trusted service behavior.

      [x] 6.2.2.1 Subtask - Use explicit actor classes for orchestrators, run workers, and external ingress paths when mutating control-plane resources.
      [x] 6.2.2.2 Subtask - Preserve audit trails that explain which human or machine actor performed each mutation.
      [x] 6.2.2.3 Subtask - Keep runtime-overlay policy checks and product data-plane checks distinct in operator-visible failure paths.

  [x] 6.3 Section - Backfill, Rollout, and Operational Compatibility
    Complete the migration with safe data transition, rollback-ready coexistence, and operator-facing rollout evidence.

    [x] 6.3.1 Task - Backfill legacy records into the preferred control-plane model
      Make existing data usable under the new architecture before compatibility shims are removed.

      [x] 6.3.1.1 Subtask - Backfill current `Project` records into `ManagedRepo` and related governance records.
      [x] 6.3.1.2 Subtask - Backfill current `WorkflowRun` history into governed `Run`-adjacent records where needed for continuity.
      [x] 6.3.1.3 Subtask - Preserve rollback-safe coexistence until operator-visible surfaces no longer depend on the legacy records.

    [x] 6.3.2 Task - Add rollout evidence and removal criteria for compatibility shims
      Make the final migration auditable and explicitly reversible while trust is still being established.

      [x] 6.3.2.1 Subtask - Emit rollout evidence showing which surfaces still depend on `Project` or `WorkflowRun` compatibility paths.
      [x] 6.3.2.2 Subtask - Define removal criteria for legacy resource shims and route aliases.
      [x] 6.3.2.3 Subtask - Preserve typed rollback procedures if rollout signals show broken operator workflows or unsafe policy drift.

  [x] 6.4 Section - Phase 6 Integration Tests
    Validate UI migration, hardened authorization, backfilled compatibility, and rollout safety before legacy control-plane assumptions are retired.

    [x] 6.4.1 Task - Operator-surface migration scenarios
      Verify workbench, repo detail, dashboard, and run detail all operate correctly on the new control-plane model.

      [x] 6.4.1.1 Subtask - Add coverage for `ManagedRepo`-backed workbench and repo-detail flows.
      [x] 6.4.1.2 Subtask - Add coverage for governed `Run` and decision-aware dashboard or run-detail flows.
      [x] 6.4.1.3 Subtask - Verify compatibility routes and deep links still work during the coexistence period.

    [x] 6.4.2 Task - Rollout-hardening scenarios
      Verify policy, backfill, and rollback behavior are safe enough to retire the transitional architecture.

      [x] 6.4.2.1 Subtask - Add coverage for actor-aware authorization across the full migrated control-plane flow.
      [x] 6.4.2.2 Subtask - Add coverage for legacy-data backfill and mixed-mode coexistence.
      [x] 6.4.2.3 Subtask - Verify rollout evidence and rollback procedures are sufficient before compatibility shims are removed.
