# Phase 56 - Setup Onboarding Hybrid Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/frontend_architecture.spec.md`
- `../specs/setup_onboarding.spec.md`
- `../specs/runtime_environment_defaults.spec.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `../decisions/jido_code.runtime_environment_selection_is_persisted_setup_metadata.md`
- `../decisions/jido_code.setup_onboarding_live_vue_surface_split.md`
- `lib/jido_code_web/components/live_vue_components.ex`
- `lib/jido_code_web/live/setup_live.ex`
- `lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue`
- `lib/jido_code/setup/environment_defaults.ex`
- `lib/jido_code/setup/github_repository_listing.ex`
- `lib/jido_code/setup/project_import.ex`
- `lib/jido_code/security/encryption.ex`
- `test/support/live_vue_case.ex`
- `test/jido_code_web/live/setup_live_test.exs`

## Relevant Assumptions / Defaults
- The accepted setup-surface ADR keeps `/setup` LiveView-owned and explicitly rejects a monolithic Vue rewrite.
- PAT capture, encryption-key preflight, persistence mutations, and explicit completion into the dashboard remain server-owned controls even as richer setup widgets are added.
- GitHub repository selection is already the reference hybrid setup region and should be expanded incrementally rather than turned into a client-owned setup sub-application.
- Current setup verification is still weighted toward LiveView contract tests, so this phase should add real browser-level coverage before more setup interaction moves into Vue.

[ ] 56 Phase 56 - Setup Onboarding Hybrid Surface Adoption
  Implement the accepted `/setup` LiveView-plus-`live_vue` split by extracting bounded, choice-heavy onboarding regions into hybrid widgets while preserving server-owned setup gating, fallback behavior, and browser-level verification.

  [x] 56.1 Section - LiveView-Owned Setup Shell And View Models
    Keep `/setup` authoritative on the server while preparing section-level props and handlers that make bounded widget adoption safe and predictable.

    [x] 56.1.1 Task - Extract section-level setup view models
      Shape start-path, runtime-default, and GitHub follow-up data as bounded props and explicit emits rather than relying on ad hoc assigns inside larger template blocks.

      [x] 56.1.1.1 Subtask - Define stable prop shapes for start-path choice, runtime-default selection, and GitHub follow-up status that mirror server-authored state without leaking persistence internals.
      [x] 56.1.1.2 Subtask - Keep all persistence mutations, flash or navigation behavior, and blocking validation in LiveView events even when widgets initiate the interaction.
      [x] 56.1.1.3 Subtask - Preserve stable DOM IDs and section anchors so existing setup tests and fallback states remain selector-driven and legible.

    [x] 56.1.2 Task - Standardize setup-region fallback and deferred states
      Make each new hybrid region degrade safely so `/setup` stays usable when `live_vue` delivery is reduced or unavailable.

      [x] 56.1.2.1 Subtask - Reuse `vue_surface` fallback behavior for each new setup widget rather than bespoke client checks.
      [x] 56.1.2.2 Subtask - Keep deferred or prerequisite-gated states product-shaped in HEEx so PAT-first and restart-required flows stay clear without client code.
      [x] 56.1.2.3 Subtask - Ensure server fallbacks keep parity with the core choices and actions exposed by each richer widget.

  [x] 56.2 Section - Start Path And Runtime Default Hybrid Adoption
    Move the highest-value choice-heavy setup regions into bounded widgets after the shell contract is explicit.

    [x] 56.2.1 Task - Introduce a bounded start-path selection widget
      Replace the large server-rendered start-choice card set with a richer widget only if it improves scanning and selection without owning the route.

      [x] 56.2.1.1 Subtask - Create one setup start-path widget that renders choice cards from LiveView-authored props and emits explicit selection intents back to `choose_start_path`.
      [x] 56.2.1.2 Subtask - Keep recommendation badges, deployment-mode emphasis, and save gating server-authored rather than recreated in client-owned heuristics.
      [x] 56.2.1.3 Subtask - Add a server-rendered fallback that preserves the current start-path experience if the richer path degrades.

    [x] 56.2.2 Task - Introduce a bounded runtime-environment widget
      Give runtime-default selection richer layout and progressive disclosure while leaving validation and persistence on the server.

      [x] 56.2.2.1 Subtask - Render local-versus-cloud runtime defaults, persisted selection context, and workspace-root affordances through bounded props rather than a client-owned store.
      [x] 56.2.2.2 Subtask - Route validation and save behavior back through `change_runtime_environment` and `save_runtime_environment` without moving environment checks into Vue.
      [x] 56.2.2.3 Subtask - Keep local workspace-root errors, disabled states, and fallback submission usable in plain LiveView.

  [ ] 56.3 Section - GitHub Follow-Up Hybrid Convergence
    Expand the existing hybrid GitHub follow-up pattern without crossing the sensitive-control boundary defined by the ADR.

    [ ] 56.3.1 Task - Keep PAT capture and explicit completion server-owned
      Make the non-negotiable LiveView-owned setup controls explicit while richer GitHub follow-up regions evolve around them.

      [ ] 56.3.1.1 Subtask - Preserve PAT entry, encryption preflight, and secret-persistence messaging in HEEx rather than migrating those controls into Vue.
      [ ] 56.3.1.2 Subtask - Preserve explicit completion into the dashboard as a LiveView-owned control that remains available under degraded frontend delivery.
      [ ] 56.3.1.3 Subtask - Keep GitHub prerequisite gating and deferred selector messaging server-authored so fallback behavior stays clear.

    [ ] 56.3.2 Task - Deepen the repository-selection widget and follow-up overview
      Improve the existing GitHub hybrid region by pushing more choice-heavy, non-sensitive follow-up UI into bounded widgets.

      [ ] 56.3.2.1 Subtask - Move repository listing status, selected-repository summary, and import-status chrome fully into the GitHub widget where that improves scanning and resume behavior.
      [ ] 56.3.2.2 Subtask - Keep refresh, selection, and import events mapped back into LiveView without introducing a client-owned import state machine.
      [ ] 56.3.2.3 Subtask - Preserve a complete server-rendered fallback selector, including scrollable repository choice and import success affordances.

  [ ] 56.4 Section - Setup Route Browser Verification And Phase Integration Tests
    Close the gap between LiveView contract tests and real hybrid behavior before any more sensitive setup controls are considered for client adoption.

    [ ] 56.4.1 Task - Expand setup route hybrid contract coverage
      Keep `setup_live_test.exs` as the primary routed-surface harness while verifying each new widget boundary explicitly.

      [ ] 56.4.1.1 Subtask - Add LiveVue-aware assertions for new setup widgets, emitted handlers, and bounded prop contracts.
      [ ] 56.4.1.2 Subtask - Add fallback-path coverage proving new widgets reduce cleanly to server-rendered setup controls.
      [ ] 56.4.1.3 Subtask - Preserve regression coverage for PAT encryption preflight, persistence gating, and setup completion under the hybrid split.

    [ ] 56.4.2 Task - Add browser-level setup interaction coverage
      Add a real browser harness for setup widgets so client behavior is tested beyond static prop and handler inspection.

      [ ] 56.4.2.1 Subtask - Add browser coverage for start-path and runtime-default widget interaction inside the LiveView-owned `/setup` route.
      [ ] 56.4.2.2 Subtask - Add browser coverage for GitHub repository filtering, scrollable selection, and import initiation through the hybrid widget.
      [ ] 56.4.2.3 Subtask - Verify degraded or fallback setup states remain navigable without the richer client path.
