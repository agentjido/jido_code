# Phase 2 - Demand Ingress, Observation, and Work Synthesis

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `JidoCode.GitHub.WebhookPipeline`
- `JidoCode.Setup`
- `JidoCode.Workbench`
- `JidoCode.Projects`

## Relevant Assumptions / Defaults
- `ManagedRepo` and `PolicySet` exist from Phase 1.
- Existing inbound demand surfaces such as GitHub webhooks, setup flows, and operator-triggered actions should be normalized rather than rewritten feature-by-feature.
- `WorkItem` should not yet assume full run or approval governance until the execution phase lands.

[x] 2 Phase 2 - Demand Ingress, Observation, and Work Synthesis
  Normalize repository and operator demand into durable intake, observation, event, assessment, and work-item records so the product stops treating those inputs as disconnected feature-specific flows.

  [x] 2.1 Section - Inbound Demand Capture and External Object Mapping
    Capture external and operator-originated demand in canonical control-plane records before downstream planning or execution begins.

    [x] 2.1.1 Task - Add `Observation`, `Intake`, and `ExternalObject` baseline records
      Create stable product records for what is seen, what is requested, and what external entities the factory is tracking.

      [x] 2.1.1.1 Subtask - Add `Observation` for repo-derived or system-derived facts.
      [x] 2.1.1.2 Subtask - Add `Intake` for operator-originated or trusted-ingress requests that should enter the factory loop.
      [x] 2.1.1.3 Subtask - Add `ExternalObject` for tracked GitHub issues, pull requests, and future external references.

    [x] 2.1.2 Task - Normalize existing inbound feature paths into the new demand records
      Make current webhook, setup, and operator-triggered flows produce control-plane demand instead of jumping straight to ad hoc action logic.

      [x] 2.1.2.1 Subtask - Route GitHub webhook and issue-oriented demand through `ExternalObject`, `Observation`, and `Event` creation seams.
      [x] 2.1.2.2 Subtask - Route operator-triggered setup or workbench actions through `Intake` rather than direct one-off execution triggers.
      [x] 2.1.2.3 Subtask - Preserve source metadata, actor attribution, and correlation continuity across those normalized ingress paths.

  [x] 2.2 Section - Event and Assessment Synthesis
    Turn captured demand into durable control-plane meaning before work is scheduled.

    [x] 2.2.1 Task - Add `Event` as the durable actionable record of what happened or was requested
      Replace feature-local interpretation with a common record of actionable occurrences.

      [x] 2.2.1.1 Subtask - Add `Event` records derived from observation, intake, and external-object changes.
      [x] 2.2.1.2 Subtask - Preserve typed event categories and repo correlation for later work synthesis.
      [x] 2.2.1.3 Subtask - Keep runtime signals and UI events distinct from durable control-plane `Event` records.

    [x] 2.2.2 Task - Add `Assessment` as the durable interpretation layer above events
      Give the factory a place to record what an event means before work is created.

      [x] 2.2.2.1 Subtask - Add `Assessment` records tied to events and managed repos.
      [x] 2.2.2.2 Subtask - Capture priority, urgency, and recommended next action at the assessment layer.
      [x] 2.2.2.3 Subtask - Preserve space for future posture, policy, and repo-native state inputs to shape assessment outcomes.

  [x] 2.3 Section - Work Synthesis Baseline
    Introduce the durable operational work object that sits between interpreted demand and execution.

    [x] 2.3.1 Task - Add `WorkItem` as the canonical operational record
      Make work creation and reprioritization explicit instead of hiding it inside direct workflow or bot-specific launch paths.

      [x] 2.3.1.1 Subtask - Add `WorkItem` with links back to `ManagedRepo`, `Assessment`, and initiating demand records.
      [x] 2.3.1.2 Subtask - Preserve category, priority, status, and initiating-actor metadata on each work item.
      [x] 2.3.1.3 Subtask - Keep direct execution launch optional so Phase 2 can stop at durable work creation when needed.

    [x] 2.3.2 Task - Add reprioritization and deduplication rules for synthesized work
      Keep the work queue durable and governed rather than allowing demand bursts to create chaotic duplicates.

      [x] 2.3.2.1 Subtask - Deduplicate equivalent work candidates arising from the same repo and external-object context.
      [x] 2.3.2.2 Subtask - Allow fresh assessment data to reprioritize existing work instead of always creating new work items.
      [x] 2.3.2.3 Subtask - Preserve auditability for why work was created, updated, merged, or suppressed.

  [x] 2.4 Section - Phase 2 Integration Tests
    Validate demand normalization, durable event and assessment synthesis, and stable work-item creation across existing ingress paths.

    [x] 2.4.1 Task - Demand normalization scenarios
      Verify existing inbound surfaces create durable control-plane records before execution decisions are made.

      [x] 2.4.1.1 Subtask - Add coverage for GitHub webhook demand flowing into `ExternalObject`, `Observation`, `Event`, and `Assessment`.
      [x] 2.4.1.2 Subtask - Add coverage for operator-originated demand flowing into `Intake` and downstream work synthesis.
      [x] 2.4.1.3 Subtask - Add coverage for attribution and correlation continuity across normalized ingress paths.

    [x] 2.4.2 Task - Work synthesis scenarios
      Verify work creation is durable, deduplicated, and tied back to interpreted repo demand.

      [x] 2.4.2.1 Subtask - Add coverage for `WorkItem` creation from `Assessment`.
      [x] 2.4.2.2 Subtask - Add coverage for reprioritization and duplicate suppression.
      [x] 2.4.2.3 Subtask - Verify the system can stop at durable work creation without requiring immediate execution launch.
