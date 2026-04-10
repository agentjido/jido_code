# Jido.Code Memory Ontology Guide

This guide explains the coding-memory ontology used by `jido_code` and how it
fits into the repository's semantic architecture.

The ontology itself lives in [priv/ontologies/jido-memory.ttl](priv/ontologies/jido-memory.ttl).
Its current-truth architectural contract lives in
[.spec/specs/memory_ontology.spec.md](.spec/specs/memory_ontology.spec.md).

## What The Ontology Is For

The memory ontology gives `jido_code` a durable semantic model for knowledge
that accumulates while working on a repository over time.

It is meant to answer questions like:

- What have we learned about this codebase?
- Which module, function, file, or symbol is that knowledge about?
- Which work session, agent run, review, or tool invocation produced it?
- Is that knowledge still fresh for the current revision?
- What evidence supports it, and what later change may have invalidated it?

The ontology complements the repository `source_code` graph rather than
replacing it.

- `source_code` models repository structure and code entities
- `workflow_provenance` models bounded work activity and runtime provenance
- `memory` models durable, adopted knowledge that should survive beyond a
  single run

## Core Concept Groups

### 1. Durable Memory

`jido:Memory` is the base class for durable knowledge recorded about a
repository.

The ontology currently models these main memory kinds:

- `jido:Fact`
  A durable factual statement. Facts require `confidence`.
- `jido:Decision`
  A recorded decision with explicit `rationale`.
- `jido:LessonLearned`
  A lesson from prior work with explicit `context`.
- `jido:Invariant`
  A condition that should continue to hold over time.
- `jido:Convention`
  A repository-specific coding or operational convention.
- `jido:KnownIssue`
  A durable record of a known problem, caveat, or weakness.
- `jido:OpenQuestion`
  An unresolved question worth preserving.
- `jido:Pattern`
  A reusable design or implementation pattern.
- `jido:AntiPattern`
  A recurring pattern that should be avoided.

These are the classes that represent durable memory, not transient agent
output.

## 2. Workflow Provenance

The ontology also models how work happened, not just what was learned.

Important provenance entities are:

- `jido:WorkSession`
  A bounded session of repository work.
- `jido:AgentRun`
  One specialist or agent execution.
- `jido:ToolInvocation`
  A specific tool use during that work.
- `jido:PromptTurn`
  A prompt or instruction turn associated with a session.
- `jido:Plan`
  A plan artifact produced during work.
- `jido:Patch`
  A patch or change artifact produced during work.
- `jido:Review`
  A review activity tied to a session or artifact.

This lets the system preserve provenance such as:

- which session started the work
- which agent produced an artifact
- which tool was invoked
- which review used which patch

## 3. Code Anchors

Memories and workflow nodes are meant to point back to stable code entities in
the `source_code` graph.

The ontology provides these anchor relationships:

- `jido:aboutRepository`
- `jido:aboutFile`
- `jido:aboutModule`
- `jido:aboutFunction`
- `jido:aboutTest`
- `jido:aboutConfig`
- `jido:affectsSymbol`

These links are what make memory useful to a coding system. They let the
repository ask not just "what do we know?" but "what do we know about this
module, function, or symbol?"

## 4. Change And Revision Provenance

The ontology tracks how knowledge relates to code evolution over time.

Main provenance entities:

- `jido:Commit`
- `jido:PullRequest`
- `jido:Issue`
- `jido:TestRun`
- `jido:RepositoryRevision`

Main relationships:

- `jido:introducedInCommit`
- `jido:validatedByTestRun`
- `jido:mentionedInPR`
- `jido:derivedFromIssue`
- `jido:observedAtRevision`
- `jido:invalidatedByRevision`
- `jido:validForRevision`

This is what lets knowledge stay revision-aware instead of becoming timeless
and untrustworthy.

## 5. Decision Structure

Decisions are modeled as more than just notes.

The ontology supports:

