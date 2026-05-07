# Phase 5 - Repo-Native State, Posture, and Trust Progression

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/factory_control_plane.spec.md`
- `../specs/policy_layers.spec.md`
- `../specs/vsm_recursion.spec.md`
- `../README.md`
- `JidoCode.SupportAgentConfigs`
- repo-local `.spec/` state
- optional Beadwork repo state

## Relevant Assumptions / Defaults
- The control-plane work loop exists from earlier phases.
- `.spec/` is already a repo-native source of current truth in this repository and should become an observable control input rather than just contributor documentation.
- Beadwork remains optional and should stay additive rather than mandatory.

[x] 5 Phase 5 - Repo-Native State, Posture, and Trust Progression
  Turn repo-native state into first-class control inputs and introduce posture and trust records so the factory can calibrate supervision, review burden, and autonomy progression over time.

  [x] 5.1 Section - Spec-Led and Git-Native Planning Observation
    Make repo-native state observable by the factory loop instead of leaving it as external human-only context.

    [x] 5.1.1 Task - Observe `.spec/` as a repo-native current-truth signal
      Let spec strength and drift inform planning, review, and execution readiness without collapsing repo-native state into Ash.

      [x] 5.1.1.1 Subtask - Add observation paths that read `.spec/` authored subjects and generated state for managed repos where available.
      [x] 5.1.1.2 Subtask - Surface spec drift, coverage health, or verification confidence as inputs to assessment and posture checks.
      [x] 5.1.1.3 Subtask - Preserve `.spec/` as Git-traveling repo-native state rather than re-storing it as full control-plane truth.

    [x] 5.1.2 Task - Add optional Beadwork observation and alignment behavior
      Treat Git-native planning state as a useful signal without making it mandatory for all repos.

      [x] 5.1.2.1 Subtask - Add optional observation paths for Beadwork work state when a repo adopts it.
      [x] 5.1.2.2 Subtask - Align Beadwork plans and progress with durable `WorkItem` or future `Initiative` records without collapsing them together.
      [x] 5.1.2.3 Subtask - Preserve clear typed behavior for repos that do not use Beadwork at all.

  [x] 5.2 Section - Repo Posture and Posture Check Model
    Add the durable records that summarize trust, readiness, and operational health at the managed-repo level.

    [x] 5.2.1 Task - Add `RepoPosture` as the summary trust and readiness record
      Give the factory one repo-scoped summary object for how safe and autonomous a managed repo currently is.

      [x] 5.2.1.1 Subtask - Add `RepoPosture` with dimensions such as execution readiness, validation reliability, review burden, drift rate, recovery resilience, and requirements confidence.
      [x] 5.2.1.2 Subtask - Tie posture updates back to evidence, assessments, and repo-native state observations.
      [x] 5.2.1.3 Subtask - Preserve explainability so posture changes can always be traced back to contributing checks and evidence.

    [x] 5.2.2 Task - Add `PostureCheck` as the contributing dimension record
      Prevent posture from becoming an opaque score by preserving the contributing signals explicitly.

      [x] 5.2.2.1 Subtask - Add typed `PostureCheck` records for each contributing dimension.
      [x] 5.2.2.2 Subtask - Preserve stable links from `PostureCheck` to `Evidence`, `Observation`, and `Assessment`.
      [x] 5.2.2.3 Subtask - Keep posture computation reviewable rather than implicit in hidden service logic.

  [x] 5.3 Section - Supervision Modes and Trust Progression
    Translate posture into explicit operator-supervision semantics without allowing uncontrolled autonomy jumps.

    [x] 5.3.1 Task - Add explicit supervision-mode semantics
      Make the factory’s trust progression legible and reversible at the repo level.

      [x] 5.3.1.1 Subtask - Introduce `directed`, `guided`, `delegated`, and `autonomous` supervision modes as managed-repo operating posture.
      [x] 5.3.1.2 Subtask - Define which review and approval behaviors change across those modes.
      [x] 5.3.1.3 Subtask - Preserve explicit downgrade and escalation behavior when confidence drops or viability threats appear.

    [x] 5.3.2 Task - Add algedonic escalation paths for viability-threatening conditions
      Keep the VSM framing practical by letting serious repo conditions bypass normal queueing when needed.

      [x] 5.3.2.1 Subtask - Define posture or assessment triggers that escalate directly to higher policy or operator review.
      [x] 5.3.2.2 Subtask - Preserve evidence-rich escalation records that explain why normal flow was bypassed.
      [x] 5.3.2.3 Subtask - Keep escalation bounded and typed rather than enabling arbitrary out-of-band overrides.

  [x] 5.4 Section - Phase 5 Integration Tests
    Validate repo-native observation, posture computation, and trust-progression behavior across repos with and without optional Git-native state layers.

    [x] 5.4.1 Task - Repo-native signal scenarios
      Verify `.spec/` and optional Beadwork state can inform the factory without becoming the factory’s only source of truth.

      [x] 5.4.1.1 Subtask - Add coverage for `.spec/` observation affecting posture or assessment inputs.
      [x] 5.4.1.2 Subtask - Add coverage for optional Beadwork observation and alignment with work records.
      [x] 5.4.1.3 Subtask - Add coverage for repos that omit Beadwork and still behave predictably.

    [x] 5.4.2 Task - Posture and supervision scenarios
      Verify posture, posture checks, supervision modes, and escalation rules remain explainable and reversible.

      [x] 5.4.2.1 Subtask - Add coverage for `RepoPosture` updates from multiple contributing checks.
      [x] 5.4.2.2 Subtask - Add coverage for supervision-mode transitions and downgrade behavior.
      [x] 5.4.2.3 Subtask - Add coverage for viability-threat algedonic escalation paths with explicit evidence linkage.
