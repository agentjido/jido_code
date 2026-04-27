---
id: jido_code.settings_github_add_repository_uses_managed_repo_import
status: accepted
date: 2026-04-26
affects:
  - package.jido_code
  - architecture.factory_control_plane
  - architecture.frontend_stack
  - architecture.policy_layers
  - auth.operator_settings
---

<!-- covers: architecture.factory_control_plane.settings_github_add_uses_canonical_repo_import -->
<!-- covers: architecture.frontend_stack.settings_routes_keep_repo_import_liveview_owned -->
<!-- covers: architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations -->
<!-- covers: package.jido_code.spec_led_workspace -->

# Settings GitHub Add Repository Uses Managed Repo Import

## Context

`/setup` already imports GitHub repositories through the canonical managed-repo
boundary. That path provisions or reuses `SourceRepo` plus `ManagedRepo`
control-plane records, persists repo-scoped workspace metadata, and makes the
repository visible to the rest of the product.

The later `/settings/github` add-repository modal did not do that. It only
created a `JidoCode.GitHub.Repo` row for the settings surface itself. That made
the route look successful while workbench, repo inventory, repo detail, and
other managed-repository surfaces still had no canonical repository to work
with.

At the same time, the settings route already has a good UI boundary:

- the routed page shell is LiveView-owned
- the overview widget is a bounded richer summary region
- the add-repository modal is server-rendered and actor-bound

The needed change is a truth-boundary correction, not a new client shell.

## Decision

The signed-in `/settings/github` add-repository flow shall use the canonical
managed-repository import boundary instead of treating a settings-only GitHub
row as product truth.

Specifically:

1. The add-repository modal remains LiveView-owned.
2. Submitting owner/name routes through the managed import boundary used for
   later GitHub additions.
3. That import must create or reuse canonical `SourceRepo` and `ManagedRepo`
   records before the settings route reports success.
4. A `JidoCode.GitHub.Repo` row may still exist as a settings-facing anchor for
   route-local configuration, but it is secondary and must not be treated as
   the canonical repository object.
5. The settings route continues to propagate the current authenticated actor
   through its explicit mutation paths rather than bypassing policy through a
   trusted client shortcut.

## Consequences

### Positive

- Repositories added after onboarding become visible to the same control-plane
  surfaces as repositories imported during onboarding.
- The settings route no longer creates a misleading success case where only the
  local settings list sees the repository.
- The LiveView-plus-bounded-Vue composition on `/settings` stays intact.

### Constraints

- The settings route must surface managed-import failures as product-oriented
  modal feedback instead of silently falling back to a settings-only row.
- The `JidoCode.GitHub.Repo` table is no longer sufficient proof that a
  repository is part of the managed control plane.
- Later settings-only GitHub metadata still needs to coexist with the canonical
  managed-repository graph instead of replacing it.

## Implementation Status

This decision is now landed in product code.

Current implementation behaves as follows:

- `/settings/github` keeps its add-repository interaction in a LiveView-owned
  modal.
- successful submission now routes through the canonical managed import
  boundary and requires a ready import report before closing the modal.
- the settings route still ensures a GitHub-repo anchor row exists for its own
  list and per-route metadata, but that anchor is created only after canonical
  managed-repository import succeeds.
- blocked import reports now remain visible inside the modal as operator-facing
  remediation instead of producing a misleading success.
- focused LiveView coverage now proves that adding a repository from settings
  creates canonical managed-repository scope and that blocked managed-import
  results keep the modal open with remediation.
