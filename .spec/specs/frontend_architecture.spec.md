# Frontend Architecture

<!-- current_truth.reconciled_with_branch: the LiveView-hosted setup surface keeps PAT capture and completion server-owned while start-path selection, runtime defaults, and GitHub repository selection are bounded live_vue regions with server fallback, runtime-default copy now frames the workspace root as seed metadata for new imports rather than a permanent shared-root rule, forced frontend fallback keeps the real built asset manifest so routed LiveView pages stay interactive, setup now has route-level Playwright coverage for both richer and degraded delivery, the GitHub selector layout continues to use the bounded Vue region for full-width scrollable multi-repository scanning while completed imports clear active selection, linked repositories group by account origin with the account name visible on each card in both richer and fallback paths, and the import-state badge stays distinct from selectable repos, phase-58 through phase-60 route integration coverage now exercise the shared LiveView route harness across bootstrap, continue-setup, ready-state auth boundaries, provider-auth redirects, and the settings-owned auth-settings cutover, the settings-owned `/settings/auth` destination now keeps provider-login and Git integration management inside that same routed LiveView shell through a shared helper boundary, ready-state auth handoff now enters dashboard by default across that harness, signed-in `/welcome` now uses a dashboard-first handoff card above a compact auth-settings cue, repo detail now keeps sidebar-selected family navigation, repo-scoped workspace-binding readiness and repair, consistent repo-scoped runtime wording across conversations, semantic, memory, and workflows, plus degraded continuity LiveView-owned while overview and graph exploration remain bounded hybrid regions and browser coverage exercises clarification, reload recovery, snapshot fallback, desktop sidebar behavior, and narrow-screen fallback navigation on that routed surface, and dashboard now keeps route-owned concern tabs plus a summary-first overview on the same LiveView shell rather than a client-owned dashboard application. -->

This subject defines the browser technology composition that `jido_code` should
use as it grows beyond plain HEEx-only screens without fragmenting product
ownership across multiple unrelated frontend stacks.

```spec-meta
id: architecture.frontend_stack
kind: policy
status: active
summary: Jido.Code keeps Phoenix LiveView as the routed product host shell while adopting `live_vue` as the canonical bridge for richer client-side Vue components, standardizing on a LiveView-plus-Vue composition model with product-owned mounting and operator-state boundaries, a repo-owned Mix start path that respects the current browser toolchain even while the root Mix surface carries additional source-code graph and memory-graph runtime dependencies plus dedicated semantic verification aliases, and LiveVue-aware test helpers instead of a parallel React or SPA frontend, beginning with bounded operator summary surfaces before deeper workflow pages and extending to bounded semantic repository inspection plus bounded memory and provenance exploration where richer graph exploration is useful across managed-repository, dashboard-summary, governed-run, work-item, evidence, decision, and other canonical product surfaces, including repo detail as a LiveView-owned route with route-selected overview, conversations, semantic, memory, and workflows families plus LiveView-owned repo-scoped workspace-binding repair, consistent repo-scoped runtime wording, and product-shaped memory follow-up previews, dashboard as a LiveView-owned authenticated landing with route-owned concern tabs and a summary-first overview rather than a future SPA shell, and setup as a LiveView-owned route whose bounded runtime-defaults widget still presents import-seed copy through server-authored props while degrading safely to LiveView-owned contracts.
decisions:
  - jido_code.factory_control_plane_and_runtime_overlay
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.live_vue_frontend_adoption
  - jido_code.dashboard_concern_tabs_and_overview_handoff
  - jido_code.setup_onboarding_live_vue_surface_split
  - jido_code.memory_graph_product_adoption
  - jido_code.memory_graph_surface_rollout_and_governance_actions
  - jido_code.memory_graph_workflow_and_operator_expansion
  - jido_code.source_code_graph_product_adoption
surface:
  - .spec/decisions/jido_code.dashboard_concern_tabs_and_overview_handoff.md
  - .spec/decisions/jido_code.live_vue_frontend_adoption.md
  - .spec/decisions/jido_code.setup_onboarding_live_vue_surface_split.md
  - .spec/specs/frontend_architecture.spec.md
  - .spec/specs/package.spec.md
  - .spec/specs/product_foundation_docs.spec.md
  - lib/jido_code_web/router.ex
  - lib/jido_code_web.ex
  - lib/jido_code/mix/frontend_start.ex
  - lib/jido_code/workbench/project_semantic_inspection.ex
  - lib/jido_code_web/components/live_vue_components.ex
  - lib/jido_code_web/frontend_assets.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - lib/jido_code_web/components/conversation_surface_components.ex
  - lib/jido_code_web/live/project_detail_live.ex
  - lib/jido_code/workbench/project_workspace_binding.ex
  - lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue
  - lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue
  - lib/jido_code_web/live/SetupStartPathSelectorWidget.vue
  - lib/jido_code_web/live/
  - lib/jido_code_web/components/
  - lib/mix/tasks/frontend.start.ex
  - assets/
  - mix.exs
  - config/
  - test/jido_code/frontend_start_test.exs
  - test/support/live_vue_case.ex
  - test/support/browser_setup.ex
  - test/support/failing_conversation_subscriber.ex
  - test/support/test_browser_scenario_controller.ex
  - test/support/test_browser_session_controller.ex
  - test/e2e/
  - test/e2e/conversation-ui.spec.ts
  - test/jido_code_web/components/
  - test/jido_code_web/components/operator_state_components_test.exs
  - test/jido_code_web/live/
  - test/jido_code_web/live/phase_sixty_three_integration_test.exs
  - test/jido_code_web/live/phase_sixty_four_integration_test.exs
  - test/jido_code_web/live/phase_twenty_five_integration_test.exs
  - test/jido_code_web/live/phase_twenty_seven_integration_test.exs
  - test/jido_code_web/live/phase_sixteen_integration_test.exs
```

