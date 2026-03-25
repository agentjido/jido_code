<!-- covers: docs.product_foundation.vision_defined -->

# Jido.Code Vision

## Core Idea

`Jido.Code` is a software factory for Git-backed repositories.

Its job is to reduce the need for constant human intervention by operating inside
declared policy, doing work safely, and earning broader autonomy over time.

The goal is not to remove humans from software delivery. The goal is to move humans
up from manual orchestration into supervision, policy, and exception handling.

## What We Are Building

`Jido.Code` wraps a source repository in a managed control system that can:

- understand what should be true
- observe what is true
- detect meaningful gaps between the two
- create and execute work to close those gaps
- surface only the decisions that require human judgment

This is not a chat-first coding assistant and not a passive dashboard.

It is a repository control system.

For the first user, this should feel like:

`My Jido Code Factory`

That means one operator, their repositories, one personal control center, and one
trust relationship that grows over time.

## Trust Model

The product thesis is progressive trust.

Autonomy should be:

- earned through behavior
- bounded by policy
- increased gradually
- reversible when confidence drops

The system should not wait for humans to reach down into it and micromanage every
step. It should know when to ask for help, why it is asking, and what evidence goes
with the request.

Each repository should be able to operate in one of four supervision modes:

- `directed`: humans review nearly every meaningful mutation
- `guided`: the system does more work, but still explains and escalates often
- `delegated`: the system handles routine work inside clear policy bounds
- `autonomous`: humans govern policy and exceptions rather than day-to-day execution

## Product Principles

- Repository first
- Policy before mutation
- Observe before acting
- Escalate by policy
- Evidence before approval
- Safe execution before landing
- Durable state over ephemeral magic

## Human Role

The human defines policy, sets the operating posture, reviews exceptions, and adjusts
autonomy as trust grows.

The human should supervise the factory, not manually drive every software delivery
step forever.

## Initial Scope

The first meaningful version of `Jido.Code` should stay focused:

- GitHub-backed repositories
- feature delivery, maintenance, and conformance work
- safe isolated execution and verification
- policy-aware pull request and approval flows
- strong auditability and rollback context

Depth matters more than breadth in the first version.

## Near-Term Product Priorities

The next planning layer should stay small and reinforce the core thesis.

The highest-priority additions are:

- `RepoPosture` and `PostureCheck` so each repository has a visible operating posture
  that explains trust, autonomy, and what is holding progress back
- `ExecutionProfile` so fresh sandbox setup, repository prep, validation defaults, and
  resume behavior are explicit and repeatable
- `Initiative` so larger outcomes can group multiple work items, runs, approvals, and
  results without turning the product into a generic project manager
- `ReviewPolicy` so approval requests clearly explain why the system could not proceed
  safely on its own
- a simple control stack of `FactoryDefaults -> PolicyPack -> PolicySet ->
  OperatorOverride` so one operator can govern the factory without enterprise sprawl
- a headless control surface so the same factory can be operated through CLI or API
  without bypassing durable state, policy, or evidence

## Long-Term Direction

If `Jido.Code` succeeds, software delivery should feel less like a loose collection of
tools and more like a governed production system that can be trusted with increasing
levels of autonomy.
