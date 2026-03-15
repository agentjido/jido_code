# JidoCode Vision

## Project Brief
JidoCode is an open-source, self-hosted coding companion for OSS maintainers and software developers.
Its positioning is companion-driven operations, not human-driven orchestration.

Setup defines intent; operations realize intent.

Product contract:
The maintainer defines intent, policy, and trust posture once. Jido continuously operates within that definition by observing project signals, proposing and executing eligible actions, and producing reviewable pull requests with full provenance.

Primary audience:
- OSS maintainers managing ongoing issue and PR flow
- solo developers and small-team leads operating a few repositories with repeatable delivery standards

Phase limits (MVP planning boundary):
- in scope: onboarding, repo import, built-in workflows, issue bot triggers, approval gates, git/PR automation, observability, typed RPC coverage
- out of scope: visual workflow builder, scheduled workflows, multi-repo orchestration, marketplace templates, broad non-issue-bot agent ecosystem

## The Two Flows That Must Stay in Balance
JidoCode is designed around two coupled flows:

1. Setup/Definition Flow (Control Plane)
2. Operational Flow (Companion Plane)

Concrete model:
- setup/definition produces a governing configuration state
- operations continuously consume that state to make proactive decisions
- trust mode governs what can be proposed, started, and shipped

Handoff rule:
Every operational decision must be derivable from configured criteria (policy, mode, playbook, workflow scope, and integration capability).

Failure modes of imbalance:
- under-specified setup:
  Jido cannot make safe decisions, so operations degrade into noise, frequent manual intervention, or blocked execution.
- over-constrained setup:
  Jido produces low throughput because automation eligibility is too narrow; suggestions pile up without meaningful execution.

Balance target:
Control plane defines clear intent without overfitting, while the companion plane executes continuously without violating constraints.

## Flow 1: Setup/Definition (Control Plane)
The control plane defines how Jido is allowed to behave.

Configuration domains:
1. Identity and auth posture
- single-owner instance control (AshAuthentication)
- browser session auth plus API key/bearer automation modes
- production-safe bootstrap and registration posture

2. Integrations and environment defaults
- GitHub app or PAT connectivity and webhook readiness
- compute defaults (cloud-first with local fallback support)
- project import readiness and workspace baseline rules

3. Secret model
- root secrets from environment/secret manager
- operational secrets via encrypted references only
- rotation, revocation, and redaction posture

4. Policy and playbook model
- safety checks (secret scan, diff policies, branch/push rules)
- scope and quality constraints per project/workflow
- shipping approval requirements and trusted exceptions

5. Autonomy definition
- per-project and per-workflow mode eligibility
- promotion/demotion criteria
- intervention controls and rollback posture

Output artifact:
Control Plane Baseline (versioned settings state used by the companion plane).

Planning-level baseline shape:
- `baseline_version`
- `project_scope`
- `integration_state`
- `policy_profile`
- `playbook_stack`
- `companion_mode_defaults`
- `autonomy_policy_refs`
- `override_controls`

Control plane guarantee:
Every autonomous action in operations must trace back to a specific baseline version and applicable policy/playbook set.

## Flow 2: Operational Companion (Delivery/Companion Plane)
The companion plane is where Jido continuously executes delivery work against the control plane baseline.

Continuous loop:
1. signal ingestion
- issues, PR activity, webhook events, stale work, failing runs, failed checks

2. prioritization and recommendation generation
- score opportunities against policy, mode, project priority, and current risk

3. mode-governed execution
- propose/start/ship behavior constrained by `CompanionMode` and `AutonomyPolicy`

4. outcome publication
- run states, artifacts, approval requests/decisions, PR metadata, policy outcomes

Expected UX surfaces:
- `/dashboard`: cross-project health and active execution pulse
- `/workbench`: issue/PR-oriented operations and kickoff actions
- `/projects/:id`: project cockpit for health, work, runs, specs, automation, config
- `/projects/:id/runs/:run_id`: run-level execution details, approvals, artifacts, provenance

Canonical data and decision sequence:
1. maintainer configures baseline
2. companion observes operational signals
3. companion scores opportunities against policy + mode
4. companion proposes or executes based on `CompanionMode`
5. safety gates apply before any shipping action
6. outcomes generate `TrustEvidence`
7. mode may remain, promote, or downgrade