## Requirements

```spec-requirements
- id: architecture.frontend_stack.liveview_remains_product_host_shell
  statement: Routed browser product surfaces shall keep Phoenix LiveView as the canonical host shell for router ownership, authentication and session boundaries, server-authored state, and page composition rather than being replaced by a separate SPA frontend.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  statement: Rich interactive browser components shall standardize on Vue mounted through `live_vue` so client-side components participate in LiveView props, events, uploads, and stream-driven updates instead of relying on ad hoc client islands or an unrelated React surface.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.product_owned_mounting_boundary
  statement: Vue-backed product surfaces shall mount through a product-owned helper boundary that standardizes component naming, prop delivery, stream delivery, and emit-to-LiveView event wiring instead of scattering raw LiveVue attribute conventions across individual pages.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.server_authored_props_streams_and_events
  statement: The LiveView shell shall remain the source of truth for server-authored browser state, with bounded props, top-level streams, uploads, and explicit event handoff rules crossing into Vue while ephemeral client-only state remains presentation-local.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  statement: Once Vue-backed surfaces are adopted, the canonical browser asset path for those surfaces shall use the `live_vue`-aligned Vite and SSR toolchain rather than a React-specific or one-off client build path.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
  statement: `jido_code` shall not maintain React as a parallel product frontend technology stack after `live_vue` is chosen as the standard rich-component bridge.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.adoption_is_incremental_per_surface
  statement: The product may adopt `live_vue` incrementally on the surfaces that justify richer client composition while leaving simpler LiveView-only routes and forms on plain HEEx where that remains the clearer implementation.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
  statement: The signed-in `/setup` route shall stay LiveView-owned and, when richer onboarding follow-up composition is justified, shall expand through bounded `live_vue` regions for choice-heavy interactions rather than a monolithic Vue rewrite of the full setup surface.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  statement: Browser-facing verification shall keep LiveView tests as the primary routed-surface harness and should add LiveVue-aware test helpers for Vue-mounted surfaces instead of assuming a standalone SPA testing model.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
  statement: Managed-repository conversation routes should keep transcript, repo-scoped workspace-binding readiness, clarification handling, and degraded continuity in the LiveView-owned route shell even when adjacent overview or summary widgets use bounded Vue regions and the route uses LiveView-owned family navigation.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  statement: Hybrid operator surfaces shall fall back safely to product-owned LiveView regions when the richer Vue delivery path is unavailable, degraded, or intentionally reduced to fallback mode.
  priority: must
  stability: evolving

- id: architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
  statement: Frontend rollout observability for LiveVue delivery, SSR reduction, and fallback delivery shall remain distinguishable from runtime-service observability and describe degraded browser behavior in product-oriented terms.
  priority: should
  stability: evolving

- id: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  statement: Semantic repository inspection, memory history, provenance exploration, and impact-exploration surfaces may use bounded LiveView-hosted Vue regions when richer graph exploration is valuable, but they shall remain canonical managed-repository or governed product surfaces rather than separate graph-only browser applications.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.frontend_stack.scenario_rich_surface_needs_client_composability
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - A routed product page needs richer client-side component composition than plain HEEx or lightweight hooks comfortably provide.
  when:
    - The product introduces a richer browser component layer for that page.
  then:
    - LiveView remains the page host shell and the richer client component is expected to arrive through `live_vue` and its aligned tooling rather than through a separate SPA or React island.

- id: architecture.frontend_stack.scenario_hybrid_surface_uses_shared_boundary
  covers:
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  given:
    - A LiveView-owned product surface needs a richer Vue-backed island.
  when:
    - The surface mounts that island and wires events back into LiveView.
  then:
    - The mount uses the shared product boundary, server-owned data stays bounded in props or streams, and test helpers can inspect the Vue contract without replacing the normal LiveView test harness.

- id: architecture.frontend_stack.scenario_simple_surface_stays_plain_liveview
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - A product route remains mostly form-driven or server-rendered.
  when:
    - That route does not need richer client-side composition.
  then:
    - The route may remain a plain LiveView or HEEx surface without being forced into Vue unnecessarily.

- id: architecture.frontend_stack.scenario_operator_summary_route_adopts_bounded_vue_widget
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - An operator-facing route such as dashboard or settings benefits from richer summary grouping or client-local filtering.
  when:
    - The route adopts a bounded Vue-backed widget for that summary region.
  then:
    - The route stays LiveView-owned, server-authored props remain bounded, and the Vue-backed region augments rather than replaces the routed product shell.

- id: architecture.frontend_stack.scenario_setup_entry_route_expands_incrementally
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  given:
    - The signed-in `/setup` route needs richer scanning or progressive disclosure for onboarding follow-up work.
  when:
    - The route introduces a Vue-backed region such as toggle-based repository multi-selection while keeping sensitive setup control flow on the server.
  then:
    - `/setup` remains a LiveView-owned route.
    - The richer region mounts through the shared product boundary with bounded props and mapped emits.
    - Credential preflight, secret persistence, and explicit completion continue to degrade safely through server-rendered setup controls rather than a client-owned setup shell.

- id: architecture.frontend_stack.scenario_workflow_route_adopts_bounded_vue_overview
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
  given:
    - A workflow-heavy operator route such as repo detail, run detail, or a workbench summary region needs richer overview composition.
  when:
    - The route adds a bounded Vue-backed overview widget while preserving existing LiveView controls below it.
  then:
    - Conversation, governance, filters, and runtime evidence continue to flow through LiveView-owned product boundaries while the Vue-backed region only renders bounded projections and mapped emits.

- id: architecture.frontend_stack.scenario_repo_detail_conversation_shell_stays_liveview_owned
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
    - architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  given:
    - Repo detail already uses LiveView-owned family navigation, a bounded Vue-backed overview widget, and the productive conversation route shell.
  when:
    - Browser coverage exercises clarification, blocked runtime readiness, reload recovery, snapshot-only degraded continuity, or switching between repo-detail families on that route.
  then:
    - Family selection remains route-authored rather than becoming client-owned tab state.
    - The transcript, readiness notices, and recovery state remain LiveView-owned and route-authored instead of moving into a client-owned conversation shell.
    - Any richer Vue region remains bounded to overview or summary composition and does not own productive conversation control flow.

- id: architecture.frontend_stack.scenario_semantic_repo_inspection_uses_hybrid_region
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  given:
    - A managed-repository surface needs richer semantic repository inspection such as module exploration or bounded impact visualization.
  when:
    - The route adopts a semantic inspection region inside a dedicated repo-detail family.
  then:
    - The route remains LiveView-owned and repository-scoped.
    - Any Vue-backed semantic region mounts through the shared product boundary.
    - Server-owned semantic freshness and recovery state remain explicit in the LiveView-owned contract.

- id: architecture.frontend_stack.scenario_memory_and_provenance_exploration_use_hybrid_region
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  given:
    - A managed-repository surface needs richer memory history or workflow provenance exploration such as decision timelines, memory freshness context, or cross-graph navigation.
  when:
    - The route adopts a memory or provenance exploration region inside a dedicated repo-detail family.
  then:
    - The route remains LiveView-owned and repository-scoped.
    - Any Vue-backed memory/provenance region mounts through the shared product boundary.
    - Server-owned freshness, invalidation, and recovery state remain explicit in the LiveView-owned contract.

- id: architecture.frontend_stack.scenario_frontend_stack_does_not_re_fragment
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  given:
    - Contributors need a standard way to build and verify richer browser UI.
  when:
    - The repository documents or implements that richer UI path.
  then:
    - The standard stack remains LiveView plus `live_vue`, and testing/documentation do not reintroduce React or SPA assumptions as a second frontend model.

- id: architecture.frontend_stack.scenario_hybrid_surface_degrades_to_liveview_fallback
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
    - architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
  given:
    - A routed operator page includes a Vue-backed hybrid region.
  when:
    - SSR or richer client delivery for that region is unavailable, degraded, or reduced to fallback mode.
  then:
    - The LiveView-owned route remains legible, bounded fallback messaging stays product-oriented, and degraded frontend signals remain observable without leaking raw runtime-service or toolchain contracts as the product interface.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.live_vue_frontend_adoption.md
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: .spec/decisions/jido_code.setup_onboarding_live_vue_surface_split.md
  covers:
    - architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions

- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_product_adoption.md
  covers:
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions

- kind: source_file
  target: .spec/decisions/jido_code.memory_graph_product_adoption.md
  covers:
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions

- kind: source_file
  target: lib/jido_code_web/live/project_detail_live.ex
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
    - architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned

- kind: source_file
  target: .spec/specs/frontend_architecture.spec.md
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.react_is_not_parallel_product_frontend_stack
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_five_integration_test.exs
  covers:
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_seven_integration_test.exs
  covers:
    - architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades

- kind: source_file
  target: lib/jido_code_web/components/live_vue_components.ex
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades

- kind: source_file
  target: lib/jido_code_web/frontend_assets.ex
  covers:
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling

- kind: source_file
  target: test/e2e/conversation-ui.spec.ts
  covers:
    - architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
    - architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented

- kind: source_file
  target: lib/jido_code_web/live/project_inventory_live.ex
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/setup_live.ex
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions

- kind: source_file
  target: test/support/live_vue_case.ex
  covers:
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: test/jido_code_web/live/project_inventory_live_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: test/jido_code_web/live/agents_live_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: test/jido_code_web/live/workflows_live_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/DashboardRunSummaryWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/DashboardRuntimePostureWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/SettingsOverviewWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/ProjectDetailOverviewWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/RunGovernanceOverviewWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/WorkbenchSummaryWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface

- kind: source_file
  target: lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions

- kind: source_file
  target: lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions

- kind: source_file
  target: lib/jido_code_web/live/SetupStartPathSelectorWidget.vue
  covers:
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/live/security_settings_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/live/project_detail_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/live/workbench_live_test.exs
  covers:
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.server_authored_props_streams_and_events

- kind: source_file
  target: test/jido_code_web/live/setup_live_test.exs
  covers:
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades

- kind: source_file
  target: test/e2e/setup-onboarding.spec.ts
  covers:
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades

- kind: command
  target: mix browser.verify
  covers:
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: test/jido_code_web/live/phase_sixty_one_integration_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned

- kind: source_file
  target: test/jido_code_web/components/live_vue_components_test.exs
  covers:
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades

- kind: source_file
  target: test/jido_code_web/frontend_assets_test.exs
  covers:
    - architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
    - architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented

- kind: source_file
  target: test/jido_code_web/live/phase_thirteen_integration_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: test/jido_code_web/live/phase_fourteen_integration_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
    - architecture.frontend_stack.product_owned_mounting_boundary
    - architecture.frontend_stack.server_authored_props_streams_and_events
    - architecture.frontend_stack.adoption_is_incremental_per_surface
    - architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers

- kind: source_file
  target: test/jido_code_web/live/phase_fifteen_integration_test.exs
  covers:
    - architecture.frontend_stack.liveview_remains_product_host_shell
    - architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
    - architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented

```
