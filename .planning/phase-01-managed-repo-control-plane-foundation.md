# Phase 1 - Managed Repo Control-Plane Foundation

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/policy_layers.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `JidoCode.Projects.Project`
- `JidoCode.Workbench.ProjectDetail`
- `JidoCode.Setup.ProjectImport`

## Relevant Assumptions / Defaults
- The current `Project` resource remains live during this phase.
- `ManagedRepo` becomes the preferred control-plane object, but compatibility with existing project IDs and workbench routes must be preserved initially.
- Governance records should start narrow and additive rather than forcing an all-at-once domain rewrite.

[x] 1 Phase 1 - Managed Repo Control-Plane Foundation
  Establish the control-plane foundation for the software-factory direction by introducing the transitional managed-repo model, control-plane domain layout, and minimal governance scaffolding without breaking current project import and project-detail flows.

  [x] 1.1 Section - Repo Ontology and Transitional Resource Bridge
    Introduce the preferred repository control-plane model while preserving compatibility with the current `Project`-centric implementation.

    [x] 1.1.1 Task - Introduce `SourceRepo` and `ManagedRepo` as additive control-plane resources
      Add the preferred repo ontology beside the current `Project` shape so the architecture has a durable target model before deeper migration begins.

      [x] 1.1.1.1 Subtask - Add Ash resources and domains for `SourceRepo` and `ManagedRepo` with stable identifiers and repo ownership relationships.
      [x] 1.1.1.2 Subtask - Map current `Project` identity, GitHub full-name, and default-branch data into transitional `ManagedRepo` compatibility reads or backfills.
      [x] 1.1.1.3 Subtask - Preserve existing project import and project detail entrypoints while the preferred ontology shifts underneath them.

    [x] 1.1.2 Task - Establish control-plane-friendly repo configuration boundaries
      Move repo-scoped configuration away from an undifferentiated `settings` bag and toward governed control-plane ownership.

      [x] 1.1.2.1 Subtask - Separate repo identity from governance, execution, and integration settings in the new resource model.
      [x] 1.1.2.2 Subtask - Preserve current setup and import defaults while creating clear extension points for future policy and posture records.
      [x] 1.1.2.3 Subtask - Prepare foreign-key relationships from later work, run, evidence, and decision records back to `ManagedRepo`.

  [x] 1.2 Section - Governance Domain Baseline and Actor Model
    Add the first durable governance surfaces so later work-loop and approval behavior have a real home in the control plane.

    [x] 1.2.1 Task - Add `PolicySet` and embedded review-governance baseline
      Introduce the repo-governance object that will eventually own repo behavior, approval thresholds, and autonomy limits.

      [x] 1.2.1.1 Subtask - Add a minimal `PolicySet` resource associated with `ManagedRepo`.
      [x] 1.2.1.2 Subtask - Embed the initial `ReviewPolicy` shape inside `PolicySet` rather than scattering approval semantics across feature-specific settings.
      [x] 1.2.1.3 Subtask - Preserve compatibility with existing approval-oriented settings while establishing `PolicySet` as the preferred authority.

    [x] 1.2.2 Task - Establish explicit data-plane actor classes for factory resources
      Replace permissive placeholder policy posture with a credible actor model that can grow with the control plane.

      [x] 1.2.2.1 Subtask - Define explicit actor classes for `admin`, `operator`, `factory_system`, `managed_repo_orchestrator`, `run_worker`, and `external_ingress`.
      [x] 1.2.2.2 Subtask - Apply initial Ash policy scaffolding to new control-plane resources using those actor classes.
      [x] 1.2.2.3 Subtask - Preserve current auth and hosted-user flows while narrowing future control-plane mutation paths.

  [x] 1.3 Section - Phase 1 Integration Tests
    Validate the new managed-repo bridge, governance baseline, and actor model without regressing current project import and detail behavior.

    [x] 1.3.1 Task - Managed-repo bridge scenarios
      Verify existing project-oriented flows remain usable while the preferred repo ontology is introduced.

      [x] 1.3.1.1 Subtask - Add coverage for project import and lookup paths that now back or mirror `ManagedRepo`.
      [x] 1.3.1.2 Subtask - Add coverage for project detail compatibility during mixed `Project` and `ManagedRepo` operation.
      [x] 1.3.1.3 Subtask - Add coverage for identity and default-branch continuity across transitional reads and writes.

    [x] 1.3.2 Task - Governance baseline scenarios
      Verify the first governance surfaces and actor classes are present, bounded, and compatible with existing setup flows.

      [x] 1.3.2.1 Subtask - Add coverage for `PolicySet` creation and repo association.
      [x] 1.3.2.2 Subtask - Add coverage for actor-aware authorization on new control-plane resources.
      [x] 1.3.2.3 Subtask - Verify setup and import workflows still complete under the transitional governance model.
