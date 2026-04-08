---
id: jido_code.factory_control_plane_and_runtime_overlay
status: accepted
date: 2026-03-29
affects:
  - package.jido_code
  - architecture.factory_control_plane
  - architecture.demand_ingress
  - architecture.event_assessment_synthesis
  - architecture.work_synthesis
  - architecture.policy_layers
  - docs.product_foundation
---

<!-- covers: architecture.factory_control_plane.product_is_governed_software_factory -->
<!-- covers: architecture.factory_control_plane.source_repo_and_managed_repo_are_primary_repo_objects -->
<!-- covers: architecture.factory_control_plane.durable_control_loop_normalizes_demand_into_work -->
<!-- covers: architecture.factory_control_plane.repo_native_state_layers_inform_control_plane -->
<!-- covers: architecture.factory_control_plane.lightweight_hosted_multi_user_posture -->
<!-- covers: architecture.demand_ingress.external_object_tracks_repo_external_entities -->
<!-- covers: architecture.demand_ingress.observation_captures_repo_and_system_facts -->
<!-- covers: architecture.demand_ingress.intake_captures_operator_and_trusted_requests -->
<!-- covers: architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation -->
<!-- covers: architecture.event_assessment_synthesis.event_records_derived_from_ingress -->
<!-- covers: architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved -->
<!-- covers: architecture.event_assessment_synthesis.assessment_records_interpret_events -->
<!-- covers: architecture.event_assessment_synthesis.assessment_priority_and_next_action -->
<!-- covers: architecture.event_assessment_synthesis.assessment_space_for_future_inputs -->
<!-- covers: architecture.work_synthesis.work_item_is_canonical_operational_record -->
<!-- covers: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved -->
<!-- covers: architecture.work_synthesis.work_item_creation_can_stop_before_execution -->
<!-- covers: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression -->
<!-- covers: architecture.work_synthesis.work_item_auditability_preserved -->
<!-- covers: architecture.policy_layers.repository_governance_policy_is_repo_control_layer -->
<!-- covers: architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane -->
<!-- covers: architecture.policy_layers.runtime_policy_governs_runtime_capability -->
<!-- covers: architecture.policy_layers.policy_layers_interlock_without_collapsing -->
<!-- covers: architecture.policy_layers.explicit_human_and_machine_actor_classes -->
<!-- covers: docs.product_foundation.durable_architecture_record_in_spec_workspace -->

# Factory Control Plane

## Context

`jido_code` already contains several strong architectural strands, but they are not
yet fully organized around one product center.

The current implementation has:

- a Phoenix and Ash product shell with local and provider-backed authentication
- imported Git-backed repositories represented today by `Project`
- workflow-run execution records represented today by `WorkflowRun`
- architecture ADRs that center execution on `Jido.Runic` and model the
  factory plus each managed repository as recursive viable systems

At the same time, the product still risks being interpreted as a chat-first coding
assistant or as a collection of loosely related repository features. The desired
direction is stronger: `Jido.Code` is a governed software factory for Git-backed
repositories. Conversations, coding assistance, repo-native spec state, and workflow
execution are all important, but they should orbit one durable control plane rather
than becoming parallel centers of truth.

## Decision

`Jido.Code` shall be treated as a governed software-factory control plane for
Git-backed repositories rather than as a chat-first assistant or a passive project
dashboard.

The primary repository objects are:

- `SourceRepo`: the external Git repository identity
- `ManagedRepo`: the durable managed wrapper around that repository inside the
  product control plane

The current `Project` resource is therefore transitional implementation vocabulary,
not the preferred long-term control-plane object model.

The durable factory loop shall normalize demand into governed work. At a high level,
that loop is:

1. synchronize the `SourceRepo`
2. load the active `PolicySet`
3. observe repo-native state such as `.spec/` and optional Git-native planning state
4. capture inbound `Intake` and fresh `Observation`
5. upsert relevant `ExternalObject` records
6. normalize actionable `Event`
7. derive `Assessment`
8. create or reprioritize `WorkItem`
9. execute a `Run`
10. produce `Evidence` and `ChangeRequest` when needed
11. persist `Decision` when governance requires it
12. update posture and trust-related operating confidence

Verified external demand and signed-in operator demand must enter that loop through
durable ingress records first. GitHub webhook deliveries and other trusted external
signals should normalize into `ExternalObject` and `Observation`, while setup and
workbench-originated operator requests should normalize into `Intake`, preserving
actor attribution, source metadata, and managed-repository correlation before `Event`
or `Assessment` synthesis begins.

Operator-originated repository demand follows the same rule. It is not a second
control-plane lane; it is normalized product demand with actor, request,
correlation, and managed-repository context preserved through durable `Intake`,
`Event`, `Assessment`, and `WorkItem` records. When incoming demand explicitly
targets an existing work item, the control plane should steer that record rather
than force a duplicate work object.

That decision still happens in layers. Product-side policy decides whether the
demand should create new work, steer an existing work item, or halt before
execution begins. Ash remains the authorization membrane around the durable
records that capture that choice.

After ingress capture, interpretation becomes a system-owned control-plane step.
`Event` and `Assessment` records should be synthesized under product authority,
not written directly by external ingress actors, so typed actionable meaning,
priority, urgency, and recommended next action remain part of the governed
factory loop instead of becoming ad hoc feature-local side effects.

Repo-native state should influence that interpretation through compact signal
snapshots rather than through direct duplication of repo files into product
records. `.spec/` verification health and optional Git-native planning layers
such as Beadwork may be observed into durable `Observation` records and then
fed into later assessment, posture, planning, and review decisions while the
repo-native files themselves remain the Git-traveling source of truth.

Once actionable meaning exists, the next durable step is `WorkItem`, not
immediate execution. Equivalent work demand should reconcile through governed
work synthesis that can create a new work record, reprioritize an existing one,
or suppress a duplicate while retaining an audit trail of why the work state
changed.

Repo-native state layers are first-class inputs to the factory, but not replacements
for the product control plane. Authored `.spec/` state and optional Git-native
planning layers such as Beadwork should inform posture, review, planning, and work
selection while Ash remains the durable control-plane store for the factory's own
records.

The policy model remains explicitly layered:

- repository governance policy in `PolicySet` and adjacent review or posture rules
- Ash policies as the product's data-plane authority membrane

Hosted multi-user support remains intentionally lightweight. The product is
single-user-first, but cloud-hosted deployments should support admins and standard
operators supervising the same factory without introducing a heavy enterprise
permission lattice in the first version.

## Consequences

- `ManagedRepo`, governed `Run`, and adjacent governance records remain the
  canonical product truth, which keeps older `Project`- and `WorkflowRun`-era
  seams internal and removable.
- Policy stays layered: repo governance, Ash authorization, and bounded runtime
  capability policy must cooperate without collapsing into one anonymous approval
  mechanism.
- Runtime-oriented evidence can influence posture and review, but product-facing
  operator narratives still come from durable control-plane records instead of
  runtime-native transport state.

## Deprecation Note

As of 2026-04-06, this control plane no longer integrates with `jido_os` runtime.
See `jido_code.jido_os_deprecation` for details.
