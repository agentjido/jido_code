# Phase 3 - Run, Evidence, Decision, and Execution Governance

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/execution_pipeline.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.runic_execution_model.md`
- `JidoCode.Orchestration.WorkflowRun`
- `JidoCode.Forge`
- `Jido.Runic`

## Relevant Assumptions / Defaults
- `WorkItem` is available from Phase 2.
- `WorkflowRun` is the current execution record and should be treated as the migration seam toward the preferred `Run` model.
- Approval and review flows should move toward first-class governance records rather than living only inside run-local maps.

[ ] 3 Phase 3 - Run, Evidence, Decision, and Execution Governance
  Rework execution around the governed run model by evolving workflow runs into control-plane `Run` records and adding evidence, change-request, decision, review, and execution-profile records around explicit `Jido.Runic` execution.

  [ ] 3.1 Section - Run and Execution Profile Migration
    Move from a workflow-run-first lifecycle model to the preferred governed run model without losing current execution capability.

    [ ] 3.1.1 Task - Rebase `WorkflowRun` into the preferred `Run` control-plane record
      Make the run record a governed projection around execution rather than the entire work system by itself.

      [ ] 3.1.1.1 Subtask - Introduce `Run` as the preferred control-plane execution record linked to `WorkItem`.
      [ ] 3.1.1.2 Subtask - Preserve current workflow status, step, retry, and audit metadata through a transitional bridge from `WorkflowRun`.
      [ ] 3.1.1.3 Subtask - Keep `Jido.Runic` as the canonical execution integration layer beneath the new run model.

    [ ] 3.1.2 Task - Add `ExecutionProfile` as the governed execution-environment description
      Separate environment and validation governance from ad hoc per-run settings.

      [ ] 3.1.2.1 Subtask - Define `ExecutionProfile` for sandbox shape, repo prep, validation defaults, and checkpoint or resume expectations.
      [ ] 3.1.2.2 Subtask - Associate work and run creation with an effective execution profile.
      [ ] 3.1.2.3 Subtask - Preserve compatibility with current project-level and workflow-level execution settings during migration.

  [ ] 3.2 Section - Evidence, Change Requests, and Decisions
    Add the governance records that justify execution outcomes and human review behavior.

    [ ] 3.2.1 Task - Add `Evidence` and `ChangeRequest` around run outcomes
      Make run outputs durable and governable instead of leaving key outcome context inside step-local maps.

      [ ] 3.2.1.1 Subtask - Add `Evidence` records for validation outputs, diff summaries, risk notes, and runtime diagnostics.
      [ ] 3.2.1.2 Subtask - Add `ChangeRequest` as the durable reviewable artifact when governance requires explicit human judgment.
      [ ] 3.2.1.3 Subtask - Preserve traceability from `ManagedRepo` to `WorkItem` to `Run` to `Evidence` and `ChangeRequest`.

    [ ] 3.2.2 Task - Add `Decision` as the durable governance outcome
      Move approval and rejection behavior toward a first-class control-plane decision model.

      [ ] 3.2.2.1 Subtask - Add `Decision` records for approve, reject, defer, and similar governed outcomes.
      [ ] 3.2.2.2 Subtask - Preserve actor attribution, rationale, and evidence references on each decision.
      [ ] 3.2.2.3 Subtask - Keep current approval-gate UX working while the durable decision model is introduced underneath.

  [ ] 3.3 Section - Review Policy and Run-Governance Wiring
    Connect repo governance to explicit run review and approval behavior.

    [ ] 3.3.1 Task - Wire `PolicySet` review thresholds into the run lifecycle
      Make review and stop-or-continue logic an explicit repo-governance concern instead of a run-local special case.

      [ ] 3.3.1.1 Subtask - Use `PolicySet` and embedded review-policy fields to determine when runs create `ChangeRequest` and await `Decision`.
      [ ] 3.3.1.2 Subtask - Preserve explicit typed remediation when review context is missing or blocked.
      [ ] 3.3.1.3 Subtask - Keep run lifecycle transitions explainable through evidence and decision records rather than opaque status changes.

    [ ] 3.3.2 Task - Preserve explicit repo-prep and validation steps under the governed run model
      Ensure the run model remains compatible with the explicit execution pipeline already captured in the existing execution ADRs.

      [ ] 3.3.2.1 Subtask - Keep repo attach, repo sync, repo prep, validation, approval, and cleanup as explicit governed execution stages.
      [ ] 3.3.2.2 Subtask - Preserve fan-out and join semantics for lint, tests, and spec checks under `Jido.Runic`.
      [ ] 3.3.2.3 Subtask - Keep generic sandbox bootstrap separate from repo-specific prep and validation.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Validate governed run projection behavior, evidence and decision records, and review-policy-controlled execution flow end to end.

    [ ] 3.4.1 Task - Run-governance scenarios
      Verify work items launch governed runs with explicit evidence and review semantics.

      [ ] 3.4.1.1 Subtask - Add coverage for `WorkItem` to `Run` launch and execution-profile resolution.
      [ ] 3.4.1.2 Subtask - Add coverage for `Evidence` and `ChangeRequest` creation from run outputs.
      [ ] 3.4.1.3 Subtask - Add coverage for `Decision`-driven approval and rejection behavior with actor attribution.

    [ ] 3.4.2 Task - Execution-pipeline compatibility scenarios
      Verify the migration preserves the existing execution ADR’s explicit step and sandbox assumptions.

      [ ] 3.4.2.1 Subtask - Add coverage for explicit repo-prep and validation stages under the new run model.
      [ ] 3.4.2.2 Subtask - Add coverage for blocked review-context and typed remediation paths.
      [ ] 3.4.2.3 Subtask - Verify `Jido.Runic` remains the only execution integration layer used by the governed run surface.
