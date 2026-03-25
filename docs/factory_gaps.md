<!-- covers: docs.product_foundation.factory_gap_note_present -->

# Factory Gaps

This note compares the current `Jido.Code` plan to the publicly visible `Factory.ai`
product and docs reviewed on 2026-03-23.

The goal is not to copy `Factory.ai` feature-for-feature.

The goal is to identify where `Factory.ai` is ahead as a product and then define how
`Jido.Code` should close those gaps in a Jido-centric, Elixir-native way.

This note assumes a focused first user:

- one operator
- their repositories
- one personal control center
- one evolving trust relationship with the factory

The target is not "enterprise fleet management."

The target is:

`My Jido Code Factory`

The canonical plan now lives in:

- `docs/VISION.md`
- `docs/TECHNICAL_IMPLEMENTATION.md`
- `docs/DATA_ONTOLOGY.md`

This note should be treated as supporting context and differentiation guidance, not as
the primary product plan.

## Core View

`Factory.ai` appears to optimize for broad agent presence across the development stack:
backlog, IDE, browser, CLI, Slack, analytics, and enterprise rollout.

`Jido.Code` should stay centered on a different thesis:

- a repository is a governed control system
- autonomy is earned through evidence and policy
- orchestration is durable, stateful, and supervised
- execution is explicit, inspectable, and recoverable

That means our question is not "how do we become Factory?"

It is:

"Which product capabilities matter, and how do we implement them in a way that is only
really possible because we are building on Elixir, OTP, Ash, `Jido.Runic`, and sprites?"

## Where Factory Is Ahead

### 1. Repo Posture As A Product Surface

`Factory.ai` has a more productized readiness story:

- maturity levels
- scored criteria
- stored reports
- dashboard views
- API access
- remediation direction

`Jido.Code` has the ingredients for this in `PolicySet`, `Observation`, `Assessment`,
and `ManagedRepo`, but not yet the explicit product object.

Recommendation:

- add `RepoPosture` and `PostureCheck`
- tie posture directly to `autonomy_mode`
- make posture historical and comparable across repositories
- let posture drive suggested remediation work

In `My Jido Code Factory`, this should answer:

- is this repo trustworthy enough for more autonomy
- what is holding it back
- what should I fix next

Proposed shape:

- `RepoPosture`
  current posture for one managed repo
- `PostureCheck`
  one contributing check, gate, or trust dimension

Suggested posture dimensions:

- policy conformance
- execution readiness
- validation reliability
- review burden
- repo drift
- recovery resilience
- spec coverage or requirements confidence

### 2. Multi-Step Initiative Management

`Factory.ai` appears to package larger efforts above the level of one task.

`Jido.Code` currently has a strong `WorkItem -> Run -> ChangeRequest` loop, but it needs
a higher-order unit for feature delivery and coordinated maintenance.

Recommendation:

- add a higher-order unit above `WorkItem`
- model it as a Jido-centric repository program, not as a generic project tracker
- use it to group multiple work items, runs, approvals, and outcomes

- `Initiative`

For the single-user case, `Initiative` should mean:

- one meaningful outcome for one repo
- composed of several `WorkItem`s
- possibly spanning planning, implementation, review, and cleanup
- always grounded in the repo's existing policy and posture

### 3. Review As A Stronger Decision Surface

`Factory.ai` seems further along in turning review into a product surface with richer
review guidelines and decision support.

`Jido.Code` has the right nouns already:

- `ChangeRequest`
- `Decision`
- `Evidence`
- `PolicySet`

But the model should go further.

Recommendation:

- embed review policy inside `PolicySet`
- support path-scoped and repo-scoped review rules
- make review packets first-class evidence bundles
- distinguish code-change review, policy override review, and operational approval

For the single-user case, the most important simplification is:

- do not build a generic review platform
- build one strong decision surface for "why is Jido asking me now?"

That means every review packet should show:

- what changed
- why Jido could not safely proceed alone
- which policy or posture checks were involved
- what evidence was gathered
- what will happen after approval

### 4. Headless And Automated Entry Points

`Factory.ai` is ahead in non-UI automation surfaces.

`Jido.Code` needs a clean way to trigger and control the factory without requiring the
web UI.

Recommendation:

- add a headless interface for assessment, remediation, approval, and run kickoff
- support CLI and API entry points into the same control-plane records
- ensure headless execution still produces the same durable `WorkItem`, `Run`, and
  `Evidence` trail as the UI

For `My Jido Code Factory`, this should probably start as:

- `jidocode posture`
- `jidocode assess`
- `jidocode run`
- `jidocode approve`
- `jidocode remediate`

The key is that the CLI should feel like operating your own factory, not like invoking a
detached assistant.

### 5. Productized Workspace And Sandbox Experience

`Factory.ai` seems to present remote workspaces as a clear product primitive.

`Jido.Code` already has stronger raw building blocks through sprites and the Forge
subsystem, but they are not yet framed as a repo-centric execution product.

Recommendation:

- make sandbox lifecycle a first-class operator concept
- define reusable execution profiles per repo or policy pack
- expose bootstrap, checkpoint, resume, cache, and validation behavior explicitly
- treat fresh sandbox setup and repo prep as separate concerns