Operational rule:
Trust flow is closed-loop. Operational outcomes continuously update autonomy posture.

## Trust Progression Model (Suggest -> Assisted Auto -> Full Auto)
Autonomy is earned, not assumed.
Default mode is `suggest` until trust criteria are satisfied.

### Conceptual Interfaces
- `CompanionMode`
  - values: `suggest`, `assisted_auto`, `full_auto`
  - meaning: permission envelope at decision time

- `AutonomyPolicy`
  - scope: project + workflow
  - planning-level fields:
    - allowed triggers
    - auto-start eligibility
    - shipping approval requirement
    - risk and size thresholds
    - downgrade triggers
    - manual override permissions

- `TrustEvidence`
  - evidence classes:
    - run reliability trend
    - policy violation history
    - rollback and override frequency
    - approval confidence trend

- `HumanOverride`
  - immediate controls:
    - pause companion operations
    - force mode downgrade
    - cancel active runs
    - require approval on next actions

Permissions matrix:

| Mode | Propose | Auto-start | Auto-ship |
|---|---|---|---|
| `suggest` | yes | no | no |
| `assisted_auto` | yes | yes (eligible workflows) | no by default |
| `full_auto` | yes | yes | yes only where explicitly policy-permitted |

Progression and regression rules:
- progression is opt-in, gradual, and reversible
- promotion requires `TrustEvidence` thresholds defined in `AutonomyPolicy`
- regression triggers on violations, reliability degradation, repeated overrides, or explicit maintainer action
- approval-before-shipping remains default unless explicitly changed by trusted policy

Trust guarantee:
Autonomy can always be reduced immediately. No mode is irreversible.

## What Jido Proactively Does
Once configured, Jido should continuously:

1. Work detection and triage
- detect new and changed issues
- detect stale PRs and blocked runs
- detect repeated failure patterns and regression hotspots

2. Prioritized recommendations
- rank candidate actions by urgency, impact, and policy fit
- surface "what to do next" with rationale and expected outcome

3. Context packaging
- compose execution context from project specs, playbooks, prior runs, and repository state
- preserve context provenance for reviewability

4. Policy-safe run kickoff
- auto-start only where mode and policy permit
- default to preparation-only behavior in `suggest`

5. Approval packet generation
- provide risk summary, diff/test summary, and policy check status
- present explicit approval/reject paths and recommended remediation

6. Follow-through on delivery outcomes
- track run lifecycle, branch/PR status, and post-action health
- feed outcomes back into `TrustEvidence`

Clause:
Jido is never proactive without policy. Eligibility must be explicitly configured.

## What Never Changes (Safety Invariants)
The perspective shift does not relax safety. The following remain non-negotiable:

1. Single-user/operator governance for instance control
2. Encrypted secrets at rest; no plaintext operational secret persistence
3. Redaction across logs, PubSub/events, artifacts, prompts, and UI
4. Authenticated and idempotent webhook handling
5. Mandatory git safety checks before commit/push/PR actions
6. Approval gates by default for shipping-critical transitions
7. Auditable provenance for workflow and git side effects
8. Cloud VM first deployment with local fallback compatibility
9. Typed RPC coverage for required product-domain actions

Safeguard rule:
Autonomy does not bypass safeguards. Higher autonomy only changes who initiates allowed actions, not which safeguards apply.

## Success Definition
JidoCode succeeds when it behaves like a trustworthy software companion:

1. Manual triage burden decreases while actionable throughput increases.
2. Workflow runs remain reliable and policy-compliant across all modes.
3. PR outputs are predictable in quality, reviewability, and traceability.
4. Maintainers can progress from `suggest` toward higher autonomy without trust erosion.
5. Safety invariants remain intact under both suggestion-led and autonomous execution.
6. Maintainers always retain clear visibility, intervention capability, and rollback control.

Planning-aligned KPIs (from current specs plus companion goals):
- deploy to first successful workflow run: under 15 minutes
- workflow completion to PR creation: under 30 seconds (eligible flows)
- successful run rate (non-crash): above 95 percent
- issue bot webhook-to-response latency p95: under 2 minutes
- required product action RPC coverage: 100 percent
- autonomy health: stable or improving `TrustEvidence` trend without policy violation growth
