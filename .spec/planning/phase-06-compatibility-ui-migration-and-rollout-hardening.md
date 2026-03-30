# Phase 6 - Compatibility, UI Migration, and Rollout Hardening

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/policy_layers.spec.md`
- `../specs/conversation_driver.spec.md`
- `JidoCode.Workbench`
- `JidoCodeWeb.ProjectDetailLive`
- `JidoCodeWeb.RunDetailLive`
- `JidoCodeWeb.DashboardLive`

## Relevant Assumptions / Defaults
- Earlier phases have introduced the preferred control-plane records and transitional compatibility bridges.
- Existing UI surfaces still speak mostly in `Project` and `WorkflowRun` terms and need a careful migration path.
- Rollout should be staged so operator trust is earned through evidence, not by suddenly swapping core product concepts everywhere at once.

[ ] 6 Phase 6 - Compatibility, UI Migration, and Rollout Hardening
  Finish the migration by moving remaining product surfaces onto the new managed-repo control plane, hardening policy and audit behavior, and completing compatibility and backfill rollout with explicit safeguards.

  [ ] 6.1 Section - UI and Product-Surface Migration
    Move operator-facing surfaces from transitional resource assumptions to the preferred control-plane model without destabilizing current workflows.

    [ ] 6.1.1 Task - Migrate workbench and repo-detail surfaces to `ManagedRepo`
      Make the preferred repo ontology visible to operators once compatibility bridges are proven.

      [ ] 6.1.1.1 Subtask - Rework workbench and repo-detail loaders to prefer `ManagedRepo` over `Project`.
      [ ] 6.1.1.2 Subtask - Preserve existing routes, deep links, and import entrypoints during the transition.
      [ ] 6.1.1.3 Subtask - Keep operator language and UI labels clear about the managed-repo control role rather than only “project” framing.

    [ ] 6.1.2 Task - Migrate run-detail and dashboard surfaces to the governed run model
      Make `Run`, `Evidence`, `ChangeRequest`, and `Decision` visible as first-class product concepts in operator workflows.

      [ ] 6.1.2.1 Subtask - Rework dashboard and run-detail views to prefer governed `Run` records over transitional `WorkflowRun` assumptions.
      [ ] 6.1.2.2 Subtask - Surface evidence, review requests, and decisions through first-class UI sections rather than only run-local maps.
      [ ] 6.1.2.3 Subtask - Preserve compatibility with existing run links and pending-review flows during the migration.

  [ ] 6.2 Section - Policy Hardening and Machine-Actor Rollout
    Replace permissive placeholder behavior with production-ready control-plane authorization and machine-actor boundaries.

    [ ] 6.2.1 Task - Harden Ash policies across control-plane resources
      Move from transitional permissive policies to actor-aware authorization that matches the factory architecture.

      [ ] 6.2.1.1 Subtask - Remove `authorize_if always()` placeholders from control-plane resources as the new actor model becomes available.
      [ ] 6.2.1.2 Subtask - Apply actor, relationship, and context-aware policies for read versus mutate behavior across repos, work, runs, evidence, and decisions.
      [ ] 6.2.1.3 Subtask - Preserve field-level protection for sensitive payloads, secrets, and evidence as the control plane becomes richer.

    [ ] 6.2.2 Task - Roll out explicit machine-actor usage in orchestration paths
      Make machine authority visible and bounded instead of relying on implicit trusted service behavior.

      [ ] 6.2.2.1 Subtask - Use explicit actor classes for orchestrators, run workers, and external ingress paths when mutating control-plane resources.
      [ ] 6.2.2.2 Subtask - Preserve audit trails that explain which human or machine actor performed each mutation.
      [ ] 6.2.2.3 Subtask - Keep runtime-overlay policy checks and product data-plane checks distinct in operator-visible failure paths.

  [ ] 6.3 Section - Backfill, Rollout, and Operational Compatibility
    Complete the migration with safe data transition, rollback-ready coexistence, and operator-facing rollout evidence.

    [ ] 6.3.1 Task - Backfill legacy records into the preferred control-plane model
      Make existing data usable under the new architecture before compatibility shims are removed.

      [ ] 6.3.1.1 Subtask - Backfill current `Project` records into `ManagedRepo` and related governance records.
      [ ] 6.3.1.2 Subtask - Backfill current `WorkflowRun` history into governed `Run`-adjacent records where needed for continuity.
      [ ] 6.3.1.3 Subtask - Preserve rollback-safe coexistence until operator-visible surfaces no longer depend on the legacy records.

    [ ] 6.3.2 Task - Add rollout evidence and removal criteria for compatibility shims
      Make the final migration auditable and explicitly reversible while trust is still being established.

      [ ] 6.3.2.1 Subtask - Emit rollout evidence showing which surfaces still depend on `Project` or `WorkflowRun` compatibility paths.
      [ ] 6.3.2.2 Subtask - Define removal criteria for legacy resource shims and route aliases.
      [ ] 6.3.2.3 Subtask - Preserve typed rollback procedures if rollout signals show broken operator workflows or unsafe policy drift.

  [ ] 6.4 Section - Phase 6 Integration Tests
    Validate UI migration, hardened authorization, backfilled compatibility, and rollout safety before legacy control-plane assumptions are retired.

    [ ] 6.4.1 Task - Operator-surface migration scenarios
      Verify workbench, repo detail, dashboard, and run detail all operate correctly on the new control-plane model.

      [ ] 6.4.1.1 Subtask - Add coverage for `ManagedRepo`-backed workbench and repo-detail flows.
      [ ] 6.4.1.2 Subtask - Add coverage for governed `Run` and decision-aware dashboard or run-detail flows.
      [ ] 6.4.1.3 Subtask - Verify compatibility routes and deep links still work during the coexistence period.

    [ ] 6.4.2 Task - Rollout-hardening scenarios
      Verify policy, backfill, and rollback behavior are safe enough to retire the transitional architecture.

      [ ] 6.4.2.1 Subtask - Add coverage for actor-aware authorization across the full migrated control-plane flow.
      [ ] 6.4.2.2 Subtask - Add coverage for legacy-data backfill and mixed-mode coexistence.
      [ ] 6.4.2.3 Subtask - Verify rollout evidence and rollback procedures are sufficient before compatibility shims are removed.
