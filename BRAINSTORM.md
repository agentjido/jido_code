Here’s a more “filled-in” MVP shape for the **Issue → Proposal → Approval → Implementation → PR** flow, consistent with the control-plane / companion-plane split + default approval gates in your vision doc.

## Proposed MVP operational flow (issue → PR)

### 0) Preconditions (from onboarding / control plane)

- Repo is connected via **GitHub App**, **selected repos only**.
- Repo has a per-repo **TriggerConfig** with toggles for:
  - **Assigned to bot**
  - **Label added**
  - **Slash-command comment**

- Repo has an **AutonomyPolicy** (default posture) that includes:
  - allowed triggers
  - auto-start eligibility
  - **approval required before any repo write**
  - diff/risk thresholds and downgrade triggers
    (This is the “setup defines intent; operations realize intent” contract.)

### 1) Trigger ingestion (webhook → run created)

When any enabled trigger fires:

- Jido receives an authenticated, idempotent webhook.
- Jido creates a **Run** record:
  - `run_id`, `project_id`, `repo`, `issue_number`
  - `trigger_type` (assignment/label/slash-command)
  - `baseline_version` reference (the governing config snapshot)
  - initial `status = planning`

- Jido posts an **ack comment** on the issue (fast feedback):
  - “Jido is preparing a proposal for this issue.”
  - Link to the run page (`/projects/:id/runs/:run_id`).

### 2) Proposal phase (read-only; no code changes)

Jido gathers context and generates an approval packet, still **no git writes**:

- Pulls:
  - issue body + comments, labels, assignees
  - repo metadata (default branch, CI config hints)
  - a shallow read-only checkout (or API fetch) for relevant files
  - any project playbooks/policies configured in baseline

- Produces a **Proposal** object with:
  - **Problem framing** (what it thinks the issue is asking)
  - **Acceptance criteria** (explicit checklist; inferred + quoted from issue where possible)
  - **Implementation plan** (steps, likely touched files/modules)
  - **Risk summary** (e.g., “touches auth”, “public API change”, “dependency change”)
  - **Validation plan** (tests/commands to run, linters, build steps)
  - **Policy pre-checks** (what gates will be enforced later)

Jido updates the issue comment with a clean “proposal card”:

- Short summary + link to full proposal/run details
- A clear “Approval required” section (this is the “approve button etc” moment)
- The available approve/reject actions

### 3) Approval gate (explicit human decision logged)

Jido creates an **ApprovalRequest** tied to the run:

- `approval_id`, `requested_by = jido`, `scope = implement_issue_to_pr`
- required permissions: must be a GitHub user with **write/admin** on the repo
- status: `pending → approved | rejected`
- audit fields: approver, timestamp, baseline version, trigger source, rationale (optional)

Only after approval does Jido proceed to write.

### 4) Implementation phase (writes allowed after approval)

After approval:

- Creates a branch like: `jido/issue-123-short-slug`
- Commits with a consistent convention (e.g., “Fix #123: …”)
- Runs validations defined by policy/playbook (tests, lint, secret scan)
- Opens a PR:
  - links the issue (“Fixes #123” when appropriate)
  - includes **provenance**: run_id, baseline_version, policy results, validation summary
  - includes “how to reproduce / verify” from the proposal

### 5) Outcome publication + observability

- Issue gets a final comment with:
  - PR link
  - what passed/failed
  - any manual follow-ups

- Run page shows:
  - timeline, logs (redacted), artifacts, policy outcomes
  - approval decision record
  - trust evidence updates (success/failure feeds the loop)

---

## One decision to lock next

Where should the **primary** approval action live in the MVP (the “Approve” control)?

- **A)** In **GitHub** (e.g., approve by reacting ✅ to the proposal comment and/or `/jido approve`)
- **B)** In the **Jido web UI** (real **Approve / Reject** buttons on the run page, with a deep link from the GitHub comment)
- **C)** Support **both**, but pick one as the “recommended default” (tell me which one)

Here are the **next 10 spec questions** I’d line up (in a dependency order), now that we’ve locked **Issue → Proposal → Approval → Implement → PR** and **approval in both GitHub + Jido UI**.

1. **GitHub approval semantics:** What _exact_ GitHub action(s) count as **Approve** and **Reject** for a proposal (slash command, emoji reaction, check-run action, etc.)?
2. **Approver identity + permissions:** Which GitHub users are allowed to approve/reject (repo write/admin only? maintainers? org members?), and how do we verify that via the GitHub API?
3. **Proposal payload contract:** What must every proposal include (problem framing, acceptance criteria, file touch list, risk rating, planned tests, estimated diff size, etc.) and what’s optional?
4. **Run state machine:** What are the canonical run states and transitions (e.g., `planning → awaiting_approval → implementing → validating → pr_opened → done`, plus failure/cancel paths)?
5. **Idempotency + concurrency rules:** If the issue is re-assigned, re-labeled, or multiple `/jido implement` comments happen, do we: create a new run, reuse the existing run, or dedupe? What’s the “one run per issue” policy?
6. **Branch/commit/PR conventions:** Branch naming, commit message format, whether PRs start as **draft** vs ready, how we link to the issue (“Fixes #123” rules), and whether we prefer squash vs multiple commits.
7. **Safety gates & policy defaults:** MVP defaults for size thresholds, restricted paths (e.g., `.github/workflows`), secret scanning, dependency changes, test requirements, and what triggers automatic downgrade.
8. **Validation strategy:** What commands does Jido run locally vs rely on CI for, and what constitutes “validation passed” before opening/marking PR ready?
9. **Failure handling UX:** If Jido can’t complete (tests fail, conflicts, unclear requirements), what’s the behavior—open a WIP PR, ask follow-up questions in the issue, or halt and request maintainer input?
10. **Provenance + observability artifacts:** What gets stored/shown (logs, patch/diff summary, test output, policy checks, baseline_version, run timeline), where it appears (issue comment, PR body, Jido run page), and what must be redacted by default.

### Question 1 (answer this now)

For **GitHub-side approval** in the MVP, which mechanism(s) should we support as the **official “Approve / Reject” signals**?

Pick the set you want (and tell me which is the default):

- **A)** Slash commands: `/jido approve` and `/jido reject` (with optional reason)
- **B)** Emoji reactions on the proposal comment (e.g., ✅ approve, ❌ reject)
- **C)** A GitHub **Check Run** with “Approve/Reject” actions (buttons in the Checks UI)
- **D)** Other (describe)
