# UI Reset Inventory

<!-- covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces -->
<!-- covers: architecture.frontend_stack.daisyui_removed_from_official_path -->

This inventory records the Phase 97.2 deletion and rewrite targets for the
greenfield UI reset. It is intentionally about current source files, not the
future shell implementation.

## Policy

- Current product data, auth, runtime, semantic, memory, conversation, and
  governed-work services are behavior to preserve.
- Current browser chrome, subject-tree navigation, DaisyUI component classes,
  and broad Vue auto-registration are implementation to replace.
- Current LiveVue widgets are rewritten against generated shadcn-vue primitives
  or deleted. They are not retained as DaisyUI-styled islands.
- Current stable DOM ids should survive where tests and user workflows still
  represent the same product behavior.

## LiveView Surfaces

| File | Classification | Reset Handling | Stable Behavior |
| --- | --- | --- | --- |
| `lib/jido_code_web/live/dashboard_live.ex` | root area | rewrite | authenticated home, runtime posture, repo/work summaries |
| `lib/jido_code_web/live/project_inventory_live.ex` | root area | rewrite | managed repository inventory, filters, import handoff |
| `lib/jido_code_web/live/workbench_live.ex` | root area | rewrite | dense specialist workspace and work context |
| `lib/jido_code_web/live/workflows_live.ex` | root area | rewrite | governed run launch and run history |
| `lib/jido_code_web/live/agents_live.ex` | root area | rewrite | repo-scoped support automation |
| `lib/jido_code_web/live/settings_live.ex` | root area | rewrite | auth, integrations, provider settings |
| `lib/jido_code_web/live/project_detail_live.ex` | detail route | rewrite | managed repo detail, conversation, semantic, memory, workflows |
| `lib/jido_code_web/live/run_detail_live.ex` | detail route | rewrite | governed run evidence, approvals, retry controls |
| `lib/jido_code_web/live/work_item_detail_live.ex` | detail route | rewrite | governed work-item detail |
| `lib/jido_code_web/live/evidence_detail_live.ex` | detail route | rewrite | governed evidence detail |
| `lib/jido_code_web/live/decision_detail_live.ex` | detail route | rewrite | governed decision detail |
| `lib/jido_code_web/live/home_live.ex` | public/bootstrap route | rewrite later | welcome, sign-in handoff, readiness routing |
| `lib/jido_code_web/live/setup_live.ex` | public/setup route | rewrite later | setup onboarding, runtime defaults, GitHub import |

## HEEx Component Surfaces

| File | Classification | Reset Handling | Notes |
| --- | --- | --- | --- |
| `lib/jido_code_web/components/layouts.ex` | shell chrome | rewrite | becomes ariston-style area shell layout |
| `lib/jido_code_web/components/core_components.ex` | Phoenix core | rewrite selectively | keep forms, inputs, icons, flashes where appropriate |
| `lib/jido_code_web/components/live_vue_components.ex` | LiveVue boundary | keep and revise | preserve bounded mount helper and degraded fallback |
| `lib/jido_code_web/components/conversation_surface_components.ex` | product component | rewrite | remove DaisyUI badges and base color classes |
| `lib/jido_code_web/components/memory_surface_components.ex` | product component | rewrite | move to shared tokens and SaladUI wrappers |
| `lib/jido_code_web/components/managed_repo_inventory_components.ex` | product component | rewrite/delete | merge into new repository area if duplicated |
| `lib/jido_code_web/components/operator_shell_components.ex` | legacy shell | delete | superseded by `JidoCodeWeb.Areas` and new layout |
| `lib/jido_code_web/components/operator_state_components.ex` | product status | rewrite | keep product state shaping, replace visual classes |

## Vue Widgets

| File | Classification | Reset Handling | Notes |
| --- | --- | --- | --- |
| `lib/jido_code_web/live/DashboardRunSummaryWidget.vue` | retained island candidate | rewrite | use `@/vue/components/ui/*` |
| `lib/jido_code_web/live/DashboardRuntimePostureWidget.vue` | retained island candidate | rewrite | use explicit registry |
| `lib/jido_code_web/live/ProjectDetailOverviewWidget.vue` | retained island candidate | rewrite | remove DaisyUI classes |
| `lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue` | retained island candidate | rewrite | keep semantic degradation product-oriented |
| `lib/jido_code_web/live/RunGovernanceOverviewWidget.vue` | retained island candidate | rewrite | preserve governed action semantics |
| `lib/jido_code_web/live/SettingsOverviewWidget.vue` | retained island candidate | rewrite/delete | may collapse into HEEx if not interactive enough |
| `lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue` | retained island candidate | rewrite | preserve setup event handoff |
| `lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue` | retained island candidate | rewrite | preserve setup event handoff |
| `lib/jido_code_web/live/SetupStartPathSelectorWidget.vue` | retained island candidate | rewrite | preserve setup event handoff |
| `lib/jido_code_web/live/WorkbenchSummaryWidget.vue` | retained island candidate | rewrite/delete | keep only if richer local interaction remains useful |

## DaisyUI Dependency Inventory

| Boundary | Current Reference | Reset Handling |
| --- | --- | --- |
| npm dependency | `package.json` includes `daisyui` | remove after first-party references reach zero |
| Tailwind plugin | `assets/css/app.css` imports DaisyUI plugin and themes | replace with shadcn-aligned tokens |
| HEEx classes | `btn`, `badge`, `alert`, `tabs`, `base-*`, `rounded-box`, `join-*` | replace with SaladUI wrappers or `.ui-*` utilities |
| Vue classes | `btn`, `badge`, `alert`, `base-*`, `join-*` | replace with generated shadcn-vue primitives |
| tests | selector expectations using old nav or DaisyUI-shaped classes | replace with product behavior and shell contract assertions |

## Stable Product Behaviors To Preserve

- Local owner sign-in and sign-out flow.
- Public `/welcome` and `/setup` bootstrap flows until folded into the new shell.
- Authenticated access control for product routes.
- Managed repository inventory, detail, workspace binding, and import behavior.
- Productive conversation runtime, cancellation, clarification, and event-stream behavior.
- Governed run, work-item, evidence, and decision detail behavior.
- Semantic, memory, provenance, and source-code graph degraded behavior.
- LiveVue mount fallback when SSR, manifest, or client assets degrade.
