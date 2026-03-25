---
id: jido_code.namespace_and_control_naming
status: accepted
date: 2026-03-23
affects:
  - package.jido_code
  - docs.product_foundation
---

# Canonical Namespace And Control-Plane Naming

## Context

`Jido.Code` is converging on a clearer product and architecture vocabulary. The current
`jido_code` codebase still uses `JidoCode.*` module names in many places, while the new product
documents are establishing the intended long-term control-plane model.

At the same time, some early ontology names are more clever than helpful. `RepoCell`
captures the control-cell idea, but it is not the clearest v1 data name. `Signal` is
also likely to be confused with `Jido.Signal` and other runtime signal concepts.

## Decision

The canonical namespace for the product and its future architecture docs is `Jido.Code`.

Current implementation modules may continue to use `JidoCode.*` until they are
intentionally migrated, but new conceptual layouts, domain examples, and naming guidance
should prefer `Jido.Code.*`.

For the first control-plane ontology:

- `SourceRepo` remains the external repository identity
- `ManagedRepo` replaces `RepoCell` as the internal managed wrapper around a source repository
- `PolicySet` remains the desired-state object
- `Event` replaces `Signal` as the durable control-plane record of something that happened or was asked
- `Observation`, `Assessment`, `WorkItem`, `Run`, `ChangeRequest`, `Decision`, and `Evidence` remain the preferred names

## Consequences

- Product and architecture docs should use `Jido.Code` as the canonical namespace.
- Ash domain examples should prefer `Jido.Code.Repos`, `Jido.Code.Governance`, `Jido.Code.Control`, and `Jido.Code.Operations`.
- Mapping sections may still reference existing `JidoCode.*` modules when describing the current implementation.
- Future renames from `JidoCode.*` to `Jido.Code.*` should be treated as intentional implementation work rather than implied by documentation alone.
- The data ontology becomes more legible to operators and contributors by using `ManagedRepo` and `Event` instead of `RepoCell` and `Signal`.