- `jido:rationale`
- `jido:decisionStatus`
- `jido:alternativeConsidered`
- `jido:supersedes`
- `jido:hasConsequence`

Decision status is modeled explicitly with values such as:

- `jido:proposed`
- `jido:accepted`
- `jido:superseded`
- `jido:rejected`

This makes it possible to track decision lineage over time instead of losing
older context whenever a decision changes.

## 6. Freshness, Validation, And Evidence

The ontology explicitly models whether a memory is still trustworthy.

Key properties include:

- `jido:freshnessScore`
- `jido:staleReason`
- `jido:lastValidatedAt`
- `jido:validForRevision`
- `jido:supportedBy`
- `jido:confidenceSource`
- `jido:evidenceArtifact`

The ontology also includes `jido:EvidenceArtifact` as a first-class entity for
supporting evidence.

This part of the model is what helps the system avoid treating old knowledge as
if it were still automatically valid.

## 7. Runtime And Session Context

The ontology captures the runtime context in which work happened.

Important supporting entities:

- `jido:Actor`
- `jido:Model`
- `jido:Toolchain`

`jido:WorkSession` also carries session-scoped context such as:

- `jido:sessionId`
- `jido:sessionGoal`
- `jido:sessionOutcome`
- `jido:branchName`
- `prov:startedAtTime`
- `jido:performedByActor`
- `jido:usedModel`
- `jido:usedToolchain`

This is what keeps memories attributable to a repo revision, actor, model, and
tooling context instead of turning them into anonymous notes.

## 8. Tags And Typing Hygiene

The ontology prefers semantic typing over string fields.

Instead of older stringly patterns like:

- one `memoryType` field
- comma-delimited tag blobs

the model uses:

- `rdf:type` for class membership
- `jido:hasTag` for first-class tags
- `jido:Tag` as a tag entity class

The legacy fields `jido:memoryType` and `jido:tags` still exist only as
deprecated compatibility concepts inside the ontology.

## How To Think About The Model

A useful mental model is:

- `source_code` tells us what exists in the codebase
- `workflow_provenance` tells us what happened while working on it
- `memory` tells us what should still be remembered later

That division matters.

Not every prompt turn or artifact becomes durable memory.
Not every memory is detached from the code that motivated it.
Not every memory remains valid forever.

The ontology is designed to preserve all three distinctions:

- knowledge versus activity
- durable memory versus transient workflow output
- current knowledge versus stale or superseded knowledge

## Where Individuals Enter The Graph

The ontology only becomes useful if the repository writes individuals into it in
bounded, explainable places.

The current write seam is:

- `workflow_provenance` receives `WorkSession`, `PromptTurn`, `AgentRun`,
  `ToolInvocation`, `Plan`, `Patch`, and `Review` individuals from
  `AgentWorkspace` and product workflow boundaries
- `memory` receives durable `Fact`, `Decision`, `LessonLearned`, `Invariant`,
  `Convention`, `KnownIssue`, `OpenQuestion`, `Pattern`, and `AntiPattern`
  individuals only after explicit classification or governed adoption
- freshness, validation, invalidation, and supersession updates are written as
  bounded memory-update events tied to revision and evidence metadata

That means the repository treats semantic memory as curated product knowledge,
not as a raw dump of everything an agent happened to say during one run.
Raw runtime or model output is not durable memory until a bounded product path
explicitly adopts it.

## Why This Helps A Coding System

In practical terms, this ontology helps a coding LLM or agent system:

- retrieve knowledge by code entity instead of by fuzzy text search alone
- preserve decisions, issues, and conventions across many sessions
- understand where a memory came from
- reason about freshness and invalidation
- connect work sessions, tool use, reviews, patches, and plans to later memory
- avoid treating transient model output as durable knowledge unless it is
  explicitly adopted

That makes the repository's semantic memory more durable, more explainable, and
more useful over long-running development work.