For `Jido.Code`, I would rename this concept to `ExecutionProfile`.

An `ExecutionProfile` should describe:

- what kind of sprite to start
- how to bootstrap it
- how to attach the repo
- how to prepare the repo in a fresh environment
- which validation steps run by default
- what can be checkpointed or resumed

### 6. Policy Hooks And Control Layers

`Factory.ai` has strong signs of productized hooks, governance, and enterprise posture.

`Jido.Code` should not just match this. It should be more explicit and more durable.

Recommendation:

- add deterministic policy hook points
- support instance defaults, policy packs, repo policy, and operator overrides
- make escalations, pauses, approvals, and exception paths part of the core model

For the single-user case, the control stack should stay simple:

- `FactoryDefaults`
- `PolicyPack`
- `PolicySet`
- `OperatorOverride`

That is enough for a personal factory without importing enterprise complexity too early.

### 7. Analytics And Trust Progression

`Factory.ai` is clearly thinking about analytics and ROI.

For `Jido.Code`, the more important question is trust progression:

- when can the system be trusted more
- what evidence justified that change
- how much human review load is being removed safely

Recommendation:

- measure posture trend
- measure validation pass rate
- measure approval load by repo and policy type
- measure drift frequency and remediation latency
- measure autonomy progression and regressions over time

## Where Jido Should Go Further

This is where a Jido-centric system should surpass `Factory.ai`.

### 1. Durable Repo Orchestrators

Each `ManagedRepo` should have a durable orchestrator with long-lived policy, memory,
queue state, and supervisory context.

This is stronger than a stateless agent entrypoint.

Elixir advantage:

- OTP supervision
- process isolation
- explicit backpressure
- restart semantics
- mailbox-driven orchestration

### 2. Recursive Governance

We already decided that the factory and each `ManagedRepo` should be modeled as recursive
viable systems.

This gives `Jido.Code` a more coherent control story than a loose "agent platform."

Elixir advantage:

- viable subsystems map naturally to supervised process structure
- signals, escalations, and health are explicit rather than implied

### 3. `Jido.Runic` As The Execution Center

This is a major differentiator.

`Jido.Code` should not merely run commands in sandboxes.

It should run explicit, inspectable, resumable `Jido.Runic` workflows whose step
progression is visible and governable.

Elixir advantage:

- workflow state is local, inspectable, serializable, and recoverable
- step mode and auto mode map naturally to trust levels
- lint, tests, and spec checks can fan out and rejoin as real workflow nodes

### 4. Ash-Native Policy And Auditability

`Factory.ai` may have governance features, but `Jido.Code` can make policy and evidence
more first-class because Ash is already our control-plane substrate.

Elixir advantage:

- rich resource modeling
- explicit relationships
- policy as data
- durable evidence and approval history
- one control model shared by UI, runtime, and automation

### 5. Real-Time Operational Control

`Jido.Code` should use LiveView to make the software factory feel like a control center,
not a report viewer.

Elixir advantage:

- real-time operational state
- low-latency updates
- no split between "monitoring view" and "app state"

## Recommendations To Close The Gaps

This is the streamlined single-user roadmap.

### Priority 1

- Add `RepoPosture` and `PostureCheck` as first-class resources.
- Tie posture directly to supervision mode and autonomy progression.
- Make `Jido.Runic` the explicit execution center in product language, runtime modeling, and review flows.
- Add `ExecutionProfile` for sprite-backed fresh runs, resume, validation, and cache behavior.

Concrete v1 additions:

- `RepoPosture`
- `PostureCheck`
- `ExecutionProfile`

### Priority 2

- Add `Initiative` above `WorkItem`.
- Add review policy to `PolicySet`, including path-scoped guidance and evidence requirements.
- Add headless entry points for assessment, run kickoff, remediation, and approval flows.
- Add simple control layering through factory defaults, policy packs, repo policy, and operator overrides.

Concrete v1 additions:

- `Initiative`
- `ReviewPolicy`
- `FactoryDefaults`
- `OperatorOverride`

### Priority 3

- Add analytics focused on trust progression rather than generic activity metrics.
- Add remediation workflows from posture or assessment failures.
- Add operator-facing queue views across repositories with backpressure and policy context.

Concrete v1 additions:

- posture trend views
- approval load views
- drift and remediation latency views
- autonomy progression timeline

## What Not To Copy

These are likely traps for `Jido.Code`.

- Do not optimize first for "agents everywhere" across every interface.
- Do not turn model routing into the center of the product.
- Do not become a generic productivity layer with weak repo governance.
- Do not hide execution behind vague agent language when `Jido.Runic` can make it explicit.

## Jido-Centric Direction

The strongest version of `Jido.Code` is not a broader `Factory.ai`.

It is a deeper software factory:

- more governed
- more durable
- more inspectable
- more policy-native
- more autonomy-aware
- more operationally coherent

If `Factory.ai` shows what a broad agent-native product looks like, `Jido.Code` should
show what a BEAM-native, policy-first, repository control system looks like.

And in the first version, that system should feel personal:

- my repos
- my policies
- my execution environments
- my approvals
- my trust ladder
- my factory
